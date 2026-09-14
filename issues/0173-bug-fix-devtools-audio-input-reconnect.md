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

## 再現手順 (要再確定)

観測時の操作列は確定できていない。`Disconnect` は `_disposeClient()` を通じて `_localStream` を破棄する (`devtools/lib/main.dart` の `_disconnect` と `_disposeClient`、`_clearLocalPreview`) ため、`Audio Input` を変更してから接続する操作では `existingLocalStream` が null になり、`## 原因` に挙げた再利用分岐へ到達しない。実際に症状が出た操作列を特定して本節を書き直すこと。

切り分けとして、次の 4 経路を順に試し、経路ごとに `windows_audio_restore` のデバイス ID を記録する。

1. Windows 実機で devtools を起動し、音声入力にデバイス A、音声出力に実デバイスを選択する
2. Connect Audio を有効、Send Beep Audio を無効、role を sendonly にして接続し、`windows_audio_restore` が A になることを確認する
3. Disconnect を押し、音声入力デバイスを B に変更して再接続する
4. Sora サーバー側から接続を閉じさせ、Disconnect を押さずに再接続する
5. 手順 4 と同じ切断のあと、音声入力デバイスを B に変更して再接続する

手順 4 と 5 の切断は、Sora サーバー側から接続を閉じさせ、devtools の `Disconnect` ボタンを押さずに `Connect` を押す。切断されたことは Diagnostics タブの state が `disconnected` に戻ることで確認する。

### 経路ごとの分岐到達の判定

原因の判断には、`_prepareLocalStream` がどちらの分岐を通ったかの記録を必ず対にする。追加する `audio_input_reconnect:` ログ (後述) で判定する。

| 経路 | 期待する分岐 |
| --- | --- |
| 3. Disconnect 後に B へ変更して再接続 | 新規生成 (`branch=create`)。再利用分岐には到達しない |
| 4. サーバー切断後に B へ変更せず再接続 | 再利用 (`branch=reuse`) |
| 5. サーバー切断後に B へ変更して再接続 | 再利用 (`branch=reuse`) |

経路 4 と 5 で `branch=reuse` にならない場合は、`existingLocalStream` に音声トラックが残っていないことを意味する。その場合は再利用分岐を原因から棄却し、`## 原因` の候補 2 以降の切り分けへ進む。

## 原因

`native: windows_audio_restore` は `WebrtcClient._selectedRecordingDevice` を再適用する。この値は `WebrtcClient.setRecordingDeviceByGuid` が成功したときだけ更新される (`lib/src/ffi/webrtc_client.dart` の `_trySetRecordingDeviceByGuid`)。したがってログが前回のデバイスのままであることは、再接続時に `setRecordingDeviceByGuid(B)` が成功していないことを示す。

現時点で確定していない原因候補を次に示す。実装前に切り分けて 1 つに絞ること。

1. デバイスが見つからないため設定が握り潰されている。`_trySetRecordingDeviceByGuid` は一致するデバイスが無いと `StateError('Audio input device not found: $deviceId')` を返し (`lib/src/ffi/webrtc_client.dart`)、`MediaDevices.createAudioTrack` はこの `StateError` をデバイス不存在として握り潰して続行する (`lib/src/sora_media_devices.dart` の `createAudioTrack`、`lib/src/media/sora_media_device_platform.dart` の `isAudioInputDeviceNotFoundError`)。この場合 `_selectedRecordingDevice` は更新されず、ADM には前回のデバイスが残ったまま `windows_audio_restore` が前回のデバイスを再適用する。観測した症状と最も整合する
2. 音声トラックが再利用されている。`_prepareLocalStream` の再利用分岐は、既存 stream に音声トラックがあると `createAudioTrack` を呼ばない (`devtools/lib/src/devtools_connection_controller.dart` の `_prepareLocalStream`)。この分岐は映像トラックを `useExternalVideoTrack` のときに作り直すが、音声トラックには同じ作り直しが無い。`## 再現手順 (要再確定)` のとおりこの分岐に到達していたかは未確定である
3. `SetRecordingDevice` が rc != 0 で失敗している。この場合 `_trySetRecordingDeviceByGuid` が `StateError('SetRecordingDevice failed: ... rc=...')` を返し、`isAudioInputDeviceNotFoundError` の対象外のため `createAudioTrack` が rethrow する (`lib/src/sora_media_devices.dart`)。`_prepareLocalStream` の catch が stream を破棄して rethrow するため接続自体が失敗し、`windows_audio_restore` は出力されない。観測したログが出ていることと矛盾するため、候補としては低い
4. 選択中のデバイス ID が `null` になっている。`setAudioInputDevice(null)` は既定入力デバイスへ戻す (`lib/src/media/sora_media_device_platform.dart`)

