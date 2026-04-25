---
name: code-review-and-security-audit
description: Review code for quality, correctness, and security vulnerabilities across the GDScript / Rust GDExtension / FFI surface. Use when the user asks to review code, audit for security issues, or check for bugs and anti-patterns.
argument-hint: file path, component name, or scope of review
---

# Code Review and Security Audit

You are performing code review and security auditing for **清正学園将棋部** (SeiShinGakuen_ShougiBu) — a single-player Android Shogi game built with Godot 4.6.2 (GDScript / scenes / Mobile renderer) on top of a Rust GDExtension (`native/shogi_core/`) that owns rules, position encoding, MCTS, and on-device ONNX inference via the `tract` crate.

## Scope

Two complementary concerns:

1. **Code Review** — correctness, readability, maintainability, adherence to project conventions.
2. **Security Audit** — vulnerabilities, unsafe patterns, attack surfaces. The threat model is narrow (no network, no untrusted input from third parties), but it isn't empty — see "Threat model" below.

## Project context

Read this before assuming anything. The project's surface differs sharply from a typical Android app.

- **Two layers, narrow FFI.** GDScript (`scripts/`, `scenes/`) owns UI, input, the scene graph, turn orchestration, and the MCTS `Thread`. Rust (`native/shogi_core/`) owns board state, rule enforcement, encoder, move index, MCTS, NN inference. Cross only via the `#[func]`s in [`native/shogi_core/src/lib.rs`](../../native/shogi_core/src/lib.rs).
- **Same `.so` desktop + Android** — `x86_64-unknown-linux-gnu` for dev, `aarch64-linux-android` shipped in the APK. Built via [`tools/build_all.sh`](../../tools/build_all.sh).
- **No network.** All inference is on-device via `tract` against [`models/bonanza.onnx`](../../models/bonanza.onnx) (1.3 MB). On Android, the model is extracted from the APK to `user://` on first launch (`Settings.model_absolute_path()`).
- **No untrusted document parsing.** No SAF, no Storage, no EPUBs, no biometric. Persistence is two `ConfigFile`s under `user://` (`prefs.cfg`, `saved_game.cfg`).
- **MCTS runs on a worker thread.** GDScript's `Thread` calls into Rust; the AI's `&mut Board` is shared *only* with that worker. The main thread must not call `_core.*` while the worker is alive — `_thinking` / `_teacher_thinking` flags are the gate.
- **Encoder byte-parity is load-bearing.** `native/shogi_core/src/encode.rs` (45 planes) and `native/shogi_core/src/move_index.rs` (139 planes) are byte-parity-tested against ShogiDojo's Python reference via `tools/gen_fixtures.py` → `native/shogi_core/src/parity_tests.rs`. Encoding drift = AI plays garbage with no error. **Treat any change here as Critical until parity tests pass.**

## Threat model

The app accepts no third-party content over the network and has no IPC surface beyond what Godot's Android template provides. Real risks worth auditing:

1. **Encoder drift.** Silent — won't crash, won't log, just produces an AI that plays nonsense. Caught only by `cargo test`.
2. **`undo_move` / `apply_move` desync.** The board log must round-trip exactly; an `undo_move` that doesn't perfectly reverse a capture corrupts hand counts. MCTS calls these millions of times, so any divergence accumulates.
3. **Cross-thread access to `_core`.** GDScript main thread reading `_core.hand()` / `_core.piece_at()` while Rust worker holds `&mut self.board` is a data race. godot-rust may panic, return defaults, or worse depending on the version. The `_thinking` flag is the only thing keeping us safe — review any new code path that touches `_core` for whether it's gated.
4. **Saved-game tampering.** `user://saved_game.cfg` is user-writable and gets fed back through `_core.load_sfen(...)` on resume. A malformed SFEN must not crash the app.
5. **Settings / prefs corruption.** Same — corrupt `prefs.cfg` shouldn't brick the title screen.
6. **Android `tract` model extraction.** On first launch, the bundled `bonanza.onnx` is copied from the APK to `user://`. Audit that the destination is canonicalised under `user://`, the source path is bundled (not user-provided), and partial copies don't get used (atomic write).
7. **Resource leakage / leaks.** `Thread.start()` + `wait_to_finish()` discipline; tween / timer leakage when scenes change.

