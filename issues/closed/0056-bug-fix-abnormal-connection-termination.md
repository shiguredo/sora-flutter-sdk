# 異常終了時に Sora クライアント要求仕様どおり接続を終了する

- Created: 2026-08-03
- Completed: 2026-08-27
- Branch: feature/fix-abnormal-connection-termination
- Polished: 2026-08-03

## 目的

確立済みの接続で `RTCPeerConnection`、WebSocket、または `RTCDataChannel` に異常が発生した場合に、Sora クライアント要求仕様どおり接続を終了する。

現状は一部の異常をエラーイベントとして通知するだけで、ネイティブセッションの破棄、接続状態の初期化、切断イベントの通知まで実行されない経路がある。

また、DataChannel シグナリングへの切り替え後に WebSocket が切断された場合の処理が、`ignore_disconnect_websocket` の値に応じた要求仕様を満たしていない。

## 仕様

[Sora クライアント要求仕様](https://sora-doc.shiguredo.jp/SORA_CLIENT) の異常終了処理に従う。

| 発生条件 | 期待する処理 |
|---|---|
| `RTCPeerConnectionState.failed` | `disconnect` メッセージを送信せず、接続を終了する |
| DataChannel シグナリングへ切り替える前の WebSocket `onclose` / `onerror` | 接続を終了する |
| 切り替え後かつ `ignore_disconnect_websocket` が `true` | WebSocket の切断を無視し、WebRTC 接続を維持する |
| 切り替え後かつ `ignore_disconnect_websocket` が `false` | DataChannel 経由で理由付きの `disconnect` メッセージを送信してから接続を終了する |
| WebSocket `onclose` | `WEBSOCKET-ONCLOSE` を理由として使用する |
| WebSocket `onerror` | `WEBSOCKET-ONERROR` を理由として使用する |
| `RTCDataChannel` の `onclose` / `onerror` | 要求仕様のタイムアウトを考慮して接続を終了する |

## 現状

- `lib/src/ffi/webrtc_client.dart` の `WebrtcClient._onConnectionChange` は、`RTCPeerConnectionState.failed` をエラーイベントへ変換するだけである
- `lib/src/sora_connection.dart` の `SoraConnection._handleWebrtcEvent` は、接続確立後の `error` に対してネイティブセッションの破棄と接続状態の初期化を行わない
- `WebrtcClient._handleDataChannelState` は DataChannel の `open` だけを通知し、`closing` と `closed` を処理しない
- `lib/src/sora_connection_signaling.dart` の `SoraConnectionSignaling._handleWebSocketDone` は `signalingSwitched` を一部考慮しているが、`ignore_disconnect_websocket` の値に応じた分岐を持たない。また `closeCode != null` 時に無条件で `_webrtcClient.handleDisconnect()` を呼び、DataChannel 経由の理由付き `disconnect` 送信や接続維持の判断を行わない
- `SoraConnectionSignaling._handleWebSocketError` は `signalingSwitched` と `ignore_disconnect_websocket` を全く参照しない
- WebSocket 切断時に `WEBSOCKET-ONCLOSE` または `WEBSOCKET-ONERROR` を理由とする `disconnect` メッセージ送信が実装されておらず、理由コードを表す定数も定義されていない
- `switched` メッセージで確定した `ignore_disconnect_websocket` の値が `SoraConnectionSignaling._handleSwitchedMessage` 内のローカル変数として読み捨てられており、その後の切断ハンドラから参照できない
- 複数の異常イベントが連続して発生した場合に、終了処理や切断イベントが重複する可能性がある。たとえば PeerConnection failed → DataChannel closed の連鎖や、`_handleWebSocketDone` で `handleDisconnect()` が発火した後に `peer_connection_closed` が遅延到達する経路がある
- `e2e_test_app/integration_test/connection_failure_e2e_test.dart` は接続確立前の失敗を中心に検証しており、接続確立後の異常終了を検証していない
- close frame が届かない WebSocket 異常切断（`closeCode == null`）では `_handleWebSocketDone` 内の `handleDisconnect()` が呼ばれず、接続が維持されたままになる

## 設計方針

### 状態管理

- `switched` メッセージ受信時に確定した `ignore_disconnect_websocket` の値を `SignalingSessionState` に保持する。切り替え前の接続ではデフォルト値（`false`）として扱う
- 異常終了処理の開始をガードするフラグを導入し、`_disconnecting` とは独立して複数の異常イベントの重複実行を防ぐ。異常終了が完了したらこのフラグを下ろさない（1 接続につき 1 回限り）

### `WebrtcClient` の変更

- `_onConnectionChange` の `RTCPeerConnectionState.failed` は現在の `error` イベントから、`disconnect` メッセージを送信しない異常終了用のイベント種別（`state_changed` の `disconnected` に統一する）に変更する。`closed` と同じ `disconnected` type を使い、コードで区別する
- `_handleDataChannelState` に `closing` と `closed` の分岐を追加し、シグナリング用 DataChannel の異常を `SoraConnection` へ通知する。通知は既存の `_onEvent` 経路に載せ、`SoraConnection._handleWebrtcEvent` で共通異常終了処理へ集約する

### `SoraConnection` の変更

- `_handleWebrtcEvent` の `state_changed` ハンドラで、接続確立後に `error` または異常系の `disconnected`（`peer_connection_failed` 等）を受信した場合に、共通の異常終了処理を実行する
- 共通の異常終了処理は既存の `_teardownNativeSession` + `_resetConnectionSessionState` を基本とし、以下の分岐を追加する:
  - `ignore_disconnect_websocket` が `false` でシグナリング切替後の WebSocket 切断の場合、DataChannel 経由で `WEBSOCKET-ONCLOSE` または `WEBSOCKET-ONERROR` を理由とする `disconnect` メッセージを送信してから終了する
  - `ignore_disconnect_websocket` が `true` かつシグナリング切替後の WebSocket 切断の場合、切断処理全体をスキップする
- 既存の `_disconnectBody` は変更せず、アプリケーションからの通常切断と Sora からの `type: close` による切断は引き続き現在の経路を使う

### `SoraConnectionSignaling` の変更

- `_handleSwitchedMessage` で `ignore_disconnect_websocket` の値を `SignalingSessionState` へ保存する
- `_handleWebSocketDone` に `ignore_disconnect_websocket` の値に応じた分岐を追加する:
  - シグナリング切替前（`signalingSwitched == false`）: 既存の `handleDisconnect()` 呼び出しを維持する
  - シグナリング切替後（`signalingSwitched == true`）: 既存の `handleDisconnect()` 呼び出しを抑制し、`ignore_disconnect_websocket` の値に応じて接続維持または異常終了処理を呼び出す
- `_handleWebSocketError` にも同様の分岐を追加する
- WebSocket 切断時に `onerror` → `onclose` が連鎖する場合に備え、先に `onerror` を検出した時点で異常終了を開始する。`onclose` は異常終了ガードフラグで抑制する
- close frame なしの切断（`closeCode == null`）も切り替え前の異常切断として扱い、接続終了の対象とする

### 定数定義

- `WEBSOCKET-ONCLOSE` と `WEBSOCKET-ONERROR` を `SoraErrorCode` または切断理由を表す新規定数クラスに定義する

## 完了条件

- [ ] `RTCPeerConnectionState.failed` で `disconnect` メッセージを送信せず、ネイティブセッションの破棄と接続状態の初期化を経て接続が終了する
- [ ] DataChannel シグナリングへの切り替え前の WebSocket 切断またはエラー（`closeCode == null` を含む）で接続が終了する
- [ ] 切り替え後かつ `ignore_disconnect_websocket` が `true` の場合、WebSocket の切断後も WebRTC 接続を維持する
- [ ] 切り替え後かつ `ignore_disconnect_websocket` が `false` の場合、`WEBSOCKET-ONCLOSE` または `WEBSOCKET-ONERROR` を理由に指定した `disconnect` メッセージを DataChannel 経由で送信してから接続が終了する
- [ ] シグナリング用 DataChannel の切断またはエラーを検出し、接続が終了する
- [ ] WebSocket の `onerror` → `onclose` 連鎖時や PeerConnection failed → DataChannel closed の連鎖時を含め、複数の異常イベントが連続しても終了処理と `disconnected` イベントが重複しない
- [ ] 通常の `disconnect()` と Sora からの切断処理に回帰がない
- [ ] `ignore_disconnect_websocket` の値が `SignalingSessionState` に保持され、切断ハンドラから参照できる
- [ ] `WEBSOCKET-ONCLOSE` と `WEBSOCKET-ONERROR` が定数として定義されている
- [ ] モックやスタブを使用せず、接続確立後の各異常終了経路をテストする
- [ ] `flutter analyze` と関連するテストが成功する

## 解決方法

コミット `6f88ac4` (2026-08-19) で実装し、2026.1.0 リリース (2026-08-25) に含めた。

- `WebrtcClient._onConnectionChange` が `RTCPeerConnectionState.failed` を `disconnected` 型 (reason: `peer_connection_failed`) に変換するよう変更し、`disconnect` メッセージを送信しない異常終了として扱う
- `WebrtcClient._handleDataChannelState` が `closing` / `closed` を `data_channel_closing` / `data_channel_closed` イベントとして通知し、シグナリング用 DataChannel の異常を検出できるようにした
- `SoraConnection._handleWebrtcEvent` が接続確立後の異常 (`error` / 異常系 `disconnected`) を受信した場合に、共通の異常終了処理 `_handleAbnormalTermination` を実行するようにした
- `SoraConnection._handleAbnormalTermination` を追加し、`ignore_disconnect_websocket` が `false` の場合は DataChannel 経由で理由付き `disconnect` メッセージを送信してから終了し、`true` の場合は何もしない分岐を実装した。`_abnormalTerminationStarted` フラグにより複数の異常イベントが連続しても終了処理を 1 回だけにする
- `SoraConnectionSignaling._handleWebSocketDone` / `_handleWebSocketError` に `signalingSwitched` と `ignoreDisconnectWebSocket` に応じた分岐を追加した。`closeCode == null` の異常切断も切り替え前の異常切断として接続終了の対象にした
- `SoraConnectionSignaling._handleSwitchedMessage` が `ignore_disconnect_websocket` の値を `SignalingSessionState.ignoreDisconnectWebSocket` に保存するようにした
- `SoraDisconnectReason` に `websocketOnClose` (`WEBSOCKET-ONCLOSE`) / `websocketOnError` (`WEBSOCKET-ONERROR`) を追加した
- 接続確立後の異常終了経路のユニットテスト (`test/webrtc_client_test.dart` / `test/sora_error_code_test.dart` / `test/sora_signaling_session_state_test.dart`) と E2E テスト (`e2e_test_app/integration_test/connection_failure_e2e_test.dart`) を追加した
