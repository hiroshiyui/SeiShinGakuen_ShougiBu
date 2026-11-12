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
#   --aab            export a signed release AAB (implies --release,
#                    requires android/build/ template). Distribution is
#                    GitHub Releases sideload only — Play Store is out
#                    of scope — so this flag is rarely used; left in for
#                    completeness.
#   --test           run `cargo test` (unit + parity + perft) after Rust build
#   --linux          Linux desktop pipeline: portable x86_64 .so in the
#                    glibc-2.31 container, Godot export of the
#                    "Linux x86_64" preset, then the AppImage via
#                    tools/build_appimage.sh. arm64 is not shipped (the
#                    sub-scripts still take --arch arm64). Independent of
#                    the Android flags; combine with --skip-apk for
#                    Linux-only runs.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

GODOT="${GODOT:-$HOME/.local/bin/Godot_v4.7.2-stable_linux.x86_64}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Android/Sdk/ndk/30.0.16248370}"
EXPORT_PRESET="Android arm64"

DO_DESKTOP=1
DO_ANDROID=1
DO_FONTS=1
DO_APK=1
DO_TEST=0
DO_LINUX=0
RELEASE=0
AAB=0

for arg in "$@"; do
    case "$arg" in
        --skip-desktop) DO_DESKTOP=0 ;;
        --skip-android) DO_ANDROID=0 ;;
        --skip-fonts)   DO_FONTS=0 ;;
        --skip-apk)     DO_APK=0 ;;
        --release)      RELEASE=1 ;;
        # AAB is the Android App Bundle format (Play-Store-only in
        # practice); always signed, so implies --release. Reuses the
        # same preset but flips it into Gradle build + AAB format for
        # one export, then restores. Distribution targets GitHub
        # Releases sideload (.apk), not Play Store, so this flag is
        # rarely needed.
        --aab)          AAB=1; RELEASE=1 ;;
        --test)         DO_TEST=1 ;;
        --linux)        DO_LINUX=1 ;;
        -h|--help)
            sed -n '2,26p' "$0"; exit 0 ;;
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
    # Copy then rename rather than overwriting in place: an open Godot
    # editor has the old .so mmapped, and rewriting its bytes crashes
    # the editor (SIGBUS). The rename gives the new library a fresh
    # inode, and `reloadable = true` hot-reloads it on editor focus.
    cp native/shogi_core/target/release/libshogi_core.so \
       native/bin/linux/x86_64/libshogi_core.so.tmp
    mv -f native/bin/linux/x86_64/libshogi_core.so.tmp \
          native/bin/linux/x86_64/libshogi_core.so
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

# --- Portable Linux Rust (x86_64 + arm64, containerised) ---
# Replaces the host-linked x86_64 .so from the desktop step with the
# glibc-2.31 build, so what gets packaged is what was tested.
if (( DO_LINUX )); then
    log "Building portable Linux libshogi_core.so (x86_64)"
    ./tools/build_linux_native.sh --arch x86_64
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
    # of truth for Android version metadata) and tag every output filename
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
        # Back up to a fresh temp file (never overwrite an older backup)
        # and restore on any exit, including errors and Ctrl-C.
        PRESET_BACKUP="$(mktemp "${TMPDIR:-/tmp}/export_presets.XXXXXX")"
        cp "$PRESET_FILE" "$PRESET_BACKUP"
        # Idempotent: on Ctrl-C the INT trap restores, then the EXIT trap
        # runs again and must find nothing left to do.
        cleanup_preset() {
            [[ -f "$PRESET_BACKUP" ]] && mv -f "$PRESET_BACKUP" "$PRESET_FILE"
            return 0
        }
        trap cleanup_preset EXIT
        trap 'cleanup_preset; exit 130' INT TERM
        sed -i \
            -e 's|^gradle_build/use_gradle_build=.*|gradle_build/use_gradle_build=true|' \
            -e 's|^gradle_build/export_format=.*|gradle_build/export_format=1|' \
            "$PRESET_FILE"
    fi

    # Release builds need a release keystore. Godot's preset validator
    # demands "all three or none" of the keystore path / user / password
    # fields, so we leave all three empty in export_presets.cfg (so the
    # repo carries no signing secrets) and pass them via env vars at
    # build time. Godot 4.7 reads:
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
        trap - EXIT INT TERM
    fi
    if (( RELEASE )); then
        unset GODOT_ANDROID_KEYSTORE_RELEASE_PATH GODOT_ANDROID_KEYSTORE_RELEASE_USER GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD
    fi

    log "Done: $OUT ($(du -h "$OUT" | cut -f1))"
fi

# --- Linux export + AppImage ---
# Runs after fonts so the subsets are current. Exports both presets
# (release template; there's no signing on Linux) and packs them. The
# x86_64 binary gets a headless smoke run — proves the embedded PCK,
# the .so and the gdextension wiring load outside the editor.
if (( DO_LINUX )); then
    for arch in x86_64; do
        mkdir -p "build/linux/$arch"
        log "Exporting Linux $arch → build/linux/$arch/seishingakuen"
        "$GODOT" --headless --path . --export-release "Linux $arch"             "build/linux/$arch/seishingakuen"
    done
    log "Headless smoke run of the x86_64 export"
    timeout 120 build/linux/x86_64/seishingakuen --headless --quit-after 60         || { echo "x86_64 Linux export failed to run headless" >&2; exit 1; }
    ./tools/build_appimage.sh --arch x86_64
fi

log "Pipeline finished."
