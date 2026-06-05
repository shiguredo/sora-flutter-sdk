# ユーザー定義 DataChannel の送受信 E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-custom-datachannel-e2e-coverage
- Polished: 2026-06-03

## 目的

`#` プレフィックス付きユーザー定義 DataChannel の open と送受信を E2E で確認し、メッセージング API の基本品質を担保する。

## 優先度根拠

- `sendDataChannelMessage()` は主要 public API の 1 つである
- `compress` や label 解決を含む実経路はユニットテストだけでは不十分である
- 後続の RPC や switched 系より先に、基本メッセージングを固める必要があるため High とする

## 現状

- `lib/src/sora_connection.dart` は `sendDataChannelMessage()` を `DataChannelController` に委譲している
- `lib/src/sora_data_channel_controller.dart` は label ごとの open 状態やメッセージ routing を管理している
- 既存 E2E は custom DataChannel の open / message を確認していない

## 設計方針

- この issue は **custom DataChannel の基本往復** に限定する。compress の組み合わせ網羅や大容量 payload 順序検証は後続 issue に委譲する
- 2 クライアントの messaging 専用接続で `#test-channel` を使う
- `SoraDataChannelOpenEvent` の発火後に sender から receiver へバイナリを送る
- sender / receiver の両方で open を待ち、receiver 側で `SoraDataChannelMessageEvent` を待って label と payload を検証する
- 実装を安定させるため、まずは `compress: true` の 1 ケースに固定し、open event の `compress` 値でも確認する

## 完了条件

- custom DataChannel の open を確認する E2E がある
- バイナリ payload の送受信成功を確認する E2E がある
- sender / receiver 双方で `#test-channel` の open を確認している
- open event の `label` と `compress` が期待どおりであることを確認している
- 必要なら往復送信を追加し、双方向性を確認している

## 解決方法

1. `0015` の messaging-only helper を流用し、2 クライアントが同じ channel ID に入る E2E を追加する
2. `dataChannels` に `#test-channel` を含む接続設定を用意し、`compress: true` を明示する
3. sender / receiver 双方で `SoraDataChannelOpenEvent` を記録し、`label == '#test-channel'` と `compress == true` を確認する
4. sender から固定 payload を送信する
5. receiver 側で `SoraDataChannelMessageEvent.message.label` と payload が一致することを確認する
6. 必要なら receiver から sender への 1 往復も追加し、双方向性を確認する
7. flaky を避けるため open 待ち helper と message 待ち helper を共通化する
