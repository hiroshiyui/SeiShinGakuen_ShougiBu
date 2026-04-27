# Changelog

All notable changes to this project. Format follows
[Keep a Changelog](https://keepachangelog.com); per-release prose
(highlights in Japanese, full bullet list) lives under
[`docs/release-notes/`](./docs/release-notes/) and on
[GitHub Releases](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases).

## [Unreleased]

## [0.3.0] — 2026-04-28

### Added
- 棋譜検討 — saved-game library + KIF reviewer with first/prev/next/last
  navigation. 「解析」runs MCTS on every ply, classifies each played move
  as 好手 / 疑問手 / 悪手 by the win-rate delta against the engine's pick,
  and surfaces 推奨手 when a played move was at least 疑問手.
- KIF export — in-game 棋譜 dialog grows a 保存 button that writes the
  current game to the app-private external Documents directory
  (`Android/data/<pkg>/files/Documents/` on Android, `~/Documents`
  on Linux). See [ADR-0009](./docs/adr/0009-kif-library-app-private-storage.md).
- Move history panel + tap-to-rewind review mode in the in-game scene.
  Banner button "棋譜閲覧中 — タップで現在に戻る" returns to the live game.
  See [ADR-0008](./docs/adr/0008-review-mode-scratch-core.md).
- 入玉宣言 declaration — official 28/27-point asymmetric thresholds
  with 10-piece minimum (excluding the king). In-game button surfaces
  on the side-to-move's turn when their king has entered the
  opponent's camp; AI auto-declares; mutual qualification fires 持将棋
  (引き分け).
- Settings screen with sound-enabled toggle and 先生ボタンの位置 (moved
  off MainMenu). 加藤先生 circular avatar on the in-game teacher button.

### Changed
- Project-wide dark/gold button + dialog theme via `assets/themes/ui.tres`.
- MainMenu button order: 設定 → 続きから → 棋譜検討 → 新規対局.
- README screenshots refreshed to 2×3 grid covering the new flows.

### Fixed
- Android hardware/gesture back is routed to the existing `ui_cancel`
  handlers via `Settings._notification`; `quit_on_go_back=false` in
  `project.godot` stops the engine from short-circuiting to
  `get_tree().quit()` mid-game.
- KifuReviewer crashed loading a file because `clamp` / `PackedInt32Array.slice`
  return `Variant` under inference and the project treats untyped
  declarations as errors. Locals are now explicitly typed.

[Full release notes](./docs/release-notes/0.3.0.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.3.0)

## [0.2.0] — 2026-04-26

### Added
- Character picker scene (`scenes/CharacterPicker.tscn`) replacing the
  Lv 1〜8 dropdown. 8 部員 + 先生 with 肖像画 + 紹介, gold-bordered
  selection cue, tap-to-confirm.
- In-game opponent strip — character avatar + name above the board.
- Atomic copy of the model resource into `user://` on Android (avoids
  partial-extract corruption).

### Changed
- AI strength is chosen by selecting a character (`CharacterProfile`),
  not a level number. See ADR-0006.
- Font subsetter scans `assets/**/*.tres` so character bio glyphs reach
  the Noto subset. See ADR-0007.

### Fixed
- Saved-game `character_id` round-trip; opponent label uses the
  character's display name; deferred shader sync for the avatar mask;
  default character pick on first launch.

[Full release notes](./docs/release-notes/0.2.0.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.2.0)

## [0.1.2] — 2026-04-25

### Changed
- Background image fixed to the intended classroom scene (0.1.1
  shipped the wrong image by accident). App icon and README
  screenshots refreshed to match.

### Fixed
- `docs/screenshots/` gets a `.gdignore` so Godot doesn't generate
  `.import` sidecars for repo-only screenshot PNGs.

[Full release notes](./docs/release-notes/0.1.2.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.1.2)

## [0.1.1] — 2026-04-25

First public release.

### Added
- AlphaZero-style AI opponent running on-device via `tract` against
  the Bonanza-trained `models/bonanza.onnx`.
- Lv 1〜Lv 8 strength presets driven by MCTS playouts and temperature.
- 先生モード — top-3 candidate moves with 勝率 % from a single search.
- Full 本将棋 rule enforcement: check, 二歩, 打ち歩詰め, 千日手 (incl.
  perpetual-check variant), 入玉 detection.
- Piece slide animations and shogi-ban zoom transitions.

### Distribution
- Signed release APK published as a sideload-only artifact on GitHub
  Releases. Android arm64-v8a, Vulkan via the Mobile renderer,
  network permission absent.

[Full release notes](./docs/release-notes/0.1.1.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.1.1)

[Unreleased]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.3.0...HEAD
[0.3.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.1.2...0.2.0
[0.1.2]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.1.1
