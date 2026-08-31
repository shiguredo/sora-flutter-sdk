# `_handleSwitchedMessage` の subscription.cancel / sink.close の Future を捨てている

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-switched-message-unawaited-cleanup
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

DataChannel シグナリングへの切替（`type: switched`）で `ignoreDisconnectWebSocket == true` の場合に、旧 WebSocket の subscription cancel と sink close の Future を捨てているため、例外が zone unhandled error になる経路を塞ぎ、cleanup の完了を待ってから後続処理へ進むよう修正する。

## 現状

`lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._handleSwitchedMessage` は同期メソッドである。`ignore_disconnect_websocket == true` の場合、`_signalingState.webSocketSubscription?.cancel()` と `channel?.sink.close()` を呼ぶが、いずれも `Future` を返す非同期処理であるにもかかわらず await せず、`unawaited(...)` も付けていない。

- `_signalingState.webSocketSubscription = null` を直後に代入するため、cancel 完了前に参照が失われる。
- `cancel()` / `sink.close()` の Future は listen コールバック（`_handleWebSocketMessage`）の戻り Future を経由して破棄されるため、close が失敗した場合の例外は zone unhandled error になる。
- 同ファイルの他の cleanup（`_closeSignalingTransport` など）では `await` している。書き方の一貫性を欠く。
- `_handleWebSocketDone` は old channel の onDone を `currentChannel == channel` ガード（sora_connection_signaling.dart:303, 307 行）で無視し、`signalingSwitched == true` の場合は後段追跡（354 行）もスキップするため、old channel の close 完了順序は本来 `_handleWebSocketDone` の追跡には影響しない。問題の本質は Future の discard による例外の zone unhandled 化と、cleanup 完了前に次の接続へ進む競合窓の存在である。

## 設計方針

- `_handleSwitchedMessage` を `Future<void>` に変更し、cancel / close を await する。呼び出し元は `type: switched` のハンドラ（`_handleWebSocketMessage` 内の 1 箇所のみ）で await を追加する。呼び出し元の Future は listen コールバックで破棄されるため、await 化は「close 完了を待ってから後続の `_handleWebSocketMessage` 処理へ進む」ことで競合窓を縮める効果であり、独立した次回 `connect()` の完了待ちを保証するものではない。
- `cancel()` / `sink.close()` の await は try/catch で包み、失敗時は `_emitDebugMessage` にログを残して zone unhandled error を防ぐ（0072 の redirect 経路の 2 段構成と同様の扱い）。
- 完了ログを `_emitDebugMessage` に残す。

## 完了条件

- [ ] `_handleSwitchedMessage` の subscription cancel と sink close の Future が discard されない。
- [ ] `cancel()` / `sink.close()` が throw しても zone unhandled error にならない（`_emitDebugMessage` にログが残る）。
- [ ] `type: switched` のハンドラが `_handleSwitchedMessage` の完了を待つ（競合窓が縮小される）。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。