Things you **don't** need to audit (don't waste time):

- WebView / JavaScript bridge — none.
- JNI hand-rolled buffer handling — none.
- SAF / persistable URI permissions — not used.
- Biometric flow / private space — not in this project.
- Network TLS / cleartext config — no network.

## Review Checklist

### GDScript side (Godot 4.6 / Mobile renderer)

- **Thread safety with `_core`.** Any new call to `_core.*` from the main thread must be gated by checking `_thinking` and `_teacher_thinking` (or by being outside `_process` / signal handlers that can fire mid-search). The pattern `_thinking = true` before `Thread.start(...)` and clearing it on completion is non-negotiable.
- **Thread cleanup on scene change.** `_back_to_title()` / `_on_quit_confirmed()` must `wait_to_finish()` live worker threads before `change_scene_to_file`. Abandoning a `Thread` JoinHandle leaks.
- **Tween lifetime.** Tweens started in a scene must either complete before the scene tears down or be `kill()`'d. Look for `Tween` saved as a member var (e.g. `_suggestions_tween`, `_board_resize_tween`) — every restart must `kill()` the previous one to avoid double-tween fights.
- **`await` discipline.** Functions that contain `await` are coroutines; calling without `await` (fire-and-forget) is fine for animation chains but the body resumes asynchronously. Guard with `is_inside_tree()` after awaiting if the scene could tear down during the wait (see `_zoom_back_after_slide`).
- **`call_deferred` for layout reads.** `_refit_board` reads `_suggestions_panel.size.y` — only valid after layout has run for the current frame. New code reading sibling Control sizes should defer.
- **`unique_name_in_owner` references.** `@onready var _foo = %Foo` returns `null` if the node doesn't exist; always null-check before dereferencing if the node is conditional (see how `_opponent_label` is used).
- **Auto-save consistency.** `Settings.save_game(_core.to_sfen())` is called after every committed move. Don't move it under a conditional that might skip on certain move types — saved-game / live-board divergence is the kind of bug that surfaces only on resume.
- **Input gating.** `_on_board_tapped` / `_on_hand_tapped` must early-return on `_game_over` and `_thinking`, and skip when `Settings.side_is_ai(_core.side_to_move_gote())` is true. Each new input handler needs the same check.
- **Font subset coverage.** New Japanese strings in `scripts/` or `scenes/` are scanned by [`tools/build_font_subsets.py`](../../tools/build_font_subsets.py) and added to the Noto Serif JP subset. The scanner is codepoint-based (Python `re.findall`) so the historic GNU-grep / locale issue can't recur — but if a new font is added, audit its scan path the same way.
- **Naming**: snake_case for vars / functions, PascalCase for class names, ALL_CAPS for constants. Existing code is consistent — flag drift.

### Rust side (`native/shogi_core/`)

