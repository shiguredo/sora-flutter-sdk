# `SoraConnectionConfig.useAudioDevice` の dartdoc に `kDummyAudio` と書かれているが実装は `soraCreatePushAudioDevice`

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-use-audio-device-dartdoc
- Polished: 2026-09-07

## 目的

公開 API `SoraConnectionConfig.useAudioDevice` の dartdoc と実装が乖離している問題を解消する。dartdoc は「`false` にすると一切の音声デバイスを掴まず、`kDummyAudio` ADM を利用する」と説明しているが、実装は macOS / Windows / Linux の 3 プラットフォームで `soraCreatePushAudioDevice()` を使う。

## 現状

`lib/src/sora_connection_config.dart` の `SoraConnectionConfig.useAudioDevice` の dartdoc:

- 「`false` にすると一切の音声デバイスを掴まず、`kDummyAudio` ADM を利用する。」
- 「実マイクを使わずにカスタム音声ソース (BeepAudioSource 等) を使いたい場合に指定する。」

一方 `lib/src/ffi/webrtc_client.dart` の `_ensureSharedFactory` は `requestedUseAudioDevice == false` の場合、macOS / Windows / Linux のいずれでも `sharedLib.soraCreatePushAudioDevice()` を呼ぶ。`kDummyAudio` は Dart の `lib/` 内では `lib/src/ffi/bindings.dart` の `WebrtcConstants` の定義と当該 dartdoc 言及以外に参照が無い。なお native 側では `soraCreatePushAudioDevice()` が生成する PushAudioDevice が audio 層値として `kDummyAudio` (0) を報告する (`push_audio_device.cc` 等 5 ファイルの `*audio_layer = 0; // kDummyAudio`)。ADM の選択としては `soraCreatePushAudioDevice` が正しく、dartdoc の「`kDummyAudio` ADM を利用する」は不正確である。

`_ensureSharedFactory` のプラットフォーム分岐は Android / macOS / Windows / Linux のみで iOS 分岐が無い。iOS では `useAudioDevice` の値にかかわらず ADM 設定を行わない。Android では `requestedUseAudioDevice` を参照せず `createAndroidAudioDeviceModule` を使うため設定が無視される。

また dartdoc 中の `BeepAudioSource` はリポジトリ内に実体が無い stale な参照である (当該 dartdoc と本 issue の引用のみに存在する)。

利用者が dartdoc を信じて「`useAudioDevice: false` にすると PushAudio が使えない」と誤解する、あるいは「BeepAudioSource 相当のダミー音源が入る」と誤解する余地がある。

## 設計方針

- dartdoc を実態に合わせて修正する:
  - 「`false` にすると PushAudioDevice を利用する。`PushAudio.pushPcm` から任意の PCM を送出できる。」相当の説明にする。適用範囲は macOS / Windows / Linux に限定する旨を明記する。
  - Android は `createAndroidAudioDeviceModule` を使うため設定が無視される旨の既存記述は維持する。
  - iOS では `useAudioDevice` にかかわらず ADM 設定を行わない旨を明記する。
  - `kDummyAudio` への言及は削除する。`BeepAudioSource` への言及は実体が無いため削除し、`PushAudio` への参照に置き換える。
- 本 issue は dartdoc 修正のみを所有する。`kDummyAudio` 定数の存廃判断と削除実施は `0125-remove-ffi-bindings-dead-symbols` に委譲済みであり、本 issue では行わない。
- 挙動を変更しない。ドキュメントのみの修正。

## 完了条件

- [ ] `useAudioDevice` の dartdoc が `soraCreatePushAudioDevice` / PushAudio 経路を正しく説明している (macOS / Windows / Linux 限定、Android 無視、iOS は ADM 設定なしの旨を含む)。
- [ ] `useAudioDevice` の dartdoc から `kDummyAudio` と `BeepAudioSource` への言及が削除されている。
- [ ] `flutter analyze` と `flutter test test/sora_connection_config_test.dart` が成功する。
