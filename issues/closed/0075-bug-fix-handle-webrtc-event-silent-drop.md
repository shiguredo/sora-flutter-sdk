# `_handleWebrtcEvent` が返す Future を捨てているため `_require*` の StateError が silent drop する

- Created: 2026-08-27
- Completed: 2026-08-28
- Branch: feature/fix-handle-webrtc-event-silent-drop
- Polished: 2026-08-27

## 解決方法

- `SoraConnection.internalCreate` の `onEvent` ラムダを、`_handleWebrtcEvent` の Future を `unawaited(...)` で明示的にラップし、`.catchError` で例外を `_emitDebugMessage` + `_emitConnectionErrorEvent(code: SoraErrorCode.unexpectedNativeEvent, ...)` に落とす形へ修正した。内側 try/catch で捕捉・emit 済みの例外は再 throw しないため二重発火しない。
- `_handleWebrtcEvent` の remote track 系イベント（`remote_track_added` / `remote_track_removed` / `remote_video_track_added` / `remote_video_track_removed`）の分岐を try/catch で囲み、`_requireRemoteTrackKind` / `_requireRemoteTrackId` / `_requireRemoteConnectionId` が投げる StateError を `_emitDebugMessage` + `_emitConnectionErrorEvent(code: SoraErrorCode.unexpectedNativeEvent)` に変換して再 throw しないようにした。`state_changed` など既存のエラー処理を持つ経路には try/catch を追加していない。
- `SoraErrorCode.unexpectedNativeEvent`（`unexpected_native_event`）を追加した。未知の type は従来どおり silent fallthrough を維持した。
- `@visibleForTesting` な `createForTest` ファクトリと `handleWebrtcEventForTest` ラッパーを追加し、MethodChannel を介さず FFI 環境で `_handleWebrtcEvent` を直接呼べるようにした。`internalCreate` と同じ安全網（`unawaited` + `.catchError`）を共有する `_createWithOnEvent` へ生成処理を共通化した。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（成功）。`test/sora_connection_test.dart` に 4 件のテストを追加し、CI の `build-linux` ジョブの FFI テスト実行対象へ同ファイルを追加した。

## 目的

Native → Dart のイベント経路で `_requireRemoteTrackKind` / `_requireRemoteTrackId` / `RemoteTrackManager._requireRemoteConnectionId` が投げる StateError が silent drop され、想定外イベントで SDK が無音のまま壊れるバグを修正する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection.internalCreate` は `WebrtcClient.create(config: ..., onEvent: (String type, Map<String, Object?> data) { soraConnection._handleWebrtcEvent(type, data); })` を呼ぶが、`_handleWebrtcEvent` は `Future<void>` を返す async 関数であり、`onEvent` ラムダはこの Future を await せず、`.catchError` も付けずに discard している。

`_handleWebrtcEvent` の `remote_track_added` / `remote_track_removed` / `remote_video_track_added` などのケースで呼ばれる `_requireRemoteTrackKind` / `_requireRemoteTrackId` は kind が空・trackId が空のときに同期 `StateError` を投げる。`RemoteTrackManager` の `_requireRemoteConnectionId` も Sora フォーマット外の trackId で同期 StateError を投げる。

Future が discard されているため、これらの例外は zone unhandled error となる場合を除き実質 silent drop され、アプリ側にはイベントもデバッグメッセージも届かない。オーディオトラックが登録されないまま接続が続く等、原因不明のバグとして表面化しにくい。

## 設計方針

- `SoraConnection.internalCreate` の `onEvent` ラムダを、`_handleWebrtcEvent(type, data)` の Future を `unawaited(...)` で明示的にラップし、`.catchError` を付けて例外を `_emitDebugMessage` + `_emitConnectionErrorEvent(code: SoraErrorCode.unexpectedNativeEvent, ...)` に落とす形に修正する。この外側 `.catchError` は内側 try/catch で捕捉しきれなかった例外の安全網としてのみ機能させ、内側で捕捉・emit 済みの例外を再 throw しない（二重発火を防ぐ）。
- `_handleWebrtcEvent` の内部では、`_require*` 系の StateError と `RemoteTrackManager` の呼び出しから伝搬する例外を try/catch で受け、`_emitDebugMessage` と `_emitConnectionErrorEvent(code: SoraErrorCode.unexpectedNativeEvent, message: ...)` を発火し、再 throw しない。捕捉範囲は remote track 系イベント（`remote_track_added` / `remote_track_removed` / `remote_video_track_added` / `remote_video_track_removed`）の分岐に限定する。`state_changed` の `_handleAbnormalTermination` 等、既に独自のエラー発火・終了処理を持つ経路には新たな try/catch を追加しない。
- 必須フィールド欠落（kind 空、trackId 空、Sora フォーマット外 trackId）のエラーコードとして、本 issue で `SoraErrorCode.unexpectedNativeEvent` を追加する（0102 は SDP / トラック追加系 8 種類に限定されており、`unexpected_native_event` は 0102 のスコープ外のため本 issue 側で決める）。未知の type は現行の silent fallthrough（if 連鎖の末尾で何もしない）を維持し、エラー化しない。

## 完了条件

- [ ] 想定外の native イベント（kind 空、trackId 空、Sora フォーマット外 trackId）を受信しても silent drop せず、`SoraConnectionErrorEvent`（code: `unexpectedNativeEvent`）と debug message が発火する。
- [ ] 上記シナリオを exercise するユニットテストを追加する。テストは `_handleWebrtcEvent` を直接呼ぶための `@visibleForTesting` ラッパーを追加して実施する（モックやスタブは使わない）。
- [ ] `onEvent` から呼ばれる `_handleWebrtcEvent` の返り Future が zone unhandled error にならない。
- [ ] 内側 try/catch と外側 `.catchError` で同じ例外が二重に emit されない。
- [ ] `flutter analyze` と関連テストが成功する。
