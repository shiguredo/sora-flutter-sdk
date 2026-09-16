# `unawaited(_handleAbnormalTermination(...))` の `.catchError` 欠如で teardown 例外が zone unhandled になる

- Created: 2026-08-27
- Completed: 2026-08-30
- Branch: feature/fix-abnormal-termination-catch-error
- Polished: 2026-08-27
- Reopened: 2026-08-30

## reopened にする理由

初回対応（commit `c1cef36`）で `_handleAbnormalTermination` の catch block に `completer.completeError(e, st)` を追加したが、直後に `rethrow` していない。結果、非同期関数の返す Future は正常完了となり、fire-and-forget 呼び出しに付けた `.catchError((e, st) { _emitDebugMessage('abnormal termination failed: $e'); })`（`sora_connection.dart:1824` と `:2034`）が発火しない。teardown 例外は `_emitDebugMessage` を経由せず、`_ongoingDisconnect` の completer.future に error として残るだけで、外部から listen されない場合は zone unhandled error になる。当初の完了条件「zone unhandled error にならない」および「`.catchError` が付き、zone unhandled error を発生させない」を実質的に満たせていない。

この状態は Linux CI の `Run FFI-dependent package tests` step で `test/sora_connection_test.dart` の `SoraConnection._handleWebrtcEvent の想定外イベント処理 異常終了の teardown 失敗が zone unhandled error にならない` テスト（issue 0141 で追加された）が failing することにより顕在化した（run `33306954289` の Build Linux job）。issue 0141 の fix で Binding 初期化を解消して初めて当該テストが実行され、`_handleAbnormalTermination` 内の catch が rethrow していない実装バグが再露呈した。

## 前提として認識すべき「CI が長期間まともに動いていなかった」問題

本 issue の再オープンが必要になった直接の原因は、`d290330 0069 VideoTrackCaptureType と captureType getter を公開 API から撤回する` の merge 以降、CI の 4 build job (Linux / Apple / Windows / Android) がすべて `Run devtools Flutter analyze` step で `undefined_identifier` / `invalid_use_of_internal_member` を出して早期停止し続けていたことにある（issue 0145 で修正）。この analyze 失敗によって `Run FFI-dependent package tests` step は **一度も実行されないまま** commit が develop に積まれ続けており、CI は名目上「実行された」形跡はあるが、実質的には FFI 依存テストの検証が **完全に飛ばされた状態でリリース準備が進行していた**。

この期間に develop へ merge された commit 群にはテストの前提を破壊する変更（0075 の `_handleWebrtcEvent` の Future 追跡、本 issue 0079 の `.catchError` 追加、0100 / 0105 / 0141 で追加された FFI 依存テスト等）が含まれており、いずれも「テストが CI で走っていない」まま polish / closed 処理を通過している。本 issue の初回対応も同様の環境下で行われ、`.catchError` が発火しない事実は **一度も CI で検証されないまま closed** に至った。

再発防止のため、以下を規約として厳格に扱う必要がある。

- CI の 1 job でも failing している状態を「常態」として運用しない。特に static analyze の failure は「ヘッダーが読めない」状態と等価であり、以降の test / build がすべて skip されるため、最優先で塞ぐ。
- issue の完了条件に「CI が実測で pass する」が含まれる場合は、`Run FFI-dependent package tests` を含む後続 step まで到達したうえで pass することを **必ず** 確認する。analyze で早期停止した状態を pass 扱いにしない。
- リリース準備期でも 1 job の failing を許容せず、CI が赤くなった時点で **他の作業を止めて赤の除去を最優先** する運用を明文化する（CODEBASE.md への追記を別 issue で扱う）。

本 issue の再対応中に判明した以下の未検出バグ群も、上記「CI が動いていなかった」ことが遠因である。

- 0141: `sora_connection_test.dart` の 5 テストが `Binding has not yet been initialized` で failing
- 0142: `sdp_negotiation_test.dart` の 4 テストが `Expected: not Pointer<Never>` で failing
- 0143: `sora_media_stream_test.dart` の 5 テストが `AudioDeviceModule init failed: rc=-1` で failing
- 0144: `webrtc_client_test.dart` の 3 テストが `Bad state: PeerConnection closed during getStats.` の unhandled StateError で failing
- 0145: `devtools/lib/main.dart` の `@internal` 化されたシンボル参照残りで analyze failure

