# `LocalMediaStream.addTrack` / `removeTrack` の native 戻り値の契約を dartdoc に追記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-addtrack-return-value-dartdoc
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`LocalMediaStream.addTrack` / `removeTrack` が native 呼び出しの返り値 `0` を「失敗」として `StateError` を投げているが、契約が dartdoc / バインディングコメントに明記されていない。将来のバインディング変更で誤検出しやすいため、Dart 側用法としての契約を明示する。

## 現状

`lib/src/sora_media_stream.dart` の `LocalMediaStream.addTrack` は native 呼び出し（`mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack`）の返り値 `int result` が `0` の場合に `throw StateError('Failed to add ... track to MediaStream.')` を投げる。`removeTrack` も `mediaStreamRemoveTrackWithAudioTrack` / `mediaStreamRemoveTrackWithVideoTrack` の返り値 `0` の場合に同様に `StateError` を投げる。

`lib/src/ffi/bindings.dart` の該当 4 バインディングは `Int8 Function(...)` (Dart 側 `int Function(...)`) の型情報のみで、「返り値 `0` を Dart 側で失敗として扱う」用法上の契約はどこにも書かれていない。native 実装はリポジトリ内に存在しないため、本 issue で明示するのは Dart 側用法としての契約に留める。

なお `webrtc_client.dart` の `rtpSenderSetTrack` の `result == 0` 判定は別層 (sender 操作) のため対象外とする。

## 設計方針

- `LocalMediaStream.addTrack` と `removeTrack` の dartdoc に返り値の契約を追記する:
  - 「native 呼び出しの返り値 `0` を Dart 側で失敗として扱い、失敗した場合は `StateError` を投げる。」
- 該当 4 バインディング (`mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack` / `mediaStreamRemoveTrackWithAudioTrack` / `mediaStreamRemoveTrackWithVideoTrack`) の直上に同旨のコメントを明記する。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] `LocalMediaStream.addTrack` と `removeTrack` の dartdoc に返り値契約が書かれている。
- [ ] `bindings.dart` の該当 4 箇所にも契約コメントがある。
- [ ] `flutter analyze` と `flutter test test/sora_media_stream_test.dart` が成功する。
