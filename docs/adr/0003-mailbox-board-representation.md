# ADR-0003: Mailbox board representation, defer bitboards

## Status

Accepted.

## Context

Shogi has 9 × 9 = 81 squares. Two canonical representations:

1. **Mailbox.** Flat `[Option<Piece>; 81]`. Each square holds at most
   one piece. Move generation walks step/ray tables and reads/writes
   cells.
2. **Bitboards.** A 128-bit value (or two 64-bit halves) per piece
   type per colour. Move generation is table lookups and bit twiddles;
   ~5–10× faster than mailbox for a tuned implementation.

The Phase 4 ROADMAP acknowledged both and recommended starting with
whichever was faster to write.

## Decision

Mailbox. Shogi's 81 squares don't fit in a single native-word bitboard
(unlike chess's 64), so the bitboard implementation would need 128-bit
split across two u64s or a `[u64; 2]`, and every rank/file mask becomes
a two-word operation. The speedup exists but the code is harder to
audit.

## Consequences

**Makes easy:**

- Code reads like the rules: `if let Some(p) = board.piece_at(sq)`.
- `#[test]` fixtures construct positions with `board.place(sq, piece)`
  cell-by-cell; bitboards would need a helper layer.
- `undo_move` is a straight swap of `Option<Piece>` cells plus hand
  adjustments.

**Makes harder / accepts:**

- `is_square_attacked` costs O(pieces × avg_moves) ≈ ~400 ops per call
  on a full starting board. `legal_moves_from` filters via apply-undo
  loops which multiplies that. Measured: ~24 ms for a 32-playout MCTS
  think on desktop — fine for interactive play, not for competitive
  strength scaling.
- Perft past depth 3 gets slow (minutes at depth 4). Acceptable for a
  parity sanity check; not useful for deep search correctness.

**Revisit when:** AI strength tuning wants ≥1000 playouts per turn and
Phase 6 Android benchmarks show MCTS-per-second as the bottleneck
(rather than NN inference, which currently dominates at ~5 ms/playout).

## See also

- `native/shogi_core/src/board.rs` — the representation.
- `native/shogi_core/src/rules.rs::is_square_attacked` — the hot path.
- `native/shogi_core/src/tests.rs::perft_*` — the benchmark / sanity
  tests.
