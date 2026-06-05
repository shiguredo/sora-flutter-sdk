# Windows カメラキャプチャ (Media Foundation) を実装する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-windows-camera-capturer
- Polished: 2026-06-03

## 目的

Windows でカメラ映像を送信できるようにするため、Media Foundation を用いたカメラキャプチャを実装する。デバイス列挙・対応フォーマット取得・フレーム取得・I420 変換・libwebrtc の VideoTrackSource へのフレーム投入・ローカルプレビュー Texture 連動を担う。

本 issue は 0032 (Windows ネイティブ依存取得) と 0034 (Windows プラグイン基盤) の完了に依存する。

## 優先度根拠

- Windows での映像送信に必須
- Linux 先行のため Medium とする

## 現状

- Windows にカメラキャプチャ実装は存在しない。
- Dart 側は MethodChannel 経由で `enumerateVideoInputDevices` / `ensureLocalVideoTrackTexture` / `disposeLocalVideoTrackTexture` / `stopCameraCapturer` を要求する (`lib/src/media/sora_media_device_platform.dart:14-40`, `:122-168`)。
- 参照実装: macOS `SoraCameraCapturer.swift` (482 行)、Android `SoraCameraCapturer.kt` (698 行)、および Linux 版 (0027)。

## 設計方針

- Media Foundation (`MFEnumDeviceSources` / `IMFActivate`) でカメラを列挙し、デバイス ID・表示名を返す。
- `IMFMediaType` 列挙で対応フォーマット (解像度・FPS) を取得する。
- `IMFSourceReader` でフレームを取得し、NV12 / MJPEG など取得形式を I420 に変換する (libyuv 利用)。
- 変換後フレームを `AdaptedVideoTrackSource` (libwebrtc-c API) に投入する。`videoSourcePtr` で渡される VideoSource を利用する。
- ローカルプレビュー用に Flutter Windows の `TextureRegistrar` で Texture を割り当て、`textureId` を返す。Texture 方式 (ピクセルバッファ Texture / GPU Surface Texture) は 0037 のレンダリングと統一する。
- キャプチャはバックグラウンドスレッドで行い、停止・破棄でリソースを確実に解放する。COM の初期化 / 解放スコープに注意する。

## 完了条件

- `enumerateVideoInputDevices` が Windows 実機の接続カメラを列挙する。
- `ensureLocalVideoTrackTexture` でキャプチャが開始し、ローカルプレビューが表示され、相手側にカメラ映像が届く。
- `stopCameraCapturer` / `disposeLocalVideoTrackTexture` でキャプチャが停止しリソースリークしない。
- `CHANGES.md` の `## develop` に担当者行付きで `[ADD]` エントリを追記する:
  ```
  - [ADD] Windows カメラキャプチャ (Media Foundation) を実装する
    - Media Foundation によるデバイス列挙・フォーマット取得・フレームキャプチャ・I420 変換・ローカルプレビューを実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. Windows 版カメラキャプチャのソースを追加し、`sora_sdk.dll` ターゲット (0034) に含め、必要なライブラリ (mfplat / mf / mfreadwrite 等) をリンクする。
2. Media Foundation によるデバイス列挙・フォーマット取得を実装する。
3. フレーム取得と I420 変換、`AdaptedVideoTrackSource` への投入を実装する。
4. ローカルプレビュー Texture 連動を実装する。
5. 0034 の MethodChannel ハンドラから接続する。
6. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する。
