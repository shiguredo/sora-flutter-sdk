# macOS のウィンドウキャプチャ API を追加する

- Created: 2026-07-31
- Completed: {YYYY-MM-DD}
- Branch: feature/add-macos-window-capture
- Polished: 2026-07-31
- Reporter: @zztkm

## 目的

macOS 上で共有対象のウィンドウを選択し、その映像を Sora へ送信できる `LocalVideoTrack` として取得する API を追加する。

アプリごとに ScreenCaptureKit と外部映像トラックの接続処理を実装せず、Sora Flutter SDK の公開 API だけでウィンドウ共有を開始・終了できる状態を目指す。

現状でも外部映像トラックへフレームを投入することで実現できる可能性はあるが、ScreenCaptureKit から取得したフレームを Dart 側で I420 に変換して投入する処理や、権限、キャプチャ終了、ウィンドウ消失などのライフサイクル管理をアプリごとに実装する必要がある。

## 現状

- `lib/src/sora_media_devices.dart` の `MediaDevices.createCameraVideoTrack()` でカメラ映像トラックを作成できる
- `lib/src/sora_media_devices.dart` の `MediaDevices.createExternalVideoTrack()` と `lib/src/sora_media_stream.dart` の `LocalVideoTrack.writeFrame()` で、Dart 側から I420 フレームを投入できる
- 外部映像トラックへフレームを投入する場合、ScreenCaptureKit の呼び出し、フレーム変換、Dart FFI を経由するメモリコピーを利用者側で実装する必要がある
- `LocalVideoTrack.textureId` はカメラ映像トラックだけをサポートしており、外部映像トラックでは利用できない
- `macos/sora_sdk/Package.swift` は ScreenCaptureKit をリンク済みだが、共有可能なウィンドウの列挙やキャプチャを行う実装は存在しない
- macOS 15 以上をサポートしているため、ScreenCaptureKit を利用できる

### ウィンドウキャプチャ追加時に変更が必要な既存コード

- `lib/src/sora_media_stream.dart` の `LocalVideoTrack._ensureTextureId()` は `captureType != camera` で `StateError` を投げるガードがある。ウィンドウキャプチャもプレビューを提供するため、このガードを `camera` または `window` に変更する必要がある
- `lib/src/sora_media_stream.dart` の `LocalVideoTrack.dispose()` は `captureType == camera` の場合のみ `disposeLocalVideoTrackTexture` を呼ぶ。ウィンドウキャプチャ用のネイティブリソース解放経路（SCStream 停止、テクスチャ破棄）を追加する必要がある
- `lib/src/sora_connection.dart` の `_applyVideoCaptureBackend()` は `captureType != camera` で早期 return する。ウィンドウキャプチャのトラックも `textureId` 経由でプレビューを開始できるよう変更する必要がある
- `lib/src/sora_connection.dart` の `replaceVideoTrack()` は catch 節で `captureType == camera` の場合だけ `stopCameraCapturer()` を呼ぶ。ウィンドウキャプチャトラックの replace 失敗時にも SCStream のクリーンアップが必要

## 設計方針

### 公開 API

macOS で共有可能なウィンドウを列挙するため、ウィンドウ識別子、タイトル、所有アプリケーション名などを保持する値オブジェクト `WindowCaptureSource` を追加する。

`MediaDevices` に次の API を追加する。

- `MediaDevices.enumerateWindowCaptureSources()`: 非同期。`Future<List<WindowCaptureSource>>` を返す。SCShareableContent 経由でウィンドウ一覧を取得する
- `MediaDevices.createWindowVideoTrack(WindowCaptureSource source, { WindowCaptureOptions? options })`: 同期。指定したウィンドウから `LocalVideoTrack` を作成する。カメラの `createCameraVideoTrack()` と同様、track 生成自体は同期で行い、capture の開始は `_applyVideoCaptureBackend()` 経由で行う

キャプチャ設定を指定する値オブジェクト `WindowCaptureOptions` を追加する。保持するフィールドは以下。

- `width` (int?): キャプチャ解像度の幅。省略時はウィンドウの現在のサイズ
- `height` (int?): キャプチャ解像度の高さ。省略時はウィンドウの現在のサイズ
- `frameRate` (int?): キャプチャのフレームレート。省略時は 30
- `showsCursor` (bool): カーソルをキャプチャ映像に含めるか。デフォルトは true

`createWindowVideoTrack()` は内部で `_createVideoTrack(captureType: VideoTrackCaptureType.window, captureSettings: ...)` を呼び、`WindowCaptureOptions` の情報を `VideoCaptureSettings` に変換して保持する。具体的には `WindowCaptureOptions.width` / `height` / `frameRate` を `VideoCaptureSettings` の同名フィールドに、`source.id` を `VideoCaptureSettings.deviceId` にマッピングする。

