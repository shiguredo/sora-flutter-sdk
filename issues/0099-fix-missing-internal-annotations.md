# `LocalMediaStream` / `LocalMediaStreamTrack` / `LocalVideoTrack` の `@internal` 付与漏れ 4 箇所を修正する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-missing-internal-annotations
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`@internal` の付け忘れで 4 メンバーが公開 API に混入している状態を解消する。`sora_sdk.dart` の export により pub.dev の公開 API として利用者に見えており、`ignore_for_file: public_member_api_docs` で dartdoc 未記載も analyzer で検出されない。正式リリース版として API サーフェスを確定する前に固定する必要がある。

## 現状

`lib/src/sora_media_stream.dart` の以下 4 メンバーに `@internal` が付いていない:

- `LocalMediaStream.ensureNotDisposed()`
- `LocalMediaStreamTrack.nativeTrackAddress`
- `LocalMediaStreamTrack.ensureNotDisposed()`
- `LocalVideoTrack.captureType`（getter）

同一ファイル内の他メンバー（`attachToConnection`, `detachFromConnection`, `hasOtherConnectionOwner`, `withNativeTrackRefcounted`, `retainNativeTrackRefcounted`, `startCaptureForConnection`, `stopCaptureForConnection`, `videoSourceAddress`）はすべて `@internal` が付いている。書き忘れ以外に理由がない。

`lib/sora_sdk.dart` は `export 'src/sora_media_stream.dart' hide copyI420Plane, validateExternalVideoFrame;` で widely export しているため、上記 4 メンバーは pub.dev 上で公開 API として見える。

## 設計方針

- 上記 4 メンバーに `@internal` を付与する。`package:meta/meta.dart` の `@internal` を利用する。
- `LocalVideoTrack.captureType` は内部でのみ使う設計であることを再確認する。もし公開 API 上で必要であれば `@internal` ではなく public のまま dartdoc を追加する（現時点では内部限定の想定）。
- `LocalMediaStream.ensureNotDisposed()` と `LocalMediaStreamTrack.ensureNotDisposed()` は同名だが両方に付与する。
- 変更に伴い `ignore_for_file: public_member_api_docs` が不要になる場合はそれも合わせて削除する。

## 完了条件

- [ ] `LocalMediaStream.ensureNotDisposed()`, `LocalMediaStreamTrack.nativeTrackAddress`, `LocalMediaStreamTrack.ensureNotDisposed()`, `LocalVideoTrack.captureType` に `@internal` が付いている。
- [ ] 4 メンバーが公開 API と誤解される可能性がなくなる。
- [ ] `flutter analyze` と関連テストが成功する。
