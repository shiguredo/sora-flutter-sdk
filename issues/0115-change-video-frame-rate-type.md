# `VideoInputFormat.maxFrameRate` (double) と `videoFrameRate` (int) の型不整合を解消する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/change-video-frame-rate-type
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`VideoInputFormat.maxFrameRate` が `double` 型なのに、`MediaDevices.getUserMedia` の `videoFrameRate` は `int?` 型で、利用者が `enumerateVideoInputDevices()` → `supportedFormats()` から得た値をそのまま渡せない不整合を解消する。

## 現状

`lib/src/sora_video_device.dart` の `VideoInputFormat.maxFrameRate` は `double`。`lib/src/sora_media_devices.dart` の `GetUserMediaOptions.videoFrameRate` および `createCameraVideoTrack(videoFrameRate: ...)` は `int?`。

利用者が `enumerateVideoInputDevices()` で得た `format.maxFrameRate` (`double`) をそのまま `videoFrameRate` に渡せず、`.toInt()` を挟む必要がある。API 一貫性の観点で不便。

## 設計方針

**A 案（両方を `int` に統一する）を採用する。** fps を `double` で扱う実用ニーズは低く、native 側の丸めは Dart 側で明示的に `round()` する形にすれば挙動が明確になる。B 案（両方 `double` 化）は `VideoCaptureSettings.frameRate` を共有する `createScreenVideoTrack` 経由で 0114 対象の `ScreenCaptureOptions.frameRate`（int）との不整合が生じ、native 5 プラットフォームの MethodChannel 受領側の型変更まで及ぶため採用しない。C 案（変換ヘルパー）は「追加変換を挟まずに済む」という目的を満たせないため採用しない。

- `VideoInputFormat.maxFrameRate` を `int` に変更する。変換箇所（`sora_media_device_platform.dart` の `(map['maxFrameRate']! as num).toDouble()`）で `round()` により丸める。`toStringAsFixed(0)`（`sora_video_device.dart` の 44 行）も `toString()` 相当に簡素化できる。
- native 側の `videoFrameRate` 受け取りは全プラットフォームで既に int に変換されているため、native 側の変更は不要（A 案は Dart 側のみで完結する）。
- 挙動変更となるため、CHANGELOG に CHANGE（後方互換のない変更）として記載する。

## 完了条件

- [ ] `VideoInputFormat.maxFrameRate` と `getUserMedia` の `videoFrameRate` の型が `int` に揃う。
- [ ] 利用者が enumerate → getUserMedia の経路で追加変換を挟まずに済む。
- [ ] 後方互換への影響が CHANGELOG に CHANGE として明記される。
- [ ] `flutter analyze` と関連テストが成功する。
