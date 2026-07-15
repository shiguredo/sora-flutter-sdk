# CHANGES

## develop

### sora_sdk

- [ADD] Linux リモート映像レンダリングを実装する
  - RenderingSink による I420 フレーム受信・RGBA 変換・Flutter Texture 配信を実装する
  - @zztkm

- [ADD] Linux ネイティブプラグイン基盤と MethodChannel ハンドラを追加する
  - CMake で `libsora_sdk.so` を生成し、MethodChannel / EventChannel によるクライアント管理を実装する
  - @zztkm

- [ADD] WebrtcClient に Linux の AudioDeviceModule 初期化パスを追加する
  - Linux の PeerConnectionFactory 生成時に `kPlatformDefaultAudio` で ADM を初期化し、音声入出力を有効化する
  - @zztkm

- [ADD] PushAudioDevice にデバイスレスの受信音声再生を追加する
  - 10 ms ごとに受信音声を pull できる API を追加し、物理出力デバイスなしで音声デコードを進める
  - @zztkm

- [ADD] Linux カメラキャプチャ (V4L2) を実装する
  - V4L2 によるデバイス列挙・フォーマット取得・フレームキャプチャ・I420 変換・ローカルプレビューを実装する
  - @zztkm

- [ADD] Linux 音声デバイスの列挙と選択を実装する
  - PulseAudio を用いた音声入出力デバイスの列挙と入力デバイス切り替えを実装する
  - @zztkm

- [FIX] shared factory の音声デバイス初期化を明示設定に変更する
  - メディア生成前に `useAudioDevice` を指定できるようにし、呼び出し順への依存を解消する
  - @zztkm

- [FIX] PushAudio の PCM 注入時に native 関数へ渡す引数順を修正する
  - @zztkm

### misc

- [ADD] SDK のクリティカルパスを検証する E2E テストを追加する
  - 双方向 sendrecv、接続ライフサイクル、音声メディア、Texture 描画を検証する
  - @zztkm

- [ADD] Android JNI に HWAddressSanitizer / UndefinedBehaviorSanitizer ビルドオプションを追加する
  - CMake option (`SORA_SDK_ENABLE_HWASAN` / `SORA_SDK_ENABLE_UBSAN`) と Gradle property (`-Psora.hwasan=true` / `-Psora.ubsan=true`) を追加する
  - DevTools に HWASan の実機検証用 `wrap.sh` を追加する
  - UBSan はランタイム不要の trap モードを採用する
  - @zztkm

- [ADD] notify と push と signalingNotifyMetadata の E2E テストを追加する
  - @zztkm

- [ADD] devtools を Windows でも使えるようにする
  - @zztkm

- [ADD] Windows に DataChannel Observer ブリッジを実装する
  - @zztkm

- [ADD] Windows に EventChannel イベント送出機構を実装する
  - @zztkm

- [ADD] Windows にカメラキャプチャ失敗時のエラー通知を実装する
  - @zztkm

- [ADD] replaceVideoTrack の E2E テストを追加する
  - @zztkm

- [ADD] messaging 専用接続の E2E テストを追加する
  - @zztkm

- [ADD] ユーザー定義 DataChannel の送受信 E2E テストを追加する
  - @zztkm

- [ADD] 接続失敗系の E2E テストを追加する
  - @zztkm

- [ADD] dispose 後の API 拒否を確認する E2E テストを追加する
  - @zztkm

- [ADD] シグナリングフェイルオーバーの E2E テストを追加する
  - @zztkm

- [ADD] DataChannel signaling の switched E2E テストを追加する
  - @zztkm

- [FIX] Windows の VideoFormat 重複除去を汎用的な実装に修正する
  - @zztkm

- [FIX] re-offer 受信経路に応じて re-answer の送信先を切り替えるよう修正する
  - @zztkm

- [ADD] 同一 bundleId 間の受信分離を確認する E2E テストを追加する
  - @zztkm

- [ADD] CI に Linux ビルドジョブを追加する
  - `ci.yml` に `build-linux` ジョブを追加し、PR で Linux ビルドを実行する
  - `e2e-test.yml` に `integration-test-linux` ジョブを追加する
  - @zztkm

- [ADD] Linux のドキュメントを追加し README のサポート OS を更新する
  - `docs/LINUX.md` を追加し、README の対応プラットフォーム表に Linux を反映する
  - @zztkm
