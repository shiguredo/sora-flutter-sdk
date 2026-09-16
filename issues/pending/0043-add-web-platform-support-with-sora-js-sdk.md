# Web プラットフォーム対応を sora-js-sdk で追加する

- Priority: Medium
- Created: 2026-06-17
- Completed: {YYYY-MM-DD}
- Model: Kimi Code CLI
- Branch: feature/add-web-platform-support-with-sora-js-sdk
- Polished: {YYYY-MM-DD}

## 目的

sora-flutter-sdk は現状 iOS / Android / macOS / Windows に対応している。
Flutter Web 上でも Sora 接続を利用できるようにするため、Web プラットフォーム対応を追加する。
Web では `dart:ffi` が使えないため、既存の libwebrtc-c ベース実装は流用できない。
時雨堂が既に整備している sora-js-sdk を Web プラットフォーム実装として組み込むことで、
ブラウザネイティブの WebRTC API を利用する。

## 優先度根拠

Medium。Windows 対応と並行して進めているマルチプラットフォーム展開の一環。
Web 対応は flutter_webrtc 等の代替案もあるが、sora-js-sdk を活用することで
既存の Web 向け実装と挙動を揃えやすく、開発効率と品質の両立が期待できる。

## 現状

- `lib/src/ffi/webrtc_client.dart` は `dart:ffi` 経由で libwebrtc-c を呼び出しており、Web では動作しない。
- `lib/src/sora_connection.dart` は `dart:ffi` / `dart:io` / `EventChannel` / `MethodChannel` に依存しており、Web ビルドで失敗する。
- `lib/src/sora_media_devices.dart` は `dart:ffi` / `WebrtcClient.sharedFactory` を使って `LocalMediaStream` を生成しており、Web では使えない。
- `lib/src/sora_video_widget.dart` は `Texture` Widget を使っており、Web では動作しない。
- `pubspec.yaml` の `flutter.plugin.platforms` には web が登録されていない。
- sora-js-sdk は ESM パッケージとして提供されており、`Sora.connection(...)` から `sendrecv` / `sendonly` / `recvonly` / `messaging` の各 Connection を生成できる。

## 設計方針

- sora-js-sdk を Web プラットフォーム実装として組み込む。
- JS 側に `web/sora_js_sdk_adapter.js` を配置し、Dart から呼びやすい API を `window.soraJsSdkAdapter` として露出する。
- Dart 側は `dart:js_interop` / `package:web` で JS アダプターを操作する。
- `SoraConnection` の Web 専用実装 `SoraConnectionWeb` を新規作成し、既存 API と同じインターフェースを提供する。
- `MediaDevices.getUserMedia` / 映像表示 Widget も Web 専用実装を用意する。
- ネイティブ実装と Web 実装は `kIsWeb` 判定または conditional import で切り替える。
- sora-js-sdk のビルド済みファイルは `web/sora.js` として配置し、`web/index.html` から module script として読み込む。

## 完了条件

- Flutter Web 上で `sendrecv` / `sendonly` / `recvonly` / `messaging` の各接続が動作すること。
- 既存のネイティブプラットフォーム（iOS / Android / macOS / Windows）の動作が損なわれていないこと。
- `devtools` または `e2e_test_app` で Web 向けの動作確認ができること。
- `dart:ffi` / `dart:io` を import している既存コードが Web ビルドで失敗しないこと。

## 解決方法

- `web/sora_js_sdk_adapter.js` と `web/sora.js` を追加する。
- `lib/src/web/sora_js_sdk_adapter.dart` を追加し、JS アダプターの Dart ラッパーを実装する。
- `lib/src/web/sora_connection_web.dart` を追加し、`SoraConnection` と同等の API を sora-js-sdk 上に実装する。
- `lib/src/web/sora_media_devices_web.dart` を追加し、`navigator.mediaDevices.getUserMedia()` を呼び出す。
- `lib/src/web/sora_video_widget_web.dart` を追加し、`HtmlElementView` + `<video>` 要素で映像を表示する。
- `lib/src/sora.dart` の `Sora.createConnection()` で `kIsWeb` の場合は `SoraConnectionWeb` を返す。
- `pubspec.yaml` の `flutter.plugin.platforms` に web を追加する。
- `devtools` / `e2e_test_app` の `web/index.html` に sora-js-sdk の module script 読み込みを追加する。
