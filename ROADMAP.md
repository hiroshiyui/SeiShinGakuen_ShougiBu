# 清正学園将棋部 — Development Roadmap

A mobile Shogi game for Android, built in Godot 4.7 with a Rust (GDExtension)
native core for move generation, rule enforcement, and AI (ONNX Runtime +
MCTS against the Bonanza policy+value network).

---

## 1. Goals & Non-Goals

### Goals
- Full-rules 本将棋 (standard Shogi) playable on Android phones.
- Single-player vs. AI, using `bonanza.onnx` (policy+value) with MCTS.
- Human vs. human on the same local network (通信対戦, Phase 8), with no server.
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
| Engine | Godot 4.7.2 (Mobile renderer) |
| UI / scenes / input | GDScript |
| Native core | Rust via [`godot-rust` (gdext)](https://github.com/godot-rust/gdext) |
| NN inference | `ort` crate (ONNX Runtime) — fallback: `tract` (pure Rust) |
| Model | `/home/yhh/MyProjects/ShogiDojo/bonanza.onnx` (input `(B,45,9,9)` → policy `(B,139,9,9)` + value `(B,1)`) |
| Desktop dev target | `x86_64-unknown-linux-gnu` |
| Ship target | `aarch64-linux-android` (API 24+); from 1.1.1 also an `x86_64` Linux AppImage (Phase 9) |
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

Phases 1–9 are complete. Each one is condensed below into what shipped and where it shipped differently from the plan. The full checklists are in git history (Phases 1–7 before commit "docs(roadmap): digest the completed phases", Phase 8 before "docs(roadmap): digest Phase 8").

### Phase 1 — Board & input skeleton (GDScript) ✅
A 9×9 portrait board built from `Square` nodes in a `GridContainer`. It shows the starting position, with 先手 upright at the bottom and 後手 rotated 180° at the top, and taps print coordinates. The on-device test moved to Phase 6.

### Phase 2 — Movement rules & hands (GDScript) ✅
Two humans could play a full legal game on one device: per-piece and sliding moves, captures into the 駒台, drops, promotion (forced where required), turns, and SFEN export.

### Phase 3 — Full rule enforcement (GDScript) ✅
Check and the legal-move filter, 二歩, 打ち歩詰め, checkmate and stalemate, and 千日手 (4-fold repetition is a draw; perpetual check loses). Also 入玉/持将棋 detection and a one-move undo. Shipped differently: 入玉 was detection-only until the Phase 7 宣言 button. Tests are headless GDScript (`scripts/tests/rules_tests.gd`) that build positions in code rather than loading SFEN fixtures.

### Phase 4 — Rust core (GDExtension) ✅
Move generation, legality checks and SFEN moved into `native/shogi_core/`, a cdylib exposed to GDScript as `ShogiCore`, and the GDScript rules were replaced by it. Shipped differently: it uses a mailbox board (`[Option<Piece>; 81]`), not bitboards, which is fast enough. The API is wider than planned, with test-setup helpers and `legal_moves_from` + `legal_drops` to match the tap-driven UI. Perft is checked at depths 1 and 2.

### Phase 5 — AI: ONNX + MCTS ✅
`encode.rs` (45 planes) and `move_index.rs` (139 planes) are byte-exact with ShogiDojo. `tools/gen_fixtures.py` writes 13 parity SFENs that `cargo test` checks. Single-threaded PUCT MCTS with Dirichlet noise drives the Bonanza model. Shipped differently:
- **`tract`, not `ort`.** `ort` had release-candidate regressions. `tract` is pure Rust and statically linked, at about 5 ms per forward pass on desktop, and it made Android cross-compilation trivial.
- **Search runs on a Godot `Thread`.** `think_best_move` is synchronous; `GameController` runs it on the thread and polls for the result. This is simpler than owning Rust threads across the FFI.
- Temperature and strength were later driven by each character's `CharacterProfile` (Phase 7).

### Phase 6 — Android build ✅
An arm64-v8a build through `cargo-ndk --platform 24` with NDK 30 (`docs/android-build.md`), min SDK 24, portrait-locked, and tested on a real phone. Gotchas found on the way, all now in `docs/android-gotchas.md`:
- The export filter dropped `.onnx`, so the preset needs `include_filter="*.onnx"`. On first launch the model is copied from `res://` to `user://` because tract can't read files inside the PCK.
- Orientation must be the int `1`; the string `"portrait"` silently falls back to landscape.
- Mouse emulation fires every tap twice, so `Square` listens to touch only on mobile.
- The board size is fitted to the viewport at runtime.

### Phase 7 — Polish ✅
- **Look & feel:** a wooden board and pentagonal pieces drawn with `_draw()` over real Kaya textures, with each piece sampling its own patch of grain. A 4 % board margin like a real 将棋盤. Last-move highlight, and a red square under a king in check (instead of a 王手 banner). Fade-to-black transitions through the `SceneTransition` autoload, honouring the reduce-motion setting. App icon, and title, library and reviewer backgrounds chosen at random from `BackgroundSet` resources.
- **APK size:** `tools/build_font_subsets.py` subsets the piece and UI fonts against the Japanese characters found in the source plus a list of characters added at runtime. This took the APK from 103 MB to 42 MB. The 48 expression portraits import as lossy WebP.
- **Game flow:** 投了 with a confirmation, unlimited 待った, and save/resume of the SFEN plus the packed move log. 入玉宣言 checks the official thresholds (28/27 points, 10 pieces); the AI declares automatically and 持将棋 is a draw. The Android back gesture is mapped to `ui_cancel` instead of quitting. Vibration on every move, procedurally generated move and event sounds, and a settings screen (sound, teacher-button side).
- **AI strength:** each `CharacterProfile`'s playouts and temperature drive MCTS, and a weighted mood is rolled on every move. The floor is 32 playouts at τ 1.2 and the cap is 256 (ADR-0011).
- **Characters:** a fighter-game-style opponent picker with eight characters (Lv 1〜8), each with neutral, thinking, happy, worried, victory and defeat portraits that cross-fade with the AI's win rate. Speech balloons, a per-character win/loss record in `prefs.cfg`, and a 加藤先生 avatar on the hint button.
- **Game records:** a 棋譜 panel with tap-to-rewind review on a scratch core (ADR-0008). Every finished game auto-saves as KIF with its real result to app-private Documents (ADR-0009); there is no share intent. A 棋譜検討 library and reviewer offers MCTS analysis (◎/△/×, recommended move) and the 形勢グラフ. 加藤先生's post-game comment analyses only the three biggest drops in the AI's win rate, on a worker thread, instead of the whole game.
- **詰将棋:** 160 mate problems (1, 3 and 5 moves) mined from self-play, so the set has no third-party content and suits F-Droid. They are judged by `mate.rs`, with 今日の一問 and hints. `tsume_tests.gd` re-solves every problem.

### Phase 8 — Human vs Human on LAN (通信対戦) ✅
Two players on the same Wi-Fi play each other, each on their own phone, over a direct TCP connection with no server; the "Online multiplayer" non-goal stands. Rationale in [ADR-0012](./docs/adr/0012-lan-play.md), protocol and module walkthrough in "通信対戦 (LAN play)" of `docs/architecture.md`.
- **Discovery:** two paths feeding one list in `scripts/net/LanDiscovery.gd` — a UDP broadcast beacon (pure GDScript) and mDNS / DNS-SD `_seishinshogi._tcp` through the Rust `LanMdns` class (`mdns-sd` crate), so a network that passes only one still works. *Shipped differently:* the Android multicast lock is taken through Godot's Java bridge, not a Kotlin plugin; there is no manual-IP / QR fallback, so client-isolated networks can't play.
- **Session:** the `NetSession` autoload keeps one line-delimited JSON TCP connection across the lobby → game switch. Every received move goes through `ShogiCore.is_legal_move` before it is applied; a bad move or false 入玉宣言 ends the game as 中断. After a drop the guest redials for 60 s, presenting a resume token only it received in `start`; the two move lists must agree (one a prefix of the other, at most one move apart) and both sides replay the agreed one. A connection that doesn't say hello within 5 s is dropped, and every message is type- and size-checked. *Shipped differently:* no starting SFEN and no draw offer (千日手 / 持将棋 still draw automatically); reconnect is not built on 続きから, which LAN games never use.
- **UI:** a 通信対戦 lobby (`scenes/NetworkLobby.tscn`) to host or join; in game the opponent is shown by device name and side, 待った and the AI-only features are off, and leaving asks to resign. The board turns round for whoever plays 後手 (`BoardView.set_flipped`), which also fixed 先手(AI) 対 後手(人). After a game, 再戦 starts a new game with the sides swapped once both players ask.
- **Permissions and docs:** the app now requests `INTERNET` and `CHANGE_WIFI_MULTICAST_STATE`; the privacy policy and store descriptions say the traffic never leaves the LAN. Desktop firewall notes are in `docs/android-gotchas.md`.
- **Tests:** `scripts/tests/net_tests.gd` (loopback host + guest, reconnect, rematch, version mismatch, broadcast and mDNS discovery); `tools/lan_peer_bot.gd` is a headless random-move opponent for testing against a phone.

### Phase 9 — Linux desktop (AppImage) ✅
An x86_64 AppImage is attached to every GitHub Release alongside the APK, from 1.1.1. Rationale in [ADR-0013](./docs/adr/0013-linux-appimage-secondary-target.md), build steps and gotchas in [`docs/linux-build.md`](./docs/linux-build.md).
- **Portable native library:** `libshogi_core.so` is built in a Debian bullseye (glibc 2.31) podman container (`tools/build_linux_native.sh`, `tools/Containerfile.linux-builder`), and a build whose `objdump -T` needs a newer glibc fails.
- **Export and packaging:** a `Linux x86_64` export preset with an embedded PCK and the same include filters as Android, and a `linuxbsd`-only 432×960 window override (9:20, a phone's proportions, so the title menu leaves the art visible as on a phone; 540×960 until 1.1.2) that fits a 1080p desktop. `tools/build_appimage.sh` packs the AppDir with `appimagetool`, whose tooling is pinned by SHA-256 in `tools/appimage/appimage.lock`; `tools/build_all.sh --linux` runs the whole chain, including a headless smoke run of the export.
- *Shipped differently:* built on a branch in 2026-10 for x86_64 and aarch64 and merged for 1.1.1. Only x86_64 ships; the aarch64 path (verified only under qemu) is still in the scripts behind `--arch arm64`. No Flatpak, Snap or tarball, and itch.io stays Android-only.

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
`godot = "0.5"` (resolved 0.5.5) pinned in `native/shogi_core/Cargo.toml`. Godot 4.7
GDExtension API is stable across 4.7.x; rebuild on any Godot minor
bump. `.gdextension` manifest declares `compatibility_minimum = 4.6`
(godot-rust 0.5 targets the 4.6 GDExtension API by default).

### Rule edge cases
- 千日手 perpetual-check: detected in
  [`Rules::detect_sennichite`](./native/shogi_core/src/rules.rs).
  Tagging each move with `was_check` + `position_key_after` lets us
  distinguish a plain 4-fold draw from a perpetual-check loss for the
  checker.
- 入玉: full 入玉宣言 declaration shipped via `Rules::can_declare_jishogi`
  (asymmetric 28-point sente / 27-point gote thresholds, 10-piece
  minimum excluding the king, in-check rejection). Surfaced as the
  in-game 入玉宣言 button + AI auto-declaration + 持将棋 mutual draw.
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
| `1.1.1` | Phase 9 — first release with a Linux x86_64 AppImage |

---

## 8. Open Questions

- [x] ~~千日手 perpetual-check rule variant — confirm Japanese professional rules~~ — implemented as "checker loses", 4-fold detection in `Rules::detect_sennichite`. 2026-04-22.
- [x] ~~入玉 point rule — 24 or 27?~~ — 27. `Rules::jishogi_points`. 2026-04-22.
- [x] ~~In-game 入玉 claim button (currently detection-only).~~ — shipped 2026-04-28. `ShogiCore.can_declare_jishogi(is_gote)` returns `{ok, reason, points_have, points_need, pieces_have, pieces_need}`; `GameController._on_jishogi_pressed` ends the game on Ok and explains the deficit otherwise. AI auto-declares from `_check_end_state` when its side qualifies; 持将棋 fires the draw path when both sides qualify simultaneously. Asymmetric 28/27 thresholds, 10-piece minimum (excl. king), official-rule conformant.
- [x] ~~App icon + main-menu art — source or commission?~~ — AI-generated in-house, both icon (`assets/branding/`) and backgrounds (`assets/backgrounds/`) plus the 8 character portraits (`assets/characters/**/neutral.webp`). 2026-04-27.
- [x] ~~Cloud save / cross-device persistence?~~ — explicitly skipped to stay free of Google Play services dependencies. Players who uninstall lose `user://prefs.cfg` + `user://saved_game.cfg`; that's the trade-off. 2026-04-27.
- [x] ~~Play Store distribution or sideload only?~~ — sideload only via signed APK on GitHub Releases. Play Store is explicitly out of scope; we don't want the Google Play ecosystem dependencies (developer account, policy compliance, mandatory privacy URL, upload-key custody) for a single-player offline game. AAB target left in `tools/build_all.sh --aab` for completeness but unused. 2026-04-27. *Since then:* the same signed APK also ships on itch.io, and the app was accepted on F-Droid (2026-11), which builds each release tag from source with its own signing key and updates automatically. Play Store remains out of scope. From 1.1.1 a Linux x86_64 AppImage ships on GitHub Releases too (Phase 9, ADR-0013); still no app store of any kind.
- [x] ~~Any telemetry (crash reporting)?~~ — none. The app's only network traffic is LAN-only 通信対戦 (Phase 8); it never contacts a server. 2026-11-11.
- [x] ~~UI string centralisation (e.g. `Strings.gd`)~~ — deferred; strings stay inline. Reopen if we internationalise or the font subsetter's grep becomes unwieldy. 2026-11-11.

---

*Last updated: 2026-11-11 (closed the telemetry and UI string questions)*