`setRecordingDeviceByGuid(B)` が成功を返しても録音に反映されない事象は、0170 の確認でも「作成直後の設定が録音時に反映されない機序は未解明」として残っている (`issues/closed/0170-bug-fix-windows-audio-send-receive.md` の確認結果)。原因がこの事象であれば、devtools 側だけでは解決しない。

### 追加する debug ログ

原因を確定するため、devtools 側に次のログを実装してから実機で再現する。プレフィクスは `audio_input_reconnect:` に統一し、英語で出力する。

- `audio_input_reconnect: branch=reuse existing=true|false audio_tracks=<n>`
- `audio_input_reconnect: branch=create existing=false device=<id|null>`
- `audio_input_reconnect: recreate from=<id|null> to=<id|null> muted=<true|false>`
- `audio_input_reconnect: skip reason=<beep|push_audio|same_device|not_configured>`
- `MediaDevices.createAudioTrack` の呼び出し前後で、渡した `audioDeviceId` の実値と例外の有無。例外が出た場合はその型とメッセージ

`MediaDevices.createAudioTrack` はデバイス不存在の例外だけを握り潰す (`lib/src/sora_media_devices.dart` の `createAudioTrack`)。したがって `audio_input_reconnect: create device=<id>` の直後に例外ログが無いのに `native: windows_audio_restore` が前回のデバイスのままなら、候補 1 (デバイス不存在による握り潰し) が確定する。例外ログが出ている場合は候補 3、`create` が記録されない場合は候補 2 と切り分けられる。

SDK 側 (`lib/src/media/sora_media_device_platform.dart` の `setAudioInputDevice`) は `WebrtcClient` のインスタンスを持たないトップレベル関数で debug ログの出力経路が無く、ログ追加には SDK の構造変更が要る。まず上記の devtools 側ログだけで切り分け、不足する場合に限り SDK 側の出力手段を検討する。

`WebrtcClient._selectedRecordingDevice` は private で公開 API が無いため、devtools からは `native: windows_audio_restore` のログと `createAudioTrack` の成否ログを突き合わせて判断する。

原因が確定したら本節を確定事項で置き換える。原因が SDK 本体 (`lib/`) の変更を要する場合は、`## 設計方針` と `## 完了条件` を更新したうえで、SDK 側の変更を本 issue に含めるか別 issue に分離するかを決める。

## 現状

- `_prepareLocalStream` の再利用分岐は、`localStream.getAudioTracks().isEmpty` が真のときだけ `createAudioTrack(audioDeviceId: selectedAudioInputDeviceId)` を呼ぶ。beep 音声が有効なときは `audioDeviceId` 無しの `createAudioTrack()` を呼ぶ (`devtools/lib/src/devtools_connection_controller.dart` の `_prepareLocalStream`)。この分岐は映像トラックを `useExternalVideoTrack` のときに作り直すが、音声トラックには同じ作り直しが無い。音声トラックが残っていれば選択中のデバイスは使われない
- devtools は「前回の音声トラック作成時に使ったデバイス ID」を保持していないため、再利用分岐でデバイスの差分を検出できない
- `onAudioInputChanged` は `_clearLocalPreview()` を呼び、`_clearLocalPreview()` は `_localStream` を null にして stream と track を破棄する (`devtools/lib/main.dart`)。`Disconnect` も同じく `_localStream` を破棄する (`devtools/lib/main.dart` の `_disconnect` と `_disposeClient`)
- したがって、再利用分岐が問題になり得るのは `existingLocalStream` に音声トラックが残っている場合だけである。観測時の操作列がこの条件を満たしていたかは未確定であり、`## 原因` で確定する
- 予期しない切断では devtools は `_localStream` を破棄しない (`devtools/lib/src/devtools_event_handler.dart`)。接続を保持したまま再接続した場合に `_localStream` が再利用分岐へ渡る
- SDK 側の制約として、ADM は録音初期化後に `SetRecordingDevice` を -1 で拒否するため、音声トラックを作り直す場合も録音初期化前にデバイスを設定する必要がある (`lib/src/ffi/webrtc_client.dart` の `_configureWindowsAudioDeviceAfterPeerConnection` と `_restoreSelectedRecordingDevice`)
- 接続中は `canChangeAudioInput` が偽になり `Audio Input` のドロップダウンが無効化される (`devtools/lib/main.dart`, `devtools/lib/src/devtools_settings_sections.dart`)。接続中の切り替えは UI からも実行できない

## 設計方針

原因が「音声トラックの再利用」または「デバイス不存在による握り潰し」だった場合の方針を次に示す。原因が別だった場合は `## 原因` の結果に合わせて本節以降を書き換えてから実装する。

### 前回デバイス ID の保持