- **No `unsafe` without a paragraph of justification.** None today. Adding any deserves a code-review eyeball and an inline rationale, not just a `// SAFETY:` token.
- **Borrow safety across the FFI.** godot-rust's `Gd<T>` / `WithBaseField` machinery enforces single-mut at runtime; if a `#[func]` takes `&mut self`, GDScript must not call other `&self` methods on the same instance from a different thread. Review any new `#[func]` for whether it stays internally consistent (e.g. `suggest_moves_mcts` runs MCTS internally; `hand` only reads).
- **Encoder + move-index changes.** [`encode.rs`](../../native/shogi_core/src/encode.rs) and [`move_index.rs`](../../native/shogi_core/src/move_index.rs) are byte-parity-tested. Any diff here must be paired with regenerated fixtures (`tools/gen_fixtures.py`) and a passing `cargo test`. **Reject** the change otherwise.
- **`apply_move` / `undo_move` symmetry.** Every state mutation `apply_move` performs (square, hand, side-to-move, log, position counts) must be perfectly reversed by `undo_move`. MCTS pushes thousands of (apply, undo) cycles per playout — a 1-in-1000 desync still shows up.
- **MCTS sign convention.** `Searcher::playout` flips `v = -v` up the path; child Q values are stored from the *child's* STM perspective and negated when read by the parent. New traversal code (e.g. `top_k_root_children`) must match this convention exactly. The `select_child` function is the canonical reference for sign handling.
- **Terminal handling.** `nodes[idx].terminal_value` short-circuits expansion. New backup logic must respect it; double-counting a terminal causes the search to over-prefer or under-prefer mating lines.
- **Allocation discipline.** `Searcher::nodes` is a `Vec<Node>` arena. Long searches grow it monotonically; that's intentional. Don't introduce per-playout heap allocations.
- **Error paths.** `nn.forward(...)` returns `Result`; failures are swallowed (`Err(_) => 0.0`) so a transient inference error doesn't kill a playout. Don't escalate these to panics — the search is best-effort.
- **`#[func]` boundary contracts.** Methods that GDScript calls must (a) accept Godot-native types (`i64`, `f64`, `Variant`, `Array`, `Dictionary`) on the boundary, (b) handle "no model loaded" via `godot_warn!` + a sensible fallback (empty Array, `Variant::nil()`), (c) never panic on a recoverable input.

### FFI / cross-language hazards

- **Move dictionaries.** Board moves carry `from`, `to`, `promote`; drops carry `drop_kind`, `to`. Code that constructs or consumes moves must check `m.has("drop_kind")` first — e.g. animation skipping for drops in `_commit_move`. New Move-dict consumers need the same branching.
- **Vector2i conversions.** GDScript `Vector2i(file, rank)` ↔ Rust `Square::new(file, rank)`. `file` ∈ `1..=9`, `rank` ∈ `1..=9`. Rust `Square::new` panics on out-of-range — flag any `Variant`-decoded square that wasn't bounds-checked first.
- **`Array<Dictionary>` shape stability.** `legal_moves_from`, `legal_drops`, `suggest_moves`, `suggest_moves_mcts` all return arrays of move dicts. Adding fields is fine; renaming or removing fields is a breaking change for every GDScript call site. Audit consumers when changing the shape.

### Persistence

- **`Settings.save_game` / `load_saved_game`.** The format is `[game] sfen, mode, level`. Older saves wrote `playouts`; the loader falls back to current `ai_level` if `level` is missing. Any further format change needs a similar fallback or saves from older versions break on resume.
- **Malformed SFEN on resume.** `_core.load_sfen(saved.sfen)` returns `false` on parse failure; `GameController._ready` already handles this with a `push_warning` and falls back to the starting position. Preserve that fallback.
- **`prefs.cfg` corruption.** `Settings._load_prefs` already tolerates a missing/corrupt file (the `cfg.load(...) != OK` branch). New prefs must follow the same `cfg.get_value(section, key, default)` pattern; never assume a key exists.
- **First-launch model extraction (Android).** `Settings.model_absolute_path()` copies `bonanza.onnx` from `res://` to `user://` on first launch. Audit any change there for: bundled-source path validation, atomic write (write-then-rename to avoid using a partial copy), and idempotence on repeat runs (already handled via `FileAccess.file_exists(user_path)`).

### Build / packaging

- **`.android-release-pass`** must stay gitignored. If a commit ever stages it, that's Critical — the password leaks to the upstream remote. Treat any matching path in a diff as a hard stop.
- **Keystores** (`*.keystore`, `*.jks`) gitignored at repo root. Same hard stop.
- **`assets/fonts/**/*-full.otf`** are vendored sources, excluded from APK by `export_presets.cfg`'s `exclude_filter`. Confirm the filter still excludes them after any rename.
- **`gradle_build/use_gradle_build` / `gradle_build/export_format`** are toggled by `tools/build_all.sh --aab` and restored via `trap`. Any commit that leaves `use_gradle_build=true` in the working tree is a script bug.
- **Encoder fixtures**. `tools/gen_fixtures.py` writes into `tools/fixtures/` (or wherever the parity tests read from). Review changes here together with `parity_tests.rs`.

### Android-specific

