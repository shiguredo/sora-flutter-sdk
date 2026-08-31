# `MutableRemoteMediaStream` メソッドの `@internal` 二重付与を解消する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-mutable-remote-media-stream-internal
- Polished: {YYYY-MM-DD}

## 目的

`MutableRemoteMediaStream` クラスに `@internal` が付いているのに、`setAudioTrack` / `setVideoTrack` メソッド側にも `@internal` が付いており冗長。視覚ノイズを減らす。

## 現状

`lib/src/sora_remote_media_stream.dart` の:

```dart
@internal
final class MutableRemoteMediaStream implements RemoteMediaStream {
  ...
  @internal
  void setAudioTrack(RemoteMediaStreamTrack? track) { ... }
  @internal
  void setVideoTrack(RemoteMediaStreamTrack? track) { ... }
```

クラスに `@internal` が付いていれば全メンバーは自動的に internal 扱いになる（`package:meta` の `@internal` の仕様）。メソッド側の `@internal` 2 箇所は冗長。

## 設計方針

- `setAudioTrack` / `setVideoTrack` の `@internal` を削除する。
- `@internal` の付与ポリシー（`CODEBASE.md` の別 issue）と揃える。
- 挙動変更なし。

## 完了条件

- [ ] `setAudioTrack` / `setVideoTrack` の `@internal` 付与が削除されている。
- [ ] `flutter analyze` と関連テストが成功する。
