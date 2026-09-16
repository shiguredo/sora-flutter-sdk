# WebSocket シグナリングメッセージの順序保証がなく、大 offer 中に candidate が先行して silent drop する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-websocket-signaling-message-order
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

WebSocket 経路で受信するシグナリングメッセージの処理順序が保証されておらず、offer が isolate へ decode offload されている間に後続の candidate が先に handler へ届いて silent drop されるバグを修正する。redirect 中に old channel の buffer から漏れる並行処理も併せて解消する。なお、redirect 中の接続失敗のエラー処理（try/catch、`_emitConnectionErrorEvent` 等）は 0072 の範囲であり、本 issue では扱わない。

## 現状

`lib/src/sora_connection_signaling.dart` の `_connectWebSocket` は `channel.stream.listen((Object? message) => _handleWebSocketMessage(message), onError: ..., onDone: ...)` で購読する。`_handleWebSocketMessage` は `Future<void>` を返す async 関数で、内部で `_decodeJsonMapMaybeOffloaded` を await する。32KiB を超える offer は `Isolate.run` へ decode を offload するが、`listen` はコールバックが返す Future を discard するため、後続の小さい candidate（同期で decode 完了）が先に handler へ届く可能性がある。

その結果、`WebrtcClient.handleCandidate` の `_disposed || _pcRef == null` 早期 return（`lib/src/ffi/webrtc_client.dart`）で ICE candidate が silent drop され、ICE 収束が遅延あるいは失敗する。

比較として DataChannel 経路には `SoraDataChannelController._enqueueSignalingDataChannelMessage`（`lib/src/sora_data_channel_controller.dart`）による tail Future での直列化と、専用テストがある。WebSocket 経路にはこれに相当する機構がない。

redirect 経路（`_handleRedirectMessage`）でも old channel が close される前に buffer 済みメッセージが listen 側で並行処理される可能性が同じ根で存在する。

## 設計方針

- `SignalingSessionState` に「WebSocket メッセージ処理の tail Future」を持たせ、`_handleWebSocketMessage` の呼び出しをこの tail に append して直列化する。DataChannel 側の `_enqueueSignalingDataChannelMessage` と同じ設計に揃える。すなわち、append を行う `_enqueueWebSocketMessage` 相当と実処理（`_handleWebSocketMessage`）を分離し、`listen` コールバックは append 側を呼ぶ構成にする。テストは append 側（enqueue 経由）を呼ぶことで tail 直列化自体を検証する。
- `listen` の onError / onDone は既存挙動を維持し、message ハンドラだけを直列化する。
- redirect による channel 切替時は、**tail の破棄やキャンセルは行わない**。Dart の Future はキャンセル不能であり、実行開始済みの `_handleWebSocketMessage`（decode offload 中の offer 等）は完了まで走るため、破棄しても並行処理の防止にはならない。単一の tail チェーンに old / new 両 channel のメッセージを順次 append することで、redirect 直前の old channel からのメッセージが new channel のメッセージと並行処理されないことを保証する（直列化自体が完了条件 3 を満たす）。過剰に古いメッセージが残る場合は、redirect 後の新しい offer がセッションを更新するため実害がない。
- tail Future のライフサイクルは DataChannel 側と対称にする。`_resetConnectionSessionState()`（`resetSession()`）で tail を null 化し、次回 `connect()` に前回セッションの未完了 tail チェーンを持ち越さない。
- 直列化による latency 増は許容範囲内（次のメッセージが数 ms 遅れる程度）。

## 完了条件

- [x] WebSocket 経路のシグナリングメッセージが受信順に処理されることをユニットテストで担保する。テストは `_enqueueWebSocketMessage` 相当の append 側を直接呼ぶための `@visibleForTesting` ラッパーを追加して実施する（モックやスタブは使わない）。`_handleWebSocketMessage` を直接呼ぶラッパーでは tail を迂回し順序保証を検証できないため、append 側を呼ぶ。
- [x] 大 offer → 直後 candidate のシナリオで candidate が silent drop されない。
- [x] redirect 直前の old channel からのメッセージが new channel のメッセージと並行処理されない。テストは tail レベルで old / new のメッセージを enqueue 経由で投入して順序を検証する方式で実施する（モックやスタブは使わない）。
- [x] DataChannel 経路の tail 直列化テストと構造上対称なテストが `test/` 配下に存在する。
- [x] セッションリセット（`_resetConnectionSessionState()`）で tail が null 化され、次回 `connect()` に持ち越されないことをテストで確認する。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_signaling_session_state.dart` に `Future<void>? webSocketMessageTail` フィールドを追加し、`resetSession()` で null に戻す。`lib/src/sora_connection_signaling.dart` に `_enqueueWebSocketMessage(Object? message)` ヘルパを追加し、`_signalingState.webSocketMessageTail` に append することで受信順の直列化を保証する。`.catchError((Object _, StackTrace _) {})` で先行メッセージ失敗をチェーン継続させる方針は DataChannel 側の `_enqueueSignalingDataChannelMessage` と対称。

`_handleWebSocketMessage(message)` を呼び出す 3 箇所 (`_connectWebSocket` の listen、`_handleRedirectMessage` の new channel listen、`injectSignalingWebSocketForTest`) を `_enqueueWebSocketMessage(message)` 経由に差し替える。redirect による channel 切替時も tail の破棄・キャンセルは行わず、single tail chain に old / new 両 channel のメッセージを順次 append することで並行処理を防ぐ (Dart Future はキャンセル不能なため、実行開始済みのメッセージ処理は完了まで走ることを受容)。

`_enqueueWebSocketMessage` の末尾で `try { await current; } catch { _emitDebugMessage(...) }` により `_handleWebSocketMessage` の throw を吸収する。listen コールバックは返り Future を discard するため、caller に throw を伝搬させると zone unhandled error になる (0079 と同型)。DataChannel 側は caller `_dataChannelController.handleMessage(...).catchError(...)` が吸収するのに対し、WS 側は helper 内で吸収する非対称構造で、この設計理由は `_enqueueWebSocketMessage` の docstring に明記した。

テスト用フックとして `@visibleForTesting Future<void> enqueueWebSocketMessageForTest(Object? message)` と `@visibleForTesting bool get hasWebSocketMessageTailForTest` を追加。後者は internal Future を晒さず bool のみを返し、外部からの await 誤用を防ぐ。

テストは `test/sora_connection_test.dart` の `SoraConnection WebSocket シグナリングメッセージ順序` group で 4 ケース追加する。

- 大 offer (40KB padding) の Isolate offload 中に届いた小 candidate が受信順で processing される (silent drop の実効防止は tail 直列化の帰結として保証、順序保証まで直接検証)
- redirect 相当の old / new 両 channel からのメッセージが同一 tail で直列化される (2 個の StreamController を用意し、それぞれの listen を `enqueueWebSocketMessageForTest` に張って dynamic 検証)
- `disconnect()` の `_resetConnectionSessionState()` (`resetSession()`) で tail が null 化される
- 未完了 tail (40KB in-flight) のまま `disconnect()` を呼んでも tail が null 化される

## 派生 issue 化候補

- Round 2 で「Test 2 が `_handleRedirectMessage` 本体の実 flow を exercise しない」との指摘。issue 完了条件文面 (tail レベル検証) は満たしているが、redirect フロー破壊時の回帰検出力は限定的。将来的に `_handleRedirectMessage` の redirect 経路そのものが tail を破壊しないことを end-to-end で検証する追加テストの余地あり。
