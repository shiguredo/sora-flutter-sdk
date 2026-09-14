# devtools で再接続時に音声入力デバイスの選択が反映されない問題を修正する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-devtools-audio-input-reconnect
- Polished: 2026-09-14

## 目的

devtools で音声入力デバイスを変更して再接続しても、初回に使用したデバイスが使われ続ける問題を修正する。Windows 実機での確認中に発見した。

## 症状

Windows 実機で音声入力デバイスを変更して再接続しても、選択したデバイスが使われない。`native: windows_audio_restore` は前回の接続と同じデバイスを再適用し続ける。

観測したログ (デバイス ID は実値からプレースホルダへ置き換えている)。

```
[2026-09-14T15:01:28.020910] native: windows_audio_restore device=<デバイス A の ID> ok
```

`native: windows_audio_restore` は 1 回の接続で PeerConnection 作成直後と `pcAddTrack` 直前の 2 回出力される (`lib/src/ffi/webrtc_client.dart` の `_configureWindowsAudioDeviceAfterPeerConnection` と `_addExistingLocalAudioTrack`)。上記は 1 行のみで初回接続か再接続かの区別が無い。原因の確定時は、接続のたびに `connect: start role=...` (`devtools/lib/main.dart` の `_connect`) と対にして初回と再接続のログを両方記録する。SDK の debug メッセージは Diagnostics タブの Logs (app ログ) に出力される。event log は接続開始時に clear されるため使わない。

## 再現手順

1. Windows 実機で devtools を起動し、音声入力にデバイス A、音声出力に実デバイスを選択する
2. Connect Audio を有効、Send Beep Audio を無効、role を sendonly にして接続し、`windows_audio_restore` が A になることを確認する
3. `Disconnect` を押し、音声入力デバイスを B に変更する
4. 再接続し、`windows_audio_restore` が B になることを確認する

### 改善前の実測 (Windows 実機)

修正前は、再接続時の `windows_audio_restore` が A のままだった。原因確定に使ったログの要点を次に示す。

```
native: set_audio_input_device requested=B / effective=B enumerated=3 matched=true
native: recording_device_set deviceId=B
native: recording_device_set failed deviceId=B reason=no_devices count=-1
native: set_audio_input_device failed error=Bad state: No audio input devices available.
native: windows_audio_fix aec_rc=0 playout_rc=0
native: recording_device_set deviceId=A
native: windows_audio_restore device=A ok
```

初回接続では同じ箇所が `count=3` を返して `target_index=0` で成功していた。経路別の分岐到達は次のとおりである。

| 経路 | 切断操作 | デバイス変更 | `_prepareLocalStream` の分岐 | `windows_audio_restore` |
| --- | --- | --- | --- | --- |
| 初回接続 | なし | なし (A) | `branch=create` | A (期待どおり) |
| 経路 3 | `Disconnect` ボタン | A から B | `branch=create` | A (B にならない) |
| 経路 4 | Sora サーバー起因 | なし (A) | `branch=reuse` (`attach=unchanged audio_tracks=1`) | A (期待どおり) |
| 経路 5 | Sora サーバー起因 | A から B | `branch=create` | A (B にならない) |

### 改善後の実測 (Windows 実機)

修正後、再接続で選択したデバイスへ切り替わることを確認した。ログの要点を次に示す。

```
audio_input_reconnect: branch=create existing=false audio_tracks=0 ... selected_audio_device=B
native: set_audio_input_device requested=B / effective=B enumerated=3 matched=true
native: recording_device_set deferred deviceId=B reason=no_devices count=-1
audio_input_reconnect: attach=generated detail=getUserMedia device=B
native: windows_audio_fix aec_rc=0 playout_rc=0
native: recording_device_resolve deviceId=B ... target_index=1
native: recording_device_set ok deviceId=B target_index=1
native: windows_audio_restore device=B ok   (PeerConnection 作成直後と pcAddTrack 直前の 2 回)
```

再接続時は `count=-1` のため選択を保持し、ADM が復旧した再適用で `target_index=1` として B を適用している。受信側で B のマイクの音声が届くことも確認した。

### 原因確定に使った診断ログ

原因確定のあと、調査用の診断ログはすべて削除した (`27bf7f0`)。削除した内容は次のとおりである。

- SDK: `WebrtcClient.recordingDeviceDebugSink`、`MediaDevices.setRecordingDeviceDebugSink` / `recordingDeviceDebugSink`、`native: recording_device_*` / `native: set_audio_input_device` の出力
- devtools: `audio_input_reconnect:` の分岐・生成経路ログと起動マーカー、`setRecordingDeviceDebugSink` の設定
- テスト: `test/webrtc_client_recording_device_debug_sink_test.dart`

