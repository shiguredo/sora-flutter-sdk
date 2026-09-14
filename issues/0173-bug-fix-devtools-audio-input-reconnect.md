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

再接続時、`MediaDevices.createAudioTrack(audioDeviceId: B)` が呼ぶ `AudioDeviceModule` は録音デバイス数を `-1` として返す。`WebrtcClient.setRecordingDeviceByGuid` はこの状態を `StateError('No audio input devices available.')` とし、`MediaDevices.createAudioTrack` がそれをデバイス不存在として握り潰すため、切り替えは行われず、`WebrtcClient._selectedRecordingDevice` は前回のデバイス A のまま残る。その後 `windows_audio_restore` が A を再適用するため、選択した B は使われない。

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

- `setRecordingDeviceByGuid` は、ADM が録音デバイスを列挙できない場合 (`adm_unavailable` / `no_devices`) を例外にせず、選択を `_selectedRecordingDevice` に保持して戻る。ADM が復旧した時点の再適用で切り替える
  - 復旧を待つ既存の再適用は `_configureWindowsAudioDeviceAfterPeerConnection` (PeerConnection 作成直後) と `_addExistingLocalAudioTrack` (`pcAddTrack` 直前) の 2 箇所である
  - `_restoreSelectedRecordingDevice` も列挙結果を確認し、`adm_unavailable` / `no_devices` のときは `windows_audio_restore skipped: ...` を記録して次の再適用へ委ねる
  - デバイスが一覧に無い場合と `SetRecordingDevice` が rc != 0 の場合は従来どおり `StateError` を返し、`native: recording_device_resolve ... target_index=none` と `reason=set_failed rc=...` を記録する
- `MediaDevices.createAudioTrack` の握り潰しは残す。切り替えが後続の再適用で完了するため、トラック生成を失敗させる必要がない
- 選択を保持したまま再接続すると、一覧に無いデバイスを指定した場合でも再適用が `target_index=none` で失敗し、ADM には既定デバイスが残る。この状態は `native: windows_audio_restore ... error=...` で観測できる

### devtools 側の併せて直す点

`_prepareLocalStream` の再利用分岐に音声トラックのデバイス差分検出が無い非対称は残っている。到達するのは Sora サーバー起因の切断でデバイスを変更しない場合だけであり、その場合は選択と既存トラックのデバイスが一致するため実害はない。将来 `_clearLocalPreview()` の条件を見直して `_localStream` を保持する経路を増やす場合に備え、次の方針で併せて直す。

#### 前回デバイス ID の保持

- 保持先は `DevToolsConnectionController` の private field とする。`DevToolsConnectRequest` には追加しない (`devtools/test/devtools_connection_controller_test.dart` の `_createConnectRequest` を変更せずに済み、保持値の寿命も controller と一致する)
- `String?` 1 つでは「未設定」と「既定入力を使った」を区別できないため、次の 2 つで表す

  ```dart
  // 接続中の音声トラック生成に使ったデバイス ID。null は既定入力を表す。
  String? _attachedAudioDeviceId;
  // _attachedAudioDeviceId が有効かどうか。false は未設定を表す。
  bool _hasAttachedAudioDeviceId = false;
  ```

- 更新は、新規生成分岐と作り直し分岐で音声トラックを `addTrack` した直後に限る
- 破棄は次で `_hasAttachedAudioDeviceId = false` にする。`configuredAudio` が偽で音声トラックを破棄する分岐、role が sendonly / sendrecv 以外または `configuredAudio` と `configuredVideo` が両方偽の早期 return、`_prepareLocalStream` の catch で stream 全体を破棄して rethrow する直前、beep トラックへ切り替えて実音声トラックを破棄する分岐
- `DevToolsConnectionController` には dispose が無いため、controller の破棄に伴う後始末は不要とする

### 作り直しの判定

