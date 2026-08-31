# 接続失敗とタイムアウトの E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-23
- Model: GPT-5 Codex
- Branch: feature/add-connection-failure-e2e-coverage
- Polished: 2026-06-03

## 目的

正常系だけでなく、認証失敗、不達、タイムアウト時のイベント契約を E2E で保証し、実運用での障害検知精度を高める。

## 優先度根拠

- 接続失敗時の振る舞いは利用側のリトライ実装に直結する
- `SoraConnectionErrorEvent` と `SoraTimeoutEvent` は公開イベント契約である
- 回帰時の影響が大きいため High とする

## 現状

- `lib/src/sora_connection_event.dart` に `SoraConnectionErrorEvent` と `SoraTimeoutEvent` がある
- `lib/src/sora_connection_signaling.dart` は signaling candidate timeout や WebSocket error を emit する
- 既存 E2E は成功系のみで、失敗系のイベントを確認していない
- `signalingCandidateTimeout` は `SoraConnectionErrorEvent(code: signaling_candidate_timeout)` として扱われ、`SoraTimeoutEvent` とは別契約である
- `SoraTimeoutEvent` は WebSocket close reason が `TIMEOUT` の場合や native 側 timeout イベントで emit される

## 設計方針

- 認証失敗、全 URL 不達、サーバー主導 timeout をケース分けする
- 実行時間が長くなりすぎないよう、短い timeout 設定を使う
- どの失敗でどのイベントを期待するかを明確に固定する
- `signalingCandidateTimeout` と `SoraTimeoutEvent` を同じケースで混同しない
- 認証失敗のエラー code / message は server 実装差があるため完全一致よりも「接続成功しないこと」と `SoraConnectionErrorEvent` 発火を主契約にする

## 完了条件

- 認証失敗で接続が成功しないことを確認する E2E がある
- 全 URL 不達で `SoraConnectionErrorEvent(code: signaling_candidate_timeout)` が出る E2E がある
- サーバー主導 timeout を再現できる環境がある場合は `SoraTimeoutEvent` が出る E2E がある
- 失敗時に `SoraConnectionErrorEvent` の code を確認し、message は非空または原因を含むことを確認する E2E がある
- 各ケースが別 test case に分かれている

## 解決方法

1. 認証失敗用の環境変数または無効 token シナリオを定義する
2. `signalingCandidateTimeout` を短くした接続設定で全 URL 不達の `signalingUrls` へ接続し、`SoraConnectionErrorEvent.code == signaling_candidate_timeout` を確認する
3. サーバー主導 timeout を再現できる検証環境がある場合は、WebSocket close reason `TIMEOUT` または native timeout 経路を使って `SoraTimeoutEvent` を確認する
4. `SoraConnectionErrorEvent` と `SoraTimeoutEvent` のどちらが来るべきかケースごとに assertion を分ける
5. cleanup を強化し、失敗後も後続テストに影響しないようにする
6. README と `CHANGES.md` の `### misc` に失敗系 E2E の前提条件を追記する