最終的な変更は `lib/src/ffi/webrtc_client.dart` の録音デバイス選択の保持と再適用のみである。

## 原因

再接続時、`MediaDevices.createAudioTrack(audioDeviceId: B)` が呼ぶ `AudioDeviceModule` は録音デバイス数を `-1` として返す。変更前の `WebrtcClient.setRecordingDeviceByGuid` はこの状態を `StateError('No audio input devices available.')` としていたため、`MediaDevices.createAudioTrack` がそれをデバイス不存在として握り潰し、切り替えは行われず、保持していた選択は前回のデバイス A のまま残った。その後 `windows_audio_restore` が A を再適用するため、選択した B は使われない。

libwebrtc の `AudioDeviceWindowsCore::RecordingDevices()` は `_RefreshDeviceList(eCapture)` が失敗すると `-1` を返す。切断時に `Terminate()` が capture collection を解放し、次の PeerConnection 作成まで復旧しないため、トラック生成の時点では列挙できない。

`-1` は 130 ms 後の `windows_audio_fix` / `windows_audio_restore` では `3` に戻っている。つまりデバイスは存在しており、列挙できない時間帯に切り替えようとしていたことが原因である。

### 棄却した候補

- ADM のデバイス一覧と選択中の `deviceId` の表記不一致: `adm_guids` に選択中の B がそのまま含まれ、初回と復旧後は `target_index` が解決するため否定された
- `SetRecordingDevice` の `rc != 0` による失敗: rc に到達する前に列挙で失敗しており、`reason=no_devices` であるため否定された
- 選択中のデバイス ID が `null`: 実測で `selected_audio_device=B` が記録されているため否定された
- 音声トラックの再利用: 経路 3 と 5 は `branch=create` のため否定された
- `setRecordingDeviceByGuid` が成功を返すのに録音に反映されない事象: 選択が保持されていないため `windows_audio_restore` が A を再適用しており、0170 の未解明事象とは別である

## 現状

- `MediaDevices.createAudioTrack` は `setAudioInputDevice` の例外をデバイス不存在として握り潰す (`lib/src/sora_media_devices.dart` の `createAudioTrack`、`lib/src/media/sora_media_device_platform.dart` の `isAudioInputDeviceNotFoundError`)。この分類では「デバイスが本当に無い」と「ADM が一時的に列挙できない」を区別できない
- 切断後の ADM は `RecordingDevices()` が `-1` を返す時間帯があり、その間に `SetRecordingDevice` を呼んでも切り替わらない
- `_prepareLocalStream` の再利用分岐は、既存 stream に音声トラックがあると `createAudioTrack` を呼ばない。到達するのは Sora サーバー起因の切断でデバイスを変更しない場合だけであり、選択と既存トラックのデバイスが一致するため症状には関与しない
- 接続中は `canChangeAudioInput` が偽になり `Audio Input` のドロップダウンが無効化される (`devtools/lib/main.dart`, `devtools/lib/src/devtools_settings_sections.dart`)

## 設計方針

修正は SDK 側 (`lib/`) で行い、`## 原因` のとおり「ADM が録音デバイスを列挙できない時間帯に切り替えようとしていた」ことを解消する。

- 保留の対象は「ADM が録音デバイスを列挙できない (`RecordingDevices()` が負の値)」場合に限定する。このときは例外にせず、要求を保持して復旧後の再適用へ委ねる
  - 復旧を待つ既存の再適用は `_configureWindowsAudioDeviceAfterPeerConnection` (PeerConnection 作成直後) と `_addExistingLocalAudioTrack` (`pcAddTrack` 直前) の 2 箇所である
  - `_restoreSelectedRecordingDevice` も同じ判定を使い、列挙できないときは `windows_audio_restore skipped: enumerate_failed ...` を記録して次の再適用へ委ねる。録音デバイスが 1 つも無い場合は `skipped: no_devices count=0` を記録する
