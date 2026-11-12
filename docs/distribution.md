# 配布チャネル

清正学園将棋部は 3 つの窓口から配布している。GitHub Releases と itch.io は
同一の署名鍵で署名された **同じバイナリ** を配信するので、どちらから
入手しても、後からもう一方で配信されたバージョンへ再インストール無しで
更新できる。F-Droid 版は F-Droid 側がリリースタグのソースからビルドして
独自の鍵で署名するため、他の窓口の APK とは相互に上書き更新できない
（乗り換えにはアンインストールが必要）。

| 窓口 | URL | 対象 | 備考 |
|---|---|---|---|
| GitHub Releases | https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/releases | 技術寄りユーザー、開発者 | 一次配布。SHA-256 ハッシュとリリースノート全文を併載。 |
| itch.io | https://hiroshiyui.itch.io/seishingakuen-shougibu | 海外含む indie / Godot コミュニティ | プラットフォームタグ `Android`、日本語ページ。 |
| F-Droid | https://f-droid.org/ja/packages/org.seishingakuen.shougibu/ | F-Droid 利用者 | リリースタグから自動でビルド・更新される。掲載文・スクリーンショット・更新履歴は `fastlane/metadata/android/` から読まれる。 |

Linux デスクトップ版（AppImage、x86_64、1.1.1 から）は **GitHub Releases
のみ**で配布する。署名は無く、`.sha256` ファイルで整合性を確認する。
itch.io への Linux アップロードは当面行わない（ADR-0013）。

このドキュメントは itch.io 出品時にコピー＆ペーストするための原稿を
集約している。リリース毎にここを更新してから itch.io に反映する運用
を想定。

---

## 共通: 商品メタデータ

- **タイトル**: 清正学園将棋部
- **キャッチコピー（80 字以内）**: オフラインで遊べる本将棋。AlphaZero 系 AI と 8 人の対戦相手。
- **対応プラットフォーム**: Android 7.0 (API 24) 以降 / arm64-v8a。Linux (glibc 2.31 以降、x86_64) は GitHub Releases のみ
- **言語**: 日本語
- **ライセンス**: GPL-3.0-or-later
- **価格**: ¥0（無料配布）
- **ソースコード**: https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu

---

## itch.io 用商品説明（プレーンテキスト）

itch.io の Details → Description 欄は Markdown を解釈しないため、
このブロックをそのまま貼り付ける。

```text
清正学園将棋部は、端末内の AI と対局する本将棋（日本将棋）ゲームです。同じ Wi-Fi の相手との「通信対戦」もできます。インターネットには一切接続しません。

◎主な特徴

・完全な本将棋ルール — 王手、二歩、打ち歩詰め、千日手（連続王手の千日手は反則負け）、入玉判定（27 点法）まで対応。
・オフライン AI 対局 — AlphaZero 系の policy + value ネット（Bonanza 学習済み）を端末内で推論。MCTS は単一スレッド PUCT、強さは 8 段階。
・8 人の対戦相手 — 部員と先生から選んで対局。Lv 1 佐藤竜太郎 / Lv 2 鈴木すず / Lv 3 高橋ゆり子 / Lv 4 伊藤明 / Lv 5 中村アリス（部長）/ Lv 6 テリー・クラーク（主将）/ Lv 7 吉田なな（顧問）/ Lv 8 加藤よしこ（師範）。
・表情が変わる対戦相手 — 対局の流れに合わせて相手の表情が変わる。思考中は考える顔、優勢なら嬉しい顔、劣勢なら困った顔。王手をかけると一瞬たじろぎ、終局時は勝ち / 負けの表情を見せる。
・吹き出しでひと言 — 8 人の対戦相手が、対局開始や王手のときなどに、それぞれの性格に合った台詞を話す。
・あなたの戦績 — 対戦相手選択の画面に、その相手との勝敗数を表示。
・通信対戦 — 同じ Wi-Fi につないだ 2 台で人対人の対局。サーバーは使わず端末どうしが直接つながり、後手の側は盤面が反転。終局後は先後を入れ替えて再戦できます。
・先生モード — 対局中に「加藤先生！教えてください！」ボタンを押すと、上位 3 候補手を勝率付きで提示。実際に指す手はプレイヤー自身が選びます。
・対局体験 — 待った（多段階 undo）、投了、最終手ハイライト、駒音／効果音、ハプティック振動、対局の中断と続きから再開。
・棋譜の保存と検討 — 対局を .kif で保存し、タイトル画面の「棋譜検討」から一覧・再生・解析が可能。MCTS で全手を評価し、◎好手 / △疑問手 / ×悪手 のバッジと推奨手を表示。解析後は形勢グラフで対局の流れを一目で確認できる。
・加藤先生の一言 — 対局が終わると、いちばん惜しかった一手と代わりの手を加藤先生が教えてくれる。
・詰将棋 — 1手詰・3手詰・5手詰あわせて 160 問。「今日の一問」とヒントつきで、短い時間でも楽しめる。
・毎回ちがうタイトル画面 — アプリを開くたびに、吉田先生や部員たちがそれぞれの性格に合ったポーズで出迎えてくれる。ごくまれに、加藤先生と吉田先生が夕暮れの廊下で談笑する特別な一枚も。
・美しい盤面 — 本榧風の木目テクスチャ、伝統的な盤縁、五角形駒、駒文字は「Fude Goshirae」筆書体。

◎プライバシー

広告・トラッキング・アナリティクスを一切含みません。AI モデルも端末内で動作します。ネットワーク権限は同じ Wi-Fi の相手との「通信対戦」にのみ使い、インターネットには一切接続しません。

◎動作環境

Android 7.0（API 24）以降 / arm64-v8a。

◎インストール手順

1. APK をダウンロード。
2. 端末の「設定」→「セキュリティ」→「提供元不明のアプリのインストールを許可」（Android のバージョンにより場所が異なります）。
3. ダウンロードしたファイルをタップしてインストール。
4. （任意）GitHub Releases の SHA-256 ハッシュと照合すると、改変されていない正規の APK であることを確認できます。

◎ライセンスとソースコード

GPL-3.0-or-later。ソースコードと開発履歴は GitHub で公開しています。
https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu

不具合報告・要望は GitHub Issues へどうぞ。
https://github.com/hiroshiyui/SeiShinGakuen_ShougiBu/issues
```

**Genre**: Strategy
**Classification**: Game
**Platforms**: Android
**Tags**: `shogi`, `board-game`, `japanese`, `godot`, `singleplayer`, `local-multiplayer`, `ai-opponent`, `offline`, `android`
**Language**: Japanese
**Pricing**: No payments (free download)

---

## リリース毎の運用

1. GitHub Releases に v\<X.Y.Z> をタグ付けで公開（一次配布）。APK と `.idsig` に加え、`seishingakuen-v<X.Y.Z>-x86_64.AppImage` とその `.sha256` を添付する。
2. リリースノートと SHA-256 を `docs/release-notes/<X.Y.Z>.md` に反映。
3. このドキュメントの「主な特徴」が変わっていれば該当箇所を更新。
4. itch.io の Edit game → Uploads で新しい APK をアップロード（Android にチェック）、旧バージョンは「Hide this file」で非表示にする（Claude Code では `publish-to-itch-dot-io` スキルが手順を案内）。Devlog にバージョン更新を投稿（任意だがフォロワー通知が出る）。
