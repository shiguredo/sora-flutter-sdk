# notify と push と signalingNotifyMetadata の E2E テストを追加する

- Priority: Medium
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-notify-push-metadata-e2e-coverage
- Polished: 2026-06-03

## 目的

`SoraNotifyEvent`、`SoraPushEvent`、`signalingNotifyMetadata` の実経路を E2E で確認し、アプリがシグナリング由来 metadata に依存できるようにする。

## 優先度根拠

- metadata や notify は業務アプリで利用頻度が高い
- ただしサーバーや検証環境の前提が必要であり、基本接続よりは後段でよいため Medium とする

## 現状

- `lib/src/sora_connection_event.dart` は `SoraNotifyEvent` と `SoraPushEvent` を公開している
- `lib/src/sora_connection_config.dart` は `metadata` と `signalingNotifyMetadata` を公開している
- `lib/src/sora_connection_signaling.dart` は `metadata` と `signaling_notify_metadata` を connect message に載せる
- 既存 E2E は notify / push / metadata のどれも確認していない
- `connection.created` notify は self connection 分も届きうるため、`connection_id == connection.connectionId` を使って対象を特定できる

## 設計方針

- この issue は **notify + signalingNotifyMetadata の契約** を必須範囲とし、`push` は検証環境が用意できる場合の追加検証項目として扱う
- `connection.created` notify を主な検証対象にし、`signalingNotifyMetadata` が payload に含まれることを確認する
- `push` は検証環境が送出できる前提を README で明確化し、固定の `type` や payload key を環境変数で注入する
- payload 全体の厳密一致ではなく、必要な key と value の存在確認を行う

## 完了条件

- `SoraNotifyEvent` を確認する E2E がある
- `signalingNotifyMetadata` の値が notify payload に含まれることを確認している
- self connection の `connection.created` notify を `connection.connectionId` で特定している
- 検証環境が対応していれば `SoraPushEvent` の smoke test も追加され、期待 key の存在を確認している

## 解決方法

1. `signalingNotifyMetadata` を設定した接続を行う E2E を追加する
2. `SoraNotifyEvent` を待ち、`event_type == 'connection.created'` と `connection_id == connection.connectionId` を満たす notify を特定する
3. 対象 notify payload に `signaling_notify_metadata` と期待 key / value が含まれることを確認する
4. 検証環境で `push` を送れる場合は、`TEST_PUSH_EXPECTED_TYPE` などの環境変数で期待 payload を定義し、`SoraPushEvent` を確認する
5. README に必要なサーバー前提と実行条件を追記し、`push` が環境依存であることを明記する
