# 変更履歴

- CHANGE
  - 後方互換のない変更
- ADD
  - 後方互換がある追加
- UPDATE
  - 後方互換がある変更
- FIX
  - バグ修正

## develop

- [ADD] WebrtcClient に Windows の AudioDeviceModule 初期化パスを追加する
  - Windows の PeerConnectionFactory 生成時に `kPlatformDefaultAudio` で ADM を初期化し、音声入出力を有効化する
  - @zztkm
- [ADD] Windows 向けネイティブ依存取得（libwebrtc-c / webrtc）を追加する
  - @zztkm
- [ADD] Windows ネイティブプラグイン基盤と MethodChannel ハンドラを追加する
  - CMake で `sora_sdk.dll` を生成し、MethodChannel によるクライアント管理を実装する
  - @zztkm
- [ADD] Windows カメラキャプチャ (Media Foundation) を実装する
  - Media Foundation によるデバイス列挙・フォーマット取得・フレームキャプチャ・I420 変換・ローカルプレビューを実装する
  - @zztkm
- [ADD] Windows リモート映像レンダリングを実装する
  - RenderingSink による I420 フレーム受信・BGRA 変換・Flutter Texture 配信を実装する
  - @zztkm
- [ADD] Windows 音声デバイス (WASAPI) の列挙と選択を実装する
  - WASAPI を用いた音声入出力デバイスの列挙と入力デバイス切り替えを実装する
  - @zztkm
- [UPDATE] libwebrtc-c を 0.150.0 に更新する
  - @zztkm
- [UPDATE] webrtc-build を m150.7871.0.0 に更新する
  - @zztkm
- [FIX] 同一接続上で getStats() の再入競合が発生した時に StateError が送出される問題を修正する
  - 修正後は getStats() が進行中の場合、新しい呼び出しは進行中の Future を共有して同じ結果を受け取る
  - @zztkm

### misc

- [ADD] CI に Windows ビルドジョブを追加する
  - `ci.yml` に `build-windows` ジョブを追加し、PR で Windows ビルドを実行する
  - @zztkm
- [ADD] remoteMediaStreams の grouping を検証する E2E テストを追加する
  - @zztkm
- [ADD] ローカル音声と映像の有効切り替えを検証する E2E テストを追加する
  - @zztkm
