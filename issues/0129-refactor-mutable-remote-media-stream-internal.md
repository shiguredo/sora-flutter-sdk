# `MutableRemoteMediaStream` メソッドの `@internal` 二重付与を解消する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-mutable-remote-media-stream-internal
- Polished: 2026-09-07

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

当該クラスは `lib/sora_sdk.dart` で export されていない (`show RemoteMediaStream` のみ) ため、公開 API に現れない。同一パターン (`@internal` クラスでメンバー側の付与なし) の前例として `RemoteTrackManager` がある。よってメソッド側の 2 箇所は冗長と判断する。なお `package:meta` の `@internal` 仕様にクラス付与のメンバー伝播規定は無いため、本判断の根拠は仕様ではなく非 export と前例と analyzer 実測とする。

`test/` からの直接参照は 0 件であり、使用は `RemoteTrackManager` 経由の同一パッケージ内のみである。

## 設計方針

- `setAudioTrack` / `setVideoTrack` の `@internal` を削除する。クラス側は残す。
- 削除前後で `flutter analyze` の `invalid_use_of_internal_member` 警告の出方と `public_member_api_docs` への影響を実測し、警告が増えないことを確認する。
- `0131-fix-annotation-policy` は data class の modifier 統一と `@nodoc` 排除が対象であり、本件 (内部クラスの二重付与) は範囲外のため、本 issue で先行して実施する。`0131` の結論と矛盾しない。
- 挙動変更なし。

## 完了条件

- [ ] `setAudioTrack` / `setVideoTrack` の `@internal` 付与が削除されている。
- [ ] `flutter analyze` で警告が増えていない。
- [ ] `flutter test test/sora_remote_track_manager_test.dart` が成功する。
