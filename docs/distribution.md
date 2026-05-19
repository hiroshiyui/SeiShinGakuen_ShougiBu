# 配布チャネル

清正学園将棋部の APK は同一の署名鍵で署名された **同じバイナリ** を、
複数の窓口から配布する。ユーザーはどの窓口から入手しても、後から別の
窓口で配信されたバージョンへ再インストール無しで更新できる。

| 窓口 | URL | 対象 | 備考 |
|---|---|---|---|
| GitHub Releases | https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases | 技術寄りユーザー、開発者 | 一次配布。SHA-256 ハッシュとリリースノート全文を併載。 |
| itch.io | https://hiroshiyui.itch.io/seishingakuen-shougibu | 海外含む indie / Godot コミュニティ | プラットフォームタグ `Android`、日本語ページ。 |

このドキュメントは itch.io 出品時にコピー＆ペーストするための原稿を
集約している。リリース毎にここを更新してから itch.io に反映する運用
を想定。

---

## 共通: 商品メタデータ

- **タイトル**: 清正学園将棋部
- **キャッチコピー（80 字以内）**: オフラインで遊べる本将棋。AlphaZero 系 AI と 8 人の対戦相手。
- **対応プラットフォーム**: Android 7.0 (API 24) 以降 / arm64-v8a
- **言語**: 日本語
- **ライセンス**: GPL-3.0-or-later
- **価格**: ¥0（無料配布）
- **ソースコード**: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu

---

## itch.io 用商品説明（Markdown）

```markdown
**清正学園将棋部**は、シングルプレイヤー向けの本将棋（日本将棋）ゲームです。すべての処理は端末内で完結し、通信は一切行いません。

## 主な特徴

- **完全な本将棋ルール** — 王手、二歩、打ち歩詰め、千日手（連続王手の千日手は反則負け）、入玉判定（27 点法）まで対応。
- **オフライン AI 対局** — AlphaZero 系の policy + value ネット（Bonanza 学習済み）を端末内で推論。MCTS は単一スレッド PUCT、強さは 8 段階。
- **8 人の対戦相手** — 部員と先生から選んで対局。Lv 1 佐藤竜太郎 / Lv 2 鈴木すず / Lv 3 高橋ゆり子 / Lv 4 伊藤明 / Lv 5 中村アリス（部長）/ Lv 6 テリー・クラーク（主将）/ Lv 7 吉田なな（顧問）/ Lv 8 加藤よしこ（師範）。
- **先生モード** — 対局中に「加藤先生！教えてください！」ボタンを押すと、上位 3 候補手を勝率付きで提示。実際に指す手はプレイヤー自身が選びます。
- **対局体験** — 待った（多段階 undo）、投了、最終手ハイライト、駒音／効果音、ハプティック振動、対局の中断と続きから再開。
- **棋譜の保存と検討** — 対局を .kif で保存し、タイトル画面の「棋譜検討」から一覧・再生・解析が可能。MCTS で全手を評価し、◎好手 / △疑問手 / ×悪手 のバッジと推奨手を表示。
- **美しい盤面** — 本榧風の木目テクスチャ、伝統的な盤縁、五角形駒、駒文字は「Fude Goshirae」筆書体。

## プライバシー

ネットワーク権限を要求しません。広告・トラッキング・アナリティクスを一切含みません。AI モデルも端末内で動作します。

## 動作環境

Android 7.0（API 24）以降 / arm64-v8a。

## インストール手順

1. APK をダウンロード。
2. 端末の「設定」→「セキュリティ」→「提供元不明のアプリのインストールを許可」（Android のバージョンにより場所が異なります）。
3. ダウンロードしたファイルをタップしてインストール。
4. （任意）GitHub Releases の SHA-256 ハッシュと照合すると、改変されていない正規の APK であることを確認できます。

## ライセンスとソースコード

GPL-3.0-or-later。ソースコードと開発履歴は GitHub で公開しています:
<https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu>

不具合報告・要望は GitHub Issues へどうぞ。
```

**Genre**: Strategy
**Classification**: Game
**Platforms**: Android
**Tags**: `shogi`, `board-game`, `japanese`, `godot`, `singleplayer`, `ai-opponent`, `offline`, `android`
**Language**: Japanese
**Pricing**: No payments (free download)

---

## リリース毎の運用

1. GitHub Releases に v\<X.Y.Z> をタグ付けで公開（一次配布）。
2. リリースノートと SHA-256 を `docs/release-notes/<X.Y.Z>.md` に反映。
3. このドキュメントの「主な特徴」が変わっていれば該当箇所を更新。
4. itch.io の Edit game でファイルを差し替え、Devlog にバージョン更新を投稿（任意だがフォロワー通知が出る）。
