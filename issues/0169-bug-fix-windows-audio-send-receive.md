# Windows で実音声デバイス利用時に音声が送受信できない問題を修正する

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-windows-audio-send-receive
- Milestone: 2026.1.0
- Polished: {YYYY-MM-DD}

## 目的

Windows で `useAudioDevice: true` の実音声デバイス (Windows CoreAudio ADM) を利用した接続において、音声が送信されず、受信音声も再生されない問題を修正する。macOS / Linux と同様に Windows でも実マイクと実スピーカーで音声の送受信を成立させる。

## 関連 issue

- 0033: WebrtcClient に Windows の AudioDeviceModule 初期化パスを追加する
- 0036: Windows 音声デバイス (WASAPI) の列挙と選択を実装する

## 再現手順

1. Windows 実機で devtools を起動する
2. 音声入力と音声出力に実デバイスを選択し、Connect Audio を有効、Send Beep Audio を無効にする
3. `useAudioDevice: true` で Sora に接続する
4. sendonly もしくは sendrecv で、sender の `outbound-rtp` の `bytesSent` が 0 のまま増加しない
5. recvonly もしくは sendrecv で、リモート音声の `inbound-rtp` は増加するが ADM の `Playing` が false のままで再生されない

## 現状

### 原因 1: Windows 内蔵 AEC が録音開始の前提にしている再生

`WebRtcVoiceEngine::Init()` は既定 AudioOptions で `echo_cancellation = true` を適用する。
Windows の CoreAudio ADM (`webrtc::AudioDeviceWindowsCore`) は Windows 内蔵 AEC (CWMAudioAEC DMO) が利用可能な場合に
`EnableBuiltInAEC(true)` を呼び、APM のソフトウェアエコーキャンセラを無効化する。

内蔵 AEC を有効にした `AudioDeviceWindowsCore::StartRecording()` は、再生が開始済み (`_playing == true`) でない場合に -1 を返す。
一方 `AudioState::AddSendingStream()` は録音開始時に再生開始を保証しない。
このため sendonly や、受信ストリーム到着前に送信を開始する接続では録音が開始されず、音声が送信されない。

実機ログで確認した内容:

- `EnableBuiltInAEC(1)` と `Disabling EC since built-in EC will be used instead` が出力される
- `StartRecording` が -1 を返す
- `media-source` の `totalSamplesDuration` が 0 のまま

### 原因 2: 既定通信デバイスが 2ch 非対応

`adm_helpers::Init()` は再生デバイスに `kDefaultCommunicationDevice` (eCommunications) を選択する。
このときの既定通信デバイスが 4ch のみ対応である場合、libwebrtc は mono / stereo のみを試すため `IsFormatSupported()` が失敗し、
`IAudioClient::Initialize()` が `AUDCLNT_E_UNSUPPORTED_FORMAT (0x88890008)` で失敗する。
結果として `InitPlayout()` が -1 となり `Playing` が false のままになるため、受信音声が再生されない。

実機ログで確認した内容:

- `Closest match: nChannels=4, nSamplesPerSec=48000` が出力される
- `IAudioClient::Initialize() failed` と `hr=-2004287480` が出力される

### 前提: COM アパートメント

Windows の実 ADM (`webrtc::AudioDeviceWindowsCore`) のコンストラクタは MTA を要求する。
Dart の FFI 呼び出しは runner の main スレッドで実行されるため、runner が STA のままだと
ADM 生成が `RTC_DCHECK(_comInit.Succeeded())` で abort し、`WebrtcClient.sharedAudioDeviceModule` が null となって
`WebrtcClient.setRecordingDeviceByGuid` が `StateError` になる。

devtools は MTA で初期化済みだが、e2e_test_app の runner は Flutter テンプレート既定の STA のままで、
実音声デバイスを使う既存テストが失敗する状態だった。

## 設計方針

- `WebrtcClient._ensurePeerConnection` で PeerConnection 作成に成功した直後に、Windows の実 ADM を補正する `WebrtcClient._configureWindowsAudioDeviceAfterPeerConnection` を呼ぶ
  - `LibWebrtcC.audioDeviceModuleEnableBuiltInAEC` で内蔵 AEC を無効化し、録音開始が再生開始に依存しないようにする
  - `LibWebrtcC.audioDeviceModuleSetPlayoutDeviceWithWindowsDeviceType` と `WebrtcConstants.kWindowsDefaultDevice` で再生デバイスをメディア向け既定デバイス (eConsole) へ切り替える
