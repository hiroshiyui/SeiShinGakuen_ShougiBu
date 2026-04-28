# Changelog

All notable changes to this project. Format follows
[Keep a Changelog](https://keepachangelog.com); per-release prose
(highlights in Japanese, full bullet list) lives under
[`docs/release-notes/`](./docs/release-notes/) and on
[GitHub Releases](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases).

## [Unreleased]

## [1.0.0] — 2026-04-28

First stable release. Phase 1〜7 ロードマップを完走 — 完全な本将棋ルール、
オフライン AI 対局、棋譜保存と MCTS 解析、先生モード、Android arm64-v8a
向け署名付き APK のサイドロード配布まで揃った。

### Added
- 隠しクレジット画面。タイトル「清正学園将棋部」を 3 秒以内に 10 回
  タップすると `scenes/Credits.tscn` が開く。作者より、AI モデル
  (Bonanza / ShogiDojo / tract)、エンジン (Godot, godot-rust)、フォント
  謝辞 (SIL OFL 1.1) を収録。
- クレジット画面の 隠す ボタン — ヘッダーと本文パネルを畳み、背景
  アートのみを表示する。画面タップで復帰、Android バックジェスチャは
  「畳んでいたら戻す → そうでなければタイトルへ」の二段挙動。

### Fixed
- Android タイトルタップの二重カウント。`InputEventScreenTouch` と
  合成された `InputEventMouseButton` の両方を購読していたため、5 回で
  クレジット画面が開いてしまっていた。`Square.gd` と同じ
  `OS.has_feature("mobile")` 分岐に統一。

[Full release notes](./docs/release-notes/1.0.0.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/1.0.0)

## [0.5.0] — 2026-04-28

### Added
- 定跡データベースを 12 → 75 ポジションに拡充。矢倉・角換わり・横歩取り・
  中飛車・四間飛車・三間飛車・早石田・雁木の 8 戦型を 6〜14 手分まで
  整備し、序盤の脇道（端歩 / 4g4f / 3g3f）に対する短い応手を 6 系統追加。
  低段キャラクター (Lv 1〜3) で「定跡が切れた途端に弱い手を指す」傾向が
  改善。
- M PLUS 2 Regular を `assets/fonts/m-plus-2/` に同梱、フォントサブセット
  パイプラインに追加。設定・対局中・棋譜一覧・棋譜検討の主要ラベルを
  Noto Serif JP から M PLUS 2 へ移行 (駒は引き続き 筆ごしらえ)。

### Fixed
- 待った 押下後に `Settings.save_game(...)` を呼び、続きから が巻き戻し
  後の局面で再開するように。AI 先手モードでも 待った 単独で挙動が止まら
  ないよう `_maybe_start_ai_turn()` を呼び戻す。
- 状態ラベルにアウトラインを追加、対戦相手名の行を右寄せ。
- 四間飛車ラインの不正な代替手 (直前で指された 3c3d を再候補にしていた)
  を削除し定跡を再生成。

### Tests
- `scripts/tests/opening_book_tests.gd` — 初期局面が辞書にあること、各
  エントリのスキーマ、SFEN の妥当性、USI が合法手であること、重みが正の
  整数であること、候補手の USI 重複なし、を headless で検証。

[Full release notes](./docs/release-notes/0.5.0.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.5.0)

## [0.4.0] — 2026-04-28

### Added
- Opening book — ~12 mainline positions covering the first 4–5 plies
  of 相居飛車 / 矢倉 entry / 中飛車 / 四間飛車. The AI consults the book
  before MCTS each turn and only falls through to search when the
  position isn't recognised. Adds opening variety at the same character
  level and skips the ~150 ms search on book hits.
- 棋譜検討 reviewer now highlights the last-moved squares with the
  same blue overlay the in-game scene uses.

### Changed
- `RANK_KANJI` (漢数字 0..9 lookup) and the safe-area inset boilerplate
  consolidated onto the `Settings` autoload — removes verbatim
  duplicates from `GameController`, `KifuLibrary`, and `KifuReviewer`.

### Internal
- `tools/*.gd` excluded from the shipped APK — dev-only generators
  (`gen_opening_book`, `gen_sample_kif`, `setup_jishogi_test`) had been
  silently bundled. ~7 KB saved.

[Full release notes](./docs/release-notes/0.4.0.md) ·
[GitHub Release](https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.4.0)

## [0.3.0] — 2026-04-28

### Added
- License: project is now released under **GPL-3.0-or-later**. See
  [`LICENSE`](./LICENSE) and [ADR-0010](./docs/adr/0010-gpl-3-or-later.md).
  Prior releases (0.1.x, 0.2.0) shipped without a declared license;
  0.3.0 is the first GPL release.
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

[Unreleased]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/1.0.0...HEAD
[1.0.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.5.0...1.0.0
[0.5.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.4.0...0.5.0
[0.4.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.2.0...0.3.0
[0.2.0]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.1.2...0.2.0
[0.1.2]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases/tag/0.1.1