- ADM を生成できない場合 (`adm == nullptr`) は従来どおり `StateError('AudioDeviceModule is not initialized.')` を投げる。列挙不能と違って復旧しないため、保留にすると選択が無言で破棄される。この例外はデバイス不存在の分類対象外なので、`createAudioTrack` が rethrow して接続側が検知する
- 一覧にデバイスが無い場合と `SetRecordingDevice` が rc != 0 の場合は従来どおり `StateError` を返す
- 要求された選択は適用の成否にかかわらず `_requestedRecordingDevice` に保持する。適用できなかった要求を前回の成功値へ戻すと、どのデバイスを使う要求だったかが失われ、再適用のログからも判別できなくなるため。`_releaseSharedFactoryResources` で共有 factory を破棄するときに選択も破棄する
- 保留の可否判定は純粋関数 `shouldDeferRecordingDeviceApply` に切り出し、`setRecordingDeviceByGuid` と `_restoreSelectedRecordingDevice` の両方で同じ判定を使う。ネイティブライブラリ無しで単体テストする
- `MediaDevices.createAudioTrack` の握り潰しは残す。切り替えが後続の再適用で完了するため、トラック生成を失敗させる必要がない
- 選択を保持したまま再接続すると、一覧に無いデバイスを指定した場合でも再適用が `target_index=none` で失敗し、ADM には既定デバイスが残る。この状態は `native: windows_audio_restore ... error=...` で観測できる

## エッジケースと期待動作

- ADM が録音デバイスを列挙できない (`RecordingDevices()` が負の値): 例外にせず要求を保持し、復旧後の再適用で切り替える。再適用も列挙できない場合は `windows_audio_restore skipped: enumerate_failed count=...` を記録して次の再適用へ委ねる
- 録音デバイスが 1 つも無い (列挙結果が 0): 復旧しないため保留しない。再適用は `skipped: no_devices count=0` を記録する
- ADM を生成できない (`adm == nullptr`): 復旧しないため `StateError('AudioDeviceModule is not initialized.')` を投げ、接続側が検知する。要求は保持するため、同じプロセスで ADM が生成されれば再適用の対象になる
- 選択したデバイスが一覧に無い: `_trySetRecordingDeviceByGuid` が `StateError('Audio input device not found: ...')` を返す。`MediaDevices.createAudioTrack` はこれをデバイス不存在として握り潰すためトラック生成は続行し、再適用は `windows_audio_restore ... error=...` を記録して既定デバイスで接続を継続する
- `SetRecordingDevice` が rc != 0: `StateError('SetRecordingDevice failed: ...')` を返す。分類対象外のため `createAudioTrack` が rethrow し、接続処理が失敗する (既存挙動)
- 再接続を繰り返す: 再適用のたびに保持している要求を適用する
- 共有 factory の破棄時 (`_releaseSharedFactoryResources`): 保持している要求も破棄する。古い要求を次に生成した ADM へ適用しないため
- beep 音声が有効: 音声トラックは `audioDeviceId` 無しの `createAudioTrack()` で生成され、選択デバイスは適用されない (既存挙動)

## 変更対象ファイル

- `lib/src/ffi/webrtc_client.dart` (`setRecordingDeviceByGuid`、`_enumerateRecordingDevices`、`shouldDeferRecordingDeviceApply`、`_trySetRecordingDeviceByGuid`、`_restoreSelectedRecordingDevice`、`_releaseSharedFactoryResources`)
- `test/webrtc_client_recording_device_test.dart` (`shouldDeferRecordingDeviceApply` の単体テストを追加)
- `lib/src/media/sora_media_device_platform.dart` は変更しない (`setAudioInputDevice` は列挙不能時に例外を投げない経路をそのまま通すため)
- `devtools/` は変更しない。原因調査用の診断ログは削除済みである。`WebrtcClient.recordingDeviceDebugSink`、`MediaDevices.setRecordingDeviceDebugSink` / `recordingDeviceDebugSink`、`audio_input_reconnect:` ログ、`test/webrtc_client_recording_device_debug_sink_test.dart` は残さない

## テスト戦略

- 保留の可否判定は純粋関数 `shouldDeferRecordingDeviceApply` に切り出し、`test/webrtc_client_recording_device_test.dart` で単体テストする。列挙失敗 (`-1`) は保留、デバイス無し (`0`) と列挙成功 (`1` 以上) は保留しないことを固定する
- `setRecordingDeviceByGuid` の FFI 呼び出し部分と `_restoreSelectedRecordingDevice` はネイティブライブラリと Windows 実機が必要なため自動テストしない。実機の `native: windows_audio_restore device=... ok` で確認する
- `resolveRecordingDeviceIndex` の単体テスト (`test/webrtc_client_recording_device_test.dart`) は既存のものを維持する
- `_prepareLocalStream` の実処理 (removeTrack / dispose / createAudioTrack / addTrack) はネイティブライブラリと実デバイスが必要なため自動テストしない。モックやスタブは追加しない
- `e2e_test_app/integration_test/windows_audio_device_test.dart` は本 issue の検証手段に使わない。理由は次節に記す
- 実マイクが 2 本以上ある Windows 実機での手動確認を `## 手動確認手順 (Windows 実機)` に従って行う。これが本 issue の唯一の検証手段である

