# 未カバー残差 (SoraConnection 経路 / MediaDevices / PushAudio) のユニットテストを追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/test-core-modules-unit-tests
- Polished: 2026-09-07

## 目的

既存テストでカバーされていない残差 (SoraConnection の未カバー経路、`MediaDevices`、`PushAudio`) のユニットテストを追加する。race パス・世代管理・シグナリング切替の分岐など、コメントで丁寧に説明されている「race で壊れやすい経路」のうち未担保の部分を担保する。

## 現状

`test/` には `sora_connection_test.dart`、`sora_remote_track_manager_test.dart`、`sora_signaling_session_state_test.dart`、`webrtc_client_test.dart` が存在し、以下はカバー済みである:

- `_handleWebrtcEvent` の `state_changed` / track 系分岐
- `_handleRedirectMessage` のフェイルオーバー (6 件)
- `RemoteTrackManager._removedBeforeAttach` の race 制御
- `disconnect()` 時の `_disconnecting` / `_abnormalTerminationStarted` リセット
- `SignalingSessionState.resetSession` の全フィールドリセットは `0132-test-signaling-session-state-reset` に委譲する

一方、以下は対応テストが無い残差である:

- `_handleWebSocketDone` の signaling switched / `ignore_disconnect_websocket` 分岐 (`lib/src/sora_connection_signaling.dart`)
- `_connectGeneration` / `_sessionGeneration` フィルタ単体の効き (`lib/src/sora_connection.dart`)
- `disconnect()` → `connect()` の直列化 (`lib/src/sora_connection.dart`)
- `replaceVideoTrack()` の rollback (`lib/src/sora_connection.dart`)
- `MediaDevices.getUserMedia` のオプション組み合わせ (`lib/src/sora_media_devices.dart`。`test/` に対応ファイルなし)
- `PushAudio` の push / pull と `_buffer` のライフサイクル (`lib/src/sora_push_audio.dart`。`test/` に対応ファイルなし。`pushPcm` / `pullPcm` は `WebrtcClient.sharedLib` 経由の FFI 必須経路)

テスト挿入用の hook は既存であり、新設は行わない (`SoraConnection.createForTest` / `handleWebrtcEventForTest` / `handleRedirectMessageForTest` / `injectSignalingWebSocketForTest`、`WebrtcClient.create(config:onEvent:)`、`RemoteTrackManager` の ForTest フック)。

## 設計方針

- 上記残差に対するテストケースを段階的に追加する:
  - `_handleWebSocketDone` の signaling switched / `ignore_disconnect_websocket` 分岐
  - 世代フィルタ (`_connectGeneration` / `_sessionGeneration`) の効き
  - `disconnect()` → `connect()` の直列化と冪等性
  - `replaceVideoTrack` の失敗と rollback
  - `MediaDevices.getUserMedia` の各種オプション組み合わせ
  - `PushAudio` の push / pull と `_buffer` のライフサイクル
- FFI 必須経路のテストは `test/support/ffi_test_environment.dart` の `prepareFfiTestEnvironment()` + `skip:` 形式に従う (`0105` 決着)。`if (!ffiAvailable) return;` 相当の silent skip は使わない。
- 本 issue は `0150` / `0151` (テスト setup 方針) の完了後に着手し、setup の boilerplate 複製を避ける。`0135` 確定までは現行の `test/` 配置に従う。
- テスト命名は日本語、モックとスタブは使わない。

## 完了条件

- [ ] 上記残差 6 項目に対するユニットテストが追加されている。
- [ ] モックとスタブを使わず、`skip:` 形式 (理由付き) 以外の silent skip が無い。
- [ ] `flutter analyze` と `flutter test` が成功する。
