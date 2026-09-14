# devtools で再接続時に音声入力デバイスの選択が反映されない問題を修正する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-devtools-audio-input-reconnect
- Polished: {YYYY-MM-DD}

## 目的

devtools で音声入力デバイスを変更して再接続しても、初回に使用したデバイスが使われ続ける問題を修正する。選択したデバイスで音声を送信できるようにする。Windows 実機での確認中に発見した。

## 現状

- devtools は再接続時に前回の `_localStream` を `existingLocalStream` として渡す (`devtools/lib/main.dart:1120-1123`)
- `_prepareLocalStream` は既存 stream を再利用する分岐で、音声トラックが既に存在する場合は `createAudioTrack(audioDeviceId: ...)` を呼ばない (`devtools/lib/src/devtools_connection_controller.dart:777-800`)
- このため `MediaDevices.setAudioInputDevice` → `WebrtcClient.setRecordingDeviceByGuid` が呼ばれず、ADM には初回の録音デバイスが残り続ける
- 入力デバイスを変更しても `_clearLocalPreview()` が呼ばれるだけで、接続用の `_localStream` は破棄されない (`devtools/lib/main.dart:2400-2412` 付近)
- SDK 側の制約として、ADM は録音初期化後に `SetRecordingDevice` を -1 で拒否するため接続中の切り替えはできない。切り替えは音声トラックを作り直してから接続する必要がある

## 設計方針

- 再接続時に、選択中の `audioDeviceId` が前回の音声トラック作成時のものと異なる場合は、既存の音声トラックを破棄して `createAudioTrack(audioDeviceId: ...)` で作り直す
- 前回のデバイス ID を devtools 側で保持し、`_prepareLocalStream` の再利用分岐で差分を検出する
- 入力デバイス変更時に接続用の `_localStream` を破棄する方式は、映像トラックの再生成や再接続への影響が大きいため採用しない
- 接続中の切り替えは SDK の制約により対象外とし、再接続時の反映のみを対象とする
- 実デバイスが必要なため CI では検証できない。確認は Windows 実機で手動実施する

## 完了条件

- [ ] devtools で入力デバイスを変更して再接続すると、選択したデバイスで音声が送信される
- [ ] デバイスを変更せずに再接続した場合は音声トラックが不必要に作り直されない
- [ ] 接続中のデバイス変更は反映されない (再接続が必要) ことが README またはドキュメントに記載されている
- [ ] `flutter analyze` と関連テストが成功する
- [ ] モックやスタブを使用していない

## 関連 issue

- 0170: Windows で実音声デバイス利用時に音声が送受信できない問題を修正する
