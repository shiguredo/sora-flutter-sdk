# dispose 後の API 拒否を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-dispose-api-guard-e2e-coverage
- Polished: 2026-06-03

## 目的

`dispose()` 後に public API が `StateError` で拒否される契約を E2E で確認し、ライフサイクル破綻の回帰を検出できるようにする。

## 優先度根拠

- dispose 後の誤操作はアプリ側で起こりやすい
- `README.md` に明記した API 契約である
- 過去に `disconnect()` / `dispose()` 周辺の不具合修正が多く、回帰監視価値が高いため High とする

## 現状

- README に `dispose` 後の `rpc` / `getStats` / `replaceVideoTrack` / `sendDataChannelMessage` / `setAudioEnabled` などは `StateError` と明記されている
- `lib/src/sora_connection.dart` は `_ensureNotDisposed()` で各 API を防御している
- 既存 E2E は dispose 後 API を試していない

## 設計方針

- 接続前後の両方で `dispose()` を行い、代表 API が拒否されることを確認する
- 1 テストで複数 API をまとめて確認してよいが、失敗原因が分かるよう assertion を分ける
- 例外型だけでなく、誤って native 呼び出しが走らないことも間接的に保証する
- `replaceVideoTrack()` は local video track を持つ接続、`rpc()` / `sendDataChannelMessage()` は messaging 構成を必要とするため、前提が異なる API は別 test case に分ける

## 完了条件

- 接続前 dispose と接続後 dispose の少なくとも 2 系列がある
- `dispose()` 後に `getStats()` が失敗することを確認する E2E がある
- `dispose()` 後に `rpc()`、`sendDataChannelMessage()`、`replaceVideoTrack()`、`setAudioEnabled()`、`setVideoEnabled()` が失敗することを確認している
- すべて `StateError` として扱われることを確認している
- API ごとの失敗原因が assertion メッセージから判別できる

## 解決方法

1. 未接続の connection を `dispose()` した後に `getStats()`、`setAudioEnabled()`、`setVideoEnabled()` などを呼ぶ test を追加する
2. messaging-only connection を接続して `dispose()` した後に `rpc()` と `sendDataChannelMessage()` を呼ぶ test を追加する
3. video track を持つ接続を `dispose()` した後に `replaceVideoTrack()` を呼ぶ test を追加する
4. 代表 API を順に呼び、すべて `throwsA(isA<StateError>())` で確認する
5. test を分割し、どの API の契約が壊れたか追いやすくする
6. README と `CHANGES.md` の `### misc` を更新する
