# re-answer を re-offer 受信経路と同じ transport で送信するよう修正する

- Priority: High
- Created: 2026-06-19
- Completed: YYYY-MM-DD
- Model: DeepSeek V4 Pro
- Branch: feature/fix-re-answer-signaling-transport
- Polished: YYYY-MM-DD

## 目的

Sora サーバーが DataChannel シグナリングをサポートしない環境（devtools 等）で re-offer 受信時に re-answer が消失し、約 30 秒で切断される問題を修正する。

## 優先度根拠

devtools を含む DataChannel シグナリング非対応のクライアントが接続できない致命的なバグであり、早期の修正が必要。

## 現状

`lib/src/sora_connection.dart` の `_handleWebrtcEvent` 内 `signaling_message` ハンドラ (L1267-1295) では、メッセージタイプが `'re-answer'` であるかどうかのみを見て経路を振り分けている。

```dart
// L1274-1295
final msgType = msgMap['type'] as String?;
if (msgType == 're-answer') {
  // 常に DataChannel 経由で送信
  _emitDebugMessage('dc(signaling) send: $text');
  _webrtcClient.sendSignalingMessage(sendData);
} else {
  // それ以外は WebSocket 経由で送信
  _emitDebugMessage('ws send: $text');
  _signalingState.webSocketChannel?.sink.add(text);
}
```

この実装では、re-offer を **WebSocket で受信した場合でも** re-answer が DataChannel に振り分けられてしまう。DataChannel シグナリングが確立していない環境では re-answer がサーバーに届かず、約 30 秒で `code=4490 reason=TIMEOUT` 切断が発生する。

一方、sora-ios-sdk の `Sora/PeerChannel.swift` では、re-offer を受信した経路に応じて re-answer の送信先を決定している。

- WebSocket で re-offer 受信 → `createAndSendReAnswer(forReOffer:)` (L903-942) → `signalingChannel.send()` (WebSocket)
- DataChannel で re-offer 受信 → `createAndSendReAnswerOverDataChannel(forReOffer:)` (L944-1015) → `dataChannel.send()` (DataChannel)

## 設計方針

iOS SDK の仕様に合わせ、re-offer を受信した経路に応じて re-answer の送信先を切り替える。

1. `_handleWebrtcEvent` の `signaling_message` ハンドラで re-answer の transport を静的に決めるのではなく、re-offer を受信した時点で transport 情報を保持する
2. re-answer 送信時に保持した transport 情報を参照し、WS 経由なら WS、DC 経由なら DC で送信する
3. 変更対象:
   - `lib/src/sora_connection.dart`: `_handleWebrtcEvent` の re-answer 分岐、re-offer 受信時に transport 情報を保持する処理
   - `lib/src/sora_connection_signaling.dart`: WebSocket 経由の re-offer 受信時に transport=websocket を記録
   - `lib/src/sora_data_channel_controller.dart`: DataChannel 経由の re-offer 受信時に transport=datachannel を記録

## 完了条件

- DataChannel シグナリングが確立していない環境（devtools 等）で re-offer → re-answer が WebSocket 経由で正しく送信され、切断されないこと
- DataChannel シグナリングが確立している環境でも re-offer → re-answer が正しく動作すること
- 既存のテストが全て通過すること

## 解決方法

1. `SoraConnectionState` または `SoraConnection` に `_reOfferTransport` フィールド (`String?`) を追加し、re-offer 受信時に `'websocket'` または `'datachannel'` を記録する
2. `_handleWebrtcEvent` の re-answer 分岐で `_reOfferTransport` を参照し、`'datachannel'` の場合のみ DC 経由で送信、それ以外は WS 経由で送信する
3. re-answer 送信後は `_reOfferTransport` をクリアする
