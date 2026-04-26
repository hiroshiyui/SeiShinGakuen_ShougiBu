# ADR-0006: AI strength is chosen by picking a character, not a level

## Status

Accepted.

## Context

The original menu surfaced AI strength as a `Lv 1 - <name>` `OptionButton`
populated from `Settings.LEVEL_PARAMS` (8 entries, playouts × temperature
pairs). Functional but flat: the player picked a number, the name beside
it was decorative, and the player never met the same opponent twice in
any meaningful sense — the eight `LEVEL_NAMES` were just labels with no
art, no backstory, no relationship to each other.

Adding portraits + bios for the eight tiers raised a layering question.
We could:

1. **Keep the level dropdown, add a portrait beside it.** Strength stays
   the primary axis; the character is decoration. Two settings for the
   user (level + character), two sources of truth in `Settings`.
2. **Replace the level dropdown with a character picker.** The character
   *is* the difficulty — picking 加藤師範 implies Lv 8, picking 佐藤くん
   implies Lv 1. One setting for the user, one source of truth.
3. **Independent character + level.** A character has a "natural" level
   but the player can override (e.g. play a 1段 加藤師範). Three sources
   of truth, two of them the user has to reconcile.

## Decision

Option 2. The 8 strength tiers are reified as `CharacterProfile` `.tres`
files (`assets/characters/{teachers,students}/<id>.tres`) carrying a
`level: int` field. `Settings.select_character(profile)` writes both
`Settings.selected_character_id` and `Settings.ai_level` from the same
record, so they cannot drift. The MainMenu's old `LevelSelect` dropdown
is gone; in its place a single `OpponentButton` opens
`scenes/CharacterPicker.tscn` and shows the current pick once chosen.

## Consequences

**Makes easy:**

- The picker UI carries genuine information (肖像画 + 紹介 + 強さ
  ラベル), not just a number with a name beside it. Players form
  attachments to specific opponents instead of treating Lv 4 as
  interchangeable with Lv 5.
- New characters are pure data — drop a `.tres` + portrait directory
  under `assets/characters/`, and `Settings.list_characters()` picks
  it up. No code or scene edits to grow the cast.
- `GameController._character` already loaded the profile by id — the
  hook to drive future expression-swap logic (thinking / happy /
  worried portraits) is in place without further plumbing.
- Naming difficulties stays story-scoped: 「加藤師範」 reads as "the
  hardest opponent" without the player needing to reason about
  playout counts or temperatures.

**Makes harder / accepts:**

- "Play this opponent at a different strength" is no longer expressible
  in the UI. If a player wants to face 加藤師範's voice line at Lv 3
  pacing, they can't. We considered this an acceptable loss: the eight
  tiers cover the strength curve, and decoupling character from
  strength would re-introduce the confusion option 1 had.
- `LEVEL_NAMES` in `Settings.gd` is now duplicated by each
  character's `display_name`. Kept the array because legacy code
  paths (resume-from-saved-game without a selected character, the
  in-game `_opponent_label` fallback) still want a name keyed by
  level alone. Treat `LEVEL_NAMES` as a fallback table, not the
  source of truth.
- The picker's `Settings.list_characters()` walks `res://`
  directories at runtime. On Android Godot rewrites `.tres` to
  `.tres.remap` during export, and `ProjectSettings.globalize_path`
  on a `res://` path returns a non-existent OS path. The
  implementation matches both suffixes and skips the
  `dir_exists_absolute` check — see the function in
  [`Settings.gd`](../../scripts/autoload/Settings.gd) for the
  Android-specific shape.

## See also

- [`scripts/CharacterProfile.gd`](../../scripts/CharacterProfile.gd) —
  resource schema (level, playouts, temperature, strength_label,
  tagline, introduction, portrait_dir).
- [`scripts/autoload/Settings.gd`](../../scripts/autoload/Settings.gd)
  `list_characters` / `load_character` / `select_character`.
- [`scenes/CharacterPicker.tscn`](../../scenes/CharacterPicker.tscn) +
  [`scripts/CharacterPicker.gd`](../../scripts/CharacterPicker.gd) —
  the picker scene + script.
- ROADMAP Phase 7 entry "Character picker" for the user-facing copy.
