# `MediaDevices.createAudioTrack` の空 `catch (_) {}` が全例外を握りつぶす

- Created: 2026-08-27
- Completed: 2026-09-07
- Branch: feature/fix-create-audio-track-swallow-exception
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`MediaDevices.getUserMedia` 経由の audio track 作成で、`setAudioInputDevice` の呼び出しを包む `catch (_) {}` が全例外を silent に握りつぶしているため、想定外の失敗（タイムアウト、MissingPluginException、Dart Error 等）が検知できないバグを修正する。

## 現状

`lib/src/sora_media_devices.dart` の `MediaDevices.createAudioTrack` の audio track 作成経路には次の catch がある:

- コメントは「オーディオ入力デバイスが存在しない環境（CI 等）では `setAudioInputDevice` が失敗する可能性があるが、ネイティブの audio track 作成自体はデバイスがなくても成功するため、エラーは無視して続行する。」
- しかし実装は `try { await media_device_platform.setAudioInputDevice(audioDeviceId); } catch (_) {}` の形で、`TimeoutException` / `MissingPluginException` / `PlatformException` / Dart `Error` を含む全例外を silent に捨てる。
- `setAudioInputDevice` の呼び出し条件は `Platform.isMacOS || Platform.isIOS || Platform.isWindows || Platform.isLinux || audioDeviceId != null` であり、Android / iOS で `audioDeviceId == null` の場合は本経路を通らない。
- `setAudioInputDevice` のデバイス不存在時の例外型はプラットフォームで異なる。iOS / Android の MethodChannel 経路では `PlatformException`（`audio_device_not_found`）、macOS / Windows / Linux の FFI 経路では `StateError`（`getDefaultAudioInputDeviceId` の `Default audio input device not found.`、`setRecordingDeviceByGuid` の `No audio input devices available.` / `Audio input device not found: $deviceId`）が投げられる。Linux は macOS / Windows と同一の FFI 経路であり、`PlatformException` の `device_not_found` は `setAudioInputDevice` 直の応答ではなく、`deviceId == null` 時に FFI 経路が内部で呼ぶ `getDefaultAudioInputDeviceId` 経由で投げられ得る。
- FFI 経路にはデバイス不存在以外の `StateError` として `AudioDeviceModule is not initialized.` と `SetRecordingDevice failed: ...` があり、Android には `invalid_argument` / `audio_routing_failed` / `audio_routing_timeout`、iOS には `set_preferred_input_failed` がある。いずれも現行は silent に捨てられる。
- `setAudioInputDevice` は 10 秒のタイムアウト付き（`sora_media_device_platform.dart` の `.timeout()`）である。

将来 `setAudioInputDevice` の失敗経路が広がったとき、または想定外の環境で例外が起きたときに検知手段が消える。

## 設計方針

- 想定失敗（silent に無視する）を「デバイス不存在を表す例外」に限定する:
  - iOS / Android: `PlatformException` の `code == 'audio_device_not_found'`（message は条件に含めない）
  - Linux / macOS / Windows: `deviceId == null` 時に `getDefaultAudioInputDeviceId` 経由で投げられ得る `PlatformException` の `code == 'device_not_found'`（message は条件に含めない）
  - macOS / Windows / Linux: `StateError` のうち `Default audio input device not found.` と `No audio input devices available.` は完全一致、`Audio input device not found: ` から始まるものは前方一致で判定する
- それ以外の例外は握りつぶさず、上位へ rethrow する。対象は `TimeoutException` / `MissingPluginException` / その他の `PlatformException`（`invalid_argument` / `audio_routing_failed` / `audio_routing_timeout` / `set_preferred_input_failed` を含む）/ その他の `StateError`（`AudioDeviceModule is not initialized.` / `SetRecordingDevice failed: ...` を含む）/ その他の Dart `Error` である。タイムアウトは切替未完了の通知であり、静かに無視するより呼び出し側に通知する方が安全であるため、rethrow により Android 環境で `getUserMedia` が失敗する挙動変更が生じ得ることを許容する。
- `MediaDevices` static 経路のため通常のログ手段（`_emitDebugMessage`）が使えない。rethrow を既定とし、`assert` は使わない（release ビルドで検知手段が消えるため）。方針を dartdoc に明記する。
- `0108` の `setAudioInputDeviceTimeout` 可変化とは同一関数域を変更するため、適用時は rebase で競合を整理する。本 issue は catch 縮小と分類関数のみを所有し、timeout 値の可変化は `0108` が所有する。

## 完了条件

- [ ] デバイス不存在の想定失敗（iOS / Android の `PlatformException('audio_device_not_found')`、`deviceId == null` 時の `PlatformException('device_not_found')`、macOS / Windows / Linux のデバイス不存在を示す `StateError` 3 種）は silent に無視される既存挙動を保つ。
- [ ] 想定外の例外（`TimeoutException` / `MissingPluginException` / その他の `PlatformException` / その他の `StateError` / その他の Dart `Error`）は握りつぶさず rethrow され、呼び出し側で検知できる。rethrow による Android 環境の挙動変更を許容し、`CHANGELOG.md` には記載しない（正式リリース前のため）。
- [ ] 上記シナリオを exercise するユニットテストを追加する。テストは `setAudioInputDevice` の例外分類ロジックをテスト可能な純粋関数として分離して実施する（モックやスタブは使わない）。`PlatformException` / `StateError` / `TimeoutException` / `MissingPluginException` の実インスタンスを渡して分類を検証する。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

`setAudioInputDevice` の失敗分類を `isAudioInputDeviceNotFoundError` 純粋関数に分離し、デバイス不存在のみ silent に無視して他は rethrow する。方針を dartdoc に明記し、例外分類のユニットテストを追加する。正式リリース前のため `CHANGELOG.md` には記載しない。