- 判定順序は「`disposeBeepAudioTrack(localStream: localStream)` → 破棄条件の判定 → 作り直し要否の判定 → 作り直しまたは新規生成」に固定する
- beep の判定材料は `request.beepAudioEnabled` とする。`disposeBeepAudioTrack` が判定より前に beep トラックを stream から外すため、判定時点の `getAudioTracks()` に beep トラックは含まれない
- 優先順位は「beep 有効 > `useAudioDevice` 偽 > デバイス差分」とする。beep 有効時と `useAudioDevice` 偽のときは、選択中のデバイスが変わっていても作り直さない
- 作り直す条件は、`request.configuredAudio` が真、`request.beepAudioEnabled` が偽、`request.useAudioDevice` が真、音声トラックが存在する、かつ「保持値が未設定」または「保持値と選択中の `audioDeviceId` が異なる」のいずれかである
- 判定は純粋関数として `devtools/lib/src/devtools_audio_input_reconnect_policy.dart` に切り出す。引数は `hasAttachedDeviceId` (`bool`)、`attachedDeviceId` (`String?`)、`selectedDeviceId` (`String?`)、`configuredAudio`、`beepAudioEnabled`、`useAudioDevice`、`hasAudioTrack` とする。`devtools_local_preview_policy.dart` と同じ配置方針にそろえる

### 作り直しの手順

1. 既存の音声トラックをすべて `removeTrack` する
2. 各トラックを `dispose` する
3. 作り直す前に既存音声トラックの `enabled` を読む。読み出しは既存の `currentTrackEnabled` (`devtools/lib/src/devtools_track_state.dart`) を使い、SDK の track API を直接読まない
4. `MediaDevices.createAudioTrack(audioDeviceId: selectedAudioInputDeviceId)` を await する
5. 新しいトラックへ手順 3 の `enabled` を設定する
6. `addTrack` する
7. 生成に使ったデバイス ID を保持する

`LocalMediaStream.addTrack` は既に音声トラックがある状態で別の音声トラックを追加すると `StateError('Multiple audio tracks are not supported.')` を投げる (`lib/src/sora_media_stream.dart` の `addTrack`) ため、`removeTrack` と `dispose` を `addTrack` より前に行う。

### デバイス不存在の扱い

- `createAudioTrack` はデバイス不存在の例外だけを握り潰すため、デバイス設定が適用されないままトラック生成が続行する。ADM には前回適用されたデバイスが残る
- 保持しているデバイスが一覧から消えている場合は、フォールバック後の選択デバイスを正として差分を判定し、作り直す
- 選択を保持したまま接続し、復旧後の再適用でも一覧に無い場合は `target_index=none` となり、ADM には既定デバイスが残る。`native: windows_audio_restore ... error=Audio input device not found: ...` で観測できる

## エッジケースと期待動作

- ADM が録音デバイスを列挙できない (`adm_unavailable` / `no_devices`): 例外にせず選択を保持し、復旧後の再適用で切り替える
- 選択したデバイスが一覧に無い: 再適用で `target_index=none` となり、既定デバイスで接続を継続する
- `SetRecordingDevice` が rc != 0: 再適用でも失敗し、既定デバイスで接続を継続する
- 再接続を繰り返す: 再適用のたびに保持している選択を適用する
- 保持値が未設定かつ音声トラックが存在する: 作り直す
- 保持値と選択中のデバイス ID が同じ: 作り直さない
- 保持値と選択中のデバイス ID が両方 null (既定入力): 作り直さない
- 片方だけ null: 作り直す
- beep 音声が有効: 作り直す。ただし作り直しの対象は `audioDeviceId` 無しの `createAudioTrack()` であり、選択デバイスは適用されない (既存挙動)
- `useAudioDevice` が偽: 作り直さない
- デバイスを変更せずに再接続する: 再利用分岐でも作り直さない
- 作り直しの途中で例外が発生した場合: `_prepareLocalStream` の既存 catch が stream 全体を破棄して rethrow するため、個別の後始末は追加しない。保持値は破棄する

## 変更対象ファイル

