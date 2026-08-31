# `MediaDevices.createAudioTrack` の空 `catch (_) {}` が全例外を握りつぶす

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-create-audio-track-swallow-exception
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`MediaDevices.getUserMedia` 経由の audio track 作成で、`setAudioInputDevice` の呼び出しを包む `catch (_) {}` が全例外を silent に握りつぶしているため、想定外の失敗（タイムアウト、MissingPluginException、Dart Error 等）が検知できないバグを修正する。

## 現状

`lib/src/sora_media_devices.dart` の `MediaDevices.createAudioTrack` の audio track 作成経路には次の catch がある:

- コメントは「オーディオ入力デバイスが存在しない環境（CI 等）では `setAudioInputDevice` が失敗する可能性があるが、ネイティブの audio track 作成自体はデバイスがなくても成功するため、エラーは無視して続行する。」
- しかし実装は `try { await media_device_platform.setAudioInputDevice(audioDeviceId); } catch (_) {}` の形で、`TimeoutException` / `MissingPluginException` / `PlatformException` / Dart `Error` を含む全例外を silent に捨てる。
- `setAudioInputDevice` のデバイス不存在時の例外型はプラットフォームで異なる。iOS / Android の MethodChannel 経路では `PlatformException`（`audio_device_not_found`）、Linux の MethodChannel 経路では `PlatformException`（`device_not_found`、message `Default audio input device not found.`）、macOS / Windows の FFI 経路では `StateError`（`getDefaultAudioInputDeviceId` の `Default audio input device not found.`、`setRecordingDeviceByGuid` の `No audio input devices available.` / `Audio input device not found: $deviceId`）が投げられる。
- `setAudioInputDevice` は 10 秒のタイムアウト付き（`sora_media_device_platform.dart` の `.timeout()`）で、Android の Bluetooth SCO の routing 完了待ちで 10 秒を超えると `TimeoutException` が発生する。これはデバイス切替失敗の正常系として起こり得る。

将来 `setAudioInputDevice` の失敗経路が広がったとき、または想定外の環境で例外が起きたときに検知手段が消える。

## 設計方針

- 想定失敗（silent に無視する）を「デバイス不存在を表す例外」に限定する:
  - iOS / Android: `PlatformException` の `code == 'audio_device_not_found'`
  - Linux: `PlatformException` の `code == 'device_not_found'`（message `Default audio input device not found.`）
  - macOS / Windows: `StateError` のメッセージがデバイス不存在を示すもの（`Default audio input device not found.` / `No audio input devices available.` / `Audio input device not found: ...`）
- それ以外の例外（`TimeoutException` / `MissingPluginException` / その他の `PlatformException` / その他の Dart `Error`）は握りつぶさず、上位へ rethrow する。ただし `TimeoutException` は Android の Bluetooth SCO の routing 完了待ちで 10 秒を超えた場合に正常系として発生し得るため、rethrow により Android Bluetooth 環境で `getUserMedia` が失敗する挙動変更が生じる。この変更を許容する（タイムアウトはデバイス切替が完了しなかったことを意味し、静かに無視するより呼び出し側に通知する方が安全）ことを明記する。
- `MediaDevices` static 経路のため通常のログ手段（`_emitDebugMessage`）が使えない。rethrow を既定とし、`assert` は使わない（release ビルドで検知手段が消えるため）。方針を dartdoc に明記する。

## 完了条件

- [ ] デバイス不存在の想定失敗（iOS / Android の `PlatformException('audio_device_not_found')`、Linux の `PlatformException('device_not_found')`、macOS / Windows のデバイス不存在を示す `StateError`）は silent に無視される既存挙動を保つ。
- [ ] 想定外の例外（`TimeoutException` / `MissingPluginException` / その他の例外）は握りつぶさず rethrow され、呼び出し側で検知できる。
- [ ] 上記シナリオを exercise するユニットテストを追加する。テストは `setAudioInputDevice` の例外分類ロジックをテスト可能な純粋関数として分離して実施する（モックやスタブは使わない）。`PlatformException` / `StateError` の実インスタンスを渡して分類を検証する。
- [ ] `flutter analyze` と関連テストが成功する。
