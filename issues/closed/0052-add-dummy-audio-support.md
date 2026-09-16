# E2E テストでダミー音声を送信できる API を追加する

- Priority: Medium
- Created: 2026-06-23
- Completed: 2026-07-10
- Model: DeepSeek V4 Pro
- Branch: feature/add-dummy-audio-support
- Polished: 2026-06-23

## 目的

E2E テストで映像のダミー送信には `ExternalVideoTrack` + `ColorBarVideoSource` が利用可能だが、音声については実マイク入力 (`MediaDevices.createAudioTrack()`) しか存在しない。CI 環境では実マイクが存在しないケースが多く、音声送信を伴う E2E テストが実行できない。これを解消するため、映像と同様のパターンでダミー PCM 音声データを注入できる API を追加する。

## 優先度根拠

Medium: 既存の E2E テストでは音声送信を回避して対応しているが、今後の audio 関連 E2E テスト追加 (sendrecv audio、audio stats 検証等) の前提として必要な機能である。

## 現状

### 映像のダミー送信 (実装済み、参考パターン)

| レイヤー | 実装 | ファイル |
|----------|------|----------|
| Native C API | `AdaptedVideoTrackSource` (Create / AdaptFrame / OnFrame) | `third_party/libwebrtc-c/include/webrtc_c/media/base/adapted_video_track_source.h` |
| FFI Binding | `adaptedVideoTrackSourceCreate`、`OnFrame` 等 | `lib/src/ffi/bindings.dart:2802` |
| Dart API | `MediaDevices.createExternalVideoTrack()` | `lib/src/sora_media_devices.dart:238` |
| データ注入 | `LocalVideoTrack.writeFrame(ExternalVideoFrame)` | `lib/src/sora_media_stream.dart:580` |
| E2E ソース | `ColorBarVideoSource` (I420 カラーバー生成) | `e2e_test_app/integration_test/helpers/video_source.dart` |
| E2E 検証 | `VideoOutboundStats` / `VideoInboundStats` + extract 関数 | `e2e_test_app/integration_test/helpers/stats_helpers.dart` |

### 音声の現状

- `MediaDevices.createAudioTrack()` (`lib/src/sora_media_devices.dart:160`) は `pcFactoryCreateAudioSource` でマイク入力の `AudioSourceInterface` を生成し、そこから `AudioTrack` を作成する
- `LocalAudioTrack` (`lib/src/sora_media_stream.dart:393`) には `writeFrame` 相当のデータ注入メソッドが存在しない
- libwebrtc-c の C API には `AdaptedVideoTrackSource` の音声版 (`AdaptedAudioTrackSource`) が存在しない
  - audio 関連のヘッダーは `api/audio/audio_device.h`、`api/audio/audio_device_defines.h`、`api/audio/audio_processing.h` と `api/media_stream_interface.h` (AudioSourceInterface / AudioTrackSinkInterface)
  - `AudioSourceInterface` は refcounted ハンドルのみで、データ注入のための API (`AddSink` / `RemoveSink` に相当するもの) を持たない
  - `AudioTrackSinkInterface` は受信側のシンク (`OnData`) であり、送信 encoder へのデータ注入には使えない
- 統計ヘルパーには音声用の `AudioOutboundStats` / `AudioInboundStats` が存在しない
- libwebrtc-c はプリビルドアーカイブで配布されており、ソースは別リポジトリ (shiguredo/libwebrtc-c) で管理されている

## 設計方針

`AdaptedVideoTrackSource` + `ExternalVideoFrame` + `ColorBarVideoSource` のパターンをそのまま音声に移植する。libwebrtc-c 側の実装を先行し、その後 Dart SDK / E2E ヘルパーの改修を行う。

### 1. libwebrtc-c 側: AdaptedAudioTrackSource の新規実装

`adapted_video_track_source.h` / `adapted_video_track_source.cc` のパターンに倣い、以下を追加する。

**新規ヘッダー**: `include/webrtc_c/media/base/adapted_audio_track_source.h`

```c
// 必要な C API
webrtc_AdaptedAudioTrackSource_Create(int sample_rate, size_t channels);
webrtc_AdaptedAudioTrackSource_OnData(source, audio_data, samples_per_channel);
webrtc_AdaptedAudioTrackSource_CastToAudioSourceInterface(source);
// refcount 管理
webrtc_AdaptedAudioTrackSource_refcounted_get / Release
```

