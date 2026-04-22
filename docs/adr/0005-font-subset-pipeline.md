# ADR-0005: Keep full upstream fonts in-repo, subset at build time

## Status

Accepted.

## Context

The two vendored Japanese fonts (Fude Goshirae for piece kanji, Noto
Serif JP Medium + Bold for UI) totalled **~90 MB** of OTF data. A
naive APK ship of all three put the release at **103 MB** — over the
Play Store's compressed-APK warning threshold, and unreasonable for a
single-player board game.

Of the ~30,000 glyphs in each font, only ~100 ever render. Subsetting
with `pyftsubset` trivially drops each file to tens to hundreds of
kilobytes. The question was where the artefacts live:

1. **Subset in-place.** Run `pyftsubset` once; commit the result.
   Upstream file is gone; re-subsetting with a different glyph set
   requires re-downloading / re-extracting.
2. **Cache upstream locally, subset into repo.** Upstream lives in
   `~/.cache/…`; repo has only subsets. Build step re-downloads if
   cache is missing.
3. **Keep upstream in-repo AND subset in-repo.** Upstream at
   `<name>-full.otf`, subset at `<name>.otf`. `export_presets.cfg`
   excludes `*-full.otf` from the APK.

## Decision

Option 3. Repo carries both files per font; the export excludes
`-full.otf`.

## Consequences

**Makes easy:**

- Re-subsetting is fully reproducible from a clean `git clone` — no
  hidden dependency on a user-local cache or an upstream URL.
- Fude Goshirae has no public canonical URL (it was purchased from
  booth.pm); losing the local cache would lose the source. Vendoring
  protects against that.
- `tools/build_font_subsets.sh` is a pure file-in / file-out
  transform — auditable, no network fallback paths.

**Makes harder / accepts:**

- Repo size: ~90 MB of binary OTFs. A fresh `git clone --depth=1` is
  noticeably slower. If this becomes painful, upgrade to git-lfs; the
  current size is "annoying but acceptable".
- Godot re-imports `-full.otf` as `FontFile` resources and writes
  `.import` sidecars. Those sidecars are committed alongside — harmless
  but counts as "source control smell".
- Contributors must remember to re-run the subset script after adding
  UI strings; the script greps `scripts/` + `scenes/` for CJK
  characters and writes the subset, so as long as the script runs, the
  glyph set stays in sync. The catch is runtime-formatted text — see
  `UI_SAFETY` in the script, which lists digits and punctuation
  characters that might be string-interpolated rather than literal.

## See also

- `tools/build_font_subsets.sh`.
- `export_presets.cfg` — `exclude_filter="*-full.otf"`.
- `assets/fonts/*/README.md` per-font.
