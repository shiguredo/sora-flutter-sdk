# e2e_test_app

Sora Flutter SDK の recvonly / sendonly / sendrecv 接続と、2 クライアント間メディア疎通を `integration_test` で検証する最小アプリです。
加えて、ネイティブプラグインの結合テスト（Sora 接続不要でデバイス列挙等のみを検証するテスト）も含みます。

## 前提

- **Linux**: プラグインの MethodChannel が未実装のため、接続テストは現状失敗します。CI（`e2e-test.yml`）は macOS で実行します。
- **macOS**: 初回ビルド時に Swift Package Manager が `libwebrtc_c.xcframework.zip` を自動取得するため、手動 fetch は不要。アプリの最小デプロイは **15.0**。App Sandbox 有効時は **外向き TCP/TLS（シグナリング）用に `com.apple.security.network.client`** が entitlements に必要（本アプリの `DebugProfile` / `Release` に含める）。
- **audio track**: `MediaDevices.createAudioTrack()` を使用するテスト（`remote_media_stream_e2e_test.dart`、`local_media_toggle_e2e_test.dart`）は macOS のマイク入力が必要。entitlements に `com.apple.security.device.microphone` が設定されていること。CI ランナーに物理マイクが無い場合、音声デバイスが存在しない環境ではテストが失敗する可能性がある。
- **Windows**: プラグインの MethodChannel は実装済み。カメラキャプチャ (0035) と音声デバイス (0036) に対応する。Windows の接続テストは以下の前提で実行する:
  - 音声デバイステスト（`windows_audio_device_test.dart`）は Sora 接続不要のプラットフォーム結合テストで、WASAPI によるデバイス列挙と切り替えのみを検証する
  - `windows_audio_device_test.dart` は GitHub Actions の Windows Hosted Runner では実行しない。ローカル実機または self-hosted runner で実行する
  - 音声テストには物理マイクが必要。仮想オーディオデバイス（CABLE Input 等）でも動作する
  - `flutter build windows` でビルドが通る状態であること（不足システムライブラリがある場合は `windows/CMakeLists.txt` に追加する）

## 環境変数

| 変数 | 説明 |
|------|------|
| `TEST_SECRET_KEY` | 接続 metadata 用（JWT 文字列、JSON オブジェクト文字列、または平文トークン） |
| `TEST_SIGNALING_URLS` | シグナリング URL をカンマまたは空白区切り（例: `wss://a/signaling,wss://b/signaling`） |
| `TEST_CHANNEL_ID_PREFIX` | チャンネル ID のプレフィックス。CI では `GITHUB_RUN_ID` を連結し、ローカルでは時刻でユニーク化する |
| `TEST_SEND_DURATION` | （任意）sendonly / sendrecv テストの送信継続秒数（例: `60`） |
| `TEST_MACOS_CAMERA_STRESS_ROUNDS` | （任意）macOS 実カメラストレス E2E の反復回数。未指定時は `10` |
| `TEST_PUSH_EXPECTED_TYPE` | （任意）notify metadata テストで push 受信を確認する場合、期待する `event_type` 値を設定する |

接続失敗系 E2E の前提:

- 認証失敗テスト: 有効な `TEST_SIGNALING_URLS` が必要。無効な metadata で接続試行し、接続が成功しないことを確認する。エラーコードの完全一致は server 実装差があるため行わない。
- 全 URL 不達テスト: `signalingCandidateTimeout` を短く設定し、存在しない URL への接続で `SoraConnectionErrorEvent(code: signaling_candidate_timeout)` が発火することを確認する。`signalingUrls` は `localhost` で上書きされるが、`loadE2eEnvironment()` が `TEST_SIGNALING_URLS` の existence check を含むためダミー値の設定が必要。
- フェイルオーバーテスト: 先頭 URL に DNS 解決不能な `.invalid` ドメインを置き、2 件目以降の有効 URL で接続成功することを確認する。`signalingCandidateTimeout` を短く設定し、先頭候補の DNS 失敗後に速やかに次候補へ進む。`signalingUrls` の 2 件目以降は `TEST_SIGNALING_URLS` から取得するため、環境変数に有効値を設定する必要がある。

DataChannel signaling E2E の前提:

- `dataChannelSignaling` を有効にした接続テスト（`custom_data_channel_e2e_test.dart`）は、DataChannel signaling に対応した Sora サーバーが必要。
- サーバー側で `data_channel_signaling` が有効になっていない場合、`SoraSwitchedEvent` が発火せずテストがタイムアウトする。