**C++ 実装**: `rtc::AdaptedAudioTrackSource` クラスを新設し、`webrtc::AudioSourceInterface` を継承する。`OnData(const int16_t* audio_data, size_t samples_per_channel)` で PCM データを受け取る。

**注意 (audio pipeline の違い)**: 映像の `AdaptedVideoTrackSource` は `OnFrame()` で直接 encoder へ配送する push モデルだが、audio の送信 pipeline は video と異なり、encoder へのデータ経路が `AudioDeviceModule` → `AudioTransport` → `AudioSendStream` を経由する。`AdaptedAudioTrackSource` を既存の audio pipeline に統合する方法は libwebrtc-c (webrtc-rs) の実装に依存するため、実装時に以下を検証する:
- `AudioSourceInterface` の `Sink<>` 経由で encoder に到達できるか
- 到達できない場合、`AudioTransport` レベルでの注入、またはカスタム `AudioDeviceModule` の採用を検討する

**変更対象**:
- `include/webrtc_c/media/base/adapted_audio_track_source.h` (新規)
- `include/webrtc_c.h` (`#include` 追加)
- C++ ソース実装 (新規)

### 2. Dart FFI バインディング側

`lib/src/ffi/bindings.dart` に以下を追加する。

- opaque 型: `WebrtcAdaptedAudioTrackSourceRefcounted`、`WebrtcAdaptedAudioTrackSource`
- 関数バインディング:
  - `adaptedAudioTrackSourceCreate`
  - `adaptedAudioTrackSourceRefcountedGet`
  - `adaptedAudioTrackSourceRelease`
  - `adaptedAudioTrackSourceOnData`
  - `adaptedAudioTrackSourceCastToAudioSourceInterface`

### 3. Dart SDK 側

**`lib/src/sora_media_stream.dart`**:
- `AudioTrackCaptureType` enum (`microphone` / `external`) を新設する
- `ExternalAudioFrame` クラスを新設する
  - PCM データは signed 16-bit little-endian 整数列とし、Dart 側では `Int16List` で保持する
  - フィールド: `audioData` (Int16List)、`sampleRate` (int)、`channels` (int)
  - `validateExternalAudioFrame(ExternalAudioFrame frame)` 関数: `sampleRate > 0`、`channels >= 1`、`audioData.length >= channels` を検証する
- `LocalAudioTrack` に以下を追加する:
  - コンストラクタで `AudioTrackCaptureType` と `AdaptedAudioTrackSource` のポインタ参照を受け取る
  - `writeAudioSamples(ExternalAudioFrame frame)` メソッド
    - `captureType != AudioTrackCaptureType.external` なら `StateError`
    - 先頭で `validateExternalAudioFrame()` を呼び出す
    - native の `adaptedAudioTrackSourceOnData()` を呼び出して PCM データを注入する
- `LocalMediaStream` に以下を追加する:
  - `_LocalAudioTrackMetadata` 内部クラス（`_LocalVideoTrackMetadata` 相当）
  - `_audioTrackMetadata` フィールド
  - `addTrack()` での metadata 保存
  - `_reuseOrCreateAudioTrack()` での metadata 復元
  - `removeTrack()` での metadata クリア

**`lib/src/sora_media_devices.dart`**:
- `AudioTrackCaptureType` enum (`microphone` / `external`) を新設する
- `MediaDevices.createExternalAudioTrack({required int sampleRate, required int channels})` を追加する
  - `adaptedAudioTrackSourceCreate(sampleRate, channels)` → `adaptedAudioTrackSourceCastToAudioSourceInterface()` → `pcFactoryCreateAudioTrack()` の流れで external audio track を生成する
  - 生成した `LocalAudioTrack` に `AudioTrackCaptureType.external` と audio source 参照を保持させる

### 4. E2E テストヘルパー側

**`e2e_test_app/integration_test/helpers/audio_source.dart` (新規)**:
- `SineWaveAudioSource` クラス
  - コンストラクタ: `sampleRate` (Hz)、`frequency` (Hz)、`channels`、`amplitude`
  - `start(LocalAudioTrack track)` / `stop()` で周期的に `writeAudioSamples()` を呼ぶ
  - 内部で `Timer.periodic` を使って一定間隔の PCM バッファを生成する
  - 1 回の `writeAudioSamples()` あたり 10ms 相当 (`sampleRate / 100` samples/channel) を上限とし、UI スレッドへの影響を抑制する
  - E2E テスト専用のヘルパーであり、production 用途への流用は想定しない

