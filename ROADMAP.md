# 清正学園将棋部 — Development Roadmap

A mobile Shogi game for Android, built in Godot 4.6 with a Rust (GDExtension)
native core for move generation, rule enforcement, and AI (ONNX Runtime +
MCTS against the Bonanza policy+value network).

---

## 1. Goals & Non-Goals

### Goals
- Full-rules 本将棋 (standard Shogi) playable on Android phones.
- Single-player vs. AI, using `bonanza.onnx` (policy+value) with MCTS.
- Offline, single APK — no server dependency at runtime.
- Traditional kanji pieces at early stages (sprites later, optional).
- Portrait-first UI; tablet landscape is a stretch goal.

### Non-Goals (for v1)
- Online multiplayer.
- iOS build.
- KIF/CSA game-record import from external sources beyond basic SFEN.
- Multiple AI difficulty levels via separate models (single model, strength
  controlled by MCTS playout budget).

---

## 2. Target Stack

| Layer | Technology |
|---|---|
| Engine | Godot 4.6.2 (Mobile renderer) |
| UI / scenes / input | GDScript |
| Native core | Rust via [`godot-rust` (gdext)](https://github.com/godot-rust/gdext) |
| NN inference | `ort` crate (ONNX Runtime) — fallback: `tract` (pure Rust) |
| Model | `/home/yhh/MyProjects/ShogiDojo/bonanza.onnx` (input `(B,45,9,9)` → policy `(B,139,9,9)` + value `(B,1)`) |
| Desktop dev target | `x86_64-unknown-linux-gnu` |
| Ship target | `aarch64-linux-android` (API 24+) |
| Build | `cargo` for Rust, Godot export templates for APK |

---

## 3. Repository Layout (target)

```
SeiShinGakuen_ShougiBu/
├── project.godot
├── ROADMAP.md
├── icon.svg
├── scenes/
│   ├── main/             # main menu, settings
│   ├── game/             # board scene, HUD, promotion dialog
│   └── components/       # reusable UI (piece, square, hand)
├── scripts/
│   ├── game/             # GDScript game controller, board state, input
│   ├── ui/
│   └── autoload/         # Globals, Settings
├── assets/
│   ├── fonts/            # kanji font for pieces
│   ├── sfx/              # move / capture / promote sounds
│   └── sprites/          # (optional, later) piece art
├── native/
│   └── shogi_core/       # Rust crate → cdylib loaded via GDExtension
│       ├── Cargo.toml
│       └── src/
│           ├── lib.rs    # GDExtension bindings
│           ├── board.rs  # bitboards / square / piece types
│           ├── movegen.rs
│           ├── rules.rs  # check / mate / 二歩 / 打ち歩詰め / 千日手
│           ├── sfen.rs
│           ├── encode.rs # (45,9,9) planes + 139-plane move index
│           ├── mcts.rs
│           └── nn.rs     # ort inference wrapper
├── native/bin/           # built .so / .dll per platform
├── addons/               # .gdextension manifest
├── models/
│   └── bonanza.onnx      # copied from ShogiDojo (checked in or LFS)
└── android/              # export preset, keystore (gitignored)
```

---

## 4. Phase Plan

Each phase ends in a runnable, demoable state. Tag a git commit at the end
of each phase.

### Phase 1 — Board & input skeleton (GDScript) ✅
**Deliverable:** a 9×9 board renders on screen; tapping a square highlights it.

- [x] Create `scenes/game/Board.tscn` with a 9×9 `GridContainer` of `Square` nodes
- [x] `scripts/game/Square.gd` — handles touch, emits `tapped(file, rank)`
- [x] `scripts/game/BoardView.gd` — renders a stub board state (all 40 pieces in starting position, kanji text in `Label`s)
- [x] Portrait camera / layout; test on Android emulator or device
- [x] Piece orientation: 先手 bottom (upright), 後手 top (rotated 180°)
- [x] Pure presentation — no rules yet

**Done when:** starting position displays correctly; taps print coordinates.

Shipped differently: Android on-device test deferred to Phase 6 (portrait viewport configured in `project.godot`; desktop smoke-tested headless only).

### Phase 2 — Movement rules & hands (GDScript) ✅
**Deliverable:** two humans can play a full legal game locally, including
drops and promotion.

- [x] `scripts/game/BoardState.gd` — 9×9 array + two hands (`Dictionary[PieceType,int]`)
- [x] Per-piece move tables (歩 香 桂 銀 金 角 飛 王 + promoted variants)
- [x] Sliding piece ray logic (角 飛 香 and promoted 馬 龍)
- [x] Tap-to-select → highlight legal destinations → tap-to-move
- [x] Capture: move piece to hand (un-promoted)
- [x] Drop flow: tap piece in 駒台 → highlight legal drop squares → tap to drop
- [x] Promotion: when crossing the promotion zone, prompt dialog (must-promote for 歩/香 last rank, 桂 last two)
- [x] SFEN export (for debugging; read-only first)
- [x] Turn management, move log to console

**Done when:** can play a complete game to checkmate without violating movement rules.

### Phase 3 — Full rule enforcement (GDScript) ✅
**Deliverable:** all illegal moves are refused; game ends correctly.

- [x] `is_check(side)` using reverse-attack lookup from king square
- [x] Legal-move filter: no move may leave own king in check
- [x] 二歩 (nifu): cannot drop 歩 on a file that already has own unpromoted 歩
- [x] 打ち歩詰め (uchifuzume): cannot deliver mate with a dropped 歩
- [x] Checkmate / stalemate detection → game-over screen
- [x] 千日手 (sennichite): track position history by hashed SFEN; draw after 4-fold (perpetual-check variant = loss for checker)
- [x] 入玉 / 持将棋 (entering-king / impasse) — 27-point rule, basic handling
- [x] Undo last move (single-level) for convenience

**Done when:** the engine cannot be tricked into an illegal state; verified with a test suite of SFEN fixtures.

Shipped differently:
- 入玉 is detection-only (`Rules.king_entered` + `Rules.jishogi_points`). No in-game claim button yet; deferred to Phase 7 polish along with a resign button.
- Test harness is pure GDScript headless (`scripts/tests/rules_tests.gd` runnable via `godot --headless -s`) rather than a SFEN-import-driven fixture set — fixtures are constructed programmatically through `BoardState.clear_board() / place() / set_hand_count() / set_side_to_move() / seal_initial_position()`.

### Phase 4 — Rust core (GDExtension), desktop only ✅
**Deliverable:** move gen + rule checks run in Rust; GDScript calls into it.
Game still plays identically — this is a refactor, not a feature.

- [x] `native/shogi_core/` Cargo crate, `cdylib`, `godot` dep (gdext)
- [x] `addons/shogi_core.gdextension` manifest
- [x] Desktop linux build via `cargo build --release`; copy `.so` to `native/bin/linux/x86_64/`
- [x] Port types: `Piece`, `Color`, `Square`, `Move`, `Board`, `Hands`
- [x] Port move generation (bitboards preferred; start with mailbox if faster to write)
- [x] Port legality + special rules (二歩, 打ち歩詰め, check)
- [x] SFEN parse/serialize
- [x] Expose `ShogiCore` class to GDScript with:
  - `load_sfen(s)`, `to_sfen()`
  - `legal_moves() -> PackedArray`
  - `apply_move(m)`, `undo()`
  - `is_check()`, `is_checkmate()`, `result()`
- [x] Replace GDScript rule code with calls into native
- [x] Rust unit tests for rules (perft on known positions)

**Done when:** `cargo test` passes perft suite; in-game behavior matches Phase 3.

Shipped differently:
- Rust edition 2024 (requires rustc ≥ 1.85; repo's 1.93 is fine).
- godot-rust crate pinned at `0.2.4`; `.gdextension` declares `compatibility_minimum = 4.3` which works against Godot 4.6.
- Representation is mailbox (`[Option<Piece>; 81]`) rather than bitboards — fast enough for interactive play; revisit if Phase 5 MCTS benchmarks demand it.
- SFEN parser is not yet implemented (only serializer + `position_key`). Import will land with Phase 5 when the AI wants to round-trip positions.
- Exposed API is superset of the target shape (adds `clear_board / place / set_hand_count / set_side_to_move_gote / seal_initial_position` for test setup and a future editor; `legal_moves` is split into `legal_moves_from(file, rank)` + `legal_drops(kind)` matching the tap-driven UI flow).
- Perft suite verifies depth 1 (30) and depth 2 (900) from the starting position; deeper fixtures deferred until AI strength tuning needs them.

### Phase 5 — AI: ONNX + MCTS (desktop) ✅
**Deliverable:** playable vs. AI on desktop; configurable playout budget.

- [x] Add `ort` dep; bundle `models/bonanza.onnx`
- [x] `encode.rs`: implement the exact 45-plane board encoding used in ShogiDojo (verify against Python by diffing a tensor on a known SFEN)
- [x] Implement the 139-plane move index (match ShogiDojo's convention)
- [x] `nn.rs`: load session, run `(45,9,9) → (policy_logits, value)`
- [x] `mcts.rs`: PUCT MCTS with Dirichlet noise at root, virtual loss optional, single-threaded first
- [x] Expose `think(ms|playouts) -> best_move` to GDScript
- [x] Main-menu mode select: Human vs Human / Human (sente) vs AI / Human (gote) vs AI
- [x] Settings: playout count (128 / 400 / 1600), temperature
- [x] Thinking runs on Rust thread; GDScript shows spinner, awaits via signal

**Done when:** AI plays legal moves, beats a random-mover consistently, and responds within ~2s at default budget.

**Encoding-parity test (critical):** a small Python script in `tools/` dumps `(planes, policy_index)` for 20 diverse SFENs using ShogiDojo's code; Rust test loads the same SFENs and asserts byte-exact match.

Shipped differently:
- **Inference runtime is `tract`, not `ort`.** `ort` rc builds had a TLS-config regression and the v2 ep-vitis bindings mismatch against the sys crate across rc.10/rc.11/rc.12, costing hours of toolchain pain for a 1.3 MB model. `tract-onnx` is pure-Rust, statically links with no shared-lib dependency, loads the Bonanza model identically, and makes Phase 6 cross-compilation trivial. Inference cost: ~5 ms per forward pass on desktop. Revisit `ort` only if Phase 6 arm64 throughput is inadequate.
- **Fixture set is 13 SFENs**, not 20 — `tools/gen_fixtures.py` uses ShogiDojo's actual `encode_position` / `encode_move`. Tested on starting position (both colours-to-move), 8 mid-opening positions, a promoted-pieces-with-hand case, an edge-rank lance, and two kings-in-corners. All produce byte-exact tensor and u32-exact move-index output.
- **Temperature knob is not exposed yet** — MCTS currently always picks the most-visited root move. Sampling with a temperature is a one-line change in `Searcher::best_move`; defer until AI-strength tuning surfaces a need.
- **Async thinking runs on a Godot `Thread`**, not a Rust-owned thread. `ShogiCore::think_best_move` is synchronous; GameController spawns a `Thread` for it and polls `is_alive()` / `wait_to_finish()` in `_process`. Simpler than managing Rust threads across the FFI boundary.
- **Model path is dev-only at `res://models/bonanza.onnx`.** Android (Phase 6) will need to extract from the PCK into `user://` at first launch before `load_model` can reach it.

### Phase 6 — Android build ✅
**Deliverable:** signed APK runs on device, AI works offline.

- [x] Install Android NDK, Godot Android export templates
- [x] Add `aarch64-linux-android` Rust target; `cargo-ndk` or manual `--target`
- [x] Build `libshogi_core.so` for arm64-v8a; place in `native/bin/android/arm64-v8a/`
- [x] Update `.gdextension` manifest with Android entry
- [x] ~~`ort` Android feature: pull ONNX Runtime Mobile AAR~~ — obsolete, replaced by `tract` in Phase 5 (pure-Rust, no shared-lib plumbing on Android)
- [x] Godot Android export preset; min SDK 24, target SDK 34
- [x] Add signing config (debug keystore first)
- [x] Test on physical device: APK size, first-move latency, battery
- [x] Portrait-lock in manifest

**Done when:** APK installs, game plays a full match vs. AI on a mid-range phone with <3s thinking time per move.

Shipped differently:
- NDK 28.1 via `cargo-ndk --platform 24 -t arm64-v8a`. Build doc at `docs/android-build.md`.
- APK size: **58 MB**, dominated by `libgodot_android.so` (74 MB raw → compressed), `libshogi_core.so` (14 MB, tract-embedded), and the Fude Goshirae font (18 MB imported). Font-subsetting is the biggest remaining win.
- **Model packaging:** `bonanza.onnx` is *not* a Godot-recognised resource type, so the default `all_resources` export filter silently dropped it. Export preset now carries `include_filter="*.onnx"`. On first launch `Settings.model_absolute_path()` copies it from `res://` to `user://` (tract mmaps the OS path; it can't open files that live inside the PCK).
- **Portrait lock:** Godot 4.6's Android export reads `display/window/handheld/orientation` as an `int`, not a string — leaving it as `"portrait"` silently falls back to `0` (landscape). Must be `1`.
- **Touch input:** `emulate_mouse_from_touch` (default `true`) fires both an `InputEventScreenTouch` and an `InputEventMouseButton` per tap, so naive `_gui_input` handlers fire twice and the second tap deselects the first. Square now dispatches on `OS.has_feature("mobile")` — mobile listens to touch only, desktop to mouse only.
- **Layout auto-fit:** board side is computed at runtime from the viewport (`min(vw - 40, vh - reserved)`), clamped `[240, 1600]`, and re-fit on every `size_changed`. Status label was slimmed to `(N手目)` to kill the text-width feedback loop that was nudging the board off-centre each move.
- **Signing:** debug keystore only; release signing deferred to Phase 7 polish alongside the GitHub Releases / sideload story.

### Phase 7 — Polish
- [x] **Subset Fude Goshirae piece font + scan-driven subsetting for the UI font.** Both done in `tools/build_font_subsets.py`. Piece font is subset to 15 fixed glyphs; Noto Serif JP Medium + Bold are subset against all Japanese characters grep'd from `scripts/` + `scenes/` plus an always-include ASCII range (`0020-007E`) and a safety set for runtime-injected glyphs (digits, `→`, `×`, Japanese punctuation). Re-run after editing UI strings.

    Results: Fude Goshirae 39 MB → 175 KB; Noto Medium 24 MB → 79 KB; Noto Bold 25 MB → 79 KB. APK dropped from 103 MB to **42 MB** (the other fat items are `libgodot_android.so` and `libshogi_core.so` which are already at release/strip settings).

    Originals live in repo under `assets/fonts/**/*-full.otf`, excluded from the APK by `export_presets.cfg`'s `exclude_filter="*-full.otf"`. Script reads from `-full.otf` and writes to the canonical filename referenced by `assets/themes/ui.tres` and `scripts/game/Square.gd`.

    Watch-out: runtime-formatted strings (`"… %d手目" % n`) only have the literal in source, so digits are in the safety set. Add new characters there if future UI gets them via code rather than literals.

    Pieces now render procedurally (pentagonal wooden tiles, see below) so a sprite-atlas migration is no longer needed to move past the flat-Label look. Could still be pursued as a theming option — no longer tracked as a stretch goal.
- [x] **投了 (resign) button with confirmation dialog, returns to main menu.** `scenes/Main.tscn::ExitButton + QuitDialog`, `GameController._on_exit_pressed / _on_quit_confirmed`. Waits for any live AI Thread via `wait_to_finish()` before scene change to avoid leaked JoinHandles.
- [x] **Multi-level undo.** Underlying `Board::undo_move` stack is unbounded; GameController's 待った button pops one entry per press. No explicit "undo N" UI, but pressing repeatedly rewinds indefinitely.
- [x] **Haptic feedback on move.** `Input.vibrate_handheld(50)` in `GameController._commit_move`, gated by `OS.has_feature("mobile")`. Fires for both human and AI moves so the phone bumps when the AI replies.
- [x] **Save / resume current game.** `Settings.save_game(sfen)` after every commit, `clear_saved_game()` on checkmate / sennichite / 投了 / 新規対局. MainMenu shows 続きから when `has_saved_game()` is true. ConfigFile at `user://saved_game.cfg`. Caveat: `move_log` + `position_counts` aren't serialised — sennichite tracking resets on resume, board state round-trips fine.
- [x] **Last-move highlight.** Blue-tinted `LastMoveHint` overlay on the from + to squares of the most recent applied move, so the player can spot what the AI just did at a glance. Drops highlight only the to-square.
- [x] **Wooden board + pentagonal piece rendering.** Custom `_draw()`-based board background (grid, hoshi) in `BoardBackground.gd` and pentagonal shogi-piece shapes with thickness, bevel, top-left highlight and soft drop shadow in `PieceView.gd`. Hand area gets a Koma-dai panel and tile-style pieces via `HandPiece.gd`. Still uses Fude Goshirae for the kanji glyph.
- [x] **Real wood textures + 4% traditional board margin.** PNG Kaya textures (`assets/textures/shogi-ban-wood-texture.png`, `shogi-piece-wood-texture.png`) replace the procedural grain. Board inset is 4% on every side, mirroring the physical 将棋盤's border; `BoardView` wraps its 9×9 `GridContainer` in a `MarginContainer` that tracks the same inset at runtime so squares align with the painted grid lines. Each piece samples a random sub-rect of the piece-wood texture and UV-maps it onto the pentagonal polygon, so no two pieces have the same grain. Procedural palette remains as a fallback if the texture files go missing.
- [x] **Sound: move / capture / promote / check / checkmate.** Procedurally-generated WAVs in `assets/sounds/` (wood-impact synth for moves, Koto/Shamisen instrumental cues for the rest) played by `SoundManager` autoload. `GameController._commit_move` picks the highest-priority cue (checkmate > check > promote > capture > plain move). `tools/gen_sounds.py` regenerates them.
- [x] **Character picker — fighter-game-style opponent gallery + in-game portrait strip.** `scenes/CharacterPicker.tscn` replaces the original Lv 1〜8 dropdown with a dedicated picker screen: top half shows the highlighted character's 肖像画 + 名前 + Lv + 強さラベル + 紹介, bottom half is a 4×2 grid of cards (portrait thumbnail + Lv + name) with a gold-bordered selection cue, a tap-to-confirm shortcut, and 戻る / 決定 buttons. Each character is a `CharacterProfile` `.tres` under `assets/characters/{teachers,students}/` with a `level: int` field that maps the choice to `Settings.ai_level`. The 8-character cast: 佐藤竜太郎 (Lv 1, 加藤師範の甥っ子) / 鈴木すず (Lv 2, 副部長) / 高橋ゆり子 (Lv 3, 1年生・呉服店の娘) / 伊藤明 (Lv 4, 元部長・自作 AI を夢見る) / 中村アリス (Lv 5, 部長・冷ややか) / テリー・クラーク (Lv 6, 主将・海外からの転入生) / 吉田なな (Lv 7, 顧問・元プロ志望) / 加藤よしこ (Lv 8, 師範・元プロ棋士). In-game, `Main.tscn::OpponentStrip` renders a 64×64 rounded-corner avatar (rounded via `assets/shaders/rounded_corners.gdshader`) next to the opponent name above the board. AI characters can later gain `thinking.webp / happy.webp / worried.webp` to react in-game — the schema already supports it.
- [x] **App icon + main-menu art.** Adaptive Android launcher icons under `assets/branding/` (192px + 432px foreground, classroom shogi-board crop), wired through `export_presets.cfg`. Main menu uses `assets/backgrounds/main_title_bg.webp`; in-game uses `assets/backgrounds/in_game_bg.webp`. Both AI-generated, in-repo.
- [ ] Move history panel + scrubbing
- [ ] Settings screen — sound on/off, piece style. Difficulty is now shipped via the character picker above; the remaining sub-items are independent.
- [ ] (Stretch) 棋譜 KIF export/share intent

---

## 5. Key Technical Decisions & Risks

### Encoding parity (resolved)
The 45-plane input and 139-plane move index are byte-identical to
ShogiDojo's Python encoder across 13 fixture SFENs. Guarded by
`native/shogi_core/src/parity_tests.rs`; fixtures regenerated via
`tools/gen_fixtures.py`. Any change to `encode.rs` or `move_index.rs`
must re-pass these tests before landing.

### ONNX Runtime on Android (resolved → tract)
We shipped `tract-onnx` instead of `ort`. Rationale and trade-offs in
[ADR-0001](./docs/adr/0001-onnx-runtime-tract.md). Revisit only if
arm64 per-forward-pass throughput becomes the MCTS bottleneck
(currently ~5 ms, well within the interactive budget).

### MCTS throughput (monitored)
Single-threaded PUCT measured at 32 playouts / ~24 ms on desktop. 128
playouts — the default — is real-time. Higher budgets (400, 1600) are
exposed in the menu but untuned. Playouts/sec on arm64 is the next
thing to benchmark when we tune difficulty.

### GDExtension ABI stability
`godot = "0.2.4"` pinned in `native/shogi_core/Cargo.toml`. Godot 4.6
GDExtension API is stable across 4.6.x; rebuild on any Godot minor
bump. `.gdextension` manifest declares `compatibility_minimum = 4.3`.

### Rule edge cases
- 千日手 perpetual-check: detected in
  [`Rules::detect_sennichite`](./native/shogi_core/src/rules.rs).
  Tagging each move with `was_check` + `position_key_after` lets us
  distinguish a plain 4-fold draw from a perpetual-check loss for the
  checker.
- 入玉: ships as detection-only (`Rules::king_entered` +
  `Rules::jishogi_points`, 27-point rule). A player-triggered "claim"
  button is still an open question below.
- Stalemate is effectively impossible in Shogi (hand drops), but
  `has_any_legal_move` handles the corner case for free.

---

## 6. Testing Strategy

- **Rust unit tests:** perft on starting + tactical positions against known counts
- **Rust encoding tests:** fixture-diff vs. Python (ShogiDojo)
- **GDScript scene tests:** manual checklist per phase
- **End-to-end:** 10-game AI-vs-random smoke test script
- **Device testing:** at least one physical Android device each phase ≥ 6

---

## 7. Milestones & Tagging

| Tag | Content |
|---|---|
| `v0.1-board` | End of Phase 1 |
| `v0.2-rules-gd` | End of Phase 3 (full rules, GDScript) |
| `v0.3-rust-core` | End of Phase 4 |
| `v0.4-ai-desktop` | End of Phase 5 |
| `v0.5-android` | End of Phase 6 — first shippable APK |
| `v1.0` | End of Phase 7 |

---

## 8. Open Questions

- [x] ~~千日手 perpetual-check rule variant — confirm Japanese professional rules~~ — implemented as "checker loses", 4-fold detection in `Rules::detect_sennichite`. 2026-04-22.
- [x] ~~入玉 point rule — 24 or 27?~~ — 27. `Rules::jishogi_points`. 2026-04-22.
- [ ] In-game 入玉 claim button (currently detection-only).
- [x] ~~App icon + main-menu art — source or commission?~~ — AI-generated in-house, both icon (`assets/branding/`) and backgrounds (`assets/backgrounds/`) plus the 8 character portraits (`assets/characters/**/neutral.webp`). 2026-04-27.
- [x] ~~Cloud save / cross-device persistence?~~ — explicitly skipped to stay free of Google Play services dependencies. Players who uninstall lose `user://prefs.cfg` + `user://saved_game.cfg`; that's the trade-off. 2026-04-27.
- [x] ~~Play Store distribution or sideload only?~~ — sideload only via signed APK on GitHub Releases. Play Store is explicitly out of scope; we don't want the Google Play ecosystem dependencies (developer account, policy compliance, mandatory privacy URL, upload-key custody) for a single-player offline game. AAB target left in `tools/build_all.sh --aab` for completeness but unused. 2026-04-27.
- [ ] Any telemetry (crash reporting)? Default: none.
- [ ] UI string centralisation (e.g. `Strings.gd`) — currently strings live inline. Deferred until we internationalise or until the font subsetter's grep becomes unwieldy.

---

*Last updated: 2026-04-27*
