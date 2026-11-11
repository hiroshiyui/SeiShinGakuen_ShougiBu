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

Phases 1–7 are complete. Each one is condensed below into what shipped and where it shipped differently from the plan. The full checklists are in git history (before commit "docs(roadmap): digest the completed phases").

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

### Phase 8 — Human vs Human on LAN (通信対戦)

Two players on the same Wi-Fi play each other, each on their own phone, over a direct connection with no server. The "Online multiplayer" non-goal stands. Decision and rationale: [ADR-0012](./docs/adr/0012-lan-play.md).

- [x] **Discovery, v1: UDP broadcast beacon.** `scripts/net/LanDiscovery.gd`, pure GDScript. The host sends a JSON beacon (app id, protocol version, device name, TCP port) about once a second to 255.255.255.255, each local /24 broadcast address and loopback; the joiner listens on port 47123 and lists hosts heard in the last 4 s.
- [x] **Android multicast lock.** *Shipped differently:* no Kotlin plugin. `LanDiscovery` takes a `WifiManager.MulticastLock` through Godot's built-in Java bridge (`AndroidRuntime.getApplicationContext()` → `getSystemService("wifi")`) while discovery runs; the export preset adds `CHANGE_WIFI_MULTICAST_STATE`. Broadcast beacons arrive without it on a Nokia G50; mDNS is why it is there.
- [x] **Discovery, v2: mDNS / DNS-SD (Bonjour).** `native/shogi_core/src/lan_mdns.rs` wraps the `mdns-sd` crate as the `LanMdns` class: the host registers `_seishinshogi._tcp.local.` (TXT `proto`, `name`), the joiner browses it. It runs *alongside* the broadcast beacon, not instead of it; `LanDiscovery` merges both into one list keyed by address:port, and an mDNS host stays listed until its announcement is withdrawn. One code path for desktop and Android.
- [x] **Transport: TCP.** `TCPServer` / `StreamPeerTCP` in the `NetSession` autoload (`scripts/autoload/NetSession.gd`), so the connection survives the lobby → game scene change. Game port 47124, or the next free one of ten.
- [x] **Wire protocol.** One JSON object per line: `hello` (protocol version, app id, name), `start` (game id, host plays 先手 or not — the host picks at random), `move` (ply number + USI), `resign`, `declare`, `abort`, `rematch`, `ping` / `pong`, `sync`, `error`. *Shipped differently:* no starting SFEN (games always start from the initial position) and no draw offer; 千日手 and 持将棋 still end in a draw automatically.
- [x] **Validate every peer move in the Rust core.** New `ShogiCore.is_legal_move` checks the move against the full legal-move list (own king safe, 二歩, 打ち歩詰め, forced promotion); `move_to_usi` / `usi_to_move` convert. A bad move or a false 入玉宣言 ends the game as 中断.
- [x] **Disconnect and reconnect.** For 60 s after a drop the guest redials every 2 s and the host keeps listening; the board is locked with 再接続を待っています…. On reconnect the guest sends its move list, the longer list wins (the other is a prefix of it), and both sides replay it move by move. After 60 s the game ends as 中断. *Shipped differently:* not built on the 続きから save — LAN games never use that slot, since one player can't resume alone.
- [x] **UI.** `scenes/NetworkLobby.tscn`, opened by 通信対戦 on the title screen: 対局を作る / 対局に参加する, a list of found games, waiting and connecting states. In game the opponent is shown by name and side with no portrait; 待った, 先生のお薦め and the AI-only features are off; the status line says あなた / 相手 の手番. Leaving a LAN game asks to resign. Finished games auto-save to KIF with both device names. The board turns round for whoever plays 後手 (`BoardView.set_flipped`: squares keep their real coordinates, only the grid order, piece orientation and hand panels change), here and in 先手(AI) 対 後手(人). After a game the 対局終了 dialog offers 再戦: once both players tap it, the host starts a new game with the sides swapped (`rematch` message); if the opponent leaves instead, the dialog says so and offers タイトルへ. Resigning a LAN game stays on the board for that reason.
- [x] **Docs.** ADR-0012; the privacy policy, store descriptions and `docs/distribution.md` now describe the `INTERNET` permission and the LAN-only traffic. Tests: `scripts/tests/net_tests.gd` (loopback host + guest, reconnect, version mismatch, discovery); `tools/lan_peer_bot.gd` is a headless random-move opponent for testing against a phone.

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

---

## 8. Open Questions

- [x] ~~千日手 perpetual-check rule variant — confirm Japanese professional rules~~ — implemented as "checker loses", 4-fold detection in `Rules::detect_sennichite`. 2026-04-22.
- [x] ~~入玉 point rule — 24 or 27?~~ — 27. `Rules::jishogi_points`. 2026-04-22.
- [x] ~~In-game 入玉 claim button (currently detection-only).~~ — shipped 2026-04-28. `ShogiCore.can_declare_jishogi(is_gote)` returns `{ok, reason, points_have, points_need, pieces_have, pieces_need}`; `GameController._on_jishogi_pressed` ends the game on Ok and explains the deficit otherwise. AI auto-declares from `_check_end_state` when its side qualifies; 持将棋 fires the draw path when both sides qualify simultaneously. Asymmetric 28/27 thresholds, 10-piece minimum (excl. king), official-rule conformant.
- [x] ~~App icon + main-menu art — source or commission?~~ — AI-generated in-house, both icon (`assets/branding/`) and backgrounds (`assets/backgrounds/`) plus the 8 character portraits (`assets/characters/**/neutral.webp`). 2026-04-27.
- [x] ~~Cloud save / cross-device persistence?~~ — explicitly skipped to stay free of Google Play services dependencies. Players who uninstall lose `user://prefs.cfg` + `user://saved_game.cfg`; that's the trade-off. 2026-04-27.
- [x] ~~Play Store distribution or sideload only?~~ — sideload only via signed APK on GitHub Releases. Play Store is explicitly out of scope; we don't want the Google Play ecosystem dependencies (developer account, policy compliance, mandatory privacy URL, upload-key custody) for a single-player offline game. AAB target left in `tools/build_all.sh --aab` for completeness but unused. 2026-04-27. *Since then:* the same signed APK also ships on itch.io, and the app was accepted on F-Droid (2026-11), which builds each release tag from source with its own signing key and updates automatically. Play Store remains out of scope.
- [x] ~~Any telemetry (crash reporting)?~~ — none. The app's only network traffic is LAN-only 通信対戦 (Phase 8); it never contacts a server. 2026-11-11.
- [x] ~~UI string centralisation (e.g. `Strings.gd`)~~ — deferred; strings stay inline. Reopen if we internationalise or the font subsetter's grep becomes unwieldy. 2026-11-11.

---

*Last updated: 2026-11-11 (closed the telemetry and UI string questions)*