- 補正は `WebRtcVoiceEngine::Init()` による既定値の書き換え後、ローカルトラック追加 (録音初期化) より前に実行する必要があるため PeerConnection 作成直後に置く
- MediaEngine は全 PeerConnection の破棄で Terminate し、次の作成で再び Init される。補正は毎回必要になるため PeerConnection 作成ごとに呼ぶ。2 回目以降は ADM が -1 を返すだけで実害はない
- `useAudioDevice: false` (push audio device) や ADM 未生成時は何もしない。補正に失敗しても接続処理は継続する
- `e2e_test_app/windows/runner/main.cpp` の `wWinMain` を `COINIT_MULTITHREADED` に変更し、実 ADM を扱えるようにする
- 実音声デバイスの送受信は CI で自動実行できない。GitHub Actions の Windows Hosted Runner には音声入力デバイスがないため、Windows 実機で手動確認する
- エコーキャンセルは無効のままとする。APM のソフトウェアエコーキャンセラは内蔵 AEC 有効化時に無効化されており、ADM 側だけを戻しても復帰しない。AEC の復帰は設計判断が必要なため別 issue で扱う
- Flutter テンプレート既定の runner (STA) を使う実アプリでは ADM 生成が abort する問題が残る。MTA 要件のドキュメント化または SDK 側対応は別 issue で扱う

## 完了条件

- [ ] Windows 実機で sendonly / sendrecv の音声送信と recvonly / sendrecv の音声再生が成立する (手動確認)
- [ ] 音声入力に既定以外のデバイスを選択した接続でも、選択したデバイスが維持される (Windows 実機で手動確認)
- [ ] `e2e_test_app/integration_test/windows_audio_device_test.dart` が通過する
- [ ] FFI 依存テスト (`test/webrtc_client_test.dart` ほか) が通過する
- [ ] `flutter analyze --fatal-infos` がルート / devtools / e2e_test_app で成功する
- [ ] 正式リリース確定時に `CHANGELOG.md` へ `[FIX]` を追記し、Windows 内蔵 AEC が利用可能な環境でエコーキャンセルが無効になる副作用を明記する (CODEBASE.md の「正式リリース前」節のため、本ブランチでは追記しない)
- [ ] モックやスタブを使用していない

## 手動確認手順 (Windows 実機)

1. Windows 実機で devtools を起動する
2. 音声入力と音声出力に実デバイスを選択し、Connect Audio を有効、Send Beep Audio を無効にする
3. sendonly で接続し、sender の `outbound-rtp` の `bytesSent` / `packetsSent` が増加することを確認する
4. recvonly で接続し、リモート音声の `inbound-rtp` が増加し、実際に再生されることを確認する
5. sendrecv で接続し、送信と再生の両方が成立することを確認する
6. 音声入力に既定以外のデバイスを選択した接続で、既定の通信デバイスへ戻らず選択したデバイスが使われ続けることを確認する
7. 内蔵 AEC が利用可能な環境ではエコーキャンセルが無効になる副作用を確認する

CI (GitHub Actions の Windows Hosted Runner) には音声入力デバイスがないため、この手順は自動テストでは代替できない。

## 解決方法

- `lib/src/ffi/webrtc_client.dart` に `WebrtcClient._configureWindowsAudioDeviceAfterPeerConnection` を追加し、`WebrtcClient._ensurePeerConnection` の PeerConnection 作成成功直後に呼ぶようにした
- `WebrtcClient.setRecordingDeviceByGuid` の選択内容を保持し、PeerConnection 作成直後に `adm_helpers::Init()` が上書きした録音デバイスを再適用するようにした
- `lib/src/ffi/bindings.dart` に `LibWebrtcC.audioDeviceModuleEnableBuiltInAEC` と `LibWebrtcC.audioDeviceModuleSetPlayoutDeviceWithWindowsDeviceType` を追加し、`WebrtcConstants` に `kWindowsDefaultDevice` を追加した
- 録音デバイスの探索を純粋関数 `resolveRecordingDeviceIndex` へ分離し、`test/webrtc_client_recording_device_test.dart` に単体テストを追加した
- `test/webrtc_client_test.dart` に補正 API のシンボル解決と `kWindowsDefaultDevice` の値のテストを追加した
- `e2e_test_app/windows/runner/main.cpp` の `wWinMain` を `COINIT_MULTITHREADED` に変更し、`e2e_test_app/windows/runner/CMakeLists.txt` に `/utf-8` を追加した
- `CHANGELOG.md` への追記は正式リリース確定時に実施する。CODEBASE.md の「正式リリース前」節により、本ブランチでは追記しない。追記内容は `[FIX] Windows で実音声デバイス利用時に音声が送受信できない問題を修正する` とし、内蔵 AEC の無効化、再生デバイスと録音デバイスの補正、Windows 内蔵 AEC が利用可能な環境でエコーキャンセルが無効になる副作用を含める
- Windows 実機 (sendonly の sender と recvonly の receiver) で `useAudioDevice: true` の接続を行い、sender の `outbound-rtp` と receiver の `inbound-rtp` が増加することを手動確認した。sendrecv と、音声入力に既定以外のデバイスを選択した場合の選択保持は未確認
- CI では音声入力デバイスが使えないため、実音声デバイスの送受信テストは追加しない。回帰確認は Windows 実機で行う
