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
│      scenes/MainMenu.tscn, scenes/SettingsScreen.tscn,      │
│      scenes/CharacterPicker.tscn, scenes/Main.tscn,         │
│      scenes/MoveHistoryDialog.tscn (in-game 棋譜),          │
│      scenes/KifuLibrary.tscn + scenes/KifuReviewer.tscn     │
│      (棋譜検討 — saved-game library + replayer)             │
│      scripts/MainMenu.gd, scripts/SettingsScreen.gd,        │
│      scripts/CharacterPicker.gd,                            │
│      scripts/MoveHistoryDialog.gd,                          │
│      scripts/KifuLibrary.gd, scripts/KifuReviewer.gd,       │
│      scripts/game/GameController.gd                         │
│      scripts/game/{BoardView,HandView,Square}.gd            │
│      scripts/autoload/Settings.gd (session + save/resume,   │
│      safe_area_insets, NOTIFICATION_WM_GO_BACK_REQUEST →    │
│      ui_cancel synth)                                       │
│      scripts/autoload/SoundManager.gd                       │
│      scripts/CharacterProfile.gd + .tres data under         │
│      assets/characters/{teachers,students}/                 │
└────────────────────────┬────────────────────────────────────┘
                         │  FFI: #[godot_api] methods on
                         │  ShogiCore (RefCounted). Moves are
                         │  Dictionary {from, to, promote} or
                         │  {drop_kind, to}; packed move log is
                         │  a PackedInt32Array (one i32/move).
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
│        kifu.rs      LogEntry → 棋譜 string + KIF emit /     │
│                     parse + per-move i32 pack/unpack        │
│        encode.rs    (45,9,9) position tensor                │
│        move_index.rs (139,9,9) move ↔ index                 │
│        nn.rs        tract RunnableModel wrapper             │
│        mcts.rs      single-threaded PUCT + Dirichlet noise  │
│                     + top_k_root_children() for analysis    │
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

## Review mode and the kifu library

Two flows render historical positions on the board without disturbing
the live game: the in-game 棋譜 dialog and the standalone 棋譜検討
viewer. Both use the same trick — a *separate* `ShogiCore` instance
plays the role of the renderer's data source.

```
GameController                       KifuReviewer
  ├─ _core            (live)           └─ _core    (private — never live)
  └─ _review_core     (scratch,           apply_packed(prefix) on every
     populated by                         prev/next/first/last tap
     apply_packed(prefix)
     on row-tap)

_active_core() → _review_core if reviewing else _core
                  ^ used by every render; mutations always target _core
```

The packed prefix comes from `kifu::pack_log` — one i32 per move
(drop bit + from sq + to sq + promote flag). `apply_packed` resets to
the starting position and replays each move with sennichite + check
tags, so the scratch core is self-consistent at any ply (legal-move
queries, repetition detection, current-side-to-move all work).

KifuReviewer additionally runs **MCTS analysis** on demand: for each
ply, replay → `suggest_moves_mcts(top_k=32, playouts=128)` →
extract the actual move's q from the search tree → compare against
`top[0].q` → classify as 好手 / neutral / 疑問手 / 悪手 by the delta.
The recommended move (`top[0]`) is rendered to a kifu string while
the scratch core is still at the pre-move position so `piece_at(from)`
returns the right kanji.

KIF on disk uses `kifu::to_kif` (header + per-move lines + 中断) for
export and `kifu::parse_kif` (tolerates Kifu-for-Windows time
annotations + 不成 + 同　 + 中断/投了/詰み terminators) for round-trip
loading. Saved games persist under `OS.SYSTEM_DIR_DOCUMENTS,
shared_storage=false` — see [ADR-0009](./adr/0009-kif-library-app-private-storage.md).

Background on why review mode keeps a separate core instead of
rewinding `_core` in place: [ADR-0008](./adr/0008-review-mode-scratch-core.md).

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
- **New AI opponent character** — author a `.tres` under
  `assets/characters/{teachers,students}/<id>.tres` instantiating
  [`CharacterProfile`](../scripts/CharacterProfile.gd) (`level: 1..8`
  maps to `Settings.LEVEL_PARAMS`'s playouts/temperature pair).
  Drop portraits in the character's `portrait_dir` keyed by expression
  name (`neutral.webp` is required, others fall back to neutral). The
  picker scans the directory at startup via
  `Settings.list_characters()` — no scene edits needed.
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
  for 将棋部 character portraits. Each character is a `.tres`
  ([`CharacterProfile`](../scripts/CharacterProfile.gd)) named
  kebab-case after its `id`
  (`assets/characters/teachers/katou-sensei.tres`,
  `assets/characters/students/nakamura-alice.tres`) plus a sibling
  directory of the same name holding portraits keyed by expression
  (`katou-sensei/neutral.webp`, optionally `thinking.webp`,
  `happy.webp`, etc. — missing files fall back to neutral). Prefer `.webp` for AI-generated imagery
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
