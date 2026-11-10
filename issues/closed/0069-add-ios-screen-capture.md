# iOS のアプリ内画面キャプチャ API を追加する

- Created: 2026-08-17
- Completed: 2026-08-28
- Branch: feature/change-remove-screen-capture-public-api
- Polished: 2026-08-17
- Reporter: @zztkm

## 経緯

初回公開リリースの公開判定で「公開 API の画面キャプチャ機能は外部へ公開せず、内部検証実装として維持する」方針へ変更した。当初の追加実装のうち、公開 API 面だけを撤回してクローズする。

## 解決方法

- `ScreenCaptureOptions` / `MediaDevices.createScreenVideoTrack()` / `SoraErrorCode.screenCaptureError` を公開 API から削除した。
- `VideoTrackCaptureType` enum に `@internal` を付与し、`LocalVideoTrack.captureType` getter も `@internal` へ変更した。`sora_sdk.dart` の export から `VideoTrackCaptureType` を除外した。
- 内部実装（ReplayKit によるキャプチャ、Texture 管理、エラーコードの内部専用リテラル）は維持した。
- devtools / e2e / テストの画面キャプチャ処理を削除し、README と CHANGELOG を更新した。
- 検証コマンド: `flutter analyze --fatal-infos lib test`（成功）、`flutter test`（成功）。公開 DartDoc に画面キャプチャ用 API が生成されないことを確認した。

## 目的

iOS で自アプリの画面映像を ReplayKit によりキャプチャし、Sora へ送信できる `LocalVideoTrack` として利用する API を追加する。

アプリ側で ReplayKit の開始・停止や `CMSampleBuffer` の変換を実装せず、Sora Flutter SDK の公開 API だけでアプリ内画面を共有できる状態を目指す。

ネイティブのキャプチャ処理は Sora iOS SDK の `Sora/ScreenCapture.swift` にある `ScreenCaptureSettings` と `ScreenCaptureController` をベースにする。ただし、公開 API、`LocalVideoTrack` の所有権、カメラとの切り替え、Texture、エラー通知は Flutter SDK の構造に合わせて実装する。

## 現状

- `MediaDevices` はカメラ映像トラックと外部映像トラックだけを作成できる
- `VideoTrackCaptureType` は `camera` と `external` だけを定義している
- 外部映像トラックを使う場合、ReplayKit の開始・停止、フレーム変換、フレームレート制御、競合制御をアプリごとに実装する必要がある
- `LocalVideoTrack.textureId` の初回取得は Texture の確保だけでなくカメラの開始も行い、その結果を `_textureIdFuture` に保持する
- iOS の `ensureLocalVideoTrackTexture` は停止済みキャプチャの再開を行わず、`stopCameraCapturer` に対応する MethodChannel handler も存在しない
- `_applyVideoCaptureBackend()`、`replaceVideoTrack()`、`removeVideoTrack()`、切断処理には、画面キャプチャの開始・停止・復旧を扱う経路がない
- `SoraFlutterMessageHandler` は `SoraCameraCapturer` だけを管理しており、ReplayKit のキャプチャ経路は存在しない
- iOS の最低サポートバージョンは 16.0 である

## 設計方針

### 公開 API

`MediaDevices` に次の API を追加する。

- `MediaDevices.createScreenVideoTrack({ScreenCaptureOptions options = const ScreenCaptureOptions()})`
  - iOS のアプリ内画面キャプチャ用 `LocalVideoTrack` を同期的に作成する
  - iOS 以外で呼び出した場合は `UnsupportedError` を送出する

`ScreenCaptureOptions` は `frameRate` を保持する。既定値は 15 とし、入力値は Sora iOS SDK の `ScreenCaptureSettings.targetFPS` と同様に 1 から 120 へ丸める。実際の送信レートは端末負荷と画面更新頻度によって下がる場合があることを DartDoc に記載する。

画面キャプチャ用トラックを識別するため、`VideoTrackCaptureType` に `screen` を追加する。

画面キャプチャ用トラックは、初期ローカルストリームまたは `SoraConnection.replaceVideoTrack()` で接続へ設定できる。`LocalVideoTrack.textureId` は接続前でも取得できるが、この操作では Texture の確保だけを行い、ReplayKit は開始しない。Texture へ画面映像が供給されるのは、トラックが接続へ設定されて画面キャプチャが開始している間だけとする。

### キャプチャと Texture のライフサイクル分離

停止後の再開と切り替え失敗時の復旧を可能にするため、Texture の確保、キャプチャの開始、キャプチャの停止、リソースの破棄を別の操作として扱う。

