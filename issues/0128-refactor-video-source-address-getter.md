# `LocalVideoTrack` の `videoSourceAddress` / `_videoSourceAddress` の 2 段 getter を整理する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-video-source-address-getter
- Polished: 2026-09-07

## 目的

`LocalVideoTrack` の private `_videoSourceAddress` と `@internal` public `videoSourceAddress` が同じ値を返す 2 段 getter になっており冗長。統合する。

## 現状

`lib/src/sora_media_stream.dart` の `LocalVideoTrack` は同じ値を返す 2 つの getter を持つ:

- private `_videoSourceAddress`: 委譲を除き内部 8 参照 (`_ensureTextureId` 内 2、`startCaptureForConnection` 内 1、`stopCaptureForConnection` 内 1、`_disposeInternal` 内 4)
- `@internal` public `videoSourceAddress`: `sora_connection.dart` 1791 行目 (`_stopVideoCaptureBackend` 内) から 1 参照

両者は同じ値 (`_videoSourceRef` が null なら `0`、そうでなければ `address`) を返す。private を削除して `@internal` public に統一しても機能に影響しない。

## 設計方針

- private `_videoSourceAddress` を削除し、内部使用箇所も `@internal` public `videoSourceAddress` に統一する。public 削除案は置換先が存在しないため取らない。
- `0131` (data class の annotation 統一) とは対象が重ならないため矛盾しない。
- `0111` は `_stopVideoCaptureBackend` を含む映像キャプチャ関連メソッドの移動を計画しており、唯一の外部利用箇所と編集範囲が重なる。実装時は rebase で競合を整理する (`0111` が先行する場合は移動後の配置に従う)。
- 挙動変更なし。`@internal` 範囲内の整理のみ。

## 完了条件

- [ ] `LocalVideoTrack` の getter が `videoSourceAddress` 1 本に統合されている。
- [ ] 内部 8 参照と外部 1 参照が統一されている。
- [ ] `flutter analyze` と `flutter test test/sora_media_stream_test.dart test/sora_connection_test.dart` が成功する。
