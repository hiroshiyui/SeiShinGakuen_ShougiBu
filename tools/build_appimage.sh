#!/usr/bin/env bash
# Package the exported Linux build into a single-file AppImage.
#
# Usage:
#   tools/build_appimage.sh [--arch x86_64|arm64|all]
#
# Prerequisites (both produced by tools/build_all.sh --linux --skip-apk,
# or by hand):
#   native/bin/linux/<arch>/libshogi_core.so   portable .so (glibc ≤ 2.31)
#   build/linux/<arch>/seishingakuen            Godot export, embedded PCK
#   build/linux/<arch>/libshogi_core.so         copied there by the export
#
# Output:
#   build/seishingakuen-v<X.Y.Z>-<x86_64|aarch64>.AppImage  (+ .sha256)
#
# How it works: an AppImage is a squashfs of an AppDir (AppRun, .desktop,
# icon, usr/…) prefixed with a small static runtime for the target CPU.
# appimagetool itself only has to run on the host, so the x86_64 tool
# produces the aarch64 image given the aarch64 runtime via
# --runtime-file. Tools are fetched once into tools/.cache/appimage/ and
# pinned by SHA-256 in tools/appimage/appimage.lock. No FUSE is needed
# on the build host: appimagetool runs with --appimage-extract-and-run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CACHE="tools/.cache/appimage"
LOCK="tools/appimage/appimage.lock"
ARCH=all

while (( $# )); do
    case "$1" in
        --arch)   ARCH="$2"; shift 2 ;;
        --arch=*) ARCH="${1#--arch=}"; shift ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

log() { printf '\n\033[1;34m[appimage]\033[0m %s\n' "$*"; }

case "$ARCH" in
    all)    ARCHES=(x86_64 arm64) ;;
    x86_64|arm64) ARCHES=("$ARCH") ;;
    *) echo "unknown --arch $ARCH (x86_64|arm64|all)" >&2; exit 2 ;;
esac

# --- Tooling: download once, verify against the lock file every time ---
fetch() {  # fetch <repo> <asset>
    local repo="$1" asset="$2"
    if [[ ! -f "$CACHE/$asset" ]]; then
        log "Downloading $asset from $repo@continuous"
        command -v gh >/dev/null || { echo "gh CLI needed to download $asset" >&2; exit 1; }
        gh release download continuous -R "$repo" -p "$asset" -D "$CACHE" --clobber
    fi
}
verify() {  # verify <asset>
    local asset="$1" want have
    want=$(awk -v a="$asset" '$2 == a {print $1}' "$LOCK")
    have=$(sha256sum "$CACHE/$asset" | cut -d' ' -f1)
    if [[ -z "$want" ]]; then
        if [[ "${APPIMAGE_LOCK_UPDATE:-0}" == 1 ]]; then
            echo "$have  $asset" >> "$LOCK"; log "lock: added $asset $have"
        else
            echo "ERROR: $asset is not in $LOCK (set APPIMAGE_LOCK_UPDATE=1 to add)" >&2; exit 1
        fi
    elif [[ "$want" != "$have" ]]; then
        if [[ "${APPIMAGE_LOCK_UPDATE:-0}" == 1 ]]; then
            sed -i "s|^$want  $asset\$|$have  $asset|" "$LOCK"; log "lock: updated $asset → $have"
        else
            echo "ERROR: $CACHE/$asset sha256 $have != pinned $want" >&2
            echo "       Upstream 'continuous' moved. Delete the cache and re-run with APPIMAGE_LOCK_UPDATE=1 to re-pin deliberately." >&2
            exit 1
        fi
    fi
}
mkdir -p "$CACHE"
fetch AppImage/appimagetool appimagetool-x86_64.AppImage
chmod +x "$CACHE/appimagetool-x86_64.AppImage"
verify appimagetool-x86_64.AppImage
for a in "${ARCHES[@]}"; do
    rt=$([[ $a == arm64 ]] && echo runtime-aarch64 || echo runtime-x86_64)
    fetch AppImage/type2-runtime "$rt"; verify "$rt"
done

VERSION=$(sed -nE 's|^config/version="(.*)"$|\1|p' project.godot)
[[ -n "$VERSION" ]] || { echo "config/version missing in project.godot" >&2; exit 1; }

for a in "${ARCHES[@]}"; do
    appimage_arch=$([[ $a == arm64 ]] && echo aarch64 || echo x86_64)
    runtime="$CACHE/runtime-$appimage_arch"
    exe="build/linux/$a/seishingakuen"
    so="build/linux/$a/libshogi_core.so"
    [[ -x "$exe" && -f "$so" ]] || {
        echo "Missing export for $a: need $exe and $so (run: tools/build_all.sh --linux --skip-apk, then export the 'Linux $a' preset)" >&2
        exit 1; }

    # Guard against packaging a host-linked .so by mistake.
    max_glibc=$(objdump -T "$so" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' | sort -V | tail -1)
    [[ "$(printf '%s\n2.31\n' "$max_glibc" | sort -V | tail -1)" == 2.31 ]] || {
        echo "ERROR: $so needs GLIBC_$max_glibc (> 2.31). Rebuild with tools/build_linux_native.sh and re-export." >&2
        exit 1; }

    appdir="build/appimage/$a/AppDir"
    rm -rf "$appdir"; mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications" \
        "$appdir/usr/share/icons/hicolor/432x432/apps"
    cp "$exe" "$so" "$appdir/usr/bin/"
    cp tools/appimage/seishingakuen.desktop "$appdir/usr/share/applications/"
    cp tools/appimage/seishingakuen.desktop "$appdir/"
    cp assets/branding/icon_launcher_432.png "$appdir/usr/share/icons/hicolor/432x432/apps/seishingakuen.png"
    cp assets/branding/icon_launcher_432.png "$appdir/seishingakuen.png"
    cp assets/branding/icon_launcher_432.png "$appdir/.DirIcon"
    # AppRun: cd into usr/bin so Godot finds libshogi_core.so next to the
    # executable (that's where the .gdextension resolves it after export),
    # then hand over argv untouched.
    cat > "$appdir/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
cd "$HERE/usr/bin" || exit 1
exec "$HERE/usr/bin/seishingakuen" "$@"
EOF
    chmod +x "$appdir/AppRun"

    out="build/seishingakuen-v${VERSION}-${appimage_arch}.AppImage"
    log "Packing $out"
    ARCH="$appimage_arch" "$CACHE/appimagetool-x86_64.AppImage" --appimage-extract-and-run \
        --runtime-file "$runtime" --no-appstream "$appdir" "$out"
    chmod +x "$out"
    ( cd build && sha256sum "$(basename "$out")" > "$(basename "$out").sha256" )
    log "$out ($(du -h "$out" | cut -f1)) — $(file -b "$out" | cut -d, -f1-2)"
done

log "AppImages ready."