**`e2e_test_app/integration_test/helpers/stats_helpers.dart`**:
- `AudioOutboundStats` クラス
  - video 版と異なり `framesEncoded` / `framesSent` 等のフレーム系フィールドは存在しない
  - `bytesSent`、`packetsSent`、`mimeType`、`totalAudioEnergy`、`totalSamplesDuration` 等 audio 固有フィールドを保持する
- `AudioInboundStats` クラス
  - `bytesReceived`、`packetsReceived`、`mimeType`、`jitter`、`audioLevel` 等 audio 固有フィールドを保持する
- `extractAudioOutboundStats(String raw)` 関数
- `extractAudioInboundStats(String raw)` 関数
- `waitForAudioOutboundStats()` 関数
- `waitForAudioInboundStats()` 関数

### 5. E2E テスト本体 (後続 issue)

本 issue では API とヘルパーの追加までをスコープとし、E2E テスト本体 (`sendonly_dummy_audio_e2e_test.dart` 等) の追加は後続 issue とする。

## 完了条件

- libwebrtc-c に `AdaptedAudioTrackSource` が実装され、新しいバージョンとしてリリースされている
- `lib/src/ffi/bindings.dart` に audio source 関連の FFI 関数が定義されている
- `MediaDevices.createExternalAudioTrack()` が利用可能である
- `LocalAudioTrack.writeAudioSamples(ExternalAudioFrame)` が利用可能である
- `SineWaveAudioSource` がダミー音声を生成し external audio track に注入できる
- `AudioOutboundStats` / `AudioInboundStats` と extract / wait 関数が利用可能である
- 既存の E2E テスト全件が回帰していない
- `dart analyze --fatal-infos lib test` がパスする
- `CHANGES.md` の `## develop` にエントリが追加されている

## 解決方法

本 issue で提案した `AdaptedAudioTrackSource` アプローチは採用せず、別アプローチで解決した。

### 採用された代替アプローチ: PushAudioDevice + PushAudio.pushPcm()

映像の `AdaptedVideoTrackSource` パターンを音声に移植する代わりに、カスタム `AudioDeviceModule` (PushAudioDevice) を libwebrtc-c 側に実装し、Dart から `PushAudio.pushPcm()` で PCM データを注入する方式を採用した。

| レイヤー | 実装 |
|----------|------|
| C API | `webrtc_AudioTransport_RecordedDataIsAvailable()` (PushAudioDevice 経由) |
| FFI Binding | `sora_push_audio_on_data()` |
| Dart API | `PushAudio.pushPcm(Int16List, int sampleRate, int channels)` (`lib/src/push_audio.dart`) |
| Config | `MediaDevices.createAudioTrack(useAudioDevice: false)` で PushAudioDevice を選択 |
| E2E ヘルパー | `E2ePushAudioTrack` (`e2e_test_app/integration_test/helpers/push_audio_track.dart`) — 10ms ごとに無音 PCM を注入 |
| DevTools | `DevToolsBeepAudioTrack` (`devtools/lib/src/devtools_beep_audio_track.dart`) — 440Hz サイン波 beep 音を生成 |

### 本 issue の完了条件との対応

- `AdaptedAudioTrackSource` → 未実装 (不要になった)
- `MediaDevices.createExternalAudioTrack()` → 未実装 (`useAudioDevice: false` で代替)
- `LocalAudioTrack.writeAudioSamples()` → 未実装 (`PushAudio.pushPcm()` で代替)
- `SineWaveAudioSource` → 未実装 (E2E は無音、DevTools は `DevToolsBeepAudioTrack`)
- `AudioOutboundStats` / `AudioInboundStats` → 未実装
- E2E テストでのダミー音声送信 → **解決済み** (`PushAudio.pushPcm()` + `E2ePushAudioTrack`)

### 関連コミット (主要)

- `ad1623e` — `useAudioDevice` 設定を追加、Dummy ADM を選択可能に
- `12bb12d` — PushAudioSource + BeepAudioTrack を追加
- `b961c27` — Windows & Android の PushAudioSource ネイティブ実装
- `3a25d08` — PushAudioSource を PushAudioDevice (カスタム ADM) に置き換え
- `57be541` — Dummy ADM + PushAudioDevice + DevTools Beep 音機能
