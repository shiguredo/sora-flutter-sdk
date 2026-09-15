# Windows の DLL で補正 API のシンボル解決を検証する CI を追加する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/add-windows-dll-symbol-resolution-ci
- Polished: {YYYY-MM-DD}

## 目的

libwebrtc-c の更新やリンク設定の変更で Windows の `sora_sdk_plugin.dll` からシンボルが欠けた場合に、Windows 実機で実行するまで気付けない状態を防ぐこと。

## 現状

- バインディングは `late final` のため、シンボルが見つからない場合は初回アクセス時に `ArgumentError` になる (`lib/src/ffi/webrtc_client.dart`)
- Windows の DLL は `windows/CMakeLists.txt` の `WHOLEARCHIVE` と libwebrtc-c の `dllexport` で C API シンボルをエクスポートしている
- シンボル解決テスト (`test/webrtc_client_test.dart` の「音声デバイス補正 API のバインディング」) は Linux の FFI ジョブでのみ実行される
- `.github/workflows/ci.yml` の `build-windows` は devtools と e2e_test_app をビルドするだけでテストを実行しない
- E2E Test の Windows ジョブは `useAudioDevice: false` (push audio device) で動くため補正処理が早期 return し、補正 API の lookup は実行されない

## 設計方針

候補:

- `build-windows` の devtools ビルド後に、`PATH` と `SORA_FFI_TEST_LIBRARY_PATH` に `devtools/build/windows/x64/runner/Release` を指定して `flutter test test/webrtc_client_test.dart` を実行する。Linux ジョブと同型で、シンボル解決と `kWindowsDefaultDevice == -2` の両方を検証できる
- `dumpbin /exports` で `sora_sdk_plugin.dll` のエクスポートテーブルに `webrtc_AudioDeviceModule_EnableBuiltInAEC` / `webrtc_AudioDeviceModule_SetPlayoutDeviceWithWindowsDeviceType` / `webrtc_AudioDeviceModule_kDefaultDevice` が含まれることを確認する。定数値は Linux テストで確認済みのため export の有無だけを守る最小構成

どちらも `Upload devtools Windows artifact` より前に置き、Windows runner での安定性を確認して採用する。

## 完了条件

- [ ] `build-windows` で補正 API のシンボル解決 (または export の有無) が検証され、欠落時に CI が失敗する
- [ ] 追加したステップが Windows runner で安定して成功する
- [ ] 既存の CI 実行時間への影響が許容範囲である
- [ ] モックやスタブを使用していない

## 関連 issue

- 0170: Windows で実音声デバイス利用時に音声が送受信できない問題を修正する