これらは本来 CI で検出されて修正される種類のバグであり、CI が動いていれば追加時点で fail していたはずのものである。CI が長期間動かない状態を許容しない運用に切り替えない限り、同種の bug 蓄積は再発する。

追加の修正として、以下を検討する。

- `_handleAbnormalTermination` の catch block で `completer.completeError(e, st)` の直後に `rethrow;` を追加し、外側 Future にも error を伝搬させる。
- `completer.future` を外部から listen しないケースでも zone unhandled error にならないよう、`completer.future.ignore()` 等で明示的に error suppress を宣言する。

再対応時は初回対応時と同じ `@visibleForTesting teardownFailureForTest` フックで新たなユニットテストを追加し、`.catchError` 側の `_emitDebugMessage` 発火を検証する。

## 解決方法（再オープン後の追加修正）

- `lib/src/sora_connection.dart` の `_handleAbnormalTermination` の catch block を `completer.completeError(e, st);` だけの実装から `completer.future.ignore(); completer.completeError(e, st); rethrow;` の 3 行構成に変更した。これにより (1) 誰も `_ongoingDisconnect` を await していない場合でも `completer.future` が zone unhandled error にならず、(2) 外側 Future にも例外を rethrow するため `_handleAbnormalTermination()` を呼ぶ側に付いている `.catchError` (本ファイル 2 箇所と `sora_connection_signaling.dart` 6 箇所) が発火し、teardown 例外を debug message へ変換する経路が成立するようになった。
- `.ignore()` を `completeError` より先に置く順序に統一した。unhandled 判定は microtask 境界で走るため、`completeError` より前に error handler が登録されている必要は必ずしもないが、順序依存を減らすため defensive に先に張る。
- 呼び出し側 (`_handleWebrtcEvent` の 2 分岐と `sora_connection_signaling.dart` の 6 箇所) の `.catchError` chain は initial fix (commit `c1cef36`) の時点で既に配置済みであり、本修正では変更しない。
- Linux CI の `Run FFI-dependent package tests` step で `test/sora_connection_test.dart` の `異常終了の teardown 失敗が zone unhandled error にならない` テストが pass することにより検証する（本 issue 0079 と併走する issue 0141 の一部）。

## 解決方法（初回対応 — 実装バグにより不十分だった）

- `lib/src/sora_connection.dart` と `lib/src/sora_connection_signaling.dart` の `unawaited(_handleAbnormalTermination(...))` 全箇所に `.catchError((error, stackTrace) { _emitDebugMessage('abnormal termination failed: $error'); })` を付け、teardown 例外が zone unhandled error にならないようにした。
- `_handleAbnormalTermination` の try/catch を追加し、teardown が throw した場合は `completer.completeError(e, st)` で `_ongoingDisconnect` を await している呼び出し側へ伝搬するようにした。例外は再 throw せず、completer への completeError のみ行うことで二重通知を避けた。
- `_handleWebrtcEvent` の `peer_connection_failed` 分岐の `await _handleAbnormalTermination()` にも `.catchError` を付け、debug message のみで受け止めるようにした（エラーイベントの emit は 0075 の外側 catchError に委ね、二重通知を避ける）。
- `@visibleForTesting` な `teardownFailureForTest` フックを `SoraConnection` に追加し、`_teardownNativeSession` 冒頭で指定された例外を throw するようにした。モックやスタブを使わずに teardown 失敗経路を検証できる。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（成功）。`test/sora_connection_test.dart` に異常終了の teardown 失敗が zone unhandled error にならないテストを追加した。

## 目的

