#!/usr/bin/env bash
# Remove regenerable build artefacts to free disk space.
#
#   cleanup.sh            report only — list what each tier would free
#   cleanup.sh --apply    delete the safe tier
#   cleanup.sh --apply --deep
#                         also delete the caches that cost a full rebuild
#
# Never touched: native/bin/ (the editor and exports load the .so from
# there), android/build/ (one-time Godot Gradle template install),
# .godot/ (import cache), keystores, .android-release-pass, and the
# artefacts of the current version in build/.
set -euo pipefail

APPLY=0
DEEP=0
for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --deep)  DEEP=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"
[[ -f project.godot ]] || { echo "not the project root: $REPO_ROOT" >&2; exit 1; }

VERSION="$(sed -n 's|^config/version="\(.*\)"$|\1|p' project.godot)"
[[ -n "$VERSION" ]] || { echo "cannot read config/version from project.godot" >&2; exit 1; }

TARGET=native/shogi_core/target

size() {  # human-readable total of the given paths, "0" if none exist
    local existing=()
    for p in "$@"; do [[ -e "$p" ]] && existing+=("$p"); done
    (( ${#existing[@]} )) || { echo 0; return; }
    du -shc "${existing[@]}" | tail -1 | cut -f1
}

remove() {  # label, then paths
    local label="$1"; shift
    local existing=()
    for p in "$@"; do [[ -e "$p" ]] && existing+=("$p"); done
    if (( ! ${#existing[@]} )); then
        printf '  %-44s %s\n' "$label" "(nothing)"
        return
    fi
    printf '  %-44s %s\n' "$label" "$(size "${existing[@]}")"
    (( APPLY )) && rm -rf -- "${existing[@]}"
    return 0
}

# Versioned outputs in build/ that do not belong to the current version.
old_outputs=()
shopt -s nullglob
for f in build/seishingakuen-*.apk build/seishingakuen-*.apk.idsig \
         build/seishingakuen-*.aab \
         build/seishingakuen-*.AppImage build/seishingakuen-*.AppImage.sha256; do
    case "$f" in
        *"-v${VERSION}.apk"|*"-v${VERSION}.apk.idsig"|*"-v${VERSION}.aab"|*"-v${VERSION}-"*) ;;
        *) old_outputs+=("$f") ;;
    esac
done
shopt -u nullglob

before="$(df --output=avail -B1 . | tail -1)"

(( APPLY )) && echo "Deleting (current version: v$VERSION)" \
            || echo "Report only — nothing is deleted (current version: v$VERSION)"

echo "Safe tier:"
remove "cargo debug profile (cargo test)"      "$TARGET/debug"
remove "old APK / AAB / AppImage (not v$VERSION)" "${old_outputs[@]}"
remove "Linux export staging (build/linux)"    build/linux
remove "AppDir staging (build/appimage)"       build/appimage
remove "Python bytecode"                       tools/__pycache__

if (( DEEP )); then
    echo "Deep tier:"
else
    echo "Deep tier (only with --deep):"
    APPLY=0
fi
remove "cargo release profile (desktop .so)"   "$TARGET/release"
remove "cargo Android profile"                 "$TARGET/aarch64-linux-android"
remove "AppImage tooling (re-downloaded)"      tools/.cache
if command -v podman >/dev/null && podman volume exists seishingakuen-linux-target; then
    printf '  %-44s %s\n' "podman volume seishingakuen-linux-target" "(present)"
    (( APPLY )) && podman volume rm seishingakuen-linux-target >/dev/null
fi

after="$(df --output=avail -B1 . | tail -1)"
if (( after > before )); then
    echo "Freed: $(numfmt --to=iec-i --suffix=B $(( after - before )))"
fi
echo "Kept: native/bin, android/build, .godot, build/*v$VERSION*"
