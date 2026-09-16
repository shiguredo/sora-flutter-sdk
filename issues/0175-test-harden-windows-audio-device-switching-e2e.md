# Windows の音声入力デバイス切り替え E2E テストを強化する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/test-harden-windows-audio-device-switching
- Polished: {YYYY-MM-DD}

## 目的

`e2e_test_app/integration_test/windows_audio_device_test.dart` の入力デバイス切り替えテストが「`MediaDevices.createAudioTrack` が例外を投げないこと」しか確認しておらず、選択したデバイスが実際に使われたかを検証していない。デバイス切り替えの失敗を検出できる形にして Windows の CI で回す。

## 現状

- 同テストは `MediaDevices.enumerateAudioInputDevices()` の結果の先頭デバイスを `audioDeviceId` に指定して `MediaDevices.createAudioTrack` を呼び、例外が出ないことだけを確認している
- `createAudioTrack` は録音デバイスの切り替え失敗をデバイス不存在として握り潰す (`lib/src/sora_media_devices.dart` の `createAudioTrack`、`lib/src/media/sora_media_device_platform.dart` の `isAudioInputDeviceNotFoundError`)。そのため切り替えが効かなくても例外にならず、テストは成功する
- 先頭デバイスを選ぶため、既定デバイスが使われた場合と区別できない。0173 の修正前は Windows 実機で「入力デバイスを変更しても前回のデバイスが使われ続ける」症状が出ていたが、このテストはその状態でも成功し得る
- ADM に適用されたデバイスを読む公開 API は無い。`WebrtcClient` は `lib/sora_sdk.dart` で export していない
- 同テストは Sora 接続を作らないため PeerConnection が生成されず、`native: windows_audio_restore` は出力されない。再適用は `WebrtcClient._configureWindowsAudioDeviceAfterPeerConnection` (PeerConnection 作成直後) と `WebrtcClient._addExistingLocalAudioTrack` (`pcAddTrack` 直前) の 2 箇所からのみ呼ばれる
- 同テストは `.github/workflows/e2e-test.yml` の Windows マトリクスに含まれておらず CI では実行されない。ランナーは `windows-2025` を使う
- Windows のランナーで音声入力デバイスが列挙できるかは未確認である。`e2e_test_app/integration_test/audio_media_e2e_test.dart` は `PushAudioTrack` (push audio device) を使うため、実デバイスの有無を裏付ける証拠にならない

## 設計方針

候補:

- 先頭以外のデバイスを選び、切り替えの成否を検証する。既定デバイスとの一致を避けることで、デバイス指定が効いていない状態を検出できる
- SDK にテストから参照できる観測 API を追加し、要求したデバイスが解決・適用されたことを確認する。0173 の原因調査で使った診断シンク (`native: recording_device_resolve deviceId=... target_index=...` を出力する callback) と同型の API が候補になる。`e2e_test_app` から `package:sora_sdk/src/...` を import した前例が無いため、公開バレル経由で参照できる形にする
- 2 つのデバイスを順に指定して `createAudioTrack` を呼び、切り替えを検証する。1 回目の録音初期化後に 2 回目を適用する経路になり、0173 と同じ形の失敗 (切り替えが効かず例外も出ない) を検出できる可能性がある
- `.github/workflows/e2e-test.yml` の Windows マトリクスへ追加する。シークレットを必要としないテストのため、非接続のテストだけを別ジョブにする選択肢も検討する

検証の深さは「SDK が要求を受け取ったことまで」と「ADM へ適用された結果まで」で難易度が異なるため、実装時に決める。実装前に Windows のランナーで音声入力デバイスが列挙できるかを確認し、列挙できない場合はテストから skip 理由を出す形にする。

## 完了条件

- [ ] 非既定のデバイスを選んで切り替えを検証するテストになっている
- [ ] 2 つのデバイスを順に選び、切り替えが反映されることを検証している
- [ ] Windows の CI (`.github/workflows/e2e-test.yml`) で実行される
- [ ] 音声入力デバイスが利用できない環境では理由付きで skip する
- [ ] モックやスタブを使用していない

## 関連 issue

- 0173: devtools で再接続時に音声入力デバイスの選択が反映されない問題を修正する
