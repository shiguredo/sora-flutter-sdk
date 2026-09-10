# `LocalMediaStream` / `LocalMediaStreamTrack` の `@internal` 付与漏れ 3 箇所を修正する

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/fix-missing-internal-annotations
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`@internal` の付け忘れで 3 メンバーが公開 API に混入している状態を解消する。`sora_sdk.dart` の export により pub.dev の公開 API として利用者に見えており、`ignore_for_file: public_member_api_docs` で dartdoc 未記載も analyzer で検出されない。正式リリース版として API サーフェスを確定する前に固定する必要がある。

## 現状

`lib/src/sora_media_stream.dart` の以下 3 メンバーに `@internal` が付いていない:

- `LocalMediaStream.ensureNotDisposed()` (328 行目)
- `LocalMediaStreamTrack.nativeTrackAddress` (349 行目)
- `LocalMediaStreamTrack.ensureNotDisposed()` (403 行目)

同一ファイル内の他メンバー（`attachToConnection`, `detachFromConnection`, `hasOtherConnectionOwner`, `withNativeTrackRefcounted`, `retainNativeTrackRefcounted`, `startCaptureForConnection`, `stopCaptureForConnection`, `videoSourceAddress`, `captureType`）はすべて `@internal` が付いている。`captureType` は `0069` で対応済みのため本 issue の対象外とする。

3 メンバーはいずれも同一パッケージ内の内部利用のみであり、`devtools` / `e2e_test_app` / `test` からの参照は 0 件である。書き忘れ以外に理由がない。

`lib/sora_sdk.dart` は `export 'src/sora_media_stream.dart' show LocalMediaStream, LocalMediaStreamTrack, LocalAudioTrack, LocalVideoTrack, ExternalVideoFrame;` で export しているため、上記 3 メンバーは pub.dev 上で公開 API として見える。

## 設計方針

- 上記 3 メンバーに `@internal` を付与する。`package:meta/meta.dart` の `@internal` を利用する (当該ファイルで import 済み)。
- `LocalMediaStream.ensureNotDisposed()` と `LocalMediaStreamTrack.ensureNotDisposed()` は同名だが両方に付与する。
- `ignore_for_file: public_member_api_docs` は `0139-refactor-ignore-for-file-cleanup` からの委譲範囲であり、本 issue で扱う。削除条件は「`ignore` を外して `flutter analyze` が clean であること」とし、clean にならない場合は残す。
- 変更に伴う公開 API への影響は無い (外部参照 0 件のため)。

## 完了条件

- [ ] `LocalMediaStream.ensureNotDisposed()`、`LocalMediaStreamTrack.nativeTrackAddress`、`LocalMediaStreamTrack.ensureNotDisposed()` に `@internal` が付いている。
- [ ] 3 メンバーが公開 dartdoc に現れない。
- [ ] `flutter analyze` が成功する。コメント・アノテーションのみの変更のため専用の関連テストはなし。

## 解決方法

- `lib/src/sora_media_stream.dart` の `LocalMediaStream.ensureNotDisposed()`、`LocalMediaStreamTrack.nativeTrackAddress`、`LocalMediaStreamTrack.ensureNotDisposed()` に `@internal` を付与した。
- `dart doc` の生成結果から 3 メンバーが除外されることを確認した。
- `// ignore_for_file: public_member_api_docs` は、外すと `public_member_api_docs` が 11 件発生して `flutter analyze --fatal-infos` が clean にならないため残した。
- `flutter analyze --fatal-infos lib test` 成功、`flutter test` 137 件成功（FFI 依存は環境変数未指定で skip）。