- `lib/src/ffi/webrtc_client.dart` (`setRecordingDeviceByGuid`、`_trySetRecordingDeviceByGuid`、`_restoreSelectedRecordingDevice`)
- `lib/src/media/sora_media_device_platform.dart` (`setAudioInputDevice` のコメントのみ)
- `devtools/lib/src/devtools_audio_input_reconnect_policy.dart` (新規、再利用分岐の作り直し可否を判定する純粋関数。再利用分岐の非対称を直す場合のみ)
- `devtools/test/devtools_audio_input_reconnect_policy_test.dart` (新規、上記の単体テスト)
- `devtools/lib/src/devtools_models.dart` と `devtools/lib/src/devtools_settings_sections.dart` は変更しない
- 原因調査用の診断ログは削除済みである。`WebrtcClient.recordingDeviceDebugSink`、`MediaDevices.setRecordingDeviceDebugSink` / `recordingDeviceDebugSink`、`audio_input_reconnect:` ログ、`test/webrtc_client_recording_device_debug_sink_test.dart` は残さない

## テスト戦略

- ADM が録音デバイスを列挙できない場合に例外を投げず選択を保持することは、`setRecordingDeviceByGuid` が FFI を呼ぶため自動テストしない。実機の `native: windows_audio_restore device=... ok` で確認する
- `resolveRecordingDeviceIndex` の単体テスト (`test/webrtc_client_recording_device_test.dart`) は既存のものを維持する
- 再利用分岐の作り直し可否の判定を実装する場合は、純粋関数に切り出して `devtools/test/devtools_audio_input_reconnect_policy_test.dart` で表駆動の単体テストにする。固定する組み合わせは 保持値が未設定 / 同じ ID / 異なる ID / null と null / null と非 null / 非 null と null / 音声トラックなし / beep 有効 / `useAudioDevice` が偽 / `configuredAudio` が偽 とする
- `_prepareLocalStream` の実処理 (removeTrack / dispose / createAudioTrack / addTrack) はネイティブライブラリと実デバイスが必要なため自動テストしない。モックやスタブは追加しない
- 実マイクが 2 本以上ある Windows 実機での手動確認を `## 手動確認手順 (Windows 実機)` に従って行う

## 完了条件

### フェーズ 1: 原因確定 (完了)

- [x] 診断ログを実装し、Windows 実機で経路 3 / 4 / 5 の分岐到達を記録した
- [x] 原因を確定した。再接続時の ADM が録音デバイス数 `-1` を返し、その `StateError` がデバイス不存在として握り潰されるため選択が保持されない
- [x] 再利用分岐の到達条件を確定した (Sora サーバー起因の切断でデバイスを変更しない場合のみ到達し、症状の原因ではない)
- [x] 候補 (一覧の表記不一致 / rc != 0 / デバイス ID が null / 音声トラックの再利用 / 0170 の未解明事象) を棄却した
- [x] `## 原因` `## 設計方針` `## エッジケースと期待動作` `## テスト戦略` `## 完了条件` を確定内容に更新した

### フェーズ 2: 修正 (完了)

- [x] `setRecordingDeviceByGuid` が ADM の列挙不能を例外にせず選択を保持し、復旧後の再適用で切り替えるよう修正した
- [x] `_restoreSelectedRecordingDevice` が列挙不能時に `windows_audio_restore skipped: ...` を記録し、次の再適用へ委ねるよう修正した
- [x] 音声入力デバイスを A から B に変更して再接続すると `native: windows_audio_restore device=<デバイス B の ID> ok` が出力される (Windows 実機で確認)
- [x] 受信側で B のマイクの音声が届くことを確認した (Windows 実機で確認)
- [x] 原因調査用の診断ログを削除した
- [x] `flutter analyze --fatal-infos lib test` (リポジトリルート) と `flutter test` (リポジトリルート) が成功する
- [x] `cd devtools && flutter analyze --fatal-infos lib test` と `flutter test` が成功する
- [x] `dart format --output=none --set-exit-if-changed lib test` が差分なし
- [x] モックやスタブを使用していない
- [ ] `CHANGELOG.md` へは追記しない (`CODEBASE.md` の「正式リリース前」節)。正式リリース確定時に `[FIX]` を追記する

