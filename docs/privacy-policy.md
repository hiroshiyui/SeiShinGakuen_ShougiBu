# Privacy Policy — 清正学園将棋部 (SeiShinGakuen Shougi-bu)

**Effective date:** 2026-11-11
**Application:** 清正学園将棋部 (SeiShinGakuen Shougi-bu)
**Contact:** hiroshiyui@gmail.com

---

## English

### Summary

清正学園将棋部 is a Shogi (本将棋) game played against an on-device AI,
or against another person on the same local network (通信対戦). **The
application does not collect personal information or user data, and it
never contacts the internet or any server.** It stores only local
gameplay data on your device.

### Data we collect

None. The application:

- Does not require an account, sign-in, or any user identifier.
- Does not collect personally identifiable information (name, email,
  phone number, address, etc.).
- Does not collect device identifiers, advertising IDs, or location
  data.
- Does not include analytics, crash reporting, telemetry, or any other
  data-collection SDKs.
- Does not contain advertising.
- Does not contact the internet or any server. The only network traffic
  is 通信対戦 (local network play), described below.

### Data stored on your device

The application saves the following **only on your device's local
storage**. This data is never transmitted anywhere:

- Game state for save/resume of the current game, in Android `user://`.
- User preferences (sound, display, etc.), in Android `user://`.
- KIF game records you explicitly save, in the app's Documents directory
  or `user://` fallback.
- The bundled AI model file (`bonanza.onnx`), extracted from the app's
  asset bundle to `user://` on first launch.

This data is removed when you uninstall the application or clear the
app's storage from Android system settings.

### Local network play (通信対戦)

Only when you choose 通信対戦, the application talks directly to another
copy of the game on your local network (for example, the same Wi-Fi):

- While a device waits for an opponent, it announces itself on the
  local network, both as a UDP broadcast about once a second and as a
  multicast DNS (Bonjour) service: the app's identifier, protocol
  version, the device's model name (for example "Pixel 8a") and a port
  number. A device looking for a game sends multicast DNS queries for
  that service.
- Once two devices connect, they exchange the device model names, the
  moves, and game events (resign, 入玉宣言, leaving the game) directly
  with each other.
- Both devices save the finished game record (KIF), including both
  model names, on their own local storage as described above.

Nothing is sent outside your local network, and the traffic stops when
you leave the game or the lobby.

### Permissions

The application requests two Android permissions, both used only for
通信対戦 as described above: `INTERNET`, which Android requires for any
network connection, including one on the local network, and
`CHANGE_WIFI_MULTICAST_STATE`, which lets the app receive the multicast
DNS announcements while it is looking for or hosting a game. The
application does not access the camera, microphone, contacts,
location, storage outside its own sandbox, or any other sensitive
APIs.

### Children's privacy

Because the application collects no data, it does not knowingly or
unknowingly collect data from children. The application is suitable
for all ages.

### Third-party services

The application uses no third-party services, SDKs, or APIs that
collect user data. The on-device AI inference runs locally via the
[tract](https://github.com/sonos/tract) library and does not contact
any server.

### Distribution

The application is distributed via GitHub Releases sideload and may be
distributed via Google Play. The privacy practices described here
apply to all distribution channels.

### Changes to this policy

If this policy ever changes (for example, if a future version of the
application introduces optional crash reporting), the updated policy
will be published in the application's source repository and the
"Effective date" above will be updated.

### Contact

For privacy questions, contact: **hiroshiyui@gmail.com**

---

## 日本語

### 概要

「清正学園将棋部」は、端末内の AI と、または同じローカルネットワーク上の
相手と対局する(通信対戦)本将棋ゲームです。**本アプリケーションは、
個人情報・利用者データを収集せず、インターネットや外部サーバーと
通信することは一切ありません。** 端末内には、対局に必要なローカル
データのみを保存します。

### 収集する情報

ありません。本アプリケーションは以下のとおりです:

- アカウント、サインイン、利用者識別子を一切要求しません。
- 個人を識別できる情報(氏名、メールアドレス、電話番号、住所等)を
  収集しません。
- 端末識別子・広告 ID・位置情報を収集しません。
- アナリティクス、クラッシュレポート、テレメトリ等のデータ収集
  SDK を一切含みません。
- 広告を表示しません。
- インターネットや外部サーバーとは一切通信しません。ネットワーク
  通信は、下記の通信対戦(ローカルネットワーク対局)のみです。

### 端末内に保存されるデータ

以下のデータは **お使いの端末のローカルストレージ** にのみ保存され、
外部に送信されることはありません。

- 中断・再開のためのゲーム状態(Android の `user://`)
- 利用者設定(サウンド、表示等。Android の `user://`)
- 利用者が明示的に保存した KIF 棋譜(アプリの Documents ディレクトリ、
  または `user://` フォールバック)
- 同梱の AI モデルファイル(`bonanza.onnx`)。初回起動時に APK
  内のアセットから `user://` に展開されます。

これらのデータはアプリをアンインストールするか、Android のシステム
設定からアプリのデータを消去すると削除されます。

### 通信対戦(ローカルネットワーク対局)

通信対戦を選んだときに限り、本アプリケーションは同じローカル
ネットワーク(同じ Wi-Fi など)上の別の端末の本アプリケーションと
直接通信します。

- 相手を待っている間、ローカルネットワーク内に自分を告知します。
  約 1 秒ごとの UDP ブロードキャストと、マルチキャスト DNS(Bonjour)
  のサービス登録の 2 通りで、内容はアプリの識別子、プロトコルの
  バージョン、端末の機種名(例:「Pixel 8a」)、ポート番号です。
  対局を探す側は、このサービスをマルチキャスト DNS で問い合わせます。
- 2 台が接続すると、端末の機種名、指し手、対局のできごと(投了、
  入玉宣言、対局の中止)を互いに直接やり取りします。
- 終局した棋譜(KIF、両者の機種名を含む)は、上記のとおり各端末の
  ローカルストレージに保存されます。

ローカルネットワークの外には何も送信されず、対局またはロビーを
離れると通信は終わります。

### 権限

本アプリケーションが要求する Android 権限は次の 2 つで、どちらも
上記の通信対戦にのみ使用します。`INTERNET` は、ローカルネットワーク
内の通信にも Android が必要とする権限です。
`CHANGE_WIFI_MULTICAST_STATE` は、対局を探している間や相手を待って
いる間にマルチキャスト DNS の告知を受信するための権限です。カメラ、マイク、連絡先、位置情報、
サンドボックス外のストレージ、その他の機微な API には一切アクセス
しません。

### 子どものプライバシー

本アプリケーションはいかなるデータも収集しないため、子どもからの
データ収集も発生しません。全年齢対象です。

### 第三者サービス

利用者データを収集する第三者サービス・SDK・API は使用しません。
端末内 AI 推論は [tract](https://github.com/sonos/tract) ライブラリ
によりローカルで実行され、外部サーバーと通信することはありません。

### 配布

本アプリケーションは GitHub Releases によるサイドロード配布、および
Google Play による配布の可能性があります。本ポリシーに記載した
プライバシーの取り扱いはすべての配布経路に適用されます。

### ポリシーの変更

将来本ポリシーが変更される場合(例: 任意のクラッシュレポート機能が
追加される等)、最新のポリシーをソースコードリポジトリにて公開し、
冒頭の「Effective date」を更新します。

### お問い合わせ

プライバシーに関するお問い合わせ: **hiroshiyui@gmail.com**
