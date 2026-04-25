# Architecture

How the pieces fit and why. Audience: a contributor about to modify code.

## Scope

Covers runtime layering, data flow for a single move, and where to
extend. Does *not* cover the training pipeline (that lives in
[ShogiDojo](../../ShogiDojo/)) or Android export mechanics (see
[`android-build.md`](./android-build.md)).

## Invariants

The system must preserve these properties. Every phase of the roadmap
is in service of them.

1. **Rule correctness.** Every applied move must be legal under 本将棋
   rules: geometry, no self-check, 二歩, 打ち歩詰め, must-promote for
   dead pieces. Tested by
   [`native/shogi_core/src/tests.rs`](../native/shogi_core/src/tests.rs)
   and
   [`scripts/tests/rules_tests.gd`](../scripts/tests/rules_tests.gd).
2. **Encoder parity with ShogiDojo.** The 45-plane position tensor and
   139-plane move index must be byte-identical to ShogiDojo's Python
   encoder. If they drift, the model silently predicts wrong moves.
   Verified per commit by
   [`parity_tests.rs`](../native/shogi_core/src/parity_tests.rs)
   against fixtures dumped by
   [`tools/gen_fixtures.py`](../tools/gen_fixtures.py).
3. **Main thread never blocks on AI inference.** MCTS runs on a Godot
   `Thread`; GameController polls `is_alive()` per-frame.
4. **Offline single-APK ship.** No network dependency at runtime. Model
   + fonts + native library are all packed into the APK.

## Layers

```
┌─────────────────────────────────────────────────────────────┐
│ UI  — GDScript                                              │
│      scenes/MainMenu.tscn, scenes/Main.tscn                 │
│      scripts/MainMenu.gd, scripts/game/GameController.gd    │
│      scripts/game/{BoardView,HandView,Square}.gd            │
│      scripts/autoload/Settings.gd (session + save/resume)   │
└────────────────────────┬────────────────────────────────────┘
                         │  FFI: #[godot_api] methods on
                         │  ShogiCore (RefCounted). Moves are
                         │  Dictionary {from, to, promote} or
                         │  {drop_kind, to}.
┌────────────────────────┴────────────────────────────────────┐
│ Native core — Rust (cdylib via gdext 0.2.4)                 │
│      native/shogi_core/src/                                 │
│        lib.rs       ShogiCore class, #[func] API surface    │
│        board.rs     mailbox [Option<Piece>; 81] + hands +   │
│                     reversible LogEntry stack               │
│        movegen.rs   step + ray tables, must-promote pruning │
│        rules.rs     check, legal filter, mate, sennichite,  │
│                     jishogi                                 │
│        sfen.rs      parse + serialize + position_key        │
│        encode.rs    (45,9,9) position tensor                │
│        move_index.rs (139,9,9) move ↔ index                 │
│        nn.rs        tract RunnableModel wrapper             │
│        mcts.rs      single-threaded PUCT + Dirichlet noise  │
└────────────────────────┬────────────────────────────────────┘
                         │  ONNX forward pass, single batch
┌────────────────────────┴────────────────────────────────────┐
│ Model — Bonanza (tract-onnx)                                │
│      models/bonanza.onnx (1.3 MB)                           │
│      Input (1, 45, 9, 9) → policy (1, 139, 9, 9) +          │
│      value (1, 1)                                           │
└─────────────────────────────────────────────────────────────┘
```

Only two hard lines: GDScript ↔ Rust (via gdext FFI) and Rust ↔ ONNX
(via `tract::RunnableModel::run`). Everything inside each layer is free
to refactor.

## Data flow: one move

```
Square._gui_input(touch)                                  — UI tap
  └─> BoardView.square_tapped signal
      └─> GameController._on_board_tapped(file, rank)
          ├─> Rules.legal_moves_from(...) via FFI         — highlight
          │   └─> BoardView.show_move_hints([...])
          └─> (second tap) GameController._handle_board_target
              └─> ShogiCore.apply_move(dict)              — mutate state
                  ├─> Board::apply_board_move / apply_drop
                  └─> tag_last_move(was_check, position_key_after)
              └─> Settings.save_game(sfen)                — persist
              └─> GameController._maybe_start_ai_turn()   — schedule AI
                  └─> Thread.start(core.think_best_move)
                      └─> Searcher::best_move (MCTS loop)
                          ├─> NeuralNet::forward (tract)  — per leaf
                          └─> Rules::legal_moves_from / legal_drops
                      └─> returns best Move dict
                  └─> _process polls is_alive()
                      └─> Thread.wait_to_finish()
                      └─> GameController._commit_move(ai_move)
                          └─> (same path as human commit above)
```

## Extension points

**Where new features are expected to land:**

- **New UI scene** — add `.tscn` under `scenes/`, its script under
  `scripts/`. Wire from MainMenu or add to the VBoxContainer in
  `scenes/Main.tscn`.
- **New Rule** — extend
  [`native/shogi_core/src/rules.rs`](../native/shogi_core/src/rules.rs).
  Add a parity test in `tests.rs`. Do not change `encode.rs` or
  `move_index.rs` — those are pinned to training data format.
- **New ShogiCore API** — add `#[func]` to
  [`lib.rs`](../native/shogi_core/src/lib.rs). Moves cross the boundary
  as `Dictionary` keyed by string; integer `Kind` passes through (our
  `Kind` enum discriminants match GDScript's `Piece.Kind`).
- **Persistent session state** — add to
  [`scripts/autoload/Settings.gd`](../scripts/autoload/Settings.gd) and
  serialise alongside `save_game` / `load_saved_game`.
- **Tuning MCTS** — `C_PUCT`, `DIRICHLET_ALPHA`, `DIRICHLET_WEIGHT` in
  [`mcts.rs`](../native/shogi_core/src/mcts.rs).
- **New UI font** — subset pipeline in
  [`tools/build_font_subsets.py`](../tools/build_font_subsets.py); add
  the `-full.otf` original under `assets/fonts/`, keep the subset under
  the canonical filename. The script re-scans strings automatically.
- **New visual asset (ComfyUI output, illustrations, icons)** — drop
  under the folder that matches its role: `assets/backgrounds/` for
  gutter / full-screen decoration, `assets/ui/` for button/icon art,
  `assets/branding/` for title/splash/logo, `assets/textures/` for
  board or piece surfaces, `assets/characters/{teachers,students}/`
  for 将棋部 character portraits. Name characters kebab-case with
  role-first (`sensei-tanaka.webp`, `student-akira.webp`) so they sort
  naturally. For multi-expression characters, promote to a
  per-character folder (`characters/students/akira/{neutral,thinking,
  happy}.webp`). Prefer `.webp` for AI-generated imagery
  (smaller APK at equivalent quality) — reserve `.png` for pixel-art
  UI with hard edges. Keep source resolution reasonable (≤1024 px long
  edge for UI, ≤2048 px for full-screen backgrounds) since APK size
  grows fast: the current 43 MB is dominated by assets, not code.
  Commit both the image and its Godot-generated `.import` sidecar. If
  an asset is reference / work-in-progress and shouldn't ship, place
  it under a leading-underscore prefix (`assets/_wip/…`) and add the
  pattern to `export_presets.cfg`'s `exclude_filter`, same pattern
  already used for `*-full.otf`.

**Where you should not be adding code:**

- `scripts/game/Piece.gd` — slimmed to a UI-label namespace. Piece
  state lives in Rust.
- `scripts/tests/*` — test harness, not game code. Add parity tests in
  `native/shogi_core/src/tests.rs` or `parity_tests.rs` instead.
- Anything that assumes the AI runs synchronously on the main thread.
