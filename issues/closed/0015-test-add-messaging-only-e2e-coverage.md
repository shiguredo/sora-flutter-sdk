# messaging 専用接続の E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-23
- Model: GPT-5 Codex
- Branch: feature/add-messaging-only-e2e-coverage
- Polished: 2026-06-03

## 目的

`audio: false` かつ `video: false` の messaging 専用接続は、メディアなし利用の重要なユースケースである。DataChannel だけで接続できることを E2E で確認できるようにする。

## 優先度根拠

- メディアと独立した接続形態の保証が必要である
- README で公開している構成だが、現状の E2E では一切確認していない
- 後続の DataChannel / RPC E2E の土台になるため High とする

## 現状

- README に messaging 専用接続のサンプルがある
- `lib/src/sora_connection_signaling.dart` は `audio` / `video` / `data_channel_signaling` / `data_channels` を connect message へ反映する
- 既存 E2E はメディア送信前提であり、メッセージング専用構成を確認していない

## 設計方針

- この issue は **単一接続の messaging-only smoke** に限定する。実際の送受信は `0016`、RPC は `0017` に委譲する
- `SoraRole.sendonly`、`audio: false`、`video: false`、`dataChannelSignaling: true`、`#messaging` 付きで接続する
- 接続確立と custom DataChannel open を最低確認項目にする
- local stream なしで `connect()` できること、`remoteMediaStreams` が空のまま維持されること、`SoraTrackEvent` が来ないことを assertion に含める
- `sendDataChannelMessage()` の実送信成功まではこの issue の pass 条件に含めない

## 完了条件

- messaging 専用接続の integration test が追加されている
- local stream なしで `connect()` できることを確認している
- `SoraDataChannelOpenEvent` が発火することを確認している
- `remoteMediaStreams` が空で、短い観測期間中に `SoraTrackEvent` / `SoraRemoveTrackEvent` が来ないことを確認している
- メディア track に依存しない cleanup が整理されている

## 解決方法

1. messaging 専用設定の integration test を追加する
2. `connection.connect()` を stream なしで実行する
3. `SoraConnectedState` と `SoraDataChannelOpenEvent` を待つ
4. 接続完了後の短い観測期間で `remoteMediaStreams` が空のまま、`SoraTrackEvent` / `SoraRemoveTrackEvent` が来ないことを確認する
5. 後続の DataChannel 送受信 issue で再利用できる helper を整理する
6. README と `CHANGES.md` の `### misc` を更新する