### Windows E2E テストを検証手段に使わない理由

- `e2e_test_app/integration_test/windows_audio_device_test.dart` は Sora 接続を作らないため PeerConnection が生成されず、`native: windows_audio_restore` が出力されない。再適用は `_configureWindowsAudioDeviceAfterPeerConnection` (PeerConnection 作成直後) と `_addExistingLocalAudioTrack` (`pcAddTrack` 直前) の 2 箇所からのみ呼ばれるためである
- 接続なしで `MediaDevices.createAudioTrack(audioDeviceId:)` を呼んだ場合に確認できるのは「例外が出ないこと」だけで、ADM にどのデバイスが入ったかも、録音開始時にそれが使われたかも観測できない。ADM の状態を読む公開 API は無く、`WebrtcClient` は `lib/sora_sdk.dart` で export していない
- このテストは `.github/workflows/ci.yml` ではビルドのみ、`.github/workflows/e2e-test.yml` の Windows マトリクスにも含まれないため CI では実行されない。Windows 実機で手動実行したときに列挙と `createAudioTrack` が通ることを確認する煙テストとして扱う

## 完了条件

### フェーズ 1: 原因確定 (完了)

- [x] 診断ログを実装し、Windows 実機で経路 3 / 4 / 5 の分岐到達を記録した
- [x] 原因を確定した。再接続時の ADM が録音デバイス数 `-1` を返し、その `StateError` がデバイス不存在として握り潰されるため選択が保持されない
- [x] 再利用分岐の到達条件を確定した (Sora サーバー起因の切断でデバイスを変更しない場合のみ到達し、症状の原因ではない)
- [x] 候補 (一覧の表記不一致 / rc != 0 / デバイス ID が null / 音声トラックの再利用 / 0170 の未解明事象) を棄却した
- [x] `## 原因` `## 設計方針` `## エッジケースと期待動作` `## テスト戦略` `## 完了条件` を確定内容に更新した

### フェーズ 2: 修正 (完了)

- [x] `setRecordingDeviceByGuid` が ADM の列挙不能を例外にせず要求を保持し、復旧後の再適用で切り替えるよう修正した
- [x] ADM を生成できない場合は `StateError` を投げ、接続側が検知できるようにした
- [x] `_restoreSelectedRecordingDevice` が列挙不能時に `windows_audio_restore skipped: enumerate_failed ...` を記録し、次の再適用へ委ねるよう修正した
- [x] 保留の可否判定を純粋関数 `shouldDeferRecordingDeviceApply` に切り出し、単体テストを追加した
- [x] 音声入力デバイスを A から B に変更して再接続すると `native: windows_audio_restore device=<デバイス B の ID> ok` が出力される (Windows 実機で確認)
- [x] 受信側で B のマイクの音声が届くことを確認した (Windows 実機で確認)
- [x] 原因調査用の診断ログを削除した
- [x] `flutter analyze --fatal-infos lib test` (リポジトリルート) と `flutter test` (リポジトリルート) が成功する
- [x] `cd devtools && flutter analyze --fatal-infos lib test` と `flutter test` が成功する
- [x] `dart format --output=none --set-exit-if-changed lib test` が差分なし
- [x] モックやスタブを使用していない
- [ ] `CHANGELOG.md` に追記していないことを確認する (`CODEBASE.md` の「正式リリース前」節)。正式リリース確定時に `[FIX]` を追記する

## 手動確認手順 (Windows 実機)

前提: 音声入力デバイスを A と B の 2 つ以上認識する Windows 実機を使う。入力デバイスが 1 つの環境では A / B の差分を確認できない。診断ログを削除したため、確認は SDK の `native: windows_audio_restore` と受信側の音声で行う。

1. `## 再現手順` の手順 1 から 4 を実施する
2. Diagnostics タブの Logs で、再接続後に `native: windows_audio_restore device=<デバイス B の ID> ok` が PeerConnection 作成直後と `pcAddTrack` 直前の 2 回出力されることを確認する
3. Diagnostics タブの Stats で sender の audio `outbound-rtp` の `bytesSent` / `packetsSent` が増加することを確認する
4. デバイス B にのみ話しかけ、audio `outbound-rtp` の `audioLevel` または `totalAudioEnergy` が反応することを確認する
5. 受信側で B のマイクの音声だけが届くことを確認する

