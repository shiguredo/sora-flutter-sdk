# GetUserMediaOptions に音声制約 (stereo / サンプリングレート / エコーキャンセル等) を追加する
- Priority: Medium
- Created: 2026-04-14
- Model: Opus 4.6
- Polished: 2026-06-05

## 目的

現在の `GetUserMediaOptions` には音声取得の詳細制約がなく、マイクから取得する音声は SDK (libwebrtc) のデフォルト設定 (一般的に mono) に固定されている。映像側には `videoWidth` / `videoHeight` / `videoFrameRate` / `videoDeviceId` が存在するのに対し、音声側は `audio` (bool) と `audioDeviceId` (追加予定) しかなく、API の対称性が崩れている。

ブラウザの `MediaDevices.getUserMedia()` には音声側の制約として `channelCount` / `sampleRate` / `echoCancellation` / `autoGainControl` / `noiseSuppression` が定義されている。音楽配信 (stereo 送信) やゲーム配信、収音品質のチューニングを想定する場合、これらの制約をアプリから指定できないと Web 互換の体験を構築できない。

## 優先度根拠

- 音声制約は利用者の配信品質に直結する
- ただし libwebrtc-c 側の改修が前提で、 Flutter SDK 単体では完結しない
- 設計判断を先に固めないと、後戻りの大きい API 変更になる

## 設計方針

- `GetUserMediaOptions` に音声制約フィールドを追加する
  - `audioChannelCount` (`int?`): 1 (mono) / 2 (stereo)
  - `audioSampleRate` (`int?`): サンプリングレート (Hz)
  - `audioEchoCancellation` (`bool?`): エコーキャンセル
  - `audioAutoGainControl` (`bool?`): 自動ゲイン制御
  - `audioNoiseSuppression` (`bool?`): ノイズ抑制
- `null` のときは SDK デフォルト (= libwebrtc のデフォルト) を採用する
- libwebrtc の `AudioDeviceModule` / `AudioProcessing` でサポートされる範囲を優先し、プラットフォーム依存の挙動は明記する
- Opus の stereo 送信設定 (送信側) との関係を整理する。マイクを stereo で取得しても Opus を mono で送信すると結果は mono になるため、取得側と送信側の両方を意識する必要がある
- 既存の `audioCodecType` / `audioBitRate` (`SoraClientConfig` 側) と、取得側の制約 (`GetUserMediaOptions` 側) の責務境界を明確にする

## 完了条件

1. `GetUserMediaOptions` に音声制約フィールドが追加され、 Dart API から指定できる
2. Android / iOS / macOS でそれぞれの制約がどこまで反映されるかが整理されている
3. プラットフォームで対応していない制約を指定した場合のフォールバック挙動が定義されている
4. ブラウザの `getUserMedia({ audio: { ... } })` との対応関係がドキュメント化されている
5. Opus コーデックの stereo 送信設定と整合する形で動作する
6. `<DOC_REPO>/media_device.rst` の `GetUserMediaOptions` フィールド表に追記されている

## 技術的な論点

- libwebrtc の `AudioDeviceModule` 経由でチャンネル数・サンプリングレートをどこまで制御できるか
- `AudioProcessing` 系 (echoCancellation / autoGainControl / noiseSuppression) のプラットフォーム別対応状況と、OS 固有の音声処理と競合したときの優先順位
- Opus の stereo 送信は `SoraClientConfig` 側の責務か、 `GetUserMediaOptions` の責務か (現状は SoraClientConfig 側に寄せる想定)
- プラットフォームで対応していない制約が指定された場合、無視する / 例外を投げる / 最も近い値にクランプする のどれを取るか
- 後から追加される可能性のある制約 (`latency`, `suppressLocalAudioPlayback` など) との前方互換を、フィールド追加方式で確保できるかどうか

## 現状

### 現行の <PRIVATE_REPO> 側

- `GetUserMediaOptions` は `lib/src/sora_media_devices.dart` で `audio` / `video` / `audioDeviceId` / `videoDeviceId` / `videoWidth` / `videoHeight` / `videoFrameRate` のみを持つ
- `MediaDevices.createAudioTrack()` は `pcFactoryCreateAudioSource()` を引数なしで呼び、SDK 側から `webrtc::AudioOptions` 相当を渡す経路が存在しない
- `third_party/libwebrtc-c/include/webrtc_c/api/peer_connection_interface.h` の `webrtc_PeerConnectionFactoryInterface_CreateAudioSource()` も options 引数を持たず、現状の C API では音声制約を `AudioSource` 生成時に指定できない
- Android / iOS / macOS の platform 実装は現状 `audioDeviceId` による入力切り替えが中心で、`channelCount` / `sampleRate` / `echoCancellation` / `autoGainControl` / `noiseSuppression` を同じ意味で反映する面が揃っていない

### webrtc-rs 側

- `src/api/peer_connection.rs` の `create_audio_source()` も引数なしで、Flutter SDK と同様に `AudioSource` 生成時の options を公開していない
- `webrtc/src/webrtc_c/api/peer_connection_interface.cc` では `webrtc::AudioOptions options;` をデフォルト構築して `CreateAudioSource(options)` に渡しており、libwebrtc 内部には options 面がある一方、C API / Rust API では露出していない
- `webrtc/src/webrtc_c/api/audio/audio_device_defines.cc` の `webrtc_AudioParameters_new(sample_rate, channels, frames_per_buffer)` の `sample_rate` は ADM / AudioTransport が扱う実際の音声フォーマットのサンプリング周波数 (Hz) であり、`getUserMedia` の希望値 API とは役割が異なる
- `src/api/audio_device_module.rs` には stereo recording / playout の API があるが、既定実装は `available = false` と no-op であり、そのまま Flutter SDK へ持ち込める完成形ではない
- Opus stereo は `src/tests.rs` の `RtpCodecCapability` テストでも `parameters["stereo"] = "1"` のように codec parameter 側で扱っており、capture 制約とは別責務である

### 暫定結論

- issue 0002 は `GetUserMediaOptions` にフィールドを足すだけでは完結しない
- 実装には少なくとも `libwebrtc-c` の `CreateAudioSource` 拡張、Dart FFI の追従、platform ごとのフォールバック方針整理が必要
- 特に stereo capture と Opus stereo 送信は別レイヤーの設定であり、`GetUserMediaOptions` と `SoraConnectionConfig` の責務境界を先に固定する必要がある

## ステータス

- 2026-05-01: pending に移動。`libwebrtc-c` の `CreateAudioSource` に `webrtc::AudioOptions` 相当を渡す経路の追加が前提となるため、libwebrtc-c 側の改修が入るまで Flutter SDK 単体では着手できない。

## 解決方法

1. `libwebrtc-c` に `AudioOptions` を渡せる経路を追加する
2. Dart FFI と platform 実装を追従させる
3. `GetUserMediaOptions` と `SoraConnectionConfig` の責務境界を文書化する
