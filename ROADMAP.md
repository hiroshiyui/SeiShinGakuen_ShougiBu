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
- **Signing:** debug keystore only; release signing deferred to Phase 7 polish alongside the Play Store story.

### Phase 7 — Polish
- [ ] **Subset Fude Goshirae font.** Ships today as a 40 MB full-CJK OTF, ~18 MB imported into the APK — the single biggest size win available. Only ~15 glyphs are actually rendered (`歩香桂銀金角飛王玉とう杏圭全馬龍`). Approach: a `tools/subset_font.py` wrapper around `pyftsubset` (`pip install fonttools`) that re-runs deterministically, plus `--drop-tables+=FFTM,DSIG,GPOS,GSUB,MATH` to strip unused tables. Expected output: **tens of KB** (a ~30 MB APK shrink). Stretch: migrate piece glyphs to pre-rendered sprite atlas (see sprite task below) and drop the font entirely.
- [ ] **String-scan-driven font subsetting for UI fonts.** Classic console-game / VN pattern: when we vendor a UI font (bigger glyph budget than the brush font's 15 piece kanji), don't hand-curate the character list — derive it mechanically. Two parts:
    - *Centralise user-facing text* in one file (e.g. `scripts/autoload/Strings.gd`) as `const` declarations. Makes the subsetter's input unambiguous and gives us a localisation seam for free.
    - *Scan + subset* script (`tools/build_font_subset.sh`): `grep -oE` the Japanese ranges + ASCII from the strings file, union with an "always include" set (`0-9`, punctuation, any `%d`-injected substitutions), pipe to `pyftsubset --text-file=…`. Re-runs every time the strings file changes.

    Rationale: catches new characters automatically as the UI evolves, without anyone remembering to edit a `--text=` argument. Watch out for runtime-formatted strings — `"… %d手目" % n` only has the literal in source, so digits must be in the always-include set.
- [ ] Move history panel + scrubbing
- [ ] Multi-level undo + resign button
- [ ] Sound: move / capture / promote / check / checkmate
- [ ] Haptic feedback on move
- [ ] Save/resume current game
- [ ] Settings screen (difficulty, sound, piece style)
- [ ] Simple main-menu art & app icon
- [ ] (Stretch) sprite-based pieces as alternative to kanji text
- [ ] (Stretch) 棋譜 KIF export/share intent

---

## 5. Key Technical Decisions & Risks

### Encoding parity (Phase 5 risk)
The 45-plane input and 139-plane move index must byte-match ShogiDojo's
training-time convention, otherwise the model's suggestions are garbage.
Mitigation: fixture-based cross-language tests before wiring MCTS.

### ONNX Runtime on Android
`ort` crate supports Android but requires the ORT Mobile `.so`. APK may grow
~10–30 MB. If unacceptable, fall back to `tract` (pure Rust, smaller, slower).
Decide after Phase 5 benchmark on desktop.

### MCTS on mobile
Single-threaded PUCT with a small net (1.3 MB) should hit hundreds of
playouts/sec on arm64. If not: reduce playouts, add batching, or cache subtree
between turns.

### GDExtension ABI stability
Godot 4.6 GDExtension API is stable; pin `godot` crate version. Rebuild on
any Godot minor bump.

### Rule edge cases
- 千日手 perpetual-check detection (checker loses, not a draw) needs accurate side-to-check tracking
- 入玉 27-point / 24-point variants — pick one and document
- Stalemate is essentially impossible in Shogi (drops) but still handled

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

- [ ] 千日手 perpetual-check rule variant — confirm Japanese professional rules
- [ ] 入玉 point rule — 24 or 27?
- [ ] App icon / branding assets — source or commission?
- [ ] Play Store distribution or sideload only? Affects signing / policy.
- [ ] Any telemetry (crash reporting)? Default: none.

---

*Last updated: 2026-04-22*
