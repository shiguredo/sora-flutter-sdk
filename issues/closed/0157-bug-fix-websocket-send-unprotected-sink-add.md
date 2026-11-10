# WebSocket 送信 3 箇所の無防備な `sink.add` を保護する

- Created: 2026-09-07
- Completed: 2026-09-07
- Branch: feature/fix-websocket-send-unprotected-sink-add
- Polished: 2026-09-07

## 目的

切断競合時の WebSocket シグナリング送信失敗を silent にせず、調査可能にすること。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection._sendSignalingMessage` は DataChannel 分岐を try/catch して debug ログに落とす一方、WebSocket 分岐の `webSocketChannel.sink.add` は無防備である。同ファイルの `SoraConnection._disconnectBody` の切断メッセージ送信と `lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._handleWebSocketMessage` 内の pong 応答の `sink.add` も同様である。いずれも切替前または非切替時の WebSocket 経路であり、切替後は DataChannel 分岐を使うため本対象外である。

対象外とする 2 箇所は既存の重いエラー経路があるため本 issue では触れない。`SoraConnection._connect` 内の connect 送信は外側 try/catch で `_failConnectReady` と `disconnect` へ伝搬する経路であり、`_SoraConnectionSignaling._handleRedirectMessage` 内の connect 送信は `_enqueueWebSocketMessage` の失敗経路に吸収される。

## 設計方針

- 対象 3 箇所の WebSocket 送信を try/catch と `_emitDebugMessage` への記録に統一する。ログ文言は `ws send failed` と `ws pong send failed` と `ws disconnect send failed` とする（英語のみ）。
- `sent` のシグナリングイベントと `ws send` の debug ログは送信成功後に emit するよう順序を変え、失敗時は成功記録を残さない。null 安全呼び出しで channel が null の場合は送信 skip を debug ログに残す。
- 再送や再試行は追加せず、送信可否の観測可能性に絞る。
- テストは skip 分岐のみ追加する。pong skip は channel 未注入の ping で、切断 skip は未接続の `disconnect` で再現する。失敗分岐は閉じた実 channel の `onDone` 競合で flaky になるため、コードレビューで担保する。

## 完了条件

- [ ] 対象 3 箇所の送信失敗が対応する debug ログで追跡できる。
- [ ] skip 分岐のユニットテストを追加し、`test/sora_connection_test.dart` の成功で回帰を担保する。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

3 箇所の WebSocket 送信を `_trySendWebSocketText` に統一し、失敗時は debug ログに残す。成功記録は送信成功後に emit する。skip 分岐のユニットテスト 2 件で検証する。失敗分岐は実 channel の競合で flaky になるためコードレビューで担保する。正式リリース前のため `CHANGELOG.md` には記載しない。
