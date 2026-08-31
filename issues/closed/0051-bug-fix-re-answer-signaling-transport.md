# re-answer を re-offer 受信経路と同じ transport で送信するよう修正する

- Priority: High
- Created: 2026-06-19
- Completed: 2026-06-22
- Model: DeepSeek V4 Pro
- Branch: feature/fix-re-answer-signaling-transport
- Polished: 2026-06-22

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
  // re-answer は DataChannel 経由で送信する
  _emitDebugMessage('dc(signaling) send: $text');
  _emitSignalingEvent('datachannel', 'sent', msgMap);
  _webrtcClient.sendSignalingMessage(sendData);
} else {
  // それ以外は WebSocket 経由で送信
  _emitDebugMessage('ws send: $text');
  _emitSignalingEvent('websocket', 'sent', msgMap);
  _signalingState.webSocketChannel?.sink.add(text);
}
```

この実装では、re-offer を **WebSocket で受信した場合でも** re-answer が DataChannel に振り分けられてしまう。DataChannel シグナリングが確立していない環境では re-answer がサーバーに届かず、約 30 秒で `code=4490 reason=TIMEOUT` 切断が発生する。

一方、sora-ios-sdk の `Sora/PeerChannel.swift` では、re-offer を受信した経路に応じて re-answer の送信先を決定している。

- WebSocket で re-offer 受信 → `createAndSendReAnswer(forReOffer:)` → `signalingChannel.send()` (WebSocket)
- DataChannel で re-offer 受信 → `createAndSendReAnswerOverDataChannel(forReOffer:)` → `dataChannel.send()` (DataChannel)

ただし、Flutter SDK のアーキテクチャは iOS SDK と異なり、re-answer は `SdpNegotiationCallbacks` 内の SDP ネゴシエーション完了時に `emitSignalingMessage` 経由で非同期的に `_handleWebrtcEvent` へ戻ってくる。そのため、iOS SDK のように re-offer 受信時に送信経路を決定して別メソッドを呼び分けるのではなく、`_handleWebrtcEvent` の `signaling_message` ハンドラで transport を決定する設計になる。

## 設計方針

iOS SDK と同様に、シグナリングチャネルの状態に応じて re-answer の送信先を決定する。

iOS SDK では `SignalingChannel` が内部で `dataChannelSignaling` フラグを持ち、`send()` 時に DataChannel シグナリングが確立済みかどうかで transport を切り替える（確立済みなら DataChannel、未確立なら WebSocket）。

Flutter SDK では `_signalingState.signalingSwitched` がこれに相当する。`_handleWebrtcEvent` の `signaling_message` ハンドラでこのフラグを参照し、re-answer の送信先を決定する。

```dart
if (_signalingState.signalingSwitched) {
  // DataChannel シグナリング確立済み → DataChannel 経由
  _webrtcClient.sendSignalingMessage(sendData);
} else {
  // WebSocket シグナリング → WebSocket 経由
  _signalingState.webSocketChannel?.sink.add(text);
}
```

## 変更対象

- `lib/src/sora_connection.dart`:
  - `_handleWebrtcEvent` 内の re-answer 分岐を `signalingSwitched` 判定に変更

## エッジケース

### DataChannel シグナリング切替後の re-offer

DataChannel シグナリングに切り替わった後（`signalingSwitched == true`）に WebSocket 経由で re-offer が届いた場合、iOS SDK と同様に DataChannel 経由で re-answer を送信する。これは `signalingSwitched == true` の状態が「DataChannel シグナリングが利用可能」を意味するためで、iOS SDK の `SignalingChannel.send()` の挙動と一致する。

## 完了条件

- DataChannel シグナリングが確立していない環境（devtools 等）で re-offer → re-answer が WebSocket 経由で正しく送信され、切断されないこと
- DataChannel シグナリングが確立している環境でも re-offer → re-answer が正しく動作すること
- DataChannel シグナリング切替後（`signalingSwitched == true`）に WebSocket 経由で re-offer を受信した場合も iOS SDK と同様に DataChannel 経由で送信されること
- 既存のテストが全て通過すること
- デバッグメッセージとシグナリングイベントの transport が実際の送信経路と一致すること

## テスト戦略

AGENTS.md の「モックやスタブは絶対に利用しないこと」に従い、以下の方法で動作確認する:

- e2e_test_app の各プラットフォームで DataChannel シグナリングを無効にした接続（devtools 等）を行い、re-offer → re-answer が WebSocket 経由で送信されることを確認する
- DataChannel シグナリングを有効にした接続でも re-offer → re-answer が正しく動作することを確認する
- `sdp_negotiation_test.dart` 相当のテストで re-answer の transport 振り分けロジックのみを単体検証する（FFI を経由しないロジック部分に限る）
- devtools 環境での切断タイムアウト（約 30 秒）が発生しないことを確認する

## 解決方法

`_handleWebrtcEvent`（`lib/src/sora_connection.dart` L1274-1295）の re-answer 分岐で `_signalingState.signalingSwitched` を参照し、送信先を決定する。

- `signalingSwitched == true`: DataChannel 経由で送信
- `signalingSwitched == false`: WebSocket 経由で送信

```dart
if (_signalingState.signalingSwitched) {
  // DataChannel シグナリング確立済み → DataChannel 経由で送信
  _emitDebugMessage('dc(signaling) send: $text');
  _emitSignalingEvent('datachannel', 'sent', msgMap);
  final encoded = utf8.encode(text);
  final Uint8List sendData;
  if (_dataChannelController.signalingCompress) {
    sendData = _dataChannelController.deflateEncode(encoded);
  } else {
    sendData = encoded;
  }
  _webrtcClient.sendSignalingMessage(sendData);
} else {
  // WebSocket シグナリング → WebSocket 経由で送信
  _emitDebugMessage('ws send: $text');
  _emitSignalingEvent('websocket', 'sent', msgMap);
  _signalingState.webSocketChannel?.sink.add(text);
}
```

`signalingSwitched` は Sora サーバーから `type: switched` メッセージを受信した時点で `true` に設定される既存のフラグである。新規フィールドの追加や DataChannelController への callback 追加は一切不要。

### データフロー

```
re-offer (WebSocket, signalingSwitched == false)
  → _handleWebSocketMessage
    → webrtcClient.handleReOffer(payload)
      → SdpNegotiationCallbacks
        → emitSignalingMessage({'type': 're-answer', ...})
          → _handleWebrtcEvent (signaling_message)
            → signalingSwitched == false → WebSocket 経由で送信

re-offer (DataChannel, signalingSwitched == true)
  → _handleSignalingDataChannelMessage
    → webrtcClient.handleReOffer(decoded)
      → SdpNegotiationCallbacks
        → emitSignalingMessage({'type': 're-answer', ...})
          → _handleWebrtcEvent (signaling_message)
            → signalingSwitched == true → DataChannel 経由で送信
```
