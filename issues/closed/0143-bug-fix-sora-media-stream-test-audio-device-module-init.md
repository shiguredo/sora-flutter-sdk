# `sora_media_stream_test.dart` の LocalMediaStream track cache テストで `AudioDeviceModule init failed: rc=-1` になり失敗する

- Created: 2026-08-30
- Branch: feature/fix-sora-media-stream-test-audio-device-module-init
- Polished: 2026-08-30
- Completed: 2026-08-30

## 目的

Linux CI の `Run FFI-dependent package tests` step で、`test/sora_media_stream_test.dart` の LocalMediaStream track cache 系テスト 5 件が `Bad state: AudioDeviceModule init failed: rc=-1` により失敗している。この失敗を解消し、Linux CI の FFI テスト step を green に近づける。

系統 A（`Pointer<Never>`）は issue 0142、系統 C（`Binding not initialized`）は issue 0141 で扱う。本 issue は系統 B のみ。

## 現状

`Build Linux` job の `Run FFI-dependent package tests` step で以下 5 件が失敗している（run 例: `33297433461` の Build Linux job）。

- `LocalMediaStream track cache の参照管理 (FFI) cache-hit では同じインスタンスが返る`
- `LocalMediaStream track cache の参照管理 (FFI) cache 入れ替わりで新規インスタンスが生成される`
- `LocalMediaStream track cache の参照管理 (FFI) track が消えた後の再取得で新規インスタンスが生成される`
- `LocalMediaStream track cache の参照管理 (FFI) dispose 済み track は cache から再利用されない`
- `LocalMediaStream track cache の参照管理 (FFI) video track の cache-hit で同じインスタンスが返る`

失敗メッセージ:
```
Bad state: AudioDeviceModule init failed: rc=-1
```

該当テストは commit `f1cea04 0071 LocalMediaStream の track キャッシュ生成で _mediaTrackRef を double-release するのを修正する` で新規追加された（+111 行、`test/sora_media_stream_test.dart` の一部）。追加時点の CI（`33141722842`）は `d290330 0069` に起因する devtools analyze で早期停止したため、`Run FFI-dependent package tests` step が一度も実行されず、この失敗はこれまで観測されていなかった。

`AudioDeviceModule init failed: rc=-1` は WebRTC の `AudioDeviceModule` 初期化が失敗したことを示す。GitHub Actions の Linux ランナー (`ubuntu-latest`) は headless で audio subsystem を持たないため、環境要因の可能性が高い。

## 設計方針

原因は既に特定できている。CI ログの失敗スタック（`lib/src/ffi/webrtc_client.dart` line 424 `throw StateError('AudioDeviceModule init failed: rc=$initRcLinux');` → line 190 `sharedFactory` → `lib/src/sora_media_devices.dart` line 78 `createMediaStream` → `test/sora_media_stream_test.dart` line 546 の `setUp`）が示すとおり、setUp の `stream = MediaDevices.createMediaStream()` が共有 factory 初期化をトリガし、`_useAudioDevice = true`（`webrtc_client.dart` line 147 の default）の Linux 経路が headless ランナーの実 audio device に対して `audioDeviceModuleInit` を呼び、rc=-1 で失敗する。共有 factory の初期化で ADM が要求されるため、audio track を作らない video track のケースでも同じ経路で落ちる。

対応方針は以下の 3 候補があり、実装フェーズで採用を確定する。

- **候補 1: テスト側で既存 public API により push ADM に切り替える**
  - `MediaDevices.setUseAudioDevice(false)`（`lib/src/sora_media_devices.dart` line 71-73）を対象 group の `setUpAll` で呼ぶ。内部で `WebrtcClient.useAudioDevice = false` に切り替わる。
  - `useAudioDevice = false` の Linux 経路（`webrtc_client.dart` line 427-444）は `soraCreatePushAudioDevice()` を選び、その `adm_init` は `linux/push_audio_device.cc` の実装で無条件に `return 0;` を返すため、Linux CI でも成功する見込みが高い。実装時に手元 / CI で `audioDeviceModuleInit` が rc=0 を返すことを検証する。
  - `soraCreatePushAudioDevice()` は本番アプリで「外部から audio frame を push する」用途に使う公開 API 経路の本番実装であり、モック/スタブには該当しない（`sora_connection_config.dart` line 57-69 に `useAudioDevice = false` の本番仕様が明記）。したがって `AGENTS.md` 「モックやスタブは絶対に利用しないこと」に抵触しない。
  - 本 issue の対象 5 テストは「LocalMediaStream track cache の参照管理」を検証する目的で、実マイクの入力を必要としないため意図を損なわない。
  - `WebrtcClient.useAudioDevice` は共有 factory 初期化前にしか切り替えられない（`webrtc_client.dart` line 152-159）ため、`setUpAll` の `WebrtcClient.create` より先に設定するか、`sharedFactory` を触る前の group 先頭で設定する必要がある。