`_handleAbnormalTermination` を fire-and-forget する経路のうち 7 箇所で `.catchError(...)` が付いておらず、`_teardownNativeSession` 等が throw した際に zone unhandled error になるバグを修正する。同ファイル内の他の unawaited は `.catchError` を付けているため、規約の一貫性としても穴になっている。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._handleWebrtcEvent` の `data_channel_closing` / `data_channel_closed` 経路（`unawaited(_handleAbnormalTermination())`）と、`lib/src/sora_connection_signaling.dart` の `_handleWebSocketError` / `_handleWebSocketDone` の 6 箇所で `unawaited(_handleAbnormalTermination(...))` が呼ばれているが、`.catchError` が付いていない。

- `_handleAbnormalTermination` は内部で `_closeSignalingTransport()`（`sink.close()` / `subscription.cancel()`）と `_teardownNativeSession()` の `webrtcClient.disconnect()` を await する非同期処理であり、これらの失敗で throw する余地がある。なお `_teardownNativeSession` 内の `_stopVideoCaptureBackend` / `_stopPendingVideoCaptureOperation` / `detachAllRemoteVideoTracks` は try/catch で捕捉され error event に変換されるため throw しない。
- 同ファイル内の他の unawaited（DataChannel handler の `_dataChannelController.handleMessage(...).catchError(...)` など）は `.catchError` を付けているため、書き方が不揃い。
- `_handleAbnormalTermination` の finally は無条件で `completer.complete()` を呼ぶ。teardown が throw した場合でも `_ongoingDisconnect` を await している呼び出し側には成功として返る挙動になっている。

## 設計方針

- 該当する全ての `unawaited(_handleAbnormalTermination(...))`（計 7 箇所）に `.catchError((error, stackTrace) { _emitDebugMessage('abnormal termination failed: $error'); })` 相当を付け、zone unhandled error を防ぐ。
- `_handleAbnormalTermination` の finally を try/catch で挟み、teardown が throw した場合は `completer.completeError(e, st)` を呼ぶ形に変更する。この変更は `_ongoingDisconnect` を await している呼び出し側（`onSignalingClose` 内の `await existingDisconnect`、`connect()` 内の `await ongoingDisconnect` / `await disconnecting`、`disconnect()` 内の `await existing`、`_handleWebrtcEvent` 内の `await existingDisconnect`）に teardown 例外が伝搬する挙動変更をもたらすため、以下の方針で整合させる:
  - `disconnect()` の catch（764-766 行）は `completeError` + `rethrow` する既存パターンがあり、`connect()` は catch を持たず例外がそのまま呼び出し元へ伝搬する。いずれも追加の catch は不要で、teardown 例外が公開 API の呼び出し元へ伝搬する挙動になるが、これは teardown 失敗を通知する正当な挙動として許容する。
  - `onSignalingClose` 内の `await existingDisconnect`（83 行）は `_handleSignalingDataChannelMessage` の catch が受け止め、`_handleWebrtcEvent` 内の `await existingDisconnect`（1763-1765 行）は 0075 の外側 `.catchError`（onEvent ラムダに付与予定）が受け止める。この経路で teardown 例外が二重にエラー通知されないよう、`_handleAbnormalTermination` の catch 内ではエラーを再 throw せず、completer への completeError のみ行う。
  - `_handleWebrtcEvent` の `peer_connection_failed` 分岐の `await _handleAbnormalTermination()`（1746 行）は、`.catchError` が付いていない経路であるため、teardown が throw すると zone unhandled になる。この経路に本 issue で `.catchError` を付けて zone unhandled error を防ぐ。0075 の外側 `.catchError` が後に付く場合は debug message（本 issue の catchError）と error event（0075 の外側）の 2 系統の通知が併存するが、本 issue の catchError は debug message のみに限定し、エラーイベントの emit は行わないことで二重通知を避ける。
- 専用ヘルパー（例: `_runAbnormalTerminationDetached`）は追加せず、`unawaited(_handleAbnormalTermination(...).catchError(...))` の直接記述で統一する。ヘルパー追加は実装を複雑にするだけであり、既存の DataChannel handler のパターンと同型の直接記述が一貫しているため。

## 完了条件

- [ ] `unawaited(_handleAbnormalTermination(...))` の 7 箇所全てで `.catchError` が付き、zone unhandled error を発生させない。
- [ ] `_handleAbnormalTermination` の finally で teardown 例外が呼び出し側に伝わる（completer が completeError で解決する）。
- [ ] `_handleWebrtcEvent` の 1746 行経路でも teardown 例外が zone unhandled error にならない。
- [ ] 上記シナリオを exercise するユニットテストを追加する。テストは `_teardownNativeSession` の失敗を模擬する `@visibleForTesting` テストフックを production コードに追加して実施する（モックやスタブは使わない）。
- [ ] `flutter analyze` と関連テストが成功する。
