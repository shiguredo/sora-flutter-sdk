# SoraConnection / WebrtcClient / signaling / RemoteTrackManager のユニットテストを追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/test-core-modules-unit-tests
- Polished: {YYYY-MM-DD}

## 目的

コアの 2000 行超の型（`SoraConnection`, `WebrtcClient`）と、その周辺の `SignalingSessionState` / `RemoteTrackManager` / `MediaDevices` / `PushAudio` のユニットテストが 1 件も無い状態を解消する。race パス・世代管理・シグナリング切替の分岐など、コメントで丁寧に説明されている「race で壊れやすい経路」を担保する。

## 現状

`test/` 配下には以下のユニットテストが無い:

- `lib/src/sora_connection.dart`（2248 行）
- `lib/src/sora_connection_signaling.dart`（501 行）
- `lib/src/sora_remote_track_manager.dart`（504 行）
- `lib/src/sora_media_devices.dart`（332 行）
- `lib/src/sora_push_audio.dart`（93 行）

特に以下のロジックがユニットテストで担保されていない:

- `SoraConnection._connectGeneration` / `_sessionGeneration` / `_videoCaptureOperationGeneration` / `_abnormalTerminationStarted` / `_ongoingDisconnect` を絡めた状態機械
- `_handleWebSocketDone` の signaling switched / ignore_disconnect_websocket 分岐
- `RemoteTrackManager._removedBeforeAttach` の race 制御
- `_handleRedirectMessage` のフェイルオーバー
- `disconnect()` → `connect()` の直列化
- `replaceVideoTrack()` の rollback

`e2e_test_app/integration_test/` は実 Sora と接続してシナリオを検証するが、race を確実に再現する用途には向かない。プロジェクト規約でモックとスタブが禁止されているため、`WebrtcClient` のイベント callback を hook できる仕組みを活用したテスト設計が必要。

## 設計方針

- `WebrtcClient` の `onEvent` 相当を差し込める既存の仕組み（テスト向けの hook / factory 引数）を活用する、あるいは新設する。モックやスタブに頼らず、native 依存部分と Dart 状態機械を分離してテスト可能にする。
- 以下のテストケースを段階的に追加する:
  - `_handleWebrtcEvent` の `state_changed`（`connecting` / `connected` / `disconnected` / `error`）の各分岐
  - 世代フィルタ（`session_generation` / `_connectGeneration`）の効き
  - `disconnect()` → `connect()` の直列化と冪等性
  - `replaceVideoTrack` の失敗と rollback
  - `RemoteTrackManager` の `_removedBeforeAttach` race
  - `_handleRedirectMessage` の URL バリデーション以降のフェイルオーバー
  - `SignalingSessionState.resetSession` の全フィールドリセット
  - `MediaDevices.getUserMedia` の各種オプション組み合わせ
  - `PushAudio` の push/pull と `_buffer` のライフサイクル
- テスト命名は日本語、モックとスタブは使わない、`if (!ffiAvailable) return;` の silent skip は使わない（別 issue と整合させる）。

## 完了条件

- [ ] 上記モジュールの race / 世代 / 分岐に対するユニットテストが追加されている。
- [ ] モックとスタブを使わずに済むテスト設計になっている。
- [ ] silent skip なしで CI が確実にテストを走らせる。
- [ ] `flutter analyze` と関連テストが成功する。
