# Linux 音声デバイスの列挙と選択を実装する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-linux-audio-devices
- Polished: 2026-06-03

## 目的

Linux で音声入出力デバイスを列挙・選択できるようにする。マイク / スピーカーの列挙、既定入力デバイスの取得、入力デバイスの切り替えを担う。

本 issue は 0024 (Linux ネイティブ依存取得)、0025 (Linux ADM 初期化)、0026 (Linux プラグイン基盤) の完了に依存する。

## 優先度根拠

- Linux での音声入出力に必要
- デバイス選択 UI を伴う機能であり、基盤・ADM が前提
- Medium とする

## 現状

- Linux に音声デバイス管理実装は存在しない
- Dart 側が MethodChannel 経由で要求するメソッド:
  - `enumerateAudioInputDevices` / `enumerateAudioOutputDevices`
  - `getDefaultAudioInputDevice`
  - `setAudioInputDevice` — macOS は FFI 直接操作だが、Linux は MethodChannel 経由 (`sora_media_device_platform.dart:97-108`)
- 0025 の Linux ADM は `kPlatformDefaultAudio` で生成され、即時 release される。ネイティブ側 (C++ プラグイン) は Dart 側 ADM のポインタにアクセスできないため、デバイス切り替えには独自に ADM を生成して操作する必要がある
- 参照実装: macOS `SoraAudioDevices.swift` (CoreAudio)、Android `SoraAudioDevices.kt` (AudioManager)

## 設計方針

### デバイス列挙

- PulseAudio (`pa_context_get_source_info_list` / `pa_context_get_sink_info_list`) を用いてマイク・スピーカーを列挙する。PipeWire の PulseAudio 互換レイヤーもカバーされるため、実質ほとんどのディストリビューションで動作する
- デバイス ID と表示名を返す。戻り値の型は macOS/Android と同様に `{'deviceId': ..., 'label': ...}`

### 既定入力取得

- `getDefaultAudioInputDevice` で PulseAudio の既定ソース (または `@DEFAULT_SOURCE@`) を返す

### 入力デバイス切り替え

- `setAudioInputDevice` で録音デバイスを切り替える
- 実装方式: ネイティブ側が独自に libwebrtc-c の `createAudioDeviceModule` を呼び、`SetRecordingDevice` でデバイスを指定する。Dart 側の ADM (0025 で積んで即時 release したもの) は参照しない
- この方式では、PCF に積まれた ADM と切り替え操作に使う ADM が別インスタンスになるが、libwebrtc-c の ADM 実装がデバイス指定をシステム全体設定として扱うかどうかは要確認。もし ADM ごとに独立した設定を持つ場合は、PCF の ADM を取得する API が必要になる
- 仮に PCF の ADM を後から取得できない場合は、0025 の設計を変更し `_sharedAdmRef` 相当の参照保持に切り替え、FFI で `SetRecordingDevice` を呼ぶ方式に変更する。この判断は実装着手時に libwebrtc-c のソースコードを確認して行う

### CMake リンク

- PulseAudio の開発ライブラリ (`libpulse-dev` / `libpulse`) を `linux/CMakeLists.txt` にリンク追加する

## 完了条件

- `enumerateAudioInputDevices` / `enumerateAudioOutputDevices` が Linux 実機のデバイスを列挙する
- `getDefaultAudioInputDevice` が既定マイクを返す
- `setAudioInputDevice` で実際に録音デバイスが切り替わる
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] Linux 音声デバイスの列挙と選択を実装する
    - PulseAudio を用いた音声入出力デバイスの列挙と入力デバイス切り替えを実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. Linux 版音声デバイス管理のソース (C/C++) を `linux/` に追加し、`linux/CMakeLists.txt` の `libsora_sdk.so` ターゲットにビルド対象と PulseAudio のリンクを追加する
2. PulseAudio によるマイク・スピーカー列挙と既定入力取得を実装する
3. 入力デバイス切り替えを実装する (ADM 取得方式は libwebrtc-c の実装確認後に確定)
4. 0026 の MethodChannel ハンドラから接続する
5. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する
