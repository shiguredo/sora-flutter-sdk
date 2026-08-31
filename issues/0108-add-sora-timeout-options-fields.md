# `SoraTimeoutOptions` に不足するタイムアウトフィールドを追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-sora-timeout-options-fields
- Polished: 2026-08-27

## 目的

コード中に散在する hardcoded なタイムアウト値（`getStats` 5 秒、`setAudioInputDevice` 10 秒、`_replaceVideoTrackInternal` 10 秒）を利用者が調整できるよう、接続設定に関連するものを `SoraTimeoutOptions` にフィールドとして追加し、接続コンテキストに紐づかないものは API 引数で指定できるようにする。

## 現状

`lib/src/sora_timeout_options.dart` の `SoraTimeoutOptions` は現在 3 フィールドのみ:

- `signalingCandidateTimeout`
- `connectionTimeout`
- `disconnectWaitTimeout`

一方、実装内には以下の hardcoded タイムアウトがある:

- `lib/src/ffi/webrtc_client.dart` の `WebrtcClient.getStats`: 5 秒
- `lib/src/media/sora_media_device_platform.dart` の `setAudioInputDevice`: 10 秒（iOS / Android の MethodChannel 経路のみ。macOS / Windows / Linux は FFI 経路でタイムアウトなし）
- `lib/src/sora_connection.dart` の `SoraConnection._replaceVideoTrackInternal`: 10 秒（`captureType == screen` の場合は適用なし）

利用者が自環境の遅延や device 応答性に合わせて調整できず、無理に固定値でリトライすることになる。

## 設計方針

- `SoraTimeoutOptions` に以下のフィールドを追加する（名称は現行慣習に合わせる）:
  - `getStatsTimeout` (default 5 seconds)
  - `replaceVideoTrackTimeout` (default 10 seconds)
- 実装側の hardcoded 値を `SoraTimeoutOptions` の値から参照するように書き換える。配線方法は以下のとおり:
  - `replaceVideoTrackTimeout`: `SoraConnection` 内のメソッド（`_replaceVideoTrackInternal`）が `config.timeoutOptions.replaceVideoTrackTimeout` を直接参照する（既存の `connectionTimeout` / `disconnectWaitTimeout` と同じ配線。`sora_connection.dart` の 570 行の前例に倣う）。
  - `getStatsTimeout`: `SoraConnection.getStats()` が `config.timeoutOptions.getStatsTimeout` を `WebrtcClient.getStats` の optional 引数（例: `getStats({Duration? timeout})`）に渡す。null の場合は現行の hardcoded 5 秒を維持する。`WebrtcClient` の `_config`（`Map<String, Object?>`）には `timeoutOptions` が含まれないため、config map 経由ではなく引数渡しにする。
- `setAudioInputDevice` のタイムアウトは接続コンテキスト（`SoraConnectionConfig`）に紐づかず、接続前にも呼ばれるため、`SoraTimeoutOptions` には追加しない。代わりに `MediaDevices.createAudioTrack` に `Duration? setAudioInputDeviceTimeout` 引数を追加し、`sora_media_device_platform.setAudioInputDevice` へ渡す。null の場合は現行の hardcoded 10 秒を維持する。`GetUserMediaOptions` にも `setAudioInputDeviceTimeout` を追加し、`getUserMedia` はそれを `createAudioTrack` へ透過する形にする（`GetUserMediaOptions` へのフィールド追加で実現する）。
- 適用範囲の条件を維持する:
  - `setAudioInputDeviceTimeout` は iOS / Android の MethodChannel 経路のみに適用される。macOS / Windows / Linux は FFI 経路でタイムアウトを設定しておらず、この挙動を変更しない。
  - `replaceVideoTrackTimeout` は `captureType == screen` の場合は適用されない（現行の条件分岐を維持する）。
- 追加する各フィールドの dartdoc に「default 値・意味・調整の目安」を書く。
- 既存のフィールドと後方互換性を保つ（新規追加のみ）。

## 完了条件

- [ ] `SoraTimeoutOptions` に 2 フィールド（`getStatsTimeout` / `replaceVideoTrackTimeout`）が追加されている。
- [ ] `MediaDevices.createAudioTrack` に `setAudioInputDeviceTimeout` 引数が追加されている。
- [ ] `GetUserMediaOptions` に `setAudioInputDeviceTimeout` が追加され、`getUserMedia` が `createAudioTrack` へ透過する。
- [ ] 該当 3 箇所の hardcoded タイムアウトが設定値（`SoraTimeoutOptions` または API 引数）を参照するように置き換わっている。
- [ ] default 値は現行の hardcoded 値と一致し、既存挙動が変わらない（`setAudioInputDeviceTimeout` が macOS / Windows / Linux に効かないこと、`replaceVideoTrackTimeout` が screen キャプチャ時に適用されないことを含む）。
- [ ] `flutter analyze` と関連テストが成功する。