- `ensureLocalVideoTrackTexture` は `captureType` とキャプチャ設定を受け取り、capture type に対応する renderer と Texture の確保だけを担当する
- `startLocalVideoCapture` を追加し、`captureType`、`videoSourcePtr`、キャプチャ設定を必須引数として渡す
- `startLocalVideoCapture` の接続 ID は画面キャプチャでは必須とし、接続前プレビューを維持するカメラでは省略可能とする
- `stopLocalVideoCapture` を追加し、Texture と映像ソースを保持したままキャプチャだけを停止する
- `disposeLocalVideoTrackTexture` はキャプチャを停止してから Texture と renderer を破棄する
- start / stop は同じトラックと同じ接続の組み合わせに対して繰り返し呼び出せる冪等な操作とする
- stop 後の start では映像ソースを再設定し、停止済み renderer を確実に再開する

既存のカメラトラックについては、`textureId` の初回取得でキャプチャも開始する現在の公開動作を維持する。内部では新しい start / stop 操作を利用し、画面キャプチャとの切り替え時に停止と再開ができるようにする。

`_applyVideoCaptureBackend()` と対になる `_stopVideoCaptureBackend()` を追加し、capture type ごとの開始・停止を集約する。画面キャプチャに対する `_applyVideoCaptureBackend()` は実際の `SoraConnection.id` を platform の開始 API へ明示的に渡し、iOS 側は実行中エラーを通知する `SoraClientWrapper` とキャプチャの対応を保持する。

### 初期接続時の開始順序

ReplayKit は開始時に利用者の確認 UI を表示する場合があるため、その待機時間を `connectionTimeout` に含めない。

初期ローカルストリームに画面キャプチャ用トラックがある場合は、Sora のシグナリングと PeerConnection の接続を完了してから ReplayKit を開始する。画面キャプチャ用 backend の適用は `_connect()` 内で移動するだけではなく、`_connectWithTimeout()` が成功してタイムアウト監視を終了した後の処理として `connect()` から呼び出す。`_connectWithTimeout()` は Sora の接続確立までだけをタイムアウト対象とする。

PeerConnection の connected 通知は内部の接続完了待機を完了させるが、初期トラックが画面キャプチャの場合は、利用者向けの `SoraConnectedState` をまだ通知しない。ReplayKit の開始成功後に、開始時の session generation と connect generation、`_peerConnectionConnected`、対象のローカルストリームと映像トラックがすべて現在の接続と一致することを再確認してから `SoraConnectedState` を通知する。明示的な切断、server 主導の切断、新しい接続試行のいずれかにより不一致になった場合は、開始した画面キャプチャを停止し、古い接続の connected 通知を送らない。ReplayKit の開始に失敗した場合も `SoraConnectedState` を通知せずに `connect()` を失敗させ、開始途中の画面キャプチャと接続を後始末してからエラーを返す。カメラトラックの既存の開始タイミングと connected 通知順序は変更しない。

接続済みの `replaceVideoTrack()` で画面キャプチャへ切り替える場合も、ReplayKit の確認 UI を待つ処理へ固定の 10 秒タイムアウトを適用しない。

### iOS 実装

`ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift` を追加し、`RPScreenRecorder.shared()` を利用する。

Sora iOS SDK の `ScreenCaptureController` をベースに、次を実装する。

- `stopped` / `starting` / `running` / `stopping` の状態機械
- start / stop の競合時に古い開始完了コールバックを無効化する世代 ID
- `RPScreenRecorder.startCapture()` と `stopCapture()` の MainActor 上での実行
- `.video` の `RPSampleBufferType` だけの処理
- `RPScreenRecorder.isMicrophoneEnabled` と `isCameraEnabled` の無効化
- PTS と `frameRate` に基づくフレーム間引き
- PTS が利用できない場合の `ProcessInfo.processInfo.systemUptime` によるフォールバック
- 専用直列キューによるフレーム順序の保証
- セマフォを即時取得できない場合のフレーム破棄
- 実行中エラーの通知

ReplayKit から取得した `CMSampleBuffer` の `CVPixelBuffer` は、実際のピクセルフォーマットを確認してネイティブ側で I420 へ変換する。変換後のフレームは `sora_video_frame_create()` と `webrtc_AdaptedVideoTrackSource_OnFrame()` により `AdaptedVideoTrackSource` へ直接投入し、Dart の `ExternalVideoFrame` を経由しない。未対応のピクセルフォーマットは握りつぶさずエラーとして通知する。

