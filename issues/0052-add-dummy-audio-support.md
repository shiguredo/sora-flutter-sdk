# E2E テストでダミー音声を送信できる API を追加する

- Priority: Medium
- Created: 2026-06-23
- Completed: {YYYY-MM-DD}
- Model: DeepSeek V4 Pro
- Branch: feature/add-dummy-audio-support
- Polished: {YYYY-MM-DD}

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
  - audio 関連のヘッダーは `api/audio/audio_device.h`、`api/audio/audio_device_defines.h`、`api/audio/audio_processing.h` のみ
  - `mediastream_interface.h` の `AudioSourceInterface` は refcounted ハンドルのみで、データ注入 API を持たない
- 統計ヘルパーには音声用の `AudioOutboundStats` / `AudioInboundStats` が存在しない
- libwebrtc-c はプリビルドアーカイブで配布されており、ソースは別リポジトリ (shiguredo/libwebrtc-c) で管理されている (v0.149.0, webrtc m149.7827.5.0 ベース)

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

**C++ 実装**: `rtc::AdaptedAudioTrackSource` クラスを新設し、`webrtc::AudioSourceInterface` を継承する。`OnData(const int16_t* audio_data, size_t samples_per_channel)` で PCM データを受け取り、内部で `webrtc::AudioTrackSinkInterface::OnData()` を呼び出して downstream へ配送する。

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
- `ExternalAudioFrame` クラスを新設する (PCM データ、サンプルレート、チャンネル数、サンプル数を保持)
- `LocalAudioTrack` に `writeAudioSamples(ExternalAudioFrame frame)` メソッドを追加する
  - `captureType` 相当のフィールドを `LocalAudioTrack` に追加し、external audio track 以外での呼び出しを拒否する

**`lib/src/sora_media_devices.dart`**:
- `MediaDevices.createExternalAudioTrack({required int sampleRate, required int channels})` を追加する
  - `adaptedAudioTrackSourceCreate()` → `pcFactoryCreateAudioTrack()` の流れで external audio track を生成する

### 4. E2E テストヘルパー側

**`e2e_test_app/integration_test/helpers/audio_source.dart` (新規)**:
- `SineWaveAudioSource` クラス
  - コンストラクタ: `sampleRate` (Hz)、`frequency` (Hz)、`channels`、`amplitude`
  - `start(LocalAudioTrack track)` / `stop()` で周期的に `writeAudioSamples()` を呼ぶ
  - 内部で `Timer.periodic` を使って一定間隔の PCM バッファを生成する

**`e2e_test_app/integration_test/helpers/stats_helpers.dart`**:
- `AudioOutboundStats` クラス (bytesSent, packetsSent, mimeType 等)
- `AudioInboundStats` クラス (bytesReceived, packetsReceived, mimeType 等)
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
- 既存のテストが回帰していない
- `dart analyze --fatal-infos lib test` がパスする

## 解決方法

1. libwebrtc-c リポジトリで `adapted_audio_track_source.h` と C++ 実装を追加し、新しいバージョンをリリースする
2. 本リポジトリの libwebrtc-c 依存バージョンを更新する
3. `lib/src/ffi/bindings.dart` に新規 FFI バインディングを追加する
4. `lib/src/sora_media_devices.dart` に `createExternalAudioTrack()` を追加する
5. `lib/src/sora_media_stream.dart` に `ExternalAudioFrame` クラス、`LocalAudioTrack.writeAudioSamples()`、`LocalAudioTrack` の capture type 管理を追加する
6. `e2e_test_app/integration_test/helpers/audio_source.dart` に `SineWaveAudioSource` を追加する
7. `e2e_test_app/integration_test/helpers/stats_helpers.dart` に音声統計ヘルパーを追加する
