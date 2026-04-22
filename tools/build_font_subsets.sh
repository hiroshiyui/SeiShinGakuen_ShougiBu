#!/usr/bin/env bash
# build_font_subsets.sh
#
# Reproducible font subsetter. Reads the full upstream OTFs vendored
# under `assets/fonts/**/*-full.otf` and emits tiny subsets alongside
# them at the canonical filenames referenced by `assets/themes/ui.tres`
# and by `scripts/game/Square.gd`.
#
# The `*-full.otf` files are source-only and excluded from the APK via
# `export_presets.cfg`'s `exclude_filter`.
#
# Requires fontTools (`pip install fonttools`) — `pyftsubset` on $PATH.
# Re-run after editing UI strings in `scripts/` or `scenes/`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# --- resolve pyftsubset ---
if command -v pyftsubset >/dev/null 2>&1; then
    PYFTSUBSET=pyftsubset
elif [[ -x /home/yhh/MyProjects/ShogiDojo/virtualenv/bin/pyftsubset ]]; then
    PYFTSUBSET=/home/yhh/MyProjects/ShogiDojo/virtualenv/bin/pyftsubset
else
    echo "pyftsubset not found. Install with: pip install fonttools" >&2
    exit 1
fi

# --- glyph sets ---

# Piece kanji rendered on Square labels (Piece.kanji_for).
PIECE_TEXT='歩香桂銀金角飛王玉と杏圭全馬龍'

# UI text: scan every GDScript + scene file for Japanese characters,
# then add an always-include safety set for runtime-injected glyphs
# (digits, format-string filler, common punctuation).
UI_SCAN=$(grep -rhoE '[ぁ-んァ-ヶー々〆〇一-龥]' scripts/ scenes/ 2>/dev/null \
          | tr -d '\n' | fold -w1 | sort -u | tr -d '\n')
UI_SAFETY='0123456789%→×！？・、。「」…'
UI_TEXT="${UI_SCAN}${UI_SAFETY}"

# Always keep the full ASCII printable range too so any future Label
# text containing English / numeric glyphs doesn't silently render as
# `.notdef` boxes. Passed as --unicodes alongside --text.
ASCII_UNICODES='0020-007E'

# --- subset one font ---
subset() {
    local src="$1"; local dst="$2"; local text="$3"
    if [[ ! -s "$src" ]]; then
        echo "Missing source: $src" >&2
        exit 1
    fi
    local before after
    before=$(stat -c%s "$src")
    $PYFTSUBSET "$src" \
        --output-file="$dst" \
        --unicodes="$ASCII_UNICODES" \
        --text="$text" \
        --drop-tables+=FFTM,DSIG,MATH
    after=$(stat -c%s "$dst")
    printf '  %-45s  %s → %s (%d%%)\n' \
        "$(basename "$dst")" \
        "$(numfmt --to=iec --suffix=B "$before")" \
        "$(numfmt --to=iec --suffix=B "$after")" \
        "$((100 * after / before))"
}

echo "Subsetting:"
subset \
    assets/fonts/fude-goshirae/fude-goshirae-full.otf \
    assets/fonts/fude-goshirae/fude-goshirae.otf \
    "$PIECE_TEXT"
subset \
    assets/fonts/noto-serif-jp/NotoSerifCJKjp-Medium-full.otf \
    assets/fonts/noto-serif-jp/NotoSerifCJKjp-Medium.otf \
    "$UI_TEXT"
subset \
    assets/fonts/noto-serif-jp/NotoSerifCJKjp-Bold-full.otf \
    assets/fonts/noto-serif-jp/NotoSerifCJKjp-Bold.otf \
    "$UI_TEXT"

echo
echo "Done. Re-run after editing UI strings."
