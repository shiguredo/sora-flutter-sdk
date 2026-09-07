# `_handleSwitchedMessage` の subscription.cancel / sink.close の Future を捨てている

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-switched-message-unawaited-cleanup
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

DataChannel シグナリングへの切替（`type: switched`）で `ignoreDisconnectWebSocket == true` の場合に、旧 WebSocket の subscription cancel と sink close の Future を捨てているため、例外が zone unhandled error になる経路を塞ぎ、cleanup の完了を待ってから後続処理へ進むよう修正する。

## 現状

`lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._handleSwitchedMessage` は同期メソッドである。`ignore_disconnect_websocket == true` の場合、`_signalingState.webSocketSubscription?.cancel()` と `channel?.sink.close()` を呼ぶが、いずれも `Future` を返す非同期処理であるにもかかわらず await せず、`unawaited(...)` も付けていない。

- `_signalingState.webSocketSubscription = null` を直後に代入するため、cancel 完了前に参照が失われる。
- `cancel()` / `sink.close()` の Future は同期メソッド内で await も return もされず、エラーハンドラも付かないまま捨てられる。Future が後から非同期にエラー完了すると zone unhandled error になる。なお同期 throw は呼び出し元の `_handleWebSocketMessage` を await する `_enqueueWebSocketMessage` の try/catch（'ws message handler failed' ログ）で吸収されるため、問題となるのは非同期のエラー完了である。
- 同ライブラリの他の cleanup（`sora_connection.dart` の `_closeSignalingTransport`、`sora_connection_signaling.dart` の `_handleRedirectMessage` と `_failRedirect`）では、Future を捨てずに await、または await + try/catch で完了を待っている。書き方の一貫性を欠く。
- `_handleWebSocketDone` は old channel の onDone を無視する。switched（`ignore_disconnect_websocket == true`）時には `_signalingState.webSocketChannel` が null 化済みのため `currentChannel == channel` 条件に合わず、かつ `signalingSwitched == true` の場合は後段追跡（`pendingDisconnectCloseInfo` の設定と `webSocketClosedCompleter` の完了）もスキップするため、old channel の close 完了順序は `_handleWebSocketDone` の追跡には影響しない。問題の本質は Future の discard による例外の zone unhandled 化と、cleanup 完了前に後続のメッセージ処理へ進む競合窓の存在である。

## 設計方針

- `_handleSwitchedMessage` を `Future<void>` に変更し、cancel / close を await する。呼び出し元は `type: switched` のハンドラ（`_handleWebSocketMessage` 内の 1 箇所のみ）で await を追加する。`_handleWebSocketMessage` の Future は `_enqueueWebSocketMessage` が await + try/catch で捕捉するため、await 化は tail 経由の次メッセージが cleanup 完了後に開始することを保証し、独立した次回 `connect()` の完了待ちを保証するものではない。
- `cancel()` と `sink.close()` は個別の try/catch で包み、失敗時は `_emitDebugMessage` にログを残して zone unhandled error を防ぐ（0072 の redirect 経路の cancel / close 保護と同様の扱い）。ログ文言は `switched: subscription cancel failed` と `switched: old channel close failed` とする。
- 完了ログとして `_emitDebugMessage` に `switched: websocket cleanup done` を残す。cancel / close のいずれかが失敗しても catch 後に必ず出す。
- テストは dart:io の `HttpServer` + `WebSocketTransformer` による実 WebSocket（既存の `injectSignalingWebSocketForTest` の前例）を使い、`enqueueWebSocketMessageForTest` で switched メッセージを投入する。zone unhandled error の有無は `runZonedGuarded` の error collector で判定し、cleanup 完了は投入 Future の完了と `debugMessages` の完了ログで観測する。`cancel()` / `sink.close()` の失敗注入には、`SoraConnection` に `@visibleForTesting Object? switchedCancelFailureForTest` と `@visibleForTesting Object? switchedCloseFailureForTest` を追加する。各々設定時は対応する実処理を行わず指定例外を throw し、参照は throw 時に 1 回で null に戻す（`teardownFailureForTest` の前例に倣う）。cancel 失敗と close 失敗は別テストで各フックを 1 回ずつ設定して exercise し、両方の catch 経路を通す。モックやスタブは使わない。

## 完了条件

- [ ] `_handleSwitchedMessage` の subscription cancel と sink close の Future が discard されない。
- [ ] `cancel()` / `sink.close()` が throw しても zone unhandled error にならない（cancel 失敗テストで `switched: subscription cancel failed` が、`close` 失敗テストで `switched: old channel close failed` が `debugMessages` に残る。失敗注入は設計方針の各フックを各テストで 1 回ずつ設定する）。
- [ ] `type: switched` のハンドラが `_handleSwitchedMessage` の完了を待つ（tail 経由の次メッセージが cleanup 完了ログの後に開始する）。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。
