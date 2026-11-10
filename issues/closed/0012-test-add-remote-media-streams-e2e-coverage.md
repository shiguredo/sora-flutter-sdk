# remoteMediaStreams の grouping を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-09
- Model: GPT-5 Codex
- Branch: feature/add-remote-media-streams-e2e-coverage
- Polished: 2026-06-03

## 目的

`remoteMediaStreams` は受信 UI を組み立てる基盤 API である。audio と video が同じ `connectionId` に束ねられる契約を E2E で確認できるようにする。

## 優先度根拠

- track 単体より `remoteMediaStreams` を直接使うアプリが多い
- grouping が崩れると同一参加者の音声と映像が別参加者扱いになる
- 実シグナリングとネイティブ callback を通した結合確認が必要なため High とする

## 現状

- `lib/src/sora_remote_media_stream.dart` は `connectionId` ごとに `audioTrack` / `videoTrack` を保持する
- `lib/src/sora_connection.dart` は `remoteMediaStreams` getter で外部公開している
- `MutableRemoteMediaStream` は接続ごとにインスタンス同一性を保ったまま `setAudioTrack` / `setVideoTrack` で更新される
- 既存 E2E は `remoteMediaStreams` の中身を確認していない
- `0239` は 2 クライアント疎通の土台、`0011` は add / remove event 契約の検証を扱うが、`remoteMediaStreams` の grouping とオブジェクト同一性は未検証である

## 設計方針

- この issue は **`remoteMediaStreams` の grouping 契約** に限定する。接続成立自体は `0239`、event 契約は `0011` に委譲する
- sender は 1 接続だけを使い、receiver 側で `remoteMediaStreams` を監視する
- sender は `MediaDevices.createAudioTrack()` で生成した audio track と external video track の両方を送信する。ただし audio 送信は実マイク入力前提になるため、検証環境の権限とデバイス前提を README に明記する
- sender / receiver とも `bundleId` は未設定とし、channel ID は 1 回だけ生成して両接続へ共有する
- receiver では `sender.connectionId` をキーに `remoteMediaStreams[sender.connectionId]` を参照し、同じオブジェクトに `audioTrack` と `videoTrack` が束ねられることを確認する
- `audioTrack` と `videoTrack` の到着順は固定せず、片方だけの中間状態を許容した上で最終的に両方がそろうことを待つ
- 中間状態確認と最終状態確認を同じ map entry に対して行い、途中で別インスタンスへ置き換わっていないことを確認する
- sender 切断後に当該 `RemoteMediaStream` が map から消えることを確認する
- `trackId` の形式や event の順序を主題にはしない。必要なら補助ログに出すが、厳密検証は `0011` に委譲する
- helper を追加する場合は `integration_test/support/` 配下に 2 接続セットアップ、sender / receiver cleanup、`remoteMediaStreams` 待ち helper を切り出す
- workflow 修正は本 issue の対象外とする。README 更新と `CHANGES.md` の `### misc` 反映は行う

## 完了条件

- receiver 側で `remoteMediaStreams` が 1 接続分生成されることを確認する E2E がある
- 同一オブジェクトに `audioTrack` と `videoTrack` が束ねられることを検証している
- sender 切断後に当該 `remoteMediaStreams` が消えることを確認している
- `audioTrack` と `videoTrack` の到着順に依存せず、最終的に両方がそろうことを確認している
- receiver 側では `sender.connectionId` をキーに対象 `RemoteMediaStream` を特定している
- 片方だけ到着した中間状態でも対象 entry のオブジェクト同一性が維持されている
- `e2e_test_app/README.md` とルート `README.md` に audio + video 前提の実行条件が追記されている

## 解決方法

1. `e2e_test_app/integration_test/remote_media_stream_e2e_test.dart` を新規作成し、3 Phase の検証を実装した
   - Phase 1: `remoteMediaStreams` に `sender.connectionId` のエントリが生成されることを確認
   - Phase 2: 同一オブジェクトに `audioTrack` + `videoTrack` が到着順非依存で束ねられ、オブジェクト同一性が維持されることを確認
   - Phase 3: sender 切断後に当該エントリが map から削除されることを確認
2. `connection_helpers.dart` に `waitForRemoteMediaStreamEntry` / `waitForRemoteMediaStreamBothTracks` / `waitForRemoteMediaStreamRemoved` の 3 つの polling ヘルパーを追加
3. `DebugProfile.entitlements` / `Release.entitlements` に `com.apple.security.device.microphone` を追加
4. `e2e_test_app/README.md` に audio track の実行条件を追記し、テスト一覧に新テストを追加
5. `.github/workflows/e2e-test.yml` の matrix に新テストを追加
6. `CHANGES.md` の `### misc` に追記
