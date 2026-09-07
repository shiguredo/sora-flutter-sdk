# MethodChannel と FFI の二重デバイス管理を単一 façade に集約する

- Created: 2026-08-27
- Completed: 2026-09-07
- Branch: feature/refactor-device-management-consolidation
- Polished: {YYYY-MM-DD}

## 目的

音声入力デバイスの切り替え責務が Dart 層で `media/sora_media_device_platform.dart`（MethodChannel）と `ffi/webrtc_client.dart`（`setRecordingDeviceByGuid`）の 2 箇所に散在しており、片方の実装だけが更新されると挙動差が発生するリスクを解消する。

## 現状

`lib/src/media/sora_media_device_platform.dart` の `setAudioInputDevice` は「macOS/Windows/Linux は FFI 直、iOS/Android は MethodChannel」にプラットフォーム分岐して実装されている。

同じ「音声入力デバイスの切り替え」責務が:

- `sora_media_device_platform.dart`（プラットフォーム別 MethodChannel）
- `ffi/webrtc_client.dart` の `setRecordingDeviceByGuid`（FFI 直接呼び出し）

の 2 箇所に散らばっている。将来「MethodChannel 側でしかログを追加せずに FFI 側が壊れる」等の回帰が起こりうる。

## 設計方針

- 「音声入力デバイスの切り替え窓口」を 1 クラスに集約する。プラットフォームごとの実装を戦略（Strategy パターン相当）として持たせる。例: `AudioInputDeviceController` インターフェースと `FfiAudioInputDeviceController` / `MethodChannelAudioInputDeviceController` の 2 実装。
- 呼び出し側は集約された窓口のみを触る。プラットフォーム分岐は 1 か所に閉じる。
- 映像デバイス側（カメラ列挙）も同じ責務分離が必要なら、本 issue のスコープに含めるか別 issue に切る。範囲を絞るなら音声のみ。
- 既存挙動は変更しない。API サーフェスと責務境界のみを整理する。

## 完了条件

- [ ] 音声入力デバイス切り替えの Dart 側窓口が 1 クラスに集約されている。
- [ ] プラットフォーム分岐が集約クラスの内部に閉じている。
- [ ] `WebrtcClient.setRecordingDeviceByGuid` を直接呼ぶ経路が消えている（もしくは意図がコメントで明示されている）。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

対応不要として closed にする。polish 時の実ファイル照合で以下が判明したため、本 issue の前提は成立しない。

- Dart 側の窓口は既に `media/sora_media_device_platform.dart` の `setAudioInputDevice` 1 つに集約されており、プラットフォーム分岐も同関数内に閉じている。`WebrtcClient.setRecordingDeviceByGuid` は並列窓口ではなく同関数 (90 行目相当) から呼ばれる唯一の下位実装であり、他の呼び出し元は無い。呼び出し側 (`sora_media_devices.dart`) も窓口経由のみである。
- よって「二重管理」「片方だけ更新による挙動差」の動機は存在せず、Strategy 導入は過剰設計になる。音声デバイス管理に手を入れる場合は別 issue で実際の問題を特定して起票する。
