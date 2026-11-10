# `VideoCaptureSettings` が意図せず公開 API に混入している

- Created: 2026-08-27
- Completed: 2026-08-28
- Branch: feature/fix-video-capture-settings-hide
- Polished: {YYYY-MM-DD}

## 解決方法

- `lib/sora_sdk.dart` の `sora_media_stream.dart` の export を許可リスト方式（`show`）へ変更し、`VideoCaptureSettings` を公開範囲から除外した。
- 許可リストには `LocalMediaStream` / `LocalMediaStreamTrack` / `LocalAudioTrack` / `LocalVideoTrack` / `VideoTrackCaptureType` / `ExternalVideoFrame` を列挙した。従来 hide していた `copyI420Plane` / `validateExternalVideoFrame` も内部ヘルパーのため公開対象から除外した。
- `@internal` の付与は行わなかった。`show` 方式で公開範囲を固定するだけで十分であり、`@internal` は export と二重の管理になるため。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（成功）。

## 目的

class dartdoc に「内部モデル」と明記されている `VideoCaptureSettings` が `sora_sdk.dart` の export を通じて公開 API に混入している状態を解消する。pub.dev リリース後の un-export は破壊的変更となるため、正式リリース確定前に固定する。

## 現状

`lib/sora_sdk.dart` の export ポリシーが 2 種類混在している:

- `sora_media_stream.dart`: `hide copyI420Plane, validateExternalVideoFrame;` のブロックリスト方式
- `sora_remote_media_stream.dart`: `show RemoteMediaStream;` の許可リスト方式

前者を通じて `lib/src/sora_media_stream.dart` の `VideoCaptureSettings`（class dartdoc に「VideoTrack 作成時のキャプチャ条件を保持する内部モデルです。」と明記）が公開 API に漏れる。`@internal` が付いていないため、pub.dev では通常の公開クラスとして表示される。

## 設計方針

以下のいずれか、または両方を実施:

- `VideoCaptureSettings` に `@internal` を付与する（`package:meta/meta.dart` の `@internal`）。
- `lib/sora_sdk.dart` の `sora_media_stream.dart` の export を許可リスト方式 (`show ...`) に変更し、`VideoCaptureSettings` を除外する。他の hide 対象（`copyI420Plane`, `validateExternalVideoFrame`, `MutableXxx` 等）も洗い直す。

方針としては後者（許可リスト方式）が推奨される。全体の export 方針を統一する意味でも、`hide` 方式は使わず `show` 方式に揃える。

## 完了条件

- [ ] `VideoCaptureSettings` が pub.dev の公開 API に露出しない。
- [ ] `lib/sora_sdk.dart` の export 方針が統一されている（`show` 方式に揃えるか、hide 対象が網羅されている）。
- [ ] `flutter analyze` と関連テストが成功する。
