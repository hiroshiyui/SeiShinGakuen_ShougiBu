# Noto Serif JP (Medium, Bold)

Japanese serif webfont used as the game's primary UI typeface.

## Files vendored

- `NotoSerifCJKjp-Medium.otf` (25 MB) — default UI weight.
- `NotoSerifCJKjp-Bold.otf` (25 MB) — for emphasis (`Bold` theme slot).
- `OFL.txt` — SIL Open Font License v1.1 (upstream).

## Source

Files are the upstream JP subfonts from the Noto CJK project:
<https://github.com/notofonts/noto-cjk>

Google Fonts' distribution at
<https://fonts.google.com/noto/specimen/Noto+Serif+JP> is a repackage of
the same JP subfont (different filename metadata, effectively identical
glyph set). Either works; the upstream files are vendored here so there
is no hidden dependency on the Google Fonts CDN.

## License

SIL Open Font License v1.1. Full text in [`OFL.txt`](./OFL.txt). Same
license as the Fude Goshirae piece font — permissive redistribution
inside application bundles, no standalone sale.

## Size note

~50 MB total is a lot to ship; the game only uses a small slice of the
glyph set. Phase 7 scheduled task: subset both weights to the actual UI
text via the `pyftsubset`-driven `tools/` script — expected output
~200 KB per weight.
