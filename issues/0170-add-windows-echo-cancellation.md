# Windows でエコーキャンセルを有効化する

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/add-windows-echo-cancellation
- Polished: {YYYY-MM-DD}

## 目的

Windows の実音声デバイス利用時にエコーキャンセルを有効化する。

録音を成立させるため Windows 内蔵 AEC (CWMAudioAEC DMO) を無効化しており、APM のソフトウェアエコーキャンセラも復帰しないため、Windows ではエコーキャンセルが一切効かない状態になっている。

## 現状

- `WebRtcVoiceEngine::Init()` は既定 AudioOptions で `echo_cancellation = true` を適用し、Windows 内蔵 AEC が利用可能な場合は `EnableBuiltInAEC(true)` を呼ぶ
- 内蔵 AEC は録音開始に再生開始を要求するため、`WebrtcClient._configureWindowsAudioDeviceAfterPeerConnection` で `EnableBuiltInAEC(false)` を呼んで無効化している
- `EnableBuiltInAEC(true)` が成功した時点で `options.echo_cancellation` が false に変更され、APM の `echo_canceller.enabled` も false のままになる。ADM 側の内蔵 AEC だけを無効化しても APM のソフトウェア AEC は復帰しない
- libwebrtc-c 0.150.3 は `AudioDeviceModule` の `kWindowsCoreAudio2` 用ファクトリ (`CreateWindowsCoreAudioAudioDeviceModule`) を公開しておらず、Sora C++ SDK と同じ新しい CoreAudio ADM へ切り替えられない

## 設計方針

候補:

- 内蔵 AEC を維持し、録音開始前に再生を開始する。`AudioState` は最後の受信ストリーム削除で再生を停止するため、録音を再開する経路で再度失敗しうる
- APM の AEC3 を明示的に有効化する。`WebRtcVoiceEngine::ApplyOptions()` の後に APM の設定を変更する API が libwebrtc-c にあるか確認する
- libwebrtc-c に CoreAudio 2 ADM のファクトリ API を追加し、Sora C++ SDK と同じ ADM を使う

いずれの方式でも実機で sendonly / recvonly / sendrecv の録音・再生が成立することを確認する。

## 完了条件

- [ ] Windows でエコーキャンセルが有効になる
- [ ] sendonly / recvonly / sendrecv のいずれでも録音・再生が成立する
- [ ] 実音声デバイスの送受信 E2E が通る
- [ ] `flutter analyze` と関連テストが成功する
