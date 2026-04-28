# M PLUS 2 (Regular)

Japanese sans-serif webfont vendored for future UI use.

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
