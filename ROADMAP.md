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

### Phase 2 — Movement rules & hands (GDScript)
**Deliverable:** two humans can play a full legal game locally, including
drops and promotion.

- [ ] `scripts/game/BoardState.gd` — 9×9 array + two hands (`Dictionary[PieceType,int]`)
- [ ] Per-piece move tables (歩 香 桂 銀 金 角 飛 王 + promoted variants)
- [ ] Sliding piece ray logic (角 飛 香 and promoted 馬 龍)
- [ ] Tap-to-select → highlight legal destinations → tap-to-move
- [ ] Capture: move piece to hand (un-promoted)
- [ ] Drop flow: tap piece in 駒台 → highlight legal drop squares → tap to drop
- [ ] Promotion: when crossing the promotion zone, prompt dialog (must-promote for 歩/香 last rank, 桂 last two)
- [ ] SFEN export (for debugging; read-only first)
- [ ] Turn management, move log to console

**Done when:** can play a complete game to checkmate without violating movement rules.

### Phase 3 — Full rule enforcement (GDScript)
**Deliverable:** all illegal moves are refused; game ends correctly.

- [ ] `is_check(side)` using reverse-attack lookup from king square
- [ ] Legal-move filter: no move may leave own king in check
- [ ] 二歩 (nifu): cannot drop 歩 on a file that already has own unpromoted 歩
- [ ] 打ち歩詰め (uchifuzume): cannot deliver mate with a dropped 歩
- [ ] Checkmate / stalemate detection → game-over screen
- [ ] 千日手 (sennichite): track position history by hashed SFEN; draw after 4-fold (perpetual-check variant = loss for checker)
- [ ] 入玉 / 持将棋 (entering-king / impasse) — 27-point rule, basic handling
- [ ] Undo last move (single-level) for convenience

**Done when:** the engine cannot be tricked into an illegal state; verified with a test suite of SFEN fixtures.

### Phase 4 — Rust core (GDExtension), desktop only
**Deliverable:** move gen + rule checks run in Rust; GDScript calls into it.
Game still plays identically — this is a refactor, not a feature.

- [ ] `native/shogi_core/` Cargo crate, `cdylib`, `godot` dep (gdext)
- [ ] `addons/shogi_core.gdextension` manifest
- [ ] Desktop linux build via `cargo build --release`; copy `.so` to `native/bin/linux/x86_64/`
- [ ] Port types: `Piece`, `Color`, `Square`, `Move`, `Board`, `Hands`
- [ ] Port move generation (bitboards preferred; start with mailbox if faster to write)
- [ ] Port legality + special rules (二歩, 打ち歩詰め, check)
- [ ] SFEN parse/serialize
- [ ] Expose `ShogiCore` class to GDScript with:
  - `load_sfen(s)`, `to_sfen()`
  - `legal_moves() -> PackedArray`
  - `apply_move(m)`, `undo()`
  - `is_check()`, `is_checkmate()`, `result()`
- [ ] Replace GDScript rule code with calls into native
- [ ] Rust unit tests for rules (perft on known positions)

**Done when:** `cargo test` passes perft suite; in-game behavior matches Phase 3.

### Phase 5 — AI: ONNX + MCTS (desktop)
**Deliverable:** playable vs. AI on desktop; configurable playout budget.

- [ ] Add `ort` dep; bundle `models/bonanza.onnx`
- [ ] `encode.rs`: implement the exact 45-plane board encoding used in ShogiDojo (verify against Python by diffing a tensor on a known SFEN)
- [ ] Implement the 139-plane move index (match ShogiDojo's convention)
- [ ] `nn.rs`: load session, run `(45,9,9) → (policy_logits, value)`
- [ ] `mcts.rs`: PUCT MCTS with Dirichlet noise at root, virtual loss optional, single-threaded first
- [ ] Expose `think(ms|playouts) -> best_move` to GDScript
- [ ] Main-menu mode select: Human vs Human / Human (sente) vs AI / Human (gote) vs AI
- [ ] Settings: playout count (128 / 400 / 1600), temperature
- [ ] Thinking runs on Rust thread; GDScript shows spinner, awaits via signal

**Done when:** AI plays legal moves, beats a random-mover consistently, and responds within ~2s at default budget.

**Encoding-parity test (critical):** a small Python script in `tools/` dumps `(planes, policy_index)` for 20 diverse SFENs using ShogiDojo's code; Rust test loads the same SFENs and asserts byte-exact match.

### Phase 6 — Android build
**Deliverable:** signed APK runs on device, AI works offline.

- [ ] Install Android NDK, Godot Android export templates
- [ ] Add `aarch64-linux-android` Rust target; `cargo-ndk` or manual `--target`
- [ ] Build `libshogi_core.so` for arm64-v8a; place in `native/bin/android/arm64-v8a/`
- [ ] Update `.gdextension` manifest with Android entry
- [ ] `ort` Android feature: pull ONNX Runtime Mobile AAR; link statically if possible (else copy `libonnxruntime.so` alongside)
- [ ] Godot Android export preset; min SDK 24, target SDK 34
- [ ] Add signing config (debug keystore first)
- [ ] Test on physical device: APK size, first-move latency, battery
- [ ] Portrait-lock in manifest

**Done when:** APK installs, game plays a full match vs. AI on a mid-range phone with <3s thinking time per move.

### Phase 7 — Polish
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