ウィンドウキャプチャで作成したトラックを識別できるよう、`lib/src/sora_media_stream.dart` の `VideoTrackCaptureType` に `window` を追加する。

### macOS 実装

ScreenCaptureKit の以下の機能を利用する。

- `SCShareableContent` によるウィンドウ列挙
- `SCContentFilter` による共有対象ウィンドウの指定
- `SCStream` による映像フレーム取得

取得した `CVPixelBuffer` は、可能な限りネイティブ側から libwebrtc の映像ソースへ直接渡す。フレームごとに Dart の `ExternalVideoFrame` を生成してコピーする方式は採用しない。

ウィンドウキャプチャの実装クラス（例: `SoraWindowCapturer`）は `SoraCameraCapturer` と同様のパターンで `SoraFlutterMessageHandler` の `LocalVideoRenderer` 相当の管理下に置く。Dart 側の `ensureLocalVideoTrackTexture()` で `videoSourcePtr` を受け取ったネイティブ側が、track の `captureType` に応じてカメラまたはウィンドウキャプチャを起動する分岐を行う。キャプチャ設定（`WindowCaptureOptions` の内容）は MethodChannel 経由でネイティブ側へ伝達する。

### ライフサイクル

以下の状態を SDK 側で管理する。

- 画面収録権限の拒否：`enumerateWindowCaptureSources()` が権限拒否を検出した場合は `Future` のエラーとして返す。`createWindowVideoTrack()` 後のキャプチャ開始時の権限エラーは `_applyVideoCaptureBackend()` 経由で `SoraErrorCode` によるエラー通知を行う
- 選択したウィンドウの消失：キャプチャ開始前にウィンドウが存在しない場合は `createWindowVideoTrack()` がエラーを返す。キャプチャ中のウィンドウ消失は EventChannel または `SoraErrorCode` 経由で通知する
- ScreenCaptureKit のストリームエラー
- キャプチャの開始と停止
- `LocalVideoTrack.dispose()` 実行時の `SCStream` と関連リソースの解放
- Sora 接続からトラックを削除した後の安全な終了
- `replaceVideoTrack()` 失敗時の SCStream クリーンアップ：`sora_connection.dart` の `replaceVideoTrack()` catch 節で `captureType == window` の場合も対応するネイティブ停止経路を追加する

開始失敗や実行中のエラーは、既存の SDK エラー通知方式と整合する形で利用者へ通知する。

### プレビュー

ウィンドウキャプチャで作成した `LocalVideoTrack` についても、Flutter の Texture を利用したローカルプレビューを提供する。

### 非対象

本 issue では以下を対象外とする。

- 画面全体の共有
- アプリケーション単位の共有
- システム音声の共有
- iOS、Android、Windows、Linux の画面共有
- アプリ側のウィンドウ選択 UI
- Sora 接続へのトラック追加・削除を行うアプリ固有の制御

## 完了条件

### 公開 API

- macOS で共有可能なウィンドウを列挙できる
- 列挙結果から共有対象を識別するための安定した ID、ウィンドウタイトル、所有アプリケーション名を取得できる
- 選択したウィンドウから `LocalVideoTrack` を作成できる
- 作成したトラックの `captureType` がウィンドウキャプチャであることを識別できる
- 解像度、フレームレート、カーソル表示の設定を指定できる
- 作成したトラックを既存の Sora 接続へ渡して映像を送信できる
- Flutter の Texture でローカルプレビューを表示できる

### エラーとライフサイクル

- 画面収録権限が拒否された場合、利用者が原因を判別できるエラーを返す
- 選択したウィンドウがキャプチャ開始前に存在しなくなった場合、適切なエラーを返す
- キャプチャ中にウィンドウが閉じられた場合、アプリへ終了またはエラーが通知される
- `LocalVideoTrack.dispose()` により ScreenCaptureKit のストリームとネイティブリソースが解放される
- キャプチャの開始と終了を繰り返しても、ストリームや Texture が残存しない

### テストと動作確認

- ウィンドウ情報とキャプチャ設定に対する unit test が追加されている
- macOS 15 以上でウィンドウ列挙、キャプチャ開始、プレビュー、停止を確認できる
- 2 クライアント間でウィンドウ映像を Sora 経由で送受信できる
- 画面収録権限の許可と拒否の両方を手動確認できる
- devtools または E2E テストアプリから一連の動作を確認できる
- `flutter analyze --fatal-infos` が成功する
- `flutter test` が成功する
- macOS debug build が成功する

### ドキュメント

- 公開 API の DartDoc が追加されている
- macOS で必要となる画面収録権限とアプリ側の設定がドキュメントに記載されている
- `CHANGES.md` の `## develop` に `[ADD]` エントリが追加されている
