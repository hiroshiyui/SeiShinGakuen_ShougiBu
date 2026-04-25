# 筆ごしらえ (Fude Goshirae)

Japanese brush-style display font used to render kanji shogi pieces.

## Files

- `fude-goshirae-full.otf` — upstream v1.00 (unmodified, 39 MB). Kept
  in the repo as the source of truth; excluded from the APK via
  `export_presets.cfg`'s `exclude_filter="*-full.otf"`.
- `fude-goshirae.otf` — subset derived from the full font
  (`tools/build_font_subsets.py`). Contains only the 15 glyphs actually
  rendered on `Square` labels (`歩香桂銀金角飛王玉と杏圭全馬龍`) plus
  the ASCII printable range as a safety net. Shipped in the APK.

## Source

<https://booth.pm/ja/items/7797956> — version 1.00.

## License

SIL Open Font License, Version 1.1 — see [`OFL.txt`](./OFL.txt). The
subset is a Modified Version under the OFL; it inherits the license
and is distributed alongside `OFL.txt`, satisfying the
redistribution-with-license clause.

Re-generate the subset with:

```bash
./tools/build_font_subsets.py
```
