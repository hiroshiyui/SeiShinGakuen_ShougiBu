# ADR-0008: Review mode keeps a separate `_review_core` instead of rewinding the live core

## Status

Accepted.

## Context

Phase 7 added two related features that need to render an arbitrary
historical position on the board without disturbing the live game:

1. **In-game 棋譜 panel** (`scenes/MoveHistoryDialog.tscn`) — tap a row,
   board jumps to that ply. The user is reviewing while their game is
   technically still in progress; the AI may even be mid-`think_best_move`
   on a Godot `Thread`.
2. **棋譜検討 reviewer** (`scenes/KifuReviewer.tscn`) — pure-review of a
   loaded KIF, prev/next/first/last navigation, MCTS analysis of every
   ply.

Both need "render this board state" without the question "what is the
canonical state right now?" becoming ambiguous.

We considered three approaches:

1. **Rewind the live `_core` via `undo_move()` then redo.** Cheapest for
   memory but kills the in-game flow: while reviewing, the live game
   state is in an inconsistent intermediate spot. If the AI thread
   finishes mid-rewind and tries to commit, it commits onto the wrong
   position. Sennichite's `position_counts` would also need
   bump/unbump dance per scrub.
2. **Snapshot + restore the live `_core`.** Clone the whole `Board`
   before entering review, mutate freely, restore on exit. Works but
   the clone is non-trivial (mailbox + two hands + log + `position_counts`
   `HashMap<String, u32>`) and Godot's `Object.duplicate()` doesn't
   reach into the native struct.
3. **Keep a second `ShogiCore` instance for review.** All renders read
   from `_active_core()` which returns either the live `_core` or the
   review one; mutations always target the live `_core`. Review entry
   = `ClassDB.instantiate("ShogiCore")` + `apply_packed(prefix)` to
   replay from the start.

## Decision

Option 3. `_review_core: Object = null`; `_in_review: bool` toggles
which one `_active_core()` hands back. View / render paths use
`_active_core()`; mutation paths (`apply_move`, `undo_move`, AI
thinking) use `_core` directly. Input is gated by `_in_review` so the
human can't accidentally play a move from the rewound position.

KifuReviewer applies the same pattern with a single `_core` (no live
game alongside it), so `_active_core()` simplifies to just `_core` and
the locking conditions melt away — the scene still uses
`apply_packed(prefix)` per nav step to replay from the start.

## Consequences

**Makes easy:**

- The live game keeps running undisturbed during review. AI threads
  that finish mid-review commit onto the live board correctly; their
  result becomes visible the moment the user exits review.
- Save / resume always sees the live state — `Settings.save_game(sfen,
  packed_log)` is called from `_commit_move` which targets `_core`,
  not `_active_core()`.
- The MCTS analysis loop in `KifuReviewer._on_analyze` can mutate its
  scratch core freely without worrying about the user's selected ply
  view; the loop calls `_replay_to_ply()` once at the end to restore
  whichever ply the user was looking at.

**Makes harder / accepts:**

- Two `ShogiCore` instances allocated during review. Each carries a
  mailbox, two hand HashMaps, a `LogEntry` Vec and a `position_counts`
  HashMap — a few KB. Cheap.
- `apply_packed(prefix)` is O(N) per scrub step (replay from start),
  not O(1). For interactive review this is fine: 200 moves × ~5 µs
  each = 1 ms, well under a frame. We pay for cleanliness, not speed.
- Every external read of board state during review must go through
  `_active_core()` — easy to miss when adding new code. A bug here
  would render the live state into a UI that should be showing the
  review state. Mitigated by keeping the helper one short line: if
  you write `_core.foo()` instead of `_active_core().foo()` while
  reading state for a render, the bug is local and obvious in
  diff review.

## See also

- [`scripts/game/GameController.gd`](../../scripts/game/GameController.gd)
  — search for `_review_core`, `_in_review`, `_active_core()`.
- [`scripts/KifuReviewer.gd`](../../scripts/KifuReviewer.gd) — the
  pure-review counterpart.
- [`scripts/MoveHistoryDialog.gd`](../../scripts/MoveHistoryDialog.gd)
  — emits `ply_selected(ply)` which drives the scratch-core replay.
