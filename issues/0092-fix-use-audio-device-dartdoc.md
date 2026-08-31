# `SoraConnectionConfig.useAudioDevice` の dartdoc に `kDummyAudio` と書かれているが実装は `soraCreatePushAudioDevice`

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-use-audio-device-dartdoc
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

公開 API `SoraConnectionConfig.useAudioDevice` の dartdoc と実装が乖離している問題を解消する。dartdoc は「`false` にすると一切の音声デバイスを掴まず、`kDummyAudio` ADM を利用する」と説明しているが、実装は macOS / Windows / Linux の 3 プラットフォームで `soraCreatePushAudioDevice()` を使う。

## 現状

`lib/src/sora_connection_config.dart` の `SoraConnectionConfig.useAudioDevice` の dartdoc:

- 「`false` にすると一切の音声デバイスを掴まず、`kDummyAudio` ADM を利用する。」
- 「実マイクを使わずにカスタム音声ソース (BeepAudioSource 等) を使いたい場合に指定する。」

一方 `lib/src/ffi/webrtc_client.dart` の `_ensureSharedFactory` は `requestedUseAudioDevice == false` の場合、macOS / Windows / Linux のいずれでも `sharedLib.soraCreatePushAudioDevice()` を呼ぶ。`kDummyAudio` は `lib/src/ffi/bindings.dart` の `WebrtcConstants` にシンボルとして存在するが未使用。

利用者が dartdoc を信じて「`useAudioDevice: false` にすると PushAudio が使えない」と誤解する、あるいは「BeepAudioSource 相当のダミー音源が入る」と誤解する余地がある。

## 設計方針

- dartdoc を実態に合わせて修正する:
  - 「`false` にすると PushAudioDevice を利用する。`PushAudio.pushPcm` から任意の PCM を送出できる。」相当の説明にする。
  - Android は `createAndroidAudioDeviceModule` を使うため設定が無視される旨の既存記述は維持する。
- `kDummyAudio` を将来にわたって使う予定があるかを判断する。使わないなら別 issue（`ffi/bindings.dart` 内部限定 dead 定数削除）で削除する。
- 挙動を変更しない。ドキュメントのみの修正。

## 完了条件

- [ ] `useAudioDevice` の dartdoc が `soraCreatePushAudioDevice` / PushAudio 経路を正しく説明している。
- [ ] `kDummyAudio` への言及が削除される。
- [ ] `flutter analyze` と関連テストが成功する。
