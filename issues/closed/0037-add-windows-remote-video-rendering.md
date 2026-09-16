# Windows リモート映像レンダリングを実装する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-windows-remote-video-rendering
- Completed: 2026-06-15
- Polished: 2026-06-03

## 目的

Windows でリモート映像を表示できるようにする。リモートビデオトラックの attach、I420 → 表示用フォーマット変換、Flutter Texture への配信、フレーム更新通知、detach / 破棄を担う。

本 issue は 0032 (Windows ネイティブ依存取得) と 0034 (Windows プラグイン基盤) の完了に依存する。

## 優先度根拠

- Windows での映像受信・表示に必須
- Linux 先行のため Medium とする

## 現状

- Windows にリモート映像レンダリング実装は存在しない。
- Dart 側は MethodChannel 経由で `createRemoteVideoRenderer` / `disposeRemoteVideoRenderer` を要求する。戻り値は `{'rendererId': int, 'renderingSinkPtr': int, 'videoSinkPtr': int, 'textureId': int}`
- 参照実装: macOS `SoraVideoRendererSink.swift` (141 行) + `apple_bridge.c`、Android の RenderingSink + `jni_onload.c`、および Linux 版 (0029)。
- libwebrtc-c 側は `VideoSinkInterface` コールバックで I420 フレームを供給する。

## 設計方針

- リモートトラックに RenderingSink を attach し、libwebrtc-c の `VideoSinkInterface` コールバックで I420 フレームを受け取る。
- Flutter Windows の Texture 機構に合わせて配信する。`FlutterDesktopPixelBuffer` ベースのピクセルバッファ Texture (I420 → BGRA 変換、libyuv 利用) を第一候補とし、性能要件次第で `FlutterDesktopGpuSurfaceDescriptor` (D3D11 テクスチャ) を検討する。0035 のローカルプレビューと Texture 方式を統一する。
- フレーム到着ごとに `TextureRegistrar::MarkTextureFrameAvailable` で UI 更新を通知する。
- マルチスレッド安全なフレームバッファ管理を行う。
- Windows 版 C ブリッジ (0034 で土台を作る) に `windows_rendering_sink_*` 相当の関数群を実装する。

## 完了条件

- `createRemoteVideoRenderer` でリモート映像が Texture に描画され、`Texture(textureId:)` で表示できる。
- `disposeRemoteVideoRenderer` で描画が停止しリソースリークしない。
- recvonly 接続でリモート映像が表示される。
- `CHANGES.md` の `## develop` に担当者行付きで `[ADD]` エントリを追記する:
  ```
  - [ADD] Windows リモート映像レンダリングを実装する
    - RenderingSink による I420 フレーム受信・BGRA 変換・Flutter Texture 配信を実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. Windows 版 RenderingSink を C ブリッジに実装し、`sora_sdk.dll` ターゲット (0034) に含める。
2. I420 → BGRA 変換と `TextureRegistrar` への配信を実装する。
3. フレーム更新通知とスレッド安全なバッファ管理を実装する。
4. 0034 の MethodChannel ハンドラ (`createRemoteVideoRenderer` / `disposeRemoteVideoRenderer`) から接続する。
5. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する。
