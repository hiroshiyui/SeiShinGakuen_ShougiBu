# Mochiy Pop One

Rounded pop display face for headline text: the app title
「清正学園将棋部」, screen headings (設定 / 棋譜検討 / 棋譜 / クレジット),
the opponent's name on the character picker, and the 王手！ banner.
Body text and buttons stay on Noto Serif JP / M PLUS 2; piece kanji
stay on `fude-goshirae`.

## Files

- `MochiyPopOne-Regular-full.ttf` — upstream (5.2 MB). Source of
  truth in the repo; excluded from the APK via `export_presets.cfg`'s
  `exclude_filter`.
- `MochiyPopOne-Regular.ttf` — subset over the scanned UI glyph set
  (+ ASCII safety range). Shipped in the APK.
- `OFL.txt` — upstream SIL Open Font License v1.1.

Subsets are re-derived by scanning `scripts/`, `scenes/` and `assets/`
for Japanese characters — see `tools/build_font_subsets.py`.

## Source

Upstream TTF from <https://github.com/google/fonts/tree/main/ofl/mochiypopone>
(project: <https://github.com/fontdasu/Mochiypop>). Vendored here to
avoid a hidden dependency on Google Fonts' CDN.

## License

SIL Open Font License, Version 1.1 — see [`OFL.txt`](./OFL.txt). The
subset is a Modified Version under the OFL and inherits the license;
`OFL.txt` is distributed alongside it.

Re-generate the subset with:

```bash
./tools/build_font_subsets.py
```