CI (GitHub Actions の Windows Hosted Runner) には音声入力デバイスが無いため、この手順は自動テストでは代替できない。`e2e_test_app/integration_test/windows_audio_device_test.dart` も Sora 接続を作らないため再適用を観測できず、代替にならない (`## テスト戦略` を参照)。したがって本手順が本 issue の唯一の検証手段である。

## 確認結果

- `## 再現手順` に記載したとおり、改善前は再接続後も A が使われ、改善後は B が使われることを Windows 実機で確認した
- 再接続時は `RecordingDevices()` が `-1` を返すため選択を保持し、PeerConnection 作成直後の再適用で `target_index` を解決して B を適用することをログで確認した
- 受信側で B のマイクの音声が届くことを確認した

## 対象外

- 接続中の音声入力デバイス切り替え。ADM は録音初期化後に `SetRecordingDevice` を -1 で拒否し、UI 側も接続中は `Audio Input` を無効化している。SDK の `SoraConnection.replaceAudioTrack` は音声トラックを `rtpSenderSetTrack` で差し替えるだけで ADM の録音デバイスを切り替えないため、この用途には使えない
- 接続中にミュートした状態を再接続後も維持する対応。実機確認で維持されないことを確認したが、原因は devtools の UI 状態管理にある。接続中のミュートは `_toggleAudioEnabled` がトラックの `enabled` のみを変更し、`DevToolsPageNotifier.applyToggleAudio` は接続中に `connectAudio` を更新しない (`devtools/lib/src/devtools_models.dart`)。再接続時は `_prepareLocalStream` が音声トラックを `enabled = true` の既定値で新規生成するため、デバイス変更の有無に関係なくミュートが解除される。本 issue の修正対象 (SDK の録音デバイス選択) とは原因も変更対象も別であるため、別 issue に切り出す
- `_prepareLocalStream` の再利用分岐に音声トラックのデバイス差分検出が無い非対称の解消。到達するのは Sora サーバー起因の切断でデバイスを変更しない場合だけであり、その場合は選択と既存トラックのデバイスが一致するため実害がない。将来 `_clearLocalPreview()` の条件を見直して `_localStream` を保持する経路を増やす場合に別 issue で扱う
- 前回実デバイスで接続し、今回 beep 音声を有効にして再接続した場合に既存の音声トラックが残り beep トラックが追加されない既存挙動
- 再適用の 2 箇所 (`_configureWindowsAudioDeviceAfterPeerConnection` と `_addExistingLocalAudioTrack`) の両方で列挙に失敗した場合の追加対策。実機では PeerConnection 作成直後までに ADM が復旧しており、復旧しなかった場合は `native: windows_audio_restore skipped: enumerate_failed count=...` が 2 回出て成功ログが出ないため Diagnostics タブの Logs から判別できる。上位へ通知する手段は `_emitState` の接続エラー経路しかなく、接続自体は成立している状態に対してエラーを出すのは過剰である。実機でこの状態が観測された場合に別 issue で扱う
- `devtools/README.md` への制限事項の追記。ドキュメント整備は別 issue に切り出す
- `e2e_test_app/integration_test/windows_audio_device_test.dart` の検証内容の強化。このテストは Sora 接続を作らないため再適用のログを観測できず、ADM に適用されたデバイスを読む公開 API も無いため、本 issue の症状を検出する形にできない。強化するには接続を伴う別のテストとして作る必要があり、手動確認手順で代替する

## 関連 issue

- 0170: Windows で実音声デバイス利用時に音声が送受信できない問題を修正する (closed)。`setRecordingDeviceByGuid` の選択内容を保持し、PeerConnection 作成直後と `pcAddTrack` 直前に再適用する実装を追加した。解決方法と確認結果は `issues/closed/0170-bug-fix-windows-audio-send-receive.md` を参照
- 0171: Windows でエコーキャンセルを有効化する (open)。本 issue で対象外とした「接続中の切り替え不可」は ADM の `SetRecordingDevice` の制約と関連する
- 0172: Windows アプリの COM 初期化要件 (MTA) を扱う (open)。ADM を生成できない環境では `setRecordingDeviceByGuid` が `StateError('AudioDeviceModule is not initialized.')` を投げる (`lib/src/ffi/webrtc_client.dart` の `setRecordingDeviceByGuid`)。原因切り分けでこの状態と混同しないこと
