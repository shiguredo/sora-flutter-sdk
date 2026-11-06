# redirect 直後の WebSocket close が redirect 処理より先に処理されて接続に失敗するバグを修正する

- Created: 2026-11-06
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-redirect-close-race
- Polished: {YYYY-MM-DD}

## 目的

Sora のクラスター構成では、シグナリング接続時に `type: redirect` メッセージを受け取り、指定された `location` へ再接続する。Sora サーバーは redirect メッセージを送った直後に旧 WebSocket を `close(1000, "REDIRECT")` で閉じる。SDK はこの close を redirect 処理と競合させ、redirect 中の接続を「サーバー主導の切断」と誤認して `connect()` を失敗させる。クラスター redirect を経由する環境では、遅延やパケット分割の状況によって接続が不安定になるため修正する。

## 現状

- 2026-11-06 の E2E Test (develop push, run 42138410797) で、46 ジョブ中 33 ジョブが `Bad state: PeerConnection disconnected before connected` で失敗した。スタックは `_SoraConnectionSignaling._handleWebSocketDone` → `WebrtcClient.handleDisconnect` → `SoraConnection._handleWebrtcEvent` → `_failConnectReady` で、WebSocket の close が起点になっている。
- 同時刻に実行された別の E2E Test (tag push, run 42138413842) でも 46 ジョブ中 39 ジョブが失敗した。成功したジョブの顔ぶれは 2 つの run でほぼ異なり、同じテストが OS によって成功したり失敗したりした。E2E と SDK のシグナリング実装は前回成功時 (2026-09-16) から `SoraSDKVersionGen` の定数以外に差分がない。
- サーバーのフレームを直接観測すると、`{"type":"redirect","location":...}` の直後に `CLOSE code=1000 reason=REDIRECT` が届く。
- SDK の現状:
  - `_SoraConnectionSignaling._connectWebSocket` の `listen` は受信メッセージを `_enqueueWebSocketMessage` で `webSocketMessageTail` に連結し、非同期に処理する。
  - 一方、`onDone` は `_handleWebSocketDone` を同期で呼ぶ。
  - `_handleWebSocketDone` は `_signalingState.webSocketChannel` がまだ旧 channel (`currentChannel == channel`) の状態で `closeCode != null` の場合、`_webrtcClient.handleDisconnect()` を呼び、サーバー主導の切断として扱う。
  - `webSocketChannel` を `null` にするのは `_handleRedirectMessage` が非同期キューの先頭に到達してから。
- したがって、redirect メッセージと close フレームが続けて届くと、close が先に処理されて redirect が切断として扱われ、接続待ちが失敗する。close が先に処理されるかはパケット分割とイベントループの順序に依存し、ローカルで同じ順序を再現したところ 10 回中 7 回で close が先行した。
- `issues/closed/0077-bug-fix-websocket-signaling-message-order.md` ではメッセージハンドラのみを tail で直列化し、`onError` / `onDone` は既存挙動を維持すると判断していた。redirect 直後に close するサーバー挙動はこの前提を破る。
- `issues/closed/0072-bug-fix-redirect-message-error-handling.md` は redirect 失敗時の例外処理と state 復元を扱っており、close 順序の競合は対象外。

## 設計方針

- close の処理も受信メッセージと同じ tail に連結し、受信順に処理する。`onDone` から直接 `_handleWebSocketDone` を呼ばず、`_enqueueWebSocketMessage` と同様のヘルパで `webSocketMessageTail` に append する。これにより redirect メッセージの処理 (`webSocketChannel` の null 化) が完了してから close が評価される。
- `webSocketMessageTail` は redirect をまたいで単一チェーンを維持する既存方針 (0077) を踏襲する。old / new channel のメッセージと close が同じ順序で処理される。
- close の処理順を遅らせても、切断状態の確定が pending メッセージの処理後になるだけで問題ない。タイムアウトや異常終了の経路は既存のまま維持する。
- 「reason が REDIRECT の close を一律無視する」ような理由文字列依存の判定は行わない。他の 1000 close と区別できず、サーバー側の理由文字列変更にも弱いため、あくまで受信順で解決する。
- 回帰テストは `dart:io` の `HttpServer` + `WebSocketTransformer` で実 WebSocket サーバーを立て、redirect メッセージ送信直後に close するサーバーに対して `connect()` が redirect 先で成功することを検証する。既存の redirect テストは `handleRedirectMessageForTest` を直接呼ぶため、stream 経由の close 順序を exercise していない。
- redirect 失敗時の `SoraConnectionErrorEvent` と異常終了 (0072)、および tail 直列化 (0077) の既存挙動を壊さない。

## 完了条件

- [ ] redirect メッセージ直後に close するサーバーに対して、`connect()` が redirect 先で成功する
- [ ] close が redirect 処理より先に届いても `PeerConnection disconnected before connected` にならない
- [ ] redirect ではない通常のサーバー主導 close の扱いが変わらない
- [ ] redirect 失敗時のエラー通知と異常終了の挙動が変わらない
- [ ] 実 WebSocket サーバーを使った回帰テストが追加され、モックやスタブを使用していない
- [ ] `flutter analyze --fatal-infos` と関連テストが成功する
- [ ] `CHANGELOG.md` は正式リリース前のため追記しない (`CODEBASE.md` の規約に従う)

## 関連 issue

- `issues/closed/0077-bug-fix-websocket-signaling-message-order.md`: WebSocket メッセージの tail 直列化。本 issue は `onDone` も同じ順序保証に含める拡張
- `issues/closed/0072-bug-fix-redirect-message-error-handling.md`: redirect 失敗時の例外処理と state 復元
