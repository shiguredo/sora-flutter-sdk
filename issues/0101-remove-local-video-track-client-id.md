# `LocalVideoTrack._clientId` は常に null な dead field なので削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-local-video-track-client-id
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`LocalVideoTrack` のコンストラクタ引数 `clientId` と private フィールド `_clientId` が、SDK 内のいずれの生成経路からも値が渡されず常に null で運用されている。`ensureLocalVideoTrackTexture` に `clientId: _clientId ?? 0` として渡しているが iOS 側もこの値を読まない。dead field / dead 引数を削除して誤解の温床を除く。

## 現状

`lib/src/sora_media_stream.dart` の `LocalVideoTrack.fromNativeMediaTrack` は `int? clientId` を optional 引数として受け取り、`_clientId` フィールドに保存する。`_LocalVideoTrackMetadata.fromTrack` も `track._clientId` をコピーする。

- `LocalVideoTrack` を生成する 3 経路（`_reuseOrCreateVideoTrack`、`_createVideoTrack`（`sora_media_devices.dart`）、`_LocalVideoTrackMetadata.fromTrack`）のいずれも `clientId:` を明示指定しない。全経路で `_clientId == null`。
- `_ensureLocalVideoTrackTexture` へ `clientId: _clientId ?? 0` として渡すが、iOS 実装（`ios/sora_sdk/Sources/sora_sdk/SoraFlutterMessageHandler.swift`）は renderer を `videoSourcePtr` でキーイングしており、この `clientId` を読まない。
- 実際の capture 開始 `startCaptureForConnection(clientId)` では引数側の `clientId` が使われる。

現時点で機能バグは起きないが、将来「これで clientId が届いている」と誤解して依存する温床。

## 設計方針

- `LocalVideoTrack.fromNativeMediaTrack` の `int? clientId` 引数を削除。
- `LocalVideoTrack._clientId` フィールドを削除。
- `_LocalVideoTrackMetadata.clientId` フィールドを削除。`fromTrack` から該当行を削除。
- `ensureLocalVideoTrackTexture` の呼び出しから `clientId: _clientId ?? 0` を削除する。
- MethodChannel 側 (`media/sora_media_device_platform.dart`) の `ensureLocalVideoTrackTexture` API シグネチャから `clientId` 引数を削除する。iOS 側（`ios/sora_sdk/Sources/sora_sdk/SoraFlutterMessageHandler.swift`）でも読んでいない引数なので、Swift 側の該当 API 定義から削除する。
- 全経路で `clientId` 引数がなくなることを確認する。

## 完了条件

- [ ] `LocalVideoTrack.fromNativeMediaTrack` の `clientId` 引数、`_clientId` フィールド、`_LocalVideoTrackMetadata.clientId` フィールドがすべて削除されている。
- [ ] `media/sora_media_device_platform.dart` の `ensureLocalVideoTrackTexture` の `clientId` 引数が削除されている。
- [ ] iOS 側実装の `ensureLocalVideoTrackTexture` から `clientId` 引数が削除されている。
- [ ] `flutter analyze` と関連テストが成功する。
