#!/usr/bin/env python3
"""Reproducible font subsetter for the repo's vendored fonts.

Reads the `*-full.otf` sources under `assets/fonts/**/` and emits tiny
subsets alongside them at the canonical filenames referenced by
`assets/themes/ui.tres` and by `scripts/game/Square.gd`. The full files
are source-only and excluded from the APK via `export_presets.cfg`'s
`exclude_filter`.

Usage:
    tools/build_font_subsets.py

Requires fontTools (`pip install fonttools`) — `pyftsubset` on PATH, or
the virtualenv path below as a fallback.

Background: this used to be a shell script. GNU grep's `[一-龥]` range
is evaluated via locale collation weights under a ja_JP.UTF-8 locale,
silently dropping common kanji whose weight falls outside the range
(e.g. 伊, 杏, 位). Doing the scan in Python avoids the whole class of
locale-dependent bugs — `re.findall` on a Unicode string is always
codepoint-based.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# --- glyph sets ------------------------------------------------------------

# Piece kanji rendered on Square labels (Piece.kanji_for).
PIECE_TEXT = "歩香桂銀金角飛王玉と杏圭全馬龍"

# Always-include safety set for runtime-injected glyphs (digits,
# format-string filler, common punctuation). Mirrors UI_SAFETY in the
# old shell version.
#
# Kifu (棋譜) glyphs are bundled here because the strings are assembled
# in the Rust core (`kifu::log_to_lines`) and emitted via FFI — the
# scan-the-source pass would never see them. Includes ☗ ☖ side markers,
# ZENKAKU file digits, rank kanji 一..九, 同 (recapture marker), 成 / 打,
# and every piece kanji that can render in the kifu — these overlap with
# PIECE_TEXT but that set's a separate pass for the piece-tile font.
UI_SAFETY = (
    "0123456789%→×！？・、。「」…"
    "☗☖"
    "０１２３４５６７８９"
    "一二三四五六七八九"
    "同成打"
    "歩香桂銀金角飛王玉と杏圭全馬龍"
)

# Codepoint-range regex covering every Japanese glyph we care about:
# hiragana, katakana, chouon, iteration marks, CJK unified ideographs
# (BMP range — matches what the old shell scan tried to cover).
JAPANESE_CHARS_RE = re.compile(
    "["
    "ぁ-ん"   # ぁ-ん
    "ァ-ヶ"   # ァ-ヶ
    "ー"          # ー
    "々-〇"   # 々 〆 〇
    "一-龥"   # 一-龥
    "]"
)

# ASCII printable passed to pyftsubset via --unicodes alongside --text,
# so any English / numeric Label text doesn't render as .notdef boxes.
ASCII_UNICODES = "0020-007E"

# Trees we walk for Japanese-bearing source. assets/ holds the
# CharacterProfile .tres files whose `tagline` / `introduction` strings
# are user-visible at runtime — without scanning them, a kanji that
# only appears in a character bio would silently render as tofu on
# device.
SCAN_DIRS = ("scripts", "scenes", "assets")

# Only text-shaped extensions are scanned. assets/ contains lots of
# binary (.webp, .otf, .png, .ogg) which would either be skipped here
# or — worse — accidentally yield spurious matches when their bytes
# happen to look like valid UTF-8 Japanese.
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".json", ".md"}


# --- helpers ---------------------------------------------------------------


def scan_ui_glyphs() -> str:
    """Walk SCAN_DIRS, return a stable-ordered string of every
    Japanese codepoint referenced in any TEXT_SUFFIXES file."""
    glyphs: set[str] = set()
    for sub in SCAN_DIRS:
        root = REPO_ROOT / sub
        if not root.is_dir():
            continue
        for path in root.rglob("*"):
            if not path.is_file():
                continue
            if path.suffix.lower() not in TEXT_SUFFIXES:
                continue
            try:
                text = path.read_text(encoding="utf-8", errors="ignore")
            except OSError:
                continue
            glyphs.update(JAPANESE_CHARS_RE.findall(text))
    return "".join(sorted(glyphs))


def find_pyftsubset() -> str:
    on_path = shutil.which("pyftsubset")
    if on_path:
        return on_path
    venv = Path.home() / "MyProjects/ShogiDojo/virtualenv/bin/pyftsubset"
    if venv.is_file() and os.access(venv, os.X_OK):
        return str(venv)
    sys.exit("pyftsubset not found. Install with: pip install fonttools")


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f}{unit}"
        n //= 1024
    return f"{n}TB"


def subset(src: Path, dst: Path, text: str, pyftsubset: str) -> None:
    if not src.exists() or src.stat().st_size == 0:
        sys.exit(f"Missing source: {src}")
    before = src.stat().st_size
    subprocess.run(
        [
            pyftsubset,
            str(src),
            f"--output-file={dst}",
            f"--unicodes={ASCII_UNICODES}",
            f"--text={text}",
            "--drop-tables+=FFTM,DSIG,MATH",
        ],
        check=True,
    )
    after = dst.stat().st_size
    pct = 100 * after // before if before else 0
    print(f"  {dst.name:<45s}  {human_size(before)} → {human_size(after)} ({pct}%)")


def reimport_godot() -> None:
    godot = os.environ.get(
        "GODOT",
        str(Path.home() / ".local/bin/Godot_v4.6.2-stable_linux.x86_64"),
    )
    if not (os.path.isfile(godot) and os.access(godot, os.X_OK)):
        print(
            f"Godot not at {godot} — skipping reimport. Open the editor to refresh.",
            file=sys.stderr,
        )
        return
    r = subprocess.run(
        [godot, "--headless", "--import", "--path", str(REPO_ROOT)],
        capture_output=True,
    )
    if r.returncode == 0:
        print("Reimport OK.")
    else:
        print(
            "Reimport failed — open the editor manually to refresh font cache.",
            file=sys.stderr,
        )


# --- entrypoint ------------------------------------------------------------


def main() -> int:
    os.chdir(REPO_ROOT)
    pyftsubset = find_pyftsubset()
    ui_text = scan_ui_glyphs() + UI_SAFETY

    print("Subsetting:")
    subset(
        REPO_ROOT / "assets/fonts/fude-goshirae/fude-goshirae-full.otf",
        REPO_ROOT / "assets/fonts/fude-goshirae/fude-goshirae.otf",
        PIECE_TEXT,
        pyftsubset,
    )
    subset(
        REPO_ROOT / "assets/fonts/noto-serif-jp/NotoSerifCJKjp-Medium-full.otf",
        REPO_ROOT / "assets/fonts/noto-serif-jp/NotoSerifCJKjp-Medium.otf",
        ui_text,
        pyftsubset,
    )
    subset(
        REPO_ROOT / "assets/fonts/noto-serif-jp/NotoSerifCJKjp-Bold-full.otf",
        REPO_ROOT / "assets/fonts/noto-serif-jp/NotoSerifCJKjp-Bold.otf",
        ui_text,
        pyftsubset,
    )

    print()
    print("Subsets written. Triggering Godot reimport so .godot/imported/ picks them up…")
    reimport_godot()
    print("Done. Re-run after editing UI strings.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
