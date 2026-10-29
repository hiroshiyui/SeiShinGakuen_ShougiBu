# ADR-0011: Per-move "mood" roll for AI character strength

## Status

Accepted. Amends ADR-0006.

## Context

ADR-0006 moved strength selection onto `CharacterProfile` `.tres`
files, each carrying `playouts` + `temperature`. In practice
`GameController` never read them: it kept looking up
`Settings.LEVEL_PARAMS[ai_level]`, so the ladder in `Settings.gd`
was the real source of strength and the profile dials were dead data.

That ladder bottomed out at 8 playouts / temperature 2.0 for Lv 1 and
16 / 1.5 for Lv 2. With Dirichlet noise already mixed into the root
priors, sampling an 8-visit distribution at temperature 2.0 is close
to picking a random legal move. Playtesting read this as "broken",
not "beginner": the weak characters never produced a plausible move,
let alone an occasional good one, so games against them were dull
rather than easy.

Two fixes were considered independently of each other:

1. **Raise the floor.** More playouts and a lower temperature cap so
   every tier at least picks among moves the search actually looked
   at.
2. **Vary strength within a game.** A fixed (playouts, temperature)
   pair makes a character uniformly sloppy. Humans at any level
   produce the occasional strong move; an opponent that sometimes
   punishes a blunder is more fun to play than one that never does.

## Decision

Both, wired through the profile so the `.tres` files finally mean
something:

- `Settings.ai_dials()` returns the selected character's dials and is
  what `GameController` passes to `think_sampled` and
  `opening_book_pick`. `LEVEL_PARAMS` remains only as the fallback
  for the no-character-selected case (first launch, legacy saves).
- `CharacterProfile` gains `moods: Array[Dictionary]`, each entry
  `{weight, playouts, temperature}`. `roll_dials()` does a weighted
  pick every AI move; an empty list means the baseline dials.
  Missing keys in a mood fall back to the baseline value.
- The floor is 32 playouts / temperature 1.2 (Lv 1), and every tier
  and mood is capped at 256 playouts. The profiles' original numbers
  (up to 2048) were sized for the v1 net; Bonanza v2 is ~8× more
  expensive per playout and 256 is already a few seconds per move on
  arm64. `characters_tests.gd` enforces the cap.
- The teacher-hint search uses `Settings.ai_base_dials()`, i.e. the
  baseline without the mood roll. Advice should be steady; only the
  opponent is moody.

Shipped weights (weight / playouts / temperature):

| Lv | Baseline | Moods |
|---|---|---|
| 1 | 32 / 1.2 | 65% 32/1.2, 25% 64/0.5, 10% 160/0.0 |
| 2 | 48 / 1.0 | 60% 48/1.0, 30% 96/0.4, 10% 192/0.0 |
| 3 | 64 / 0.8 | 60% 64/0.8, 30% 128/0.3, 10% 256/0.0 |
| 4 | 96 / 0.6 | 65% 96/0.6, 25% 160/0.2, 10% 256/0.0 |
| 5 | 128 / 0.4 | 70% 128/0.4, 30% 256/0.0 |
| 6 | 160 / 0.2 | 75% 160/0.2, 25% 256/0.0 |
| 7 | 192 / 0.1 | none |
| 8 | 256 / 0.0 | none |

## Consequences

**Makes easy:**

- Tuning feel per character is a `.tres` edit, no code change. The
  weights above are a first guess and are expected to move after
  on-device play.
- Lv 7 and Lv 8 are unchanged in character: no moods, greedy or near
  greedy, so the top of the ladder stays deterministic-feeling.
- The whole mechanism lives in GDScript; the Rust `think_sampled`
  signature is untouched.

**Makes harder / accepts:**

- Move time now varies within a game for the weak tiers: a 10%
  "sharp" mood at 160 to 256 playouts takes noticeably longer than the
  baseline. The existing thinking indicator covers it, but the
  variance is visible.
- Strength is no longer a single number per character, so comparing
  tiers or reasoning about "how strong is Lv 3" needs the table, not
  one dial. `strength_label` on the profile is the player-facing
  summary.
- The mood roll is uniform over the game. Phase-aware adjustment
  (sharper in the endgame, rubber-banding on the root value) was
  discussed and deferred; it would slot into `roll_dials()` or
  `Settings.ai_dials()` without touching the profile schema.

## See also

- [`scripts/CharacterProfile.gd`](../../scripts/CharacterProfile.gd)
  `moods`, `roll_dials()`, `base_dials()`.
- [`scripts/autoload/Settings.gd`](../../scripts/autoload/Settings.gd)
  `ai_dials()`, `ai_base_dials()`, `LEVEL_PARAMS` (fallback).
- [`scripts/game/GameController.gd`](../../scripts/game/GameController.gd)
  `_maybe_start_ai_turn` and the teacher-hint path.
- [`scripts/tests/characters_tests.gd`](../../scripts/tests/characters_tests.gd)
  mood validation + the 256-playout cap.
- [ADR-0006](./0006-character-driven-difficulty.md).
