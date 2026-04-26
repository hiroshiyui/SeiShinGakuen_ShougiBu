# ADR-0007: Font subsetter scans `assets/**/*.tres`, not just code/scenes

## Status

Accepted. Extends [ADR-0005](./0005-font-subset-pipeline.md).

## Context

The original subsetter
([`tools/build_font_subsets.py`](../../tools/build_font_subsets.py),
established by ADR-0005) walked `scripts/` and `scenes/` recursively
and grep'd for Japanese codepoints. That covered every UI string while
they all lived in `.gd` and `.tscn` files.

When the character roster (ADR-0006) landed, character bios moved into
`.tres` resources under `assets/characters/`. Those bios introduced
glyphs the subset had never seen — 諦, 譲, 行方, 浴衣, 呉服, 部室,
etc. — none of which were detected by the existing scan. The text
still rendered on device, apparently through a Godot fallback path
(plausibly the imported `.fontdata` cache from a previous full-font
build, or whatever fallback chain Godot uses when a glyph is missing
from the active subset). It was working by luck, not by design.

We had three options:

1. **Bake bios into a generated `.gd` constant at build time.** Subsetter
   would scan that file like any other source. Splits the data —
   designers edit `.tres`, build step regenerates the `.gd` constant.
2. **Hardcode bio kanji into `UI_SAFETY`.** Fragile and high-touch:
   every new bio sentence requires a manual subset addition.
3. **Expand the subsetter's scope to walk `assets/` for `.tres`/text
   files.** Subsetter learns about more file types; data stays where
   it belongs.

## Decision

Option 3. The subsetter now walks `scripts/`, `scenes/`, and `assets/`,
restricted to a `TEXT_SUFFIXES` whitelist (`.gd`, `.tscn`, `.tres`,
`.cfg`, `.json`, `.md`). Binary assets in `assets/` (`.webp`, `.otf`,
`.png`, `.ogg`) are excluded — both for speed and to avoid spurious
matches when binary bytes happen to look like valid UTF-8 Japanese.

## Consequences

**Makes easy:**

- Character bios, character display names, taglines, strength labels —
  any Japanese string in any text-shaped resource — automatically reach
  the subset on the next build. No "remember to also do X" step.
- Future text-bearing data (extra `.tres` types: items, dialogue lines,
  if/when we get there) works the same way without further script
  changes.
- Eliminates a class of "looked fine in the editor, tofu on a fresh
  install" bugs that the previous scope was vulnerable to.

**Makes harder / accepts:**

- The subsetter is now sensitive to whatever file extensions live under
  `assets/`. If a future asset format carries Japanese text in a
  suffix not in `TEXT_SUFFIXES`, it'll silently miss it. That's the
  same tradeoff as before — explicit allowlist over a "scan everything
  binary" heuristic — but the failure mode is the one to watch for.
- Slightly larger Noto Serif JP subsets: Medium 117 KB → 182 KB,
  Bold 117 KB → 184 KB on the current cast (≈65 KB of bio kanji that
  weren't being properly subset before). Negligible relative to the
  APK total.
- Scan time grows linearly with `assets/` text-file count. Currently
  dominated by `.tres` (a few dozen) — not a measurable concern.

## See also

- [ADR-0005](./0005-font-subset-pipeline.md) — the original subset
  pipeline this extends.
- [`tools/build_font_subsets.py`](../../tools/build_font_subsets.py) —
  `SCAN_DIRS`, `TEXT_SUFFIXES` constants near the top.