- **候補 2: 環境側で仮想 audio device を用意する**
  - `pulseaudio --start` や `alsa` の dummy device、`snd-dummy` カーネルモジュールなどを CI ランナーで有効化する。`.github/workflows/ci.yml` の Linux job を更新する。
  - 副作用として実 audio subsystem 依存のテストも走らせられるが、CI ランナーの前提が変わり保守コストが上がる。
- **候補 3: native 側で audio device が無くても ADM 初期化を成功させる**
  - `createAudioDeviceModule` の `audioDeviceModuleInit` を lazy にする、または dummy ADM にフォールバックさせる。本番挙動（実 audio device の初期化失敗を検知できなくなる）を変えるため慎重に評価する。

モックやスタブを差し込む案（fake 実装をリンクする、handler をテストコードで置き換える、`AudioDeviceModule` インタフェースをテストで差し替える等）は `AGENTS.md` 「モックやスタブは絶対に利用しないこと」に抵触するため取らない。ただし既存の公開 API を切り替える操作（候補 1）はモック/スタブに該当しない。

issue 0142（系統 A-1: `createSessionDescription` の nullptr）は SDP パーサ経路であり ADM に依存しないため、根本原因を共有する可能性は低い（0142「別原因判定の基準」でも同じ結論）。独立に切り分ける。系統 C（issue 0141）も Flutter binding 依存で独立。

## 完了条件

- [ ] ローカル（macOS）で `SORA_FFI_TEST_LIBRARY_PATH` を設定して同テストを走らせ、再現するかを確認する（macOS で pass すれば Linux ランナー環境依存であることが確定する）
- [ ] 候補 1（`MediaDevices.setUseAudioDevice(false)` を setUp で呼ぶ）が Linux CI で `audioDeviceModuleInit` rc=0 を返すかを確認する
- [ ] 候補 1 / 候補 2 / 候補 3 のいずれかを採用した根拠を issue 本文か PR 説明に記録する
- [ ] `SORA_FFI_TEST_LIBRARY_PATH` を設定した状態で上記 5 テストがすべて pass する
- [ ] Linux CI の `Run FFI-dependent package tests` step で `AudioDeviceModule init failed` の失敗が消えている
- [ ] 系統 A（issue 0142）と独立に切り分けたことを確認する（同じ原因の疑いが浮上した場合は issue 統合を検討する）

## 解決方法

`test/sora_media_stream_test.dart` の `LocalMediaStream track cache の参照管理 (FFI)` group の `setUpAll` 冒頭で `MediaDevices.setUseAudioDevice(false)` を呼び、共有 factory を real ADM ではなく push ADM で初期化するように変更した。設計方針の候補 1 を採用した理由は次のとおり。

- `push_audio_device.cc` の `adm_init` は Linux / macOS / Windows / iOS / Android 全プラットフォームで無条件 `return 0;` を返すことを一次資料 (`linux/push_audio_device.cc` 他) で確認した。Linux CI ランナーの headless 環境で発生していた `AudioDeviceModule init failed: rc=-1` を回避できる。
- track cache 参照管理の検証はマイク入力を必要としないため、push ADM に切り替えても本 group の意図を損なわない。
- `setUseAudioDevice` は `WebrtcClient._useAudioDevice` を切り替える公開 API 経路であり、AGENTS.md「モックやスタブは絶対に利用しないこと」に抵触しない (`sora_connection_config.dart:57-69` にも `useAudioDevice = false` の本番仕様が明記されている)。
- 呼び出し順序: `setUseAudioDevice` は共有 factory 生成後には値変更が拒否されるため (`WebrtcClient.useAudioDevice` setter の `_sharedFactoryRef != null` チェック)、setUpAll 内の最初の共有 factory 触り (`WebrtcClient.create`) より前に呼ぶ。実際に共有 factory を生成するのは `createMediaStream` / `createAudioTrack` / `connect` などの初回呼び出しだが、防衛的に一番先頭に置いた。同ファイル内で real ADM を必要とするテストを追加できなくなる旨をコメントで残した。
- `flutter test` はテストファイルごとに独立 isolate を作成するため、`WebrtcClient._useAudioDevice` の static 状態は他 5 ファイル (`webrtc_client_test.dart` / `sdp_negotiation_test.dart` / `sora_data_channel_controller_test.dart` / `simulcast_video_encoder_factory_test.dart` / `sora_connection_test.dart`) に漏れない。

候補 2 (CI ランナーに仮想 audio device を追加) は保守コスト増、候補 3 (native 側で ADM フォールバック) は本番挙動を変えるため採用しない。
