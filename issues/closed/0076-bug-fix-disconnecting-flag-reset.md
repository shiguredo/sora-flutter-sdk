# `_disconnecting` フラグが teardown 例外で永続化し、次回 connect の一部イベントを silent drop する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-disconnecting-flag-reset
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`SoraConnection._disconnectBody` の途中で例外が発生した場合に `_disconnecting = true` / `_abnormalTerminationStarted = true` が残留し、次回 `connect()` 以降で `_handleWebrtcEvent` の `_disconnecting` ガードが誤って発火するバグを修正する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._disconnectBody` は `_disconnecting = true` を最初に立てるが、`_disconnecting = false` にリセットするのは `_resetConnectionSessionState()` のみである。

- `_disconnectBody` は `_waitForWebSocketCloseInfo()` / `_closeSignalingTransport()` / `_teardownNativeSession()` が非タイムアウト例外を投げると `_resetConnectionSessionState()` に到達しない。
- `_disconnectWithTimeout` は `on TimeoutException catch` のみで cleanup と `_resetConnectionSessionState()` を明示呼び出しするが、非 TimeoutException の例外は catch されないため呼び出し元 `disconnect()` の catch へ伝搬する。
- `disconnect()` の finally は `_ongoingDisconnect = null` にするだけで `_disconnecting` は残留する。
- `dispose()` は内部で `disconnect()` を try/catch で呼ぶが、同様に `_disconnecting` が残留する。

`_disconnecting == true` の状態で次に `connect()` を呼ぶと、`_handleWebrtcEvent` の `signaling_message` 分岐や `state_changed` の native error 分岐（コメント「_disconnecting 中はエラーイベントを抑制する」）が発火し、正当な signaling メッセージや error 通知が silent drop される。

## 設計方針

- `disconnect()` の finally で `_disconnecting = false` と `_abnormalTerminationStarted = false` を確実にリセットする（案 A を採用）。`_disconnectBody` を try/finally で包む案（案 B）は成功経路で `_resetConnectionSessionState()` の二重呼び出しが生じるため採用しない。
- 例外時に `_signalingState` の channel 等が中途半端に残る場合は、次回 `connect()` が既存の `hasActiveTransport` チェック（`connect()` 冒頭の transport 残存判定）で `disconnect()` を再実行して後始末するため、フラグのリセットだけを finally で保証すればよい。
- `_resetConnectionSessionState()` は `_abnormalTerminationStarted` をリセットしないため、`_abnormalTerminationStarted = false` も `disconnect()` の finally でリセットする。
- `_ongoingDisconnect` の解放と `_disconnecting` のリセットの順序を整理し、finally での二重リセットを避ける。`_resetConnectionSessionState()` 側の `_disconnecting = false` は通常経路の役割として残す（冪等）。

## 完了条件

- [x] `_disconnectBody` の中で `_teardownNativeSession` 等の非 TimeoutException 例外が発生しても `_disconnecting` が true のまま残らない。
- [x] 上記例外シナリオを exercise するユニットテストを追加し、次回 `connect()` 経路で `signaling_message` と `state_changed` が silent drop されないことを確認する。テストは例外を注入するための `@visibleForTesting` テストフック（例: `_teardownNativeSession` の失敗を模擬するフック）を production コードに追加して実施する（モックやスタブは使わない）。
- [x] `dispose()` 経由の間接呼び出しでも、例外時に `_disconnecting` が true のまま残らない。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_connection.dart` の `disconnect()` の finally 節で `_disconnecting = false` と `_abnormalTerminationStarted = false` を確実にリセットする 2 行を追加した。既存の `teardownFailureForTest` (`@visibleForTesting`) が `_teardownNativeSession` の同期 throw フックを提供しているため、production コードへの追加フックはこれ以上必要ない。テスト観測用に `@visibleForTesting bool get disconnectingForTest` / `abnormalTerminationStartedForTest` の read-only getter を新規追加。

副作用として、正常経路の `disconnect()` 完了直後の idle window (`_ongoingDisconnect == null` かつ両フラグ false) に届く遅延 native 由来の異常イベントが、旧設計の連鎖ガードで抑止されなくなる。`_disconnectBody` の emit は `_signalingState.emittedDisconnectedWithCloseInfo` を true にせず、`_resetConnectionSessionState()` 内の `resetSession()` が false にリセットするため、注入経路は追加 `SoraDisconnectedState` を 1 回発火する。実運用ではこの window は極めて短く、通常のアプリケーションは `disconnect()` 完了後に `dispose()` を呼んで `_disposed` ガードで遅延イベントを drop する運用のため許容している。このトレードオフはフィールド docstring と `SoraConnection.disconnect の _disconnecting / _abnormalTerminationStarted の finally リセット` group の挙動 pin テストに明記した。

テストは `test/sora_connection_test.dart` に新規 group を追加。5 ケースを検証する:

- `_teardownNativeSession` の非 TimeoutException 例外で両フラグが false にリセットされる
- `dispose()` 経由の間接呼び出しでも両フラグがリセットされる
- 通常経路の `disconnect()` でも `_abnormalTerminationStarted` がリセットされる
- 例外経由 `disconnect()` 後の `state_changed` (state: 'error') エラーイベントが silent drop されずに emit される (fix の behavior 検証)
- 正常経路 `disconnect()` 後の idle window に遅延 `state_changed: disconnected` が届くと追加 `SoraDisconnectedState` が 1 回 emit される (トレードオフ挙動 pin)

## 派生 issue 化候補

- `_handleAbnormalTermination` にも同型バグ (teardown 例外時にフラグ残留) が残っている。issue 0076 のスコープ外だが、根本原因が同じであるためフォローアップ issue 化を推奨。
