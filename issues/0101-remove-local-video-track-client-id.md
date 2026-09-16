# `LocalVideoTrack._clientId` は常に null な dead field なので削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-local-video-track-client-id
- Polished: 2026-09-07

## 目的

`LocalVideoTrack` のコンストラクタ引数 `clientId` と private フィールド `_clientId` が、生成起点のいずれからも値が渡されず常に null で運用されている。`LocalVideoTrack._ensureTextureId` から `ensureLocalVideoTrackTexture` に `clientId: _clientId ?? 0` として渡しているが、Dart 側は常に 0 を送っている。dead field / dead 引数を削除して誤解の温床を除く。まだ正式リリース前のため、MethodChannel 契約の変更を含めて直接削除する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 現状

`lib/src/sora_media_stream.dart` の `LocalVideoTrack.fromNativeMediaTrack` は `int? clientId` を optional 引数として受け取り、`_clientId` フィールドに保存する。`_LocalVideoTrackMetadata.fromTrack` も `track._clientId` をコピーする。

- `LocalVideoTrack.fromNativeMediaTrack` の直接呼び出しは 2 箇所 (`sora_media_stream.dart` の `_reuseOrCreateVideoTrack`、`sora_media_devices.dart` の `_createVideoTrack`) のみ。`_createVideoTrack` は `clientId:` を渡さず、`_reuseOrCreateVideoTrack` は `clientId: _videoTrackMetadata?.clientId` としてメタデータの中継のみ行う。起点が常に null のため全経路で `_clientId == null`。
- `LocalVideoTrack._ensureTextureId` から `media_device_platform.ensureLocalVideoTrackTexture` へ `clientId: _clientId ?? 0` として渡すため、Dart 側は常に 0 を送信している。
- ネイティブ側の `ensureLocalVideoTrackTexture` における `clientId` の扱いはプラットフォームで異なる。iOS (`ios/sora_sdk/Sources/sora_sdk/SoraFlutterMessageHandler.swift`) と macOS (`macos/sora_sdk/Sources/sora_sdk/SoraFlutterMessageHandler.swift`) は renderer を `videoSourcePtr` でキーイングしており、この `clientId` を読まない。一方 Android (`SoraSdkPlugin.kt`) は `clientId` を読み取り、`clientId != 0` の場合のみ `camera_open_error` の通知先解決に使う。Windows (`sora_sdk_plugin.cpp`) と Linux (`sora_sdk_plugin.cc`) は通知先解決に加えて capturer の所有記録にも使う。Dart 側が常に 0 を送るため当該分岐はいずれも現在不活性である。
- 実際の capture 開始 `startCaptureForConnection(clientId)` では引数側の `clientId` が使われる。削除対象の `_clientId` とは別物であり、開始・停止経路には影響しない。

現時点で機能バグは起きないが、将来「これで clientId が届いている」と誤解して依存する温床。

## 設計方針

- `LocalVideoTrack.fromNativeMediaTrack` の `int? clientId` 引数を削除。
- `LocalVideoTrack._clientId` フィールドを削除。
- `_LocalVideoTrackMetadata.clientId` フィールドを削除。`fromTrack` から該当行を削除。
- `_reuseOrCreateVideoTrack` の `clientId: _videoTrackMetadata?.clientId` 中継を削除する。
- `LocalVideoTrack._ensureTextureId` の `ensureLocalVideoTrackTexture` 呼び出しから `clientId: _clientId ?? 0` を削除する。
- MethodChannel 側 (`media/sora_media_device_platform.dart`) の `ensureLocalVideoTrackTexture` API シグネチャから `clientId` 引数を削除する。
- Android / Windows / Linux の `ensureLocalVideoTrackTexture` ハンドラにおける `clientId` 読み取りと、`clientId != 0` 時の `camera_open_error` 通知先解決・capturer 所有記録の分岐を合わせて削除する。Dart 側が常に 0 を送っていた不活性分岐の除去であり、挙動変更はない。
- iOS / macOS の `ensureLocalVideoTrackTexture` ハンドラは `clientId` を読んでいないため変更なし (Dart 側が送信しなくなるのみ)。
- `startCaptureForConnection` / `stopCaptureForConnection` / `startLocalVideoCapture` / `stopLocalVideoCapture` の `clientId` (接続側) には触れない。
- 全経路で track 側の `clientId` 引数がなくなることを確認する。

## 完了条件

- [ ] `LocalVideoTrack.fromNativeMediaTrack` の `clientId` 引数、`_clientId` フィールド、`_LocalVideoTrackMetadata.clientId` フィールド、`_reuseOrCreateVideoTrack` の中継がすべて削除されている。
- [ ] `media/sora_media_device_platform.dart` の `ensureLocalVideoTrackTexture` の `clientId` 引数が削除されている。
- [ ] Android / Windows / Linux の `ensureLocalVideoTrackTexture` における `clientId` 読み取りと関連分岐が削除されている。
- [ ] iOS / macOS の `ensureLocalVideoTrackTexture` が `clientId` なしで動作すること。
- [ ] `lib/` の `flutter analyze` と `flutter test test/sora_media_stream_test.dart` が成功し、各ネイティブの既存ビルド手順に破壊がないこと。
