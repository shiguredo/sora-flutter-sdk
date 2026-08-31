# `SoraDisconnectReason` に PeerConnection 由来コードを列挙する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-sora-disconnect-reason-pc
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`SoraConnection` 内 private 定数として `_disconnectReasonServerDisconnect` / `_disconnectReasonPeerConnectionFailed` / `_disconnectReasonPeerConnectionClosed` が定義されているが、対応する `SoraDisconnectReason` には列挙されていない。API 一貫性のため列挙側にも定義する。

## 現状

`lib/src/sora_error_code.dart` の `SoraDisconnectReason` は現在 3 値（`noError`, `websocketOnClose`, `websocketOnError`）のみで、クラスドキュメントは「Sora に送信する `disconnect` メッセージの理由コード」と定義されている。

一方 `lib/src/sora_connection.dart` には以下の private const が定義されている:

- `_disconnectReasonServerDisconnect = 'server_disconnect'`
- `_disconnectReasonPeerConnectionFailed = 'peer_connection_failed'`
- `_disconnectReasonPeerConnectionClosed = 'peer_connection_closed'`

これらは `_handleWebrtcEvent` の `state_changed` 分岐で native イベントの `reason` と比較する目的で使われている（`server_disconnect` は `WebrtcClient.handleDisconnect`、`peer_connection_failed` / `peer_connection_closed` は `WebrtcClient._onConnectionChange` が emit する）。既存の 3 値が Sora へ送信する理由コードであるのに対し、これらは native から受信する切断の内部 reason タグである。列挙側と private 定数側で分類軸がずれており、利用者が `SoraDisconnectReason` を見ても全種類を把握できない。

## 設計方針

- `SoraDisconnectReason` のクラスドキュメントを「Sora に送信する `disconnect` メッセージの理由コード」から「切断理由コード全般（Sora への送信用と、SDK 内部で切断分類に使う受信側コードの両方）」に拡張し、送信側と受信側のコードが混在することを明示する。
- `SoraDisconnectReason` に以下を追加する:
  - `serverDisconnect = 'server_disconnect'`
  - `peerConnectionFailed = 'peer_connection_failed'`
  - `peerConnectionClosed = 'peer_connection_closed'`
- `SoraConnection` の private 定数を廃止し、`SoraDisconnectReason` の値と直接比較する。
- 追加した値の dartdoc に「どの状況で発火するか」を明記する。`peerConnectionFailed` / `peerConnectionClosed` は PeerConnection 由来、`serverDisconnect` はサーバー主導の切断であることを区別して書く。
- 既存の literal 比較箇所（`_handleWebrtcEvent` の 1743, 1761-1762 行）を書き換える。

## 完了条件

- [ ] `SoraDisconnectReason` に PC 由来 / サーバー主導の 3 値が追加されている。
- [ ] `SoraDisconnectReason` のクラスドキュメントが「切断理由コード全般」に拡張されている。
- [ ] `SoraConnection` の private 定数が廃止され、enum 経由で比較している。
- [ ] 追加した値の dartdoc に発火状況が明記されている。
- [ ] `flutter analyze` と関連テストが成功する。
