# Noto Serif JP (Medium, Bold)

Japanese serif webfont used as the game's primary UI typeface.

## Files

- `NotoSerifCJKjp-Medium-full.otf` — upstream (25 MB). Source of truth
  in the repo; excluded from the APK.
- `NotoSerifCJKjp-Medium.otf` — subset (79 KB), default UI weight.
  Shipped in the APK.
- `NotoSerifCJKjp-Bold-full.otf` — upstream (25 MB). Excluded from APK.
- `NotoSerifCJKjp-Bold.otf` — subset (79 KB), used for the bold slot
  on Labels and as the default Button font so CTAs render bold.
- `OFL.txt` — upstream SIL Open Font License v1.1.

Subsets are re-derived by scanning `scripts/` and `scenes/` for
Japanese characters + an ASCII safety range + a punctuation / digits
safety set — see `tools/build_font_subsets.py`.

## Source

Upstream OTFs from <https://github.com/notofonts/noto-cjk>
(`Serif/OTF/Japanese/`). Google Fonts' distribution at
<https://fonts.google.com/noto/specimen/Noto+Serif+JP> is a repackage
of the same JP subfont (identical glyph set, different filename
metadata); the upstream files are vendored here to avoid a hidden
dependency on the Google Fonts CDN.

## License

SIL Open Font License, Version 1.1 — see [`OFL.txt`](./OFL.txt). The
subsets are Modified Versions under the OFL and inherit the license;
`OFL.txt` is distributed alongside them.

Re-generate the subsets with:

```bash
./tools/build_font_subsets.py
```
