# M PLUS 2 (Regular)

Japanese sans-serif webfont used for the modern UI labels — メインメニュー
の対戦相手名、設定、対局中の補助ラベル、棋譜検討の見出し、バージョン
表示など。本将棋らしい筆書体 (`fude-goshirae`) は駒文字専用、画面の
本文と UI ラベルは可読性重視で M PLUS 2 と Noto Serif JP に役割分担して
いる。

## Files

- `MPLUS2-Regular-full.otf` — upstream (1.2 MB). Source of truth in
  the repo; excluded from the APK via `export_presets.cfg`'s
  `exclude_filter`.
- `MPLUS2-Regular.otf` — subset, derived from the full file. Shipped
  in the APK.
- `OFL.txt` — upstream SIL Open Font License v1.1.

Subsets are re-derived by scanning `scripts/` and `scenes/` for
Japanese characters + an ASCII safety range + a punctuation / digits
safety set — see `tools/build_font_subsets.py`.

## Source

Upstream OTF from <https://github.com/coz-m/MPLUS_FONTS>
(`fonts/MPLUS2/otf/MPLUS2-Regular.otf`). Vendored here to avoid a
hidden dependency on Google Fonts' CDN.

## License

SIL Open Font License, Version 1.1 — see [`OFL.txt`](./OFL.txt). The
subset is a Modified Version under the OFL and inherits the license;
`OFL.txt` is distributed alongside it.

Re-generate the subset with:

```bash
./tools/build_font_subsets.py
```
