# Windows 音声デバイス (WASAPI) の列挙と選択を実装する

- Priority: Medium
- Created: 2026-06-03
- Completed: 2026-06-12
- Model: Opus 4.8
- Branch: feature/add-windows-audio-devices
- Polished: 2026-06-03

## 目的

Windows で音声入出力デバイスを列挙・選択できるようにする。マイク / スピーカーの列挙、既定入力デバイスの取得、入力デバイスの切り替えを担う。

本 issue は 0032 (Windows ネイティブ依存取得)、0033 (Windows ADM)、0034 (Windows プラグイン基盤) の完了に依存する。

## 優先度根拠

- Windows での音声入出力に必要
- Linux 先行のため Medium とする

## 現状

- Windows に音声デバイス管理実装は存在しない。
- Dart 側は MethodChannel 経由で `enumerateAudioInputDevices` / `enumerateAudioOutputDevices` / `getDefaultAudioInputDevice` / `setAudioInputDevice` を要求する (`lib/src/media/sora_media_device_platform.dart:42-113`)。Windows は MethodChannel 経由で実装する設計 (`:97-108`)。
- 参照実装: macOS `SoraAudioDevices.swift` (120 行)、Android の音声デバイス管理、および Linux 版 (0028)。

## 設計方針

- WASAPI (`IMMDeviceEnumerator`) でマイク (eCapture) / スピーカー (eRender) を列挙し、`IMMDevice` から表示名 (`PKEY_Device_FriendlyName`) とデバイス ID を取得する。
- `GetDefaultAudioEndpoint` で既定入力デバイスを返す。
- `setAudioInputDevice` で入力デバイスを切り替える。libwebrtc-c の ADM (0033 で積む ADM) を介した録音デバイス指定と、列挙したデバイス ID の対応付けを実装する。
- 0033 の Linux 版 ADM は 0025 と同様に即時 release される。Windows ネイティブ側 (C++ プラグイン) は Dart 側 ADM のポインタにアクセスできないため、デバイス切り替えには独自に ADM を生成して操作する必要がある。仮に PCF の ADM を後から取得できない場合は、0033 の設計を変更し `_sharedAdmRef` 相当の参照保持に切り替えることを検討する

## 完了条件

- `enumerateAudioInputDevices` / `enumerateAudioOutputDevices` が Windows 実機のデバイスを列挙する。
- `getDefaultAudioInputDevice` が既定マイクを返す。
- `setAudioInputDevice` で実際に録音デバイスが切り替わる。
- `CHANGES.md` の `## develop` に担当者行付きで `[ADD]` エントリを追記する:
  ```
  - [ADD] Windows 音声デバイス (WASAPI) の列挙と選択を実装する
    - WASAPI を用いた音声入出力デバイスの列挙と入力デバイス切り替えを実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. Windows 版音声デバイス管理のソース (`sora_audio_devices.h/cpp`) を追加し、`sora_sdk_plugin.dll` ターゲットに含めた。
2. WASAPI (`IMMDeviceEnumerator`) によるマイク (eCapture) / スピーカー (eRender) 列挙と、`GetDefaultAudioEndpoint` による既定入力取得を実装した。
3. 入力デバイス切り替え方式として、当初の設計（ネイティブ側で独自 ADM 生成）ではなく、0033 の設計を変更し `_sharedAdmRef` に ADM 参照を保持する方式を採用した。macOS と同一の FFI 経由 (`setRecordingDeviceByGuid`) でデバイス切り替えを行う。
4. 0034 の MethodChannel ハンドラから WASAPI 列挙結果を返すよう接続した。
5. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記した。
6. プラットフォーム結合テスト (`windows_audio_device_test.dart`) を追加した。Sora 接続不要で WASAPI 列挙とデバイス切り替えを検証する。
