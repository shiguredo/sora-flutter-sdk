# pub.dev の camera パッケージ利用で映像配信できるか調査する

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/debug-camera-package-video-streaming
- Polished: {YYYY-MM-DD}
- Reporter: @t-miya

## 目的

pub.dev の camera パッケージで取得した映像を Sora Flutter SDK で配信できるか、実用に耐えるかを調査し、SDK としてのサポート方針を判断する。

camera パッケージはプレビュー・撮影・`CameraImage` ストリームを提供するが、WebRTC の MediaStream / track は返さない。そのため `MediaDevices.getUserMedia()` の代替にはならず、SDK が公開している外部映像入力 (`MediaDevices.createExternalVideoTrack()` と `LocalVideoTrack.writeFrame()`) を経由する経路で実用になるかを確認する。

## 現状

- SDK は外部映像入力として `MediaDevices.createExternalVideoTrack()` と `LocalVideoTrack.writeFrame(ExternalVideoFrame)` (I420) を公開している
- devtools に検証用機能がある。接続タブの Developer Option「External Video Track」で、Android / iOS に限り camera パッケージの映像を external video track として送信できる
  - `devtools/lib/src/devtools_external_camera_manager.dart` が `CameraController` を `ResolutionPreset.medium`・音声なしで初期化し、Android は `ImageFormatGroup.yuv420`、iOS は `ImageFormatGroup.bgra8888` を要求する
  - `devtools/lib/src/devtools_external_video_source.dart` が `CameraImage` を pure Dart で I420 に変換して `writeFrame` する。iOS の bi-planar yuv420 は未対応で bgra8888 で代替しており、BGRA の色空間変換 + 4:2:0 化は pure Dart では高負荷とコメントされている
  - devtools は `camera: ^0.11.1` を利用している
- 実機での性能計測 (解像度・フレームレート・遅延・CPU 使用率) の結果は記録されていない
- SDK 内蔵のカメラ入力 (`MediaDevices.createCameraVideoTrack()` とネイティブのカメラキャプチャ実装) は OS のカメラ資源を直接占有するため、camera パッケージと同時に同じカメラを掴むことはできない
- camera パッケージの対応プラットフォームは Android / iOS / web であり、SDK が対応する desktop は対象外である

## 設計方針

- devtools の External Video Track を使い、Android / iOS の実機で映像配信の性能を計測する
- pure Dart 変換で実用に耐えるかを判断し、不足する場合は libyuv などのネイティブ変換の導入を検討する
- 計測結果をもとに、SDK として camera パッケージ連携をサポートするかを判断する。サポートする場合は変換方式と対応プラットフォーム、内蔵カメラ入力との選択方法を設計する

## 完了条件

- [ ] Android / iOS の実機で camera パッケージの映像を Sora で配信できることを確認している
- [ ] 性能計測の結果 (解像度・フレームレート・遅延・CPU 使用率) が記録されている
- [ ] pure Dart 変換で実用に耐えるか、ネイティブ変換が必要かの結論が出ている
- [ ] SDK として camera パッケージ連携をサポートするか、対応プラットフォームを含む方針が決まっている
- [ ] 方針に応じた follow-up issue が起票されている

## 関連

- `issues/closed/0088-add-external-video-frame-validation.md` (external video frame の validation)
- `issues/closed/0078-bug-fix-external-video-texture-id-leak.md` (external video track の texture 周り)