- **Orientation** is locked to portrait; Android reports orientation as an int (see `docs/android-gotchas.md`).
- **Touch double-fire.** Some input handlers in `Square.gd` / `HandPiece.gd` already guard against `InputEventScreenTouch` + `InputEventMouseButton` both firing on Android. New input handlers must handle both branches consistently.
- **`include_filter="*.onnx"`.** The model is included via the export preset's `include_filter`; if a new model is added, the filter needs updating.
- **Adaptive icons.** `assets/branding/icon_launcher_{192,432}.png` ship via `export_presets.cfg`'s `launcher_icons/*`. Adding a monochrome variant later means another file + another preset entry.
- **Safe-area insets.** `_apply_safe_area` reads `DisplayServer.get_display_safe_area()` and only applies vertical insets (horizontal cutouts cause off-centre layout in portrait). New layout code that reads safe area should follow the same pattern.

### Code smells worth flagging

- Long GDScript functions doing scene mutation + state transition + IO together — split.
- `await` chains in `_process` (fine, but make sure `_thinking` / re-entrancy is handled).
- Magic numbers in animation code — current files use named constants (`_SUGGESTIONS_FADE`, `_BOARD_RESIZE_DURATION`); new tween durations should follow the pattern.
- Duplicate piece-rendering logic across `Square` / `HandPiece` / `PieceView` — consolidate when the duplication has real behaviour, not just shape.
- Mixing layout reads (`size.y`) and layout writes (`custom_minimum_size`) within the same frame — defer reads via `call_deferred` so layout has had a frame to settle.

## Output Format

Report findings using this structure:

### Critical / High

Issues that must be fixed — encoder fixture drift, FFI thread races, `apply/undo` desync, signing-secret leakage, malformed-SFEN crash on resume.

### Medium

Logic bugs, recomposition / re-render hazards, missing error fallbacks, leak risks (tweens / threads).

### Low / Informational

Style, readability, refactor opportunities, missing comments where the *why* would be non-obvious.

For each finding, include:
- **File and line number** as a clickable link (e.g. [GameController.gd:172](../../scripts/game/GameController.gd#L172)).
- **Description** of the issue.
- **Impact** — what could go wrong, and when (cold start? mid-search? on resume?).
- **Recommendation** — how to fix it, with a code sketch when useful.

## How to Run

When invoked without arguments, review recently changed files:

```bash
git diff --name-only HEAD~5
```

When invoked with a specific scope (file, directory, or component name), focus there.

For a full audit, systematically review in this order (highest-risk first):

1. **Encoder + move index** — [`native/shogi_core/src/encode.rs`](../../native/shogi_core/src/encode.rs), [`move_index.rs`](../../native/shogi_core/src/move_index.rs), [`parity_tests.rs`](../../native/shogi_core/src/parity_tests.rs). Run `cargo test --manifest-path native/shogi_core/Cargo.toml` first; if it fails, that's the only finding that matters.
2. **Board state machine** — [`native/shogi_core/src/board.rs`](../../native/shogi_core/src/board.rs), focusing on `apply_move` / `undo_move` symmetry.
3. **MCTS** — [`native/shogi_core/src/mcts.rs`](../../native/shogi_core/src/mcts.rs), focusing on `playout` / `select_child` / `top_k_root_children` sign discipline and Dirichlet root noise.
4. **FFI surface** — [`native/shogi_core/src/lib.rs`](../../native/shogi_core/src/lib.rs), every `#[func]`.
5. **Turn orchestration / threading** — [`scripts/game/GameController.gd`](../../scripts/game/GameController.gd), focusing on `_thinking` / `_teacher_thinking` gating around `_core.*` calls and `Thread` cleanup paths.
6. **Persistence** — [`scripts/autoload/Settings.gd`](../../scripts/autoload/Settings.gd) (`save_game`, `load_saved_game`, `_load_prefs`, `model_absolute_path`).
7. **Build / signing pipeline** — [`tools/build_all.sh`](../../tools/build_all.sh), [`export_presets.cfg`](../../export_presets.cfg), `.gitignore` (any signing material drift).

## Task: $ARGUMENTS
