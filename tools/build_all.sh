#!/usr/bin/env bash
# Full build pipeline: Rust (desktop + Android) → font subsets → Godot APK.
#
# Usage:
#   tools/build_all.sh [--skip-desktop] [--skip-android] [--skip-fonts]
#                      [--skip-apk] [--release] [--test]
#
# Flags:
#   --skip-desktop   don't build/deploy the linux x86_64 .so
#   --skip-android   don't cross-compile the arm64-v8a .so
#   --skip-fonts     don't regenerate font subsets
#   --skip-apk       don't export the Android APK
#   --release        export a signed release APK (default: debug)
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

for arg in "$@"; do
    case "$arg" in
        --skip-desktop) DO_DESKTOP=0 ;;
        --skip-android) DO_ANDROID=0 ;;
        --skip-fonts)   DO_FONTS=0 ;;
        --skip-apk)     DO_APK=0 ;;
        --release)      RELEASE=1 ;;
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

# --- APK export ---
if (( DO_APK )); then
    mkdir -p build
    APK="build/seishingakuen-$([[ $RELEASE == 1 ]] && echo release || echo debug).apk"
    EXPORT_FLAG=$([[ $RELEASE == 1 ]] && echo --export-release || echo --export-debug)
    log "Exporting APK → $APK"
    "$GODOT" --headless --path . "$EXPORT_FLAG" "$EXPORT_PRESET" "$APK"
    log "Done: $APK ($(du -h "$APK" | cut -f1))"
fi

log "Pipeline finished."