- 保持先は `DevToolsConnectionController` の private field とする。`DevToolsConnectRequest` には追加しない (`devtools/test/devtools_connection_controller_test.dart` の `_createConnectRequest` を変更せずに済み、保持値の寿命も controller と一致する)
- `String?` 1 つでは「未設定」と「既定入力を使った」を区別できないため、次の 2 つで表す

  ```dart
  // 前回の音声トラック生成に使ったデバイス ID。null は既定入力を表す。
  String? _lastAudioTrackDeviceId;
  // _lastAudioTrackDeviceId が有効かどうか。false は未設定を表す。
  bool _hasLastAudioTrackDeviceId = false;
  ```

- 更新は、新規生成分岐と作り直し分岐で音声トラックを `addTrack` した直後に限る
- 破棄は次で `_hasLastAudioTrackDeviceId = false` にする。`configuredAudio` が偽で音声トラックを破棄する分岐、role が sendonly / sendrecv 以外または `configuredAudio` と `configuredVideo` が両方偽の早期 return、`_prepareLocalStream` の catch で stream 全体を破棄して rethrow する直前、beep トラックへ切り替えて実音声トラックを破棄する分岐
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
- 候補 1 が原因だった場合は、選択が反映されないまま接続が成立することを防ぐ。devtools 側で `createAudioTrack` の例外を記録したうえで、再接続を失敗させるか `audio_input_reconnect: skip reason=device_not_found` を記録して既定入力で続行するかを、原因の確定後に決める

## エッジケースと期待動作

- 保持値が未設定かつ音声トラックが存在する: 作り直す
- 保持値と選択中のデバイス ID が同じ: 作り直さない
- 保持値と選択中のデバイス ID が両方 null (既定入力): 作り直さない
- 片方だけ null: 作り直す
- beep 音声が有効: 作り直す。ただし作り直しの対象は `audioDeviceId` 無しの `createAudioTrack()` であり、選択デバイスは適用されない (既存挙動)
- `useAudioDevice` が偽: 作り直さない
- デバイスを変更せずに再接続する: 再利用分岐でも作り直さない
- 作り直しの途中で例外が発生した場合: `_prepareLocalStream` の既存 catch が stream 全体を破棄して rethrow するため、個別の後始末は追加しない。保持値は破棄する

## 変更対象ファイル

- `devtools/lib/src/devtools_connection_controller.dart` (`_prepareLocalStream`、保持 field、`audio_input_reconnect:` ログ)
- `devtools/lib/src/devtools_audio_input_reconnect_policy.dart` (新規、作り直し可否を判定する純粋関数)
- `devtools/test/devtools_audio_input_reconnect_policy_test.dart` (新規、純粋関数の単体テスト)
- `devtools/lib/main.dart` (`_clearLocalPreview()` の呼び出し条件を見直す場合のみ)
- `devtools/lib/src/devtools_models.dart` と `devtools/lib/src/devtools_settings_sections.dart` は変更しない
- `lib/` (SDK 本体) は変更しない。必要な API (`MediaDevices.createAudioTrack(audioDeviceId:)`) は既存を使う。`createAudioTrack` の挙動は変更せず、例外は devtools 側で記録する。原因切り分けの結果、SDK 側の修正が必要と判明した場合は、本 issue の設計方針と変更対象ファイルを更新して本 issue に含める。SDK 側だけを先行して修正する必要が生じた場合に限り、別 issue への分離を検討する

## テスト戦略

- 作り直し可否の判定は上記の純粋関数に切り出し、`devtools/test/devtools_audio_input_reconnect_policy_test.dart` で表駆動の単体テストにする
- 固定する組み合わせ: 保持値が未設定 / 同じ ID / 異なる ID / null と null / null と非 null / 非 null と null / 音声トラックなし / beep 有効 / `useAudioDevice` が偽 / `configuredAudio` が偽。「保持値が未設定」と「保持値が null」は別ケースとして固定する
- `_prepareLocalStream` の実処理 (removeTrack / dispose / createAudioTrack / addTrack) はネイティブライブラリと実デバイスが必要なため自動テストしない。モックやスタブは追加しない
- `DevToolsConnectRequest` にフィールドを追加しないため、`devtools/test/devtools_connection_controller_test.dart` は変更しない
- 実マイクが 2 本以上ある Windows 実機での手動確認を `## 手動確認手順 (Windows 実機)` に従って行う

## 完了条件

### フェーズ 1: 原因確定 (原因の如何にかかわらず必要)

- [ ] `## 原因` に書いた `audio_input_reconnect:` ログを devtools に実装し、Windows 実機で経路 3 / 4 / 5 の分岐到達と、`selectedAudioInputDeviceId` の実値、`createAudioTrack` の成否を記録する
- [ ] 観測した症状を説明できる原因を候補 1 から 4 のうち 1 つに絞り、棄却した候補と棄却理由を確認結果として残す (該当が無い場合は新しい原因を `## 原因` に追記する)
- [ ] 確定した原因に合わせて `## 再現手順` `## 原因` `## 設計方針` `## エッジケースと期待動作` `## テスト戦略` `## 完了条件` を更新する
- [ ] `dart format --output=none --set-exit-if-changed devtools/lib devtools/test` が差分なし
- [ ] `cd devtools && flutter analyze --fatal-infos lib test` が成功する
- [ ] モックやスタブを使用していない

