#!/usr/bin/env bash
# Full build pipeline: Rust (desktop + Android) → font subsets → Godot APK.
#
# Usage:
#   tools/build_all.sh [--skip-desktop] [--skip-android] [--skip-fonts]
#                      [--skip-apk] [--release|--aab] [--test]
#
# Flags:
#   --skip-desktop   don't build/deploy the linux x86_64 .so
#   --skip-android   don't cross-compile the arm64-v8a .so
#   --skip-fonts     don't regenerate font subsets
#   --skip-apk       don't export the Android package
#   --release        export a signed release APK (default: debug)
#   --aab            export a signed release AAB for Play Store
#                    (implies --release, requires android/build/ template)
#   --test           run `cargo test` (unit + parity + perft) after Rust build

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GODOT="${GODOT:-$HOME/.local/bin/Godot_v4.6.2-stable_linux.x86_64}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/28.1.13356709}"
EXPORT_PRESET="Android arm64"

DO_DESKTOP=1
DO_ANDROID=1
DO_FONTS=1
DO_APK=1
DO_TEST=0
RELEASE=0
AAB=0

for arg in "$@"; do
    case "$arg" in
        --skip-desktop) DO_DESKTOP=0 ;;
        --skip-android) DO_ANDROID=0 ;;
        --skip-fonts)   DO_FONTS=0 ;;
        --skip-apk)     DO_APK=0 ;;
        --release)      RELEASE=1 ;;
        # AAB is for Play Store distribution; always signed, so implies
        # --release. Reuses the same preset but flips it into Gradle
        # build + AAB format for one export, then restores.
        --aab)          AAB=1; RELEASE=1 ;;
        --test)         DO_TEST=1 ;;
        -h|--help)
            sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "unknown flag: $arg" >&2; exit 2 ;;
    esac
done

log() { printf '\n\033[1;34m[build]\033[0m %s\n' "$*"; }

# --- Sanity checks ---
[[ -x "$GODOT" ]] || { echo "Godot not found at $GODOT" >&2; exit 1; }
if (( DO_ANDROID || DO_APK )); then
    [[ -d "$ANDROID_NDK_HOME" ]] || {
        echo "Android NDK not found at $ANDROID_NDK_HOME" >&2; exit 1; }
fi

# --- Desktop Rust ---
if (( DO_DESKTOP )); then
    log "Building libshogi_core.so (linux x86_64)"
    cargo build --release --manifest-path native/shogi_core/Cargo.toml
    mkdir -p native/bin/linux/x86_64
    cp native/shogi_core/target/release/libshogi_core.so \
       native/bin/linux/x86_64/
fi

# --- Tests (optional) ---
if (( DO_TEST )); then
    log "Running cargo test (unit + parity + perft)"
    cargo test --manifest-path native/shogi_core/Cargo.toml
fi

# --- Android Rust ---
if (( DO_ANDROID )); then
    log "Cross-compiling libshogi_core.so (aarch64-linux-android)"
    command -v cargo-ndk >/dev/null || {
        echo "cargo-ndk not installed. Run: cargo install cargo-ndk" >&2
        exit 1; }
    ( cd native/shogi_core && \
      ANDROID_NDK_HOME="$ANDROID_NDK_HOME" \
      cargo ndk --platform 24 -t arm64-v8a \
        --output-dir ../../native/bin/android \
        build --release )
fi

# --- Font subsets ---
if (( DO_FONTS )); then
    log "Rebuilding font subsets"
    ./tools/build_font_subsets.py
fi

# --- Android export (APK or AAB) ---
if (( DO_APK )); then
    mkdir -p build
    # Pull version/name straight out of export_presets.cfg (single source
    # of truth for Play Store metadata) and tag every output filename
    # with it. Empty version/name → no suffix, so debug builds during
    # early development still produce predictable names.
    VERSION_NAME=$(sed -nE 's|^version/name="(.*)"$|\1|p' "$REPO_ROOT/export_presets.cfg")
    VSUFFIX=""
    [[ -n "$VERSION_NAME" ]] && VSUFFIX="-v${VERSION_NAME}"
    KIND=$([[ $RELEASE == 1 ]] && echo release || echo debug)
    EXT=$([[ $AAB == 1 ]] && echo aab || echo apk)
    OUT="build/seishingakuen-${KIND}${VSUFFIX}.${EXT}"
    EXPORT_FLAG=$([[ $RELEASE == 1 ]] && echo --export-release || echo --export-debug)

    # AAB needs Godot's Android Gradle build template + the preset
    # flipped into use_gradle_build=true / export_format=1. The Gradle
    # template lives in `android/build/` (one-time install via
    # `Project > Install Android Build Template` in the editor, or via
    # `--install-android-build-template`). We patch export_presets.cfg
    # in place for one export and restore it on EXIT so the working
    # tree stays clean even if Godot crashes mid-build.
    if (( AAB )); then
        [[ -d "$REPO_ROOT/android/build" ]] || {
            echo "AAB needs the Godot Android build template at $REPO_ROOT/android/build." >&2
            echo "Install via: $GODOT --headless --path . --install-android-build-template" >&2
            exit 1; }
        PRESET_FILE="$REPO_ROOT/export_presets.cfg"
        cp "$PRESET_FILE" "$PRESET_FILE.bak"
        cleanup_preset() { mv -f "$PRESET_FILE.bak" "$PRESET_FILE"; }
        trap cleanup_preset EXIT
        sed -i \
            -e 's|^gradle_build/use_gradle_build=.*|gradle_build/use_gradle_build=true|' \
            -e 's|^gradle_build/export_format=.*|gradle_build/export_format=1|' \
            "$PRESET_FILE"
    fi

    # Release builds need a release keystore. Godot's preset validator
    # demands "all three or none" of the keystore path / user / password
    # fields, so we leave all three empty in export_presets.cfg (so the
    # repo carries no signing secrets) and pass them via env vars at
    # build time. Godot 4.6 reads:
    #   GODOT_ANDROID_KEYSTORE_RELEASE_PATH
    #   GODOT_ANDROID_KEYSTORE_RELEASE_USER
    #   GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    # The path and alias are local config (different per project); the
    # password lives in `.android-release-pass` at the repo root
    # (gitignored).
    if (( RELEASE )); then
        PASS_FILE="$REPO_ROOT/.android-release-pass"
        [[ -r "$PASS_FILE" ]] || {
            echo "Release build needs $PASS_FILE (one line: keystore password)." >&2
            exit 1; }
        : "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:=$HOME/.local/share/godot/keystores/seishingakuen-release.keystore}"
        : "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:=seishingakuen}"
        IFS= read -r GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD < "$PASS_FILE" || true
        [[ -r "$GODOT_ANDROID_KEYSTORE_RELEASE_PATH" ]] || {
            echo "Release keystore missing: $GODOT_ANDROID_KEYSTORE_RELEASE_PATH" >&2
            exit 1; }
        export GODOT_ANDROID_KEYSTORE_RELEASE_PATH
        export GODOT_ANDROID_KEYSTORE_RELEASE_USER
        export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    fi

    log "Exporting $([[ $AAB == 1 ]] && echo AAB || echo APK) → $OUT"
    "$GODOT" --headless --path . "$EXPORT_FLAG" "$EXPORT_PRESET" "$OUT"

    if (( AAB )); then
        cleanup_preset
        trap - EXIT
    fi
    if (( RELEASE )); then
        unset GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    fi

    log "Done: $OUT ($(du -h "$OUT" | cut -f1))"
fi

log "Pipeline finished."