同じフレームから Flutter Texture 用のプレビューも更新し、`SoraConnection.localVideo` の Texture ID を `SoraLocalVideoWidget` で表示できるようにする。

`SoraFlutterMessageHandler` は `captureType` に応じてカメラまたは画面キャプチャの renderer を生成・管理する。`RPScreenRecorder.shared()` は複数の Flutter engine をまたいでプロセス共有されるため、画面キャプチャの coordinator と所有権状態も `@MainActor` の static なプロセス共有オブジェクトとする。`starting` へ遷移する前に `(messageHandlerIdentity, videoSourcePtr, connectionId)` の所有権をこの coordinator で原子的に確保する。`connectionId` は handler ごとの連番であるため、所有者の識別とエラー通知先には handler の identity も必ず含める。

本 SDK が開始できる画面キャプチャは同時に 1 件だけとする。同じ画面キャプチャ用トラックであっても、別の接続が所有している間の start はエラーにする。start の冪等性は同じ `videoSourcePtr` と接続 ID の組み合わせだけに適用し、実行中エラーは所有している接続だけへ通知する。通常の stop は一致する所有接続だけが実行でき、`LocalVideoTrack.dispose()` はそのトラックが所有するキャプチャを接続状態にかかわらず停止できるものとする。

SDK の管理外ですでに `RPScreenRecorder.isRecording` が `true` の場合も、既存キャプチャを停止または奪取せず開始エラーを返す。停止処理は本 SDK が所有するキャプチャだけを対象とする。

`ios/sora_sdk/Package.swift` から ReplayKit を利用できるようにする。

### カメラとの切り替え

Flutter SDK では `replaceVideoTrack()` によりカメラと画面キャプチャを切り替える。これは、カメラが動作中ならエラーを返す Sora iOS SDK の公開 API とは異なる Flutter SDK 固有の動作である。

切り替えは次の順序で行う。

1. 元のキャプチャ backend を停止する。ただし Texture と映像ソースは復旧用に保持する
2. sender を新しいトラックへ差し替える
3. 新しいキャプチャ backend を開始する
4. 新しいトラックでローカルストリームと `_currentVideoTrack` を更新する

いずれかの処理に失敗した場合は、新しい backend の停止、sender の復元、元の backend の再開を行い、ローカルストリームと `_currentVideoTrack` は元の状態を保持する。元のトラックがない場合は `_webrtcClient.removeVideoTrack()` で sender を空へ戻し、ローカルストリームと `_currentVideoTrack` に映像トラックを設定しない。

`replaceVideoTrack()` に渡された新しいトラックとその Texture は呼び出し側の所有物として破棄せず、停止済みで再利用可能な状態に戻す。復旧処理にも失敗した場合は元のエラーと復旧エラーの両方を返し、開始途中のキャプチャだけは残さない。

`removeVideoTrack()` と切断では実行中の画面キャプチャを停止するが、トラックと Texture は破棄しない。同じ未破棄の画面キャプチャ用トラックを再設定した場合は再び開始できる。`LocalVideoTrack.dispose()` ではキャプチャを停止し、Texture、renderer、映像ソースを破棄する。

### エラー通知

`SoraErrorCode` に `screenCaptureError` を追加する。

ReplayKit の開始拒否、開始失敗、二重開始、未対応ピクセルフォーマット、実行中エラーは `SoraConnectionErrorEvent` の `code` を `screenCaptureError` とする。原因は `SoraConnectionErrorDetails.platformError` の安定した文字列で判別できるようにする。

初期接続と `replaceVideoTrack()` における開始エラーは、呼び出し元の `Future` を失敗させるとともに、接続 ID に対応する `SoraConnection.events` へ通知する。実行中エラーも、`startLocalVideoCapture` に渡した接続 ID の EventChannel へ通知する。

Sora iOS SDK と同様に、ReplayKit の sample handler から渡される実行中エラーは通知だけを行い、その通知を理由とした自動停止や自動再開は行わない。停止は `replaceVideoTrack()`、`removeVideoTrack()`、切断、`LocalVideoTrack.dispose()`、または ReplayKit 自体の停止結果に従って処理する。

### ライフサイクル

次の条件を満たす。

- start / stop の競合で ReplayKit の二重起動や停止漏れが発生しない
- 停止開始後に到着したフレームを映像ソースまたは Texture へ投入しない
- 停止時はフレームコールバックと専用キューの処理完了を待ってからキャプチャを停止状態にする
- `LocalVideoTrack.dispose()` はキャプチャの停止、Texture の登録解除、映像ソースの解放をこの順序で行う
- `dispose()` を複数回呼び出しても安全である
- 接続開始失敗、切り替え失敗、切断の各経路で ReplayKit が継続しない
- stop 後に同じ未破棄トラックで再開できる

