# Linux リモート映像レンダリングを実装する

- Priority: Medium
- Created: 2026-06-03
- Completed: 2026-06-25
- Model: Opus 4.8
- Branch: feature/add-linux-remote-video-rendering

- Polished: 2026-06-03

## 目的

Linux でリモート映像を表示できるようにする。リモートビデオトラックの attach、I420 → RGBA 変換、Flutter Texture への配信、フレーム更新通知、detach / 破棄を担う。

本 issue は 0024 (Linux ネイティブ依存取得) と 0026 (Linux プラグイン基盤) の完了に依存する。0026 の MethodChannel ハンドラ (`createRemoteVideoRenderer` / `disposeRemoteVideoRenderer`) の実体を実装する位置付け。

## 優先度根拠

- Linux での映像受信・表示に必須
- 基盤が前提
- Medium とする

## 現状

- Linux にリモート映像レンダリング実装は存在しない。
- Dart 側は MethodChannel 経由で以下を要求する:
  - `createRemoteVideoRenderer`: `clientId` を受け取り `{'rendererId': int, 'renderingSinkPtr': int, 'videoSinkPtr': int, 'textureId': int}` を返す
  - `disposeRemoteVideoRenderer`
- 0026 の MethodChannel ハンドラでは未実装 (`FlMethodNotImplemented`) のため、実装後にハンドラを本実装に接続する
- 参照実装: macOS `SoraVideoRendererSink.swift` (141 行) + `apple_bridge.c` の `apple_rendering_sink_*` (CVPixelBuffer ベース、`FlutterTexture` 配信)。Android は `SoraSdkPlugin.kt` の RenderingSink + `jni_onload.c` の `on_android_frame` (ANativeWindow 描画)。
- libwebrtc-c 側は `VideoSinkInterface` コールバックで I420 フレームを供給する。

## 設計方針

- リモートトラックに RenderingSink を attach し、libwebrtc-c の `VideoSinkInterface` コールバックで I420 フレームを受け取る。
- I420 → RGBA 変換を行い (libyuv 利用)、Flutter Linux の `FlTextureRegistrar` 経由で `FlPixelBufferTexture` (またはそれに相当するピクセルバッファ Texture) として配信する。
- フレーム到着ごとに `fl_texture_registrar_mark_texture_frame_available` で UI 更新を通知する。
- マルチスレッド安全なフレームバッファ管理を行う (キャプチャ / レンダリングスレッドと UI スレッド間)。
- Linux 版 C ブリッジ (0026 で土台を作る) に `linux_rendering_sink_*` 相当の関数群を実装する。

## 完了条件

- `attachRemoteVideoTrack` でリモート映像が Texture に描画され、`Texture(textureId:)` で表示できる。
- `disposeRemoteVideoRenderer` で描画が停止しリソースリークしない。
- recvonly 接続でリモート映像が表示される。
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] Linux リモート映像レンダリングを実装する
    - RenderingSink による I420 フレーム受信・RGBA 変換・Flutter Texture 配信を実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

- `linux/linux_bridge.c` に `LinuxRenderingSink` を実装した
  - `VideoSinkInterface` コールバックで I420 フレーム受信、回転処理、RGBA 変換 (libyuv)
  - `FlPixelBufferTexture` 用の `copy_pixels` API (`linux_rendering_sink_copy_pixels`)
  - pthread mutex + cond による inflight 管理と安全な破棄
  - `sora_video_frame_create` 他 3 関数のスタブを実体に置き換え
- `linux/sora_sdk_plugin.cc` に MethodChannel ハンドラを実装した
  - `SoraRemoteVideoTexture`: `FlPixelBufferTexture` の GObject サブクラス
  - `createRemoteVideoRenderer` / `disposeRemoteVideoRenderer` ハンドラ
  - クライアント dispose 時のレンダラー全停止
- `linux/include/sora_sdk/sora_video_constants.h` を新設し FOURCC 定数を共通化
- `/review-diff-code` の指摘に対応した
  - `copy_pixels` のバッファ欠落時に FALSE を返すよう修正
  - `buffer_ref` の NULL チェック追加
  - pthread 系の戻り値チェック追加
  - 未使用フィールド削除、重複コードのヘルパー化

### 未検証項目

- 実機 (Linux) での recvonly 接続によるリモート映像表示は未検証
- Sora サーバーとの実機検証は後日実施する