### フェーズ 2: 修正 (原因が候補 1 または 2 と確定した場合)

- [ ] 再接続後に `audio_input_reconnect: branch=reuse` または `branch=create` と、作り直しの有無が意図どおり記録される (Windows 実機で手動確認)
- [ ] 音声入力デバイスを A から B に変更して再接続すると、`audio_input_reconnect: recreate from=<A の ID> to=<B の ID>` が 1 回だけ出力される (Windows 実機で手動確認)
- [ ] あわせて `native: windows_audio_restore device=<デバイス B の ID> ok` が PeerConnection 作成直後と `pcAddTrack` 直前に出力される (Windows 実機で手動確認)
- [ ] 上記の接続で sender の audio `outbound-rtp` の `bytesSent` / `packetsSent` が増加する (Windows 実機で手動確認)
- [ ] デバイスを変更せずに再接続した場合は `audio_input_reconnect: recreate` が出力されない
- [ ] 音声をミュートにしてから入力デバイスを変更して再接続しても、ミュートが維持される
- [ ] 追加した純粋関数の単体テストが成功する
- [ ] `cd devtools && flutter test` が成功する。devtools のテストは `.github/workflows/ci.yml` では実行されないため、ローカルで実行し結果を確認結果として残す
- [ ] `flutter analyze --fatal-infos lib test` (リポジトリルート) が成功する
- [ ] `CHANGELOG.md` へは追記しない (`CODEBASE.md` の「正式リリース前」節)。正式リリース確定時に `[FIX]` を追記する

## 手動確認手順 (Windows 実機)

前提: 音声入力デバイスを A と B の 2 つ以上認識する Windows 実機を使う。入力デバイスが 1 つの環境では A / B の差分を確認できない。

1. `## 再現手順 (要再確定)` の経路 3 / 4 / 5 を実施し、症状が再現する操作列を確定する
2. Diagnostics タブの Logs で、再接続後に `audio_input_reconnect: branch=...` の分岐と `audio_input_reconnect: recreate from=... to=...` の有無を確認する
3. 同じく Logs で、`native: windows_audio_restore device=<デバイス B の ID> ok` が PeerConnection 作成直後と `pcAddTrack` 直前の 2 回出力されることを確認する
4. Diagnostics タブの Stats で sender の audio `outbound-rtp` の `bytesSent` / `packetsSent` が増加することを確認する
5. デバイス B にのみ話しかけ、audio `outbound-rtp` の `audioLevel` または `totalAudioEnergy` が反応することを確認する
6. デバイスを変更せずに再接続し、`audio_input_reconnect: recreate` が出力されないことを確認する
7. Audio Track を無効にしてから入力デバイスを変更して再接続し、Audio Track が無効のままであることを確認する

CI (GitHub Actions の Windows Hosted Runner) には音声入力デバイスが無いため、この手順は自動テストでは代替できない。

## 対象外

- 接続中の音声入力デバイス切り替え。ADM は録音初期化後に `SetRecordingDevice` を -1 で拒否し、UI 側も接続中は `Audio Input` を無効化している。SDK の `SoraConnection.replaceAudioTrack` は音声トラックを `rtpSenderSetTrack` で差し替えるだけで ADM の録音デバイスを切り替えないため、この用途には使えない
- 前回実デバイスで接続し、今回 beep 音声を有効にして再接続した場合に既存の音声トラックが残り beep トラックが追加されない既存挙動
- `devtools/README.md` への制限事項の追記。ドキュメント整備は別 issue に切り出す

## 関連 issue

- 0170: Windows で実音声デバイス利用時に音声が送受信できない問題を修正する (closed)。`setRecordingDeviceByGuid` の選択内容を `_selectedRecordingDevice` に保持し、PeerConnection 作成直後と `pcAddTrack` 直前に再適用する実装を追加した。解決方法と確認結果は `issues/closed/0170-bug-fix-windows-audio-send-receive.md` を参照
- 0171: Windows でエコーキャンセルを有効化する (open)。本 issue で対象外とした「接続中の切り替え不可」は ADM の `SetRecordingDevice` の制約と関連する
- 0172: Windows アプリの COM 初期化要件 (MTA) を扱う (open)。ADM を生成できない環境では `setRecordingDeviceByGuid` が `StateError('AudioDeviceModule is not initialized.')` になる (`lib/src/ffi/webrtc_client.dart` の `_trySetRecordingDeviceByGuid`)。原因切り分けでこの状態と混同しないこと
