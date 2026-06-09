# e2e_test_app

Sora Flutter SDK の recvonly / sendonly / sendrecv 接続と、2 クライアント間メディア疎通を `integration_test` で検証する最小アプリです。

## 前提

- **Linux**: プラグインの MethodChannel が未実装のため、接続テストは現状失敗します。CI（`e2e-test.yml`）は macOS で実行します。
- **macOS**: 初回ビルド時に Swift Package Manager が `libwebrtc_c.xcframework.zip` を自動取得するため、手動 fetch は不要。アプリの最小デプロイは **15.0**。App Sandbox 有効時は **外向き TCP/TLS（シグナリング）用に `com.apple.security.network.client`** が entitlements に必要（本アプリの `DebugProfile` / `Release` に含める）。

## 環境変数

| 変数 | 説明 |
|------|------|
| `TEST_SECRET_KEY` | 接続 metadata 用（JWT 文字列、JSON オブジェクト文字列、または平文トークン） |
| `TEST_SIGNALING_URLS` | シグナリング URL をカンマまたは空白区切り（例: `wss://a/signaling,wss://b/signaling`） |
| `TEST_CHANNEL_ID_PREFIX` | チャンネル ID のプレフィックス。CI では `GITHUB_RUN_ID` を連結し、ローカルでは時刻でユニーク化する |
| `TEST_SEND_DURATION` | （任意）sendonly / sendrecv テストの送信継続秒数（例: `60`） |

2 クライアント E2E の前提:

- sender / receiver は同じ `channelId` を共有する
- `bundleId` は設定しない。同じ `bundleId` を設定すると相互受信しない
- sender 側は external video track を使うため、カメラ権限には依存しない

`TEST_SECRET_KEY` の扱い:

- `{` で始まる場合は JSON として `metadata` にそのまま使う
- `xxxxx.yyyyy.zzzzz` 形式（JWT 風）なら文字列の `metadata` として送る
- それ以外は `{"access_token": "<値>"}` として送る（検証環境の契約に合わせてテストコードを変える）

## ローカル実行例（macOS）

リポジトリルートから:

```bash
export TEST_SECRET_KEY='...'
export TEST_SIGNALING_URLS='wss://...'
export TEST_CHANNEL_ID_PREFIX='e2e-local-'
cd e2e_test_app
flutter pub get
flutter test integration_test/recvonly_e2e_test.dart -d macos
flutter test integration_test/sendonly_dummy_video_e2e_test.dart -d macos
flutter test integration_test/sendrecv_smoke_e2e_test.dart -d macos
flutter test integration_test/track_event_e2e_test.dart -d macos
flutter test integration_test/two_party_media_e2e_test.dart -d macos
```

## GitHub Actions

`.github/workflows/e2e-test.yml` は `workflow_dispatch` と、関連ファイル変更時の `push` で実行します。workflow では macOS ランナー上で以下 5 本の E2E を matrix 実行します。

- `integration_test/recvonly_e2e_test.dart`
- `integration_test/sendonly_dummy_video_e2e_test.dart`
- `integration_test/sendrecv_smoke_e2e_test.dart`
- `integration_test/track_event_e2e_test.dart`
- `integration_test/two_party_media_e2e_test.dart`

Actions で実行するには、**Repository secrets** に `TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX` を登録してください。
