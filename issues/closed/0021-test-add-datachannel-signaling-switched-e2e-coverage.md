# DataChannel signaling への switched を確認する E2E テストを追加する

- Priority: Medium
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-datachannel-signaling-switched-e2e-coverage
- Polished: 2026-06-03
- Completed: 2026-06-24

## 目的

`dataChannelSignaling` 利用時に `SoraSwitchedEvent` が発火し、その後も signaling が継続できることを E2E で確認する。

## 優先度根拠

- switched 周辺は過去修正が多く、回帰監視価値が高い
- ただし専用のサーバー前提や環境条件があり、基本送受信よりは優先度を下げて Medium とする

## 現状

- `lib/src/sora_connection_event.dart` に `SoraSwitchedEvent` がある
- `lib/src/sora_connection_signaling.dart` は `switched` message を処理し、`signalingSwitched` を更新している
- `CHANGES.md` に switched 後の切断競合修正が複数記録されている
- 既存 E2E は `switched` の発火を確認していない

## 設計方針

- この issue は **`SoraSwitchedEvent` 発火と switched 後継続** に限定する。`ignoreDisconnectWebSocket` の厳密検証までは含めない
- `dataChannelSignaling: true` とカスタム DataChannel を有効にした接続で確認する
- `SoraSwitchedEvent` 発火だけでなく、発火後に接続が継続し、`getStats()` または custom DataChannel 疎通が継続することまで確認する
- switched payload 自体の完全一致ではなく、イベント到達と post-switch 動作継続を主契約とする

## 完了条件

- `SoraSwitchedEvent` を待つ integration test が追加されている
- switched 後も接続が維持されることを確認している
- switched 後にも `getStats()` 成功または custom DataChannel メッセージ送受信が継続できることを確認している
- 実行に必要なサーバー前提が README に明記されている

## 解決方法

1. `ObservedConnection` に `switchedEvents` フィールドと `waitForSwitched()` メソッドを追加した
2. `custom_data_channel_e2e_test.dart` に `SoraSwitchedEvent` の発火確認と、switched 後の DataChannel 疎通継続確認を追加した
3. `e2e_test_app/README.md` に DataChannel signaling 対応サーバーが必要である旨の前提条件を追記した
4. `CHANGES.md` に変更履歴を追記した