`issues/0055-add-macos-window-capture.md` も同じ capture type 分岐とライフサイクル管理を変更対象にする。0055 の共通処理が先にマージされていれば再利用し、未マージであれば本 issue で OS 固有処理を分離できる共通構造を導入する。

### 主な変更対象

- `lib/src/sora_media_devices.dart`
- `lib/src/sora_media_stream.dart`
- `lib/src/media/sora_media_device_platform.dart`
- `lib/src/sora_connection.dart`
- `lib/src/sora_error_code.dart`
- `ios/sora_sdk/Sources/sora_sdk/SoraFlutterMessageHandler.swift`
- `ios/sora_sdk/Sources/sora_sdk/SoraScreenCapturer.swift`
- `ios/sora_sdk/Package.swift`
- unit test、iOS 実機 E2E、devtools、README、`CHANGELOG.md`

### 非対象

- Broadcast Upload Extension と `RPBroadcastSampleHandler` を利用した他アプリを含む配信
- ReplayKit から取得したアプリ音声とマイク音声の送信
- ReplayKit のカメラオーバーレイ
- Android、macOS、Windows、Linux の画面共有

## 完了条件

### 公開 API

- iOS でアプリ内画面キャプチャ用の `LocalVideoTrack` を作成できる
- `captureType` が `screen` であることを識別できる
- `frameRate` の既定値が 15 であり、入力値が 1 から 120 へ丸められる
- 初期ローカルストリームまたは `replaceVideoTrack()` で Sora へ画面映像を送信できる
- 接続前の `textureId` 取得では ReplayKit を開始せず、開始後は同じ Texture でプレビューできる
- iOS 以外では `UnsupportedError` を送出する

### エラーとライフサイクル

- ReplayKit の確認 UI の待機中に `connectionTimeout` または backend の固定タイムアウトが発生しない
- 開始拒否または開始失敗を `screenCaptureError` と `platformError` で判別できる
- 実行中エラーが開始時に紐付けた接続の `SoraConnection.events` へ通知される
- SDK 内外ですでに動作中の画面キャプチャを奪わず、二重開始をエラーにできる
- 同じ画面キャプチャ用トラックを複数接続から同時に開始できず、所有接続以外の停止でキャプチャが止まらない
- カメラと画面キャプチャを相互に切り替えられる
- 切り替え失敗時に元の sender、映像トラック、キャプチャが復元される
- 元の映像トラックがない状態で切り替えに失敗した場合は sender とローカルストリームが空へ戻る
- `removeVideoTrack()`、切断、`LocalVideoTrack.dispose()` で画面キャプチャが停止する
- remove、切断、切り替え失敗後に、同じ未破棄トラックで画面キャプチャを再開できる
- start / stop を競合させてもクラッシュ、デッドロック、二重起動、リソースリークが発生しない
- ReplayKit の確認 UI 待ち中に明示的または server 主導で切断しても、遅延した connected 通知やキャプチャが残らない

### テストと動作確認

- `ScreenCaptureOptions` の既定値と範囲処理、および `VideoTrackCaptureType.screen` を検証する unit test が追加されている
- MethodChannel の引数 Map を純粋関数で組み立て、接続 ID、capture type、キャプチャ設定をモックやスタブなしの unit test で検証している
- iOS 16.0 以上の実機で初期トラックの開始、プレビュー、停止を確認できる
- 2 クライアント間でアプリ内画面を Sora 経由で送受信できる
- 実機で開始拒否、カメラとの相互切り替え、切断後の再接続、同じトラックの再利用を確認できる
- ReplayKit の確認 UI 待ち中に明示的な切断と server 主導の切断をそれぞれ発生させ、古い connected 通知とキャプチャが残らないことを確認できる
- start / stop の連続実行、切断、dispose を含む実機テストでクラッシュやリソースリークが発生しない
- devtools または E2E テストアプリから一連の動作を確認できる
- `flutter analyze --fatal-infos` が成功する
- `flutter test` が成功する
- iOS debug build が成功する

### ドキュメント

- 公開 API の DartDoc が追加されている
- README に iOS のアプリ内画面共有の手順、対象範囲、制約、終了処理が記載されている
- `CHANGELOG.md` の `## develop` に `[ADD]` エントリが追加されている
