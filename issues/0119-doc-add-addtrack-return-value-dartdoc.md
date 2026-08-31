# `LocalMediaStream.addTrack` の native 戻り値の契約を dartdoc に追記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-addtrack-return-value-dartdoc
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`LocalMediaStream.addTrack` が `mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack` の返り値 `0` を「失敗」として `StateError` を投げているが、契約が dartdoc / native シグネチャコメントに明記されていない。将来のバインディング変更で誤検出しやすいため、契約を明示する。

## 現状

`lib/src/sora_media_stream.dart` の `LocalMediaStream.addTrack` は native 呼び出し（`mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack`）の返り値 `int result` が `0` の場合に `throw StateError('Failed to add ... track to MediaStream.')` を投げる。

`lib/src/ffi/bindings.dart` の該当関数バインディングには型情報しか無い（`Int32 Function(...)` 相当）。「返り値 `0 = 失敗、非 0 = 成功`」の契約はどこにも書かれていない。

## 設計方針

- `LocalMediaStream.addTrack` の dartdoc に返り値の契約を追記する:
  - 「native の `mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack` は `0 = 失敗、非 0 = 成功` を返す。失敗した場合は `StateError` を投げる。」
- 該当バインディングの近傍にコメントで契約を明記する（`lib/src/ffi/bindings.dart` の `late final mediaStreamAddTrackWithAudioTrack` / `mediaStreamAddTrackWithVideoTrack` の直上）。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] `LocalMediaStream.addTrack` の dartdoc に返り値契約が書かれている。
- [ ] `bindings.dart` の該当箇所にも契約コメントがある。
- [ ] `flutter analyze` と関連テストが成功する。
