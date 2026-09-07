# WebSocket 送信分岐の無防備な `sink.add` を保護する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-websocket-send-unprotected-sink-add
- Polished: {YYYY-MM-DD}

## 目的

切断競合時のシグナリング送信失敗を silent にせず、調査可能にすること。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._sendSignalingMessage` は DataChannel 分岐を try/catch して debug ログに落とす一方、WebSocket 分岐の `webSocketChannel.sink.add` は無防備である。同ファイルの `SoraConnection._disconnectBody` の切断メッセージ送信と `lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._handleWebSocketMessage` 内の pong 応答の `sink.add` も同様である。切替直後の送信失敗が表に出ない。

## 設計方針

- WebSocket 分岐も try/catch と `_emitDebugMessage` への記録に統一する。
- 再送や再試行は追加せず、送信可否の観測可能性に絞る。

## 完了条件

- [ ] WebSocket 分岐の送信失敗が debug ログまたはシグナリングイベントで追跡できる。
- [ ] `flutter analyze` と関連テストが成功する。
