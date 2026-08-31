# remote track の追加と削除イベントを確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-09
- Model: GPT-5 Codex
- Branch: feature/add-track-event-e2e-coverage
- Polished: 2026-06-03

## 目的

利用者は `SoraTrackEvent` と `SoraRemoveTrackEvent` を基準に UI を更新する。remote track の追加と削除が E2E で確認されていない状態を解消する。

## 優先度根拠

- track event は SDK 利用者が直接購読する主要 API である
- 受信開始と切断時の両方で正しくイベントが出ないと UI が壊れる
- 単体テストだけではシグナリングからネイティブ bridge をまたぐ統合経路を保証しにくいため High とする

## 現状

- `lib/src/sora_connection_event.dart` に `SoraTrackEvent` / `SoraRemoveTrackEvent` がある
- `lib/src/sora_connection.dart` は `_remoteTrackManager` 経由で remote track event を emit している
- `lib/src/sora_remote_track_manager.dart` は audio / video の追加時に `onTrackEvent`、削除時に `onRemoveTrackEvent` を発火し、video track の detach-all 中も remove event を流す
- `0239` は 2 クライアントの土台シナリオを扱うが、track event の順序、重複、対応関係の厳密検証は対象外である
- 既存の integration test は track event の検証をしていない

## 設計方針

- この issue は **event 契約の検証** に限定する。sender / receiver の疎通成立自体は `0239`、`remoteMediaStreams` の grouping は `0012` に委譲する
- `0239` の 2 クライアント接続 helper または同等の接続手順を再利用し、receiver 側でイベント列を記録する
- sender は `sendonly` + `video: true` + `audio: false`、receiver は `recvonly` とし、`bundleId` は未設定のまま同一 channel ID を共有する
- receiver の subscription を sender 接続前に開始し、`SoraTrackEvent` は sender 接続と sender のフレーム投入後に待つ
- sender 側を `disconnect()` し、receiver 側で対応する `SoraRemoveTrackEvent` を待つ
- 同一 remote video track について `SoraTrackEvent` が二重発火しないこと、`SoraRemoveTrackEvent` が漏れないことを確認する
- assertion は `trackId`、`connectionId`、`kind` に絞り、`remoteMediaStreams` の中身まではこの issue で検証しない
- receiver 側で add / remove の観測期間を明確に分ける。sender 接続前から receiver の購読を開始し、remove 待ちが終わるまで購読を閉じない
- `SoraConnectionErrorEvent` は sender / receiver のどちらでも即時失敗とし、失敗時には receiver の記録済みイベント列を出力する
- cleanup は `0239` と同様に sender / receiver の両方を `finally` で解放し、sender の frame source 停止を `dispose()` より先に行う

## 完了条件

- `SoraTrackEvent` の発火を確認する E2E がある
- sender 切断後に `SoraRemoveTrackEvent` の発火を確認する E2E がある
- 受信 track の `connectionId`、`trackId`、`kind` が assertion に含まれている
- add / remove が同じ `trackId` と `connectionId` に対応することを確認している
- 同一 remote video track について `SoraTrackEvent` が 1 回だけ発火することを確認している
- sender 切断完了前に receiver 側 subscription を閉じていない
- `remoteMediaStreams` の grouping や stats 成長は本 issue の pass 条件に含めていない

## 解決方法

1. `0239` の 2 クライアント接続 helper または同等の接続手順を流用できる形に整える
2. receiver 側で `SoraTrackEvent` / `SoraRemoveTrackEvent` を時系列で記録する
3. sender connected 後に `sender.connectionId` を確定し、receiver 側で `kind == video` の `SoraTrackEvent` を 1 回待つ
4. 追加イベントの `trackId` と `connectionId` が sender 由来であることを確認する
5. sender 側を `disconnect()` し、receiver 側で対応する `SoraRemoveTrackEvent` を待つ
6. remove イベントの `trackId` / `connectionId` が add イベントと一致することを確認する
7. 同一 track に対する add の重複発火がないこと、remove 漏れがないことを確認する
8. sender disconnect 開始から receiver remove 観測完了まで receiver の subscription を維持する
9. タイムアウト時には receiver の記録済みイベント列と sender / receiver の `connectionId` を出力し、原因追跡しやすくする
10. 必要な README / `CHANGES.md` 更新があれば `0239` と同じ方針で反映する
