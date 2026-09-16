# ローカル音声と映像の有効切り替えを確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-09
- Model: GPT-5 Codex
- Branch: feature/add-local-media-toggle-e2e-coverage
- Polished: 2026-06-03

## 目的

`setAudioEnabled()` と `setVideoEnabled()` は通話アプリの基本操作である。mute / unmute と video off / on が実際の送信状態に反映されることを E2E で確認できるようにする。

## 優先度根拠

- 基本操作であり、壊れると利用者影響が大きい
- 現在は public API として公開されているが E2E 検証が無い
- 単純な setter 動作ではなく、実送信の変化を確認する必要があるため High とする

## 現状

- `lib/src/sora_connection.dart` に `setAudioEnabled()` / `setVideoEnabled()` と `isAudioEnabled` / `isVideoEnabled` がある
- 既存 E2E は接続後に track enabled を切り替えていない
- README でも dispose 後 API と並ぶ主要操作として公開されている
- `setAudioEnabled()` / `setVideoEnabled()` は Dart 側で `_currentAudioTrack?.enabled` / `_currentVideoTrack?.enabled` を直接切り替える実装である
- `track.enabled == false` 時の実ネットワーク上の bytes 停止量は WebRTC 実装依存でぶれうるため、単純な `bytesSent == 停止` を pass 条件にすると flaky になりやすい

## 設計方針

- この issue は **public API と local track state の切り替え契約** を E2E で確認することに限定する。remote 側での無音化 / 黒画面化の厳密検証は WebRTC 実装差が大きいため、この issue の pass 条件から外す
- sender / receiver の 2 クライアント構成で接続し、toggle 前後で接続継続と `getStats()` 成功を確認した上で、public getter と local track の `enabled` 状態が一致して変化することを確認する
- video は external video track を使い、`setVideoEnabled(false/true)` と `isVideoEnabled`、`stream.currentVideoTrackOrNull.enabled` の対応を確認する
- audio は `MediaDevices.createAudioTrack()` を使い、`setAudioEnabled(false/true)` と `isAudioEnabled`、`stream.currentAudioTrackOrNull.enabled` の対応を確認する
- video toggle と audio toggle は別 test case に分ける。片方だけ壊れたときに失敗箇所を即判別できるようにする
- `bytesSent` / `packetsSent` の完全停止は pass 条件にしない。toggle 後も `connection.getStats()` が成功し、切断せずに `enabled` 状態が反映されることを主契約とする
- audio 権限前提は README に明記する

## 完了条件

- `setVideoEnabled(false/true)` の前後で `isVideoEnabled` と local video track の `enabled` が一致して切り替わることを確認する E2E がある
- `setAudioEnabled(false/true)` の前後で `isAudioEnabled` と local audio track の `enabled` が一致して切り替わることを確認する E2E がある
- toggle 前後でも接続が維持され、`getStats()` が取得できることを確認している
- video toggle と audio toggle が別 test case に分かれている
- `bytesSent` の完全停止を pass 条件にしていない理由が issue 本文に明記されている

## 解決方法

1. `e2e_test_app/integration_test/local_media_toggle_e2e_test.dart` を新規作成し、video toggle と audio toggle の 2 test case を実装した
   - video test: sender sendonly (video:true) + external video track + ColorBarVideoSource
   - audio test: sender sendonly (audio:true) + `MediaDevices.createAudioTrack()`
   - 各 test: toggle 前後で `isVideoEnabled` / `isAudioEnabled` と `stream.current*TrackOrNull.enabled` の一致を確認
   - `getStats()` で DTLS / ICE 確立を `statsJsonSuggestsMediaPathUp()` で検証
   - `bytesSent` の完全停止は pass 条件にしていない
2. `e2e_test_app/README.md` に audio track 前提とテスト一覧を追加
3. `.github/workflows/e2e-test.yml` の matrix に新テストを追加
4. `CHANGES.md` の `### misc` に追記
