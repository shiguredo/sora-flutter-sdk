# replaceVideoTrack の送信継続を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-replace-video-track-e2e-coverage
- Polished: 2026-06-03

## 目的

`replaceVideoTrack()` は README でも明示されている主要機能であり、カメラ切り替え相当のユースケースを支える。接続中に映像トラックを差し替えても送信が継続することを E2E で保証する。

## 優先度根拠

- 実装が複雑で、sender 差し替え、local stream 更新、rollback を含む
- 単体テストだけでは実シグナリング中の差し替え成功を保証しにくい
- 利用者が直接呼び出す public API のため High とする

## 現状

- `lib/src/sora_connection.dart` に `replaceVideoTrack()` がある
- `CHANGES.md` には `replaceVideoTrack` のロールバック修正が記録されており、回帰監視価値が高い
- 既存 E2E は接続後のトラック差し替えを確認していない

## 設計方針

- この issue は **接続中 sender の replace 契約** に限定する。カメラデバイス切替 UI や local preview の更新は対象外とする
- external video track を 2 本用意し、色やパターンの異なるフレームを流す
- 接続後に `replaceVideoTrack()` を実行し、送信 stats の継続と receiver 側受信継続を確認する
- receiver 側では replace 後も再接続不要で `video inbound-rtp` が増加し続けることを主に見る
- `replaceVideoTrack()` によって remote track が作り直されないことを補助確認として扱い、`SoraRemoveTrackEvent` が不要に出ないことを確認する

## 完了条件

- `replaceVideoTrack()` を呼ぶ integration test が追加されている
- 差し替え後も接続が維持されることを確認している
- 差し替え前後で送信 stats が継続して増えることを確認している
- receiver 側が再接続不要で `video inbound-rtp` 増加を継続できることを確認している
- replace 実行だけで `SoraRemoveTrackEvent` が発火しないこと、または remote track identity が不要に切り替わらないことを補助確認している

## 解決方法

1. 異なるフレームパターンを出す external video source を 2 つ用意する
2. sender 接続後に 1 本目で送信を開始する
3. `replaceVideoTrack()` で 2 本目へ差し替える
4. replace 前後で sender の `video outbound-rtp` と receiver の `video inbound-rtp` を取得し、どちらも継続増加することを確認する
5. receiver 側で track remove が不要に発火しないこと、または replace 前後で受信継続が途切れないことを確認する
6. README と `CHANGES.md` の `### misc` を更新する
