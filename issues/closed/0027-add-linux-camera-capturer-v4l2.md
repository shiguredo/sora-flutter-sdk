# Linux カメラキャプチャ (V4L2) を実装する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-linux-camera-capturer
- Polished: 2026-06-03

## 目的

Linux でカメラ映像を送信できるようにするため、V4L2 (Video4Linux2) を用いたカメラキャプチャを実装する。デバイス列挙・対応フォーマット取得・フレーム取得・I420 変換・libwebrtc の VideoTrackSource へのフレーム投入・ローカルプレビュー Texture 連動を担う。

本 issue は 0024 (Linux ネイティブ依存取得) と 0026 (Linux プラグイン基盤) の完了に依存する。0026 が提供する MethodChannel ハンドラ (`ensureLocalVideoTrackTexture` / `disposeLocalVideoTrackTexture` / `stopCameraCapturer`) の実体を実装する位置付け。

## 優先度根拠

- Linux での映像送信に必須の機能
- ビルド基盤・プラグイン基盤が前提であり、それらの後に着手する
- Medium とする

## 現状

- Linux にカメラキャプチャ実装は存在しない (`linux/` はスケルトン)
- Dart 側が MethodChannel 経由で要求するメソッドのうち、本 issue が実装するもの:
  - `enumerateVideoInputDevices`: カメラデバイス一覧を返す
  - `getVideoInputFormats`: 指定デバイスの対応解像度・FPS を返す
  - `ensureLocalVideoTrackTexture`: `videoSourcePtr` / `clientId` / `videoDeviceId` / `videoWidth` / `videoHeight` / `videoFrameRate` を受け取り `textureId` を返す
  - `disposeLocalVideoTrackTexture` / `stopCameraCapturer`: キャプチャ停止とリソース解放
- 0026 の MethodChannel ハンドラは本 issue の対象メソッドを `FlMethodNotImplemented` で返すため、実装後はハンドラを本実装に接続する
- 参照実装: macOS `SoraCameraCapturer.swift` (AVCaptureSession)、Android `SoraCameraCapturer.kt` (Camera2)。両者とも `enumerateDevices` / `formatsForDeviceId` / I420 変換 / `AdaptedVideoTrackSource` へのフレーム投入 / ローカルプレビュー Texture 連動を行う

## 設計方針

### V4L2 デバイス列挙

- `/dev/video*` を列挙し、`VIDIOC_QUERYCAP` でキャプチャ対応デバイスを絞り込む
- デバイス ID (パス) と表示名 (`card` フィールド) を返す

### フォーマット取得

- `VIDIOC_ENUM_FMT` で対応ピクセルフォーマットを取得
- `VIDIOC_ENUM_FRAMESIZES` / `VIDIOC_ENUM_FRAMEINTERVALS` で解像度・FPS 範囲を取得
- 戻り値の型は macOS/Android と同様に `{'deviceId': ..., 'formats': [{'width': ..., 'height': ..., 'maxFrameRate': ...}]}`

### フレーム取得と変換

- `mmap` でバッファを確保し、`VIDIOC_STREAMON` でストリーミング開始
- 取得フレーム (YUYV / MJPEG 等) を I420 に変換。libyuv が libwebrtc-c に同梱されていれば `libyuv` を利用する
- 変換後フレームを `AdaptedVideoTrackSource` に投入。`videoSourcePtr` で渡されるポインタを利用する
- キャプチャは専用スレッドで実行し、停止要求でスレッドを安全に終了させる

### ローカルプレビュー

- Flutter Linux の `FlTextureRegistrar` で Texture を登録し、`textureId` を返す
- プレビュー描画は I420 → RGBA 変換を伴う。0029 のレンダリング基盤と共通化できれば共通化する
- Texture の更新は `fl_texture_registrar_mark_texture_frame_available` で通知

### リソース管理

- `disposeLocalVideoTrackTexture` / `stopCameraCapturer` でキャプチャスレッド停止、mmap バッファ解放、Textur[[...]] 登録解除を行う
- デストラクタでも確実に停止する

## 完了条件

- `enumerateVideoInputDevices` が Linux 実機の接続カメラを列挙する
- `getVideoInputFormats` が指定デバイスの対応解像度・FPS を返す
- `ensureLocalVideoTrackTexture` でキャプチャが開始し、ローカルプレビューが表示され、相手側にカメラ映像が届く
- `stopCameraCapturer` / `disposeLocalVideoTrackTexture` でキャプチャが停止しリソースリークしない
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] Linux カメラキャプチャ (V4L2) を実装する
    - V4L2 によるデバイス列挙・フォーマット取得・フレームキャプチャ・I420 変換・ローカルプレビューを実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. Linux 版カメラキャプチャのソース (C/C++) を `linux/` に追加し、`linux/CMakeLists.txt` の `libsora_sdk.so` ターゲットにビルド対象として追加する
2. V4L2 によるデバイス列挙・フォーマット取得を実装する
3. mmap によるフレーム取得と I420 変換、`AdaptedVideoTrackSource` へのフレーム投入を実装する
4. ローカルプレビュー Texture 連動を実装する
5. 0026 の MethodChannel ハンドラから本キャプチャを呼び出すよう接続する
6. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する