Notify metadata E2E（`notify_metadata_e2e_test.dart`）の前提:

- `signalingNotifyMetadata` をサポートする Sora サーバーが必要。
- sender の接続時に発行される `connection.created` notify が channel 内の全参加者にブロードキャストされる必要がある。
- notify payload 上の key 名はサーバー実装によって `authn_metadata` または `signaling_notify_metadata` のどちらかになる。テストコードは両方をフォールバックして確認する。
- push 検証はサーバー側から push メッセージを送信できる検証環境が必要。push は sender 側で受信することを前提とする。`TEST_PUSH_EXPECTED_TYPE` 環境変数で期待する `event_type` 値を設定すると、接続後に push 受信を確認する。未設定の場合は push 検証をスキップする。

2 クライアント E2E の前提:

- sender / receiver は同じ `channelId` を共有する
- `bundleId` は設定しない。同じ `bundleId` を設定すると相互受信しない
- sender 側は external video track を使うため、カメラ権限には依存しない
- audio track を含むテスト（`remote_media_stream_e2e_test.dart`、`local_media_toggle_e2e_test.dart`）は `MediaDevices.createAudioTrack()` を使用するため、macOS のマイク権限と入力デバイスが必要

Video Codec E2E（`video_codec_e2e_test.dart`）の前提:

- macOS 専用。macOS の VideoToolbox を使う Video Encoder / Decoder Factory を含む送受信経路を検証する
- VP8 / VP9 / AV1 / H.264 / H.265 をそれぞれ sender / receiver の両方に指定し、送受信統計の増加と Codec 名の一致を確認する
- 検証環境の Sora サーバーと macOS 向け libwebrtc は、全 5 Codec のネゴシエーションと送受信に対応している必要がある。非対応 Codec はスキップせず失敗とする

bundleId 分離 E2E（`bundle_id_isolation_e2e_test.dart`）の前提:

- 3 接続（observer / sender-same / sender-other）が同じ `channelId` を共有する
- observer と sender-same は同じ `bundleId`（`bundle-a`）を設定する
- sender-other は異なる `bundleId`（`bundle-b`）を設定する
- 同じ `bundleId` を持つ observer と sender-same 間では互いのメディアを受信しない
- 異なる `bundleId` を持つ sender-other のメディアは observer が受信する
- `bundleId` 未対応の Sora サーバーでは bundleId フィルタが機能せず、observer が sender-same の media も受信するためテストが失敗する

macOS 実カメラストレス E2E（`macos_camera_runtime_stress_e2e_test.dart`）の前提:

- このテストはローカル実機専用。CI では実行しない
- macOS のカメラ入力デバイスが必要
- 初回実行時に macOS のカメラ権限ダイアログが表示される場合がある
- `removeVideoTrack` 後に camera track を dispose し、`replaceVideoTrack` で camera track を再追加し、最後に disconnect / dispose する操作を反復する
- デッドロック検出用に各 camera 操作へ timeout を設定している。強めに確認する場合は `TEST_MACOS_CAMERA_STRESS_ROUNDS=50` 以上を指定する

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
flutter test integration_test/video_codec_e2e_test.dart -d macos
flutter test integration_test/notify_metadata_e2e_test.dart -d macos
flutter test integration_test/custom_data_channel_e2e_test.dart -d macos
flutter test integration_test/remote_media_stream_e2e_test.dart -d macos
flutter test integration_test/local_media_toggle_e2e_test.dart -d macos
flutter test integration_test/bundle_id_isolation_e2e_test.dart -d macos
flutter test integration_test/connection_failure_e2e_test.dart -d macos
flutter test integration_test/connection_failover_e2e_test.dart -d macos
```

実カメラを使う macOS ローカル専用ストレス E2E:

```bash
export TEST_MACOS_CAMERA_STRESS_ROUNDS=50
flutter test integration_test/macos_camera_runtime_stress_e2e_test.dart -d macos
```

## ローカル実行例（Windows）

```powershell
cd e2e_test_app
flutter pub get
# Sora 接続不要のプラットフォーム結合テスト（物理マイクが必要）
flutter test integration_test/windows_audio_device_test.dart -d windows
```

Windows で Sora 接続を含むテストを実行する場合は macOS と同様に環境変数を設定してください。ただし `sora_camera_capturer.cpp` に Windows SDK 互換性の問題があるため、カメラを含むテストは現時点では失敗する可能性があります。