## 手動確認手順 (Windows 実機)

前提: 音声入力デバイスを A と B の 2 つ以上認識する Windows 実機を使う。入力デバイスが 1 つの環境では A / B の差分を確認できない。診断ログを削除したため、確認は SDK の `native: windows_audio_restore` と受信側の音声で行う。

1. `## 再現手順` の手順 1 から 4 を実施する
2. Diagnostics タブの Logs で、再接続後に `native: windows_audio_restore device=<デバイス B の ID> ok` が PeerConnection 作成直後と `pcAddTrack` 直前の 2 回出力されることを確認する
3. Diagnostics タブの Stats で sender の audio `outbound-rtp` の `bytesSent` / `packetsSent` が増加することを確認する
4. デバイス B にのみ話しかけ、audio `outbound-rtp` の `audioLevel` または `totalAudioEnergy` が反応することを確認する
5. 受信側で B のマイクの音声だけが届くことを確認する
6. Audio Track を無効にしてから入力デバイスを変更して再接続し、Audio Track が無効のままであることを確認する

CI (GitHub Actions の Windows Hosted Runner) には音声入力デバイスが無いため、この手順は自動テストでは代替できない。

## 確認結果

- `## 再現手順` に記載したとおり、改善前は再接続後も A が使われ、改善後は B が使われることを Windows 実機で確認した
- 再接続時は `RecordingDevices()` が `-1` を返すため選択を保持し、PeerConnection 作成直後の再適用で `target_index` を解決して B を適用することをログで確認した
- 受信側で B のマイクの音声が届くことを確認した

## 対象外

- 接続中の音声入力デバイス切り替え。ADM は録音初期化後に `SetRecordingDevice` を -1 で拒否し、UI 側も接続中は `Audio Input` を無効化している。SDK の `SoraConnection.replaceAudioTrack` は音声トラックを `rtpSenderSetTrack` で差し替えるだけで ADM の録音デバイスを切り替えないため、この用途には使えない
- 接続中にミュートした状態を再接続後も維持する対応。実機確認で維持されないことを確認したが、原因は devtools の UI 状態管理にある。接続中のミュートは `_toggleAudioEnabled` がトラックの `enabled` のみを変更し、`DevToolsPageNotifier.applyToggleAudio` は接続中に `connectAudio` を更新しない (`devtools/lib/src/devtools_models.dart`)。再接続時は `_prepareLocalStream` が音声トラックを `enabled = true` の既定値で新規生成するため、デバイス変更の有無に関係なくミュートが解除される。本 issue の修正対象 (SDK の録音デバイス選択) とは原因も変更対象も別であるため、別 issue に切り出す
- 前回実デバイスで接続し、今回 beep 音声を有効にして再接続した場合に既存の音声トラックが残り beep トラックが追加されない既存挙動
- `devtools/README.md` への制限事項の追記。ドキュメント整備は別 issue に切り出す

## 関連 issue

- 0170: Windows で実音声デバイス利用時に音声が送受信できない問題を修正する (closed)。`setRecordingDeviceByGuid` の選択内容を `_selectedRecordingDevice` に保持し、PeerConnection 作成直後と `pcAddTrack` 直前に再適用する実装を追加した。解決方法と確認結果は `issues/closed/0170-bug-fix-windows-audio-send-receive.md` を参照
- 0171: Windows でエコーキャンセルを有効化する (open)。本 issue で対象外とした「接続中の切り替え不可」は ADM の `SetRecordingDevice` の制約と関連する
- 0172: Windows アプリの COM 初期化要件 (MTA) を扱う (open)。ADM を生成できない環境では `setRecordingDeviceByGuid` が `StateError('AudioDeviceModule is not initialized.')` になる (`lib/src/ffi/webrtc_client.dart` の `_trySetRecordingDeviceByGuid`)。原因切り分けでこの状態と混同しないこと
