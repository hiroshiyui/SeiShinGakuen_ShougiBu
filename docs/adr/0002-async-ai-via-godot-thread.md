# ADR-0002: Run AI MCTS on a Godot Thread, not a Rust-owned thread

## Status

Accepted.

## Context

MCTS at the default 128 playouts takes ~1-2 s on arm64. That can't
happen on Godot's main thread — the UI would freeze. Two natural
implementations:

1. **Rust-owned worker thread.** `think()` returns immediately,
   spawns a `std::thread`, stores result in an `Arc<Mutex<_>>`. GDScript
   polls `thinking_done()` and `take_best_move()`.
2. **Godot `Thread`.** `ShogiCore::think_best_move` is synchronous;
   GDScript wraps it in a `Thread`, polls `is_alive()` and calls
   `wait_to_finish()` when done.

Both work. Option 1 hides the async detail inside the FFI; Option 2
surfaces it in GDScript.

## Decision

Use Option 2 — Godot's `Thread` class driving a synchronous Rust entry
point.

## Consequences

**Makes easy:**

- ShogiCore state stays plain Rust — no `Arc<Mutex<_>>`, no `Send`
  bound ceremony, no worrying about GodotClass + live thread
  interactions.
- `wait_to_finish()` on Godot's thread returns the `Variant` directly;
  no polling ritual.
- AI thread lifecycle is visible in GDScript code where the rest of the
  scene state lives. Debugging paths stay in one language.

**Makes harder / accepts:**

- GameController must remember to `wait_to_finish()` before scene
  changes (see `_on_quit_confirmed`) or it leaks the `JoinHandle`.
- If we ever want to cancel mid-think, we'd have to push a
  `stop_flag: AtomicBool` into the Rust searcher — the Godot Thread
  API has no interrupt primitive.
- `think_best_move` blocks its caller; calling it from the main thread
  accidentally would still freeze the UI. Documented as "spawn a
  Thread" in the `#[func]` docstring.

## See also

- `scripts/game/GameController.gd` — `_maybe_start_ai_turn`,
  `_run_ai_think`, `_process` polling.
- `native/shogi_core/src/lib.rs` — `think_best_move`.
