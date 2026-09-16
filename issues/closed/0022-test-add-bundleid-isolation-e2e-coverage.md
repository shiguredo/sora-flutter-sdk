# 同一 bundleId 間の受信分離を確認する E2E テストを追加する

- Priority: Medium
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-bundleid-isolation-e2e-coverage
- Polished: 2026-06-03
- Completed: 2026-06-24

## 目的

同一 `bundleId` を持つ接続同士で互いの音声、映像、メッセージ、通知を受信しない契約を E2E で確認する。

## 優先度根拠

- `bundleId` は複数接続を扱う利用者にとって重要な制御項目である
- サーバー仕様依存があるため基本接続よりは優先度を下げるが、未検証のまま残すべきではないため Medium とする

## 現状

- `lib/src/sora_connection_config.dart` は `bundleId` を公開している
- `lib/src/sora_connection_signaling.dart` は `bundle_id` を connect message に載せる
- README では同一 `bundle_id` 接続間で互いを受信しなくなると説明している
- 既存 E2E は `bundleId` を使っていない

## 設計方針

- この issue は **メディア受信分離** を主契約に限定する。DataChannel / notify の分離までは補助ログにとどめ、pass 条件から外す
- 同一 channel に 3 接続を参加させ、`bundleId` が同じ組と異なる組を混在させる
- 具体的には A = `recvonly` + `bundleId: bundle-a`、B = `sendonly` + `bundleId: bundle-a`、C = `sendonly` + `bundleId: bundle-b` とし、A が B を受信せず C を受信することを確認する
- `0239` の 2 クライアント helper を拡張し、観測者を 1 接続に絞って検証を単純化する

## 完了条件

- 同一 `bundleId` 同士で remote track を受信しないことを確認する E2E がある
- 異なる `bundleId` 間では受信できることを確認している
- 観測者 A の `remoteMediaStreams` または `SoraTrackEvent` が C 由来だけを受け取ることを確認している
- 実行前提と期待挙動が README に明記されている

## 解決方法

1. 同一 channel に A / B / C の 3 接続を参加させる E2E を追加する
2. A を `recvonly`、B と C を `sendonly` とし、A / B に同じ `bundleId`、C に別 `bundleId` を設定する
3. A が B 由来の `SoraTrackEvent` や `remoteMediaStreams[B.connectionId]` を受信しないことを確認する
4. A が C 由来の video track を受信し、`video inbound-rtp` が増加することを確認する
5. 必要に応じて DataChannel / notify の分離も補助ログとして残す
6. README と `CHANGES.md` の `### misc` を更新する
