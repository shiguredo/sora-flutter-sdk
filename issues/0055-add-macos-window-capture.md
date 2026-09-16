# macOS のウィンドウキャプチャを内部実装として追加する

- Created: 2026-07-31
- Completed: {YYYY-MM-DD}
- Branch: feature/add-macos-window-capture
- Polished: 2026-09-10
- Reporter: @zztkm

## 目的

macOS 上で共有対象のウィンドウを選択し、その映像を Sora へ送信できる映像入力を SDK 内部のキャプチャ種別として追加する。公開 API は増やさない。

0069（iOS 画面キャプチャ）は「初回公開リリースの公開判定で公開 API の画面キャプチャ機能は外部へ公開せず、内部検証実装として維持する」と決定し、公開 API 面を撤回した。本 issue も同じ方針に合わせ、macOS のウィンドウキャプチャを内部実装として追加する。

## 現状

- `lib/src/sora_media_stream.dart` の `VideoTrackCaptureType` は `@internal` で `camera` / `screen` / `external` を定義する。`screen` は iOS の ReplayKit 用であり、公開 API は 0069 で撤回済みである
- `lib/src/sora_media_devices.dart` の `MediaDevices` の映像トラック生成の公開 API は `createCameraVideoTrack()` と `createExternalVideoTrack()` のみで、`screen` トラックを生成する Dart 側の入口は存在しない
- `lib/src/sora_media_stream.dart` の `LocalVideoTrack` は `@internal` の `startCaptureForConnection(clientId)` / `stopCaptureForConnection(clientId)` を持ち、Texture 確保とキャプチャ開始・停止を分離する
- `lib/src/sora_connection.dart` は `_applyVideoCaptureBackend()` / `_stopVideoCaptureBackend()` / `_stopVideoCaptureBackendIfOwned()` で capture type ごとの開始・停止を集約し、`screen` の開始失敗は内部リテラルの `screen_capture_error` と `lib/src/sora_video_capture_error.dart` の `screenCapturePlatformErrorCode`、停止失敗は `_teardownNativeSession()` の固定値 `screen_capture_stop_failed` で通知する
- `macos/sora_sdk/Package.swift` は ScreenCaptureKit をリンク済みだが、共有可能なウィンドウの列挙やキャプチャを行う実装は存在しない
- macOS 15 以上をサポートしているため、ScreenCaptureKit を利用できる

### ウィンドウキャプチャ追加時に変更が必要な既存コード

- `VideoTrackCaptureType` に `window` を追加する
- `LocalVideoTrack._ensureTextureId()` のガードは `camera` と `screen` を許可しているため、`window` も許可する
- `LocalVideoTrack._disposeInternal()` の Texture 破棄分岐（`camera` / `screen`）に `window` を追加する
- `LocalVideoTrack.startCaptureForConnection()` / `stopCaptureForConnection()` は `Platform.isIOS` のみ分岐しているため、macOS の `window` 用の start / stop 分岐を追加する
- `SoraConnection._applyVideoCaptureBackend()` は `external` 以外で開始経路に入るため、`window` のネイティブ開始を追加する
- `SoraConnection._stopVideoCaptureBackend()` / `_stopVideoCaptureBackendIfOwned()` に `window` の停止経路を追加する
- `SoraConnection._teardownNativeSession()` と `_removeVideoTrackInternal()` の停止ゲートは `screen` 限定のため、`window` も停止対象に含める
- `SoraConnection._emitVideoCaptureBackendError()` は `screen` のみ特別扱いしているため、`window` も `screen_capture_error` と `platformError` で通知するよう分岐を追加する。native から届くウィンドウ消失や `SCStream` の実行中エラーも同じ `screen_capture_error` として扱う
- `SoraConnection` の `localVideo` プレビュー経路で `window` も対象にする

## 設計方針

### キャプチャ種別と内部 API

- `VideoTrackCaptureType` に `window` を追加する（`@internal` を維持する）
- 公開 API は追加しない。ウィンドウ列挙とトラック生成は `@internal` または `@visibleForTesting` の入口とし、unit test と macOS 実機での手動確認から利用する。devtools / E2E は `sora_sdk` とは別パッケージのため `@internal` / `@visibleForTesting` のメンバーを参照できず、参照すると analyze が `invalid_use_of_internal_member` で失敗する（0145 と同じ制約）。参照する場合は `ignore` を明示する
- ウィンドウ識別子・タイトル・所有アプリケーション名を保持する内部の値オブジェクトを追加する。識別子は `SCWindow.windowID`（`UInt32`）を保持し、`VideoCaptureSettings.deviceId`（`String?`）へはその文字列表現をマッピングする
- キャプチャ設定（解像度・フレームレート・カーソル表示）を内部で保持し、`VideoCaptureSettings` と MethodChannel 引数へ伝達する。`showsCursor` を伝達するため `VideoCaptureSettings` と `lib/src/media/sora_media_device_platform.dart` の引数組み立てにフィールドを追加する。既存の `createCameraVideoTrack()` / `createExternalVideoTrack()` の構築を壊さないよう optional（既定値付き）で追加する

### macOS 実装

ScreenCaptureKit の以下の機能を利用する。

- `SCShareableContent` によるウィンドウ列挙
- `SCContentFilter` による共有対象ウィンドウの指定
- `SCStream` による映像フレーム取得

取得した `CVPixelBuffer` は、可能な限りネイティブ側から libwebrtc の映像ソースへ直接渡す。フレームごとに Dart の `ExternalVideoFrame` を生成してコピーする方式は採用しない。

ウィンドウキャプチャの実装クラス（例: `SoraWindowCapturer`）は `SoraCameraCapturer` と同様に `SoraFlutterMessageHandler` 配下で管理する。0069 と同じく、`ensureLocalVideoTrackTexture` は capture type に対応する Texture の確保だけを担当し、キャプチャの開始・停止は `startLocalVideoCapture` / `stopLocalVideoCapture` に対応させる。macOS の `SoraFlutterMessageHandler` には start / stop がまだ無いため、これらを追加する。

### ライフサイクル

以下の状態を SDK 側で管理する。

- 画面収録権限の拒否：内部 API の列挙時に権限拒否を検出した場合は `Future` のエラーとして返す。キャプチャ開始時の権限エラーは `_applyVideoCaptureBackend()` 経由でエラー通知する
- 選択したウィンドウの消失：ウィンドウ存在検証は非同期のキャプチャ開始フェーズで行い、同期のトラック生成時には検証しない。キャプチャ中のウィンドウ消失は native から実行中エラーとして通知し、`screen_capture_error` と `platformError` で扱う
- ScreenCaptureKit のストリームエラー
- キャプチャの開始と停止（同じトラック・同じ接続で繰り返し呼べる冪等な操作）
- `LocalVideoTrack.dispose()` 実行時の `SCStream` と関連リソースの解放
- Sora 接続からトラックを削除した後の安全な終了
- `replaceVideoTrack()` 失敗時の停止経路：`SoraConnection._stopVideoCaptureBackend()` 経由で `window` も停止する

エラー通知は既存の内部リテラル（`screen_capture_error` 相当）と `SoraConnectionErrorDetails.platformError` の安定した文字列に合わせる。公開エラーコードは追加しない。

### プレビュー

ウィンドウキャプチャで作成した `LocalVideoTrack` についても、Flutter の Texture を利用したローカルプレビューを提供する（公開 API は増やさない）。

### 非対象

本 issue では以下を対象外とする。

- 公開 API（`MediaDevices` のウィンドウ列挙・トラック生成、公開エラーコード）の追加
- 画面全体の共有
- アプリケーション単位の共有
- システム音声の共有
- iOS、Android、Windows、Linux の画面共有
- アプリ側のウィンドウ選択 UI
- Sora 接続へのトラック追加・削除を行うアプリ固有の制御

## 完了条件

### 内部実装

- [ ] `VideoTrackCaptureType.window` が追加されている（`@internal` を維持）
- [ ] 内部 API で macOS の共有可能なウィンドウを列挙できる
- [ ] 列挙結果から共有対象を識別するための安定した ID、ウィンドウタイトル、所有アプリケーション名を取得できる
- [ ] 内部 API で選択したウィンドウから `LocalVideoTrack` を作成できる
- [ ] 解像度、フレームレート、カーソル表示の設定を指定できる
- [ ] 作成したトラックを既存の Sora 接続へ渡して映像を送信できる
- [ ] Flutter の Texture でローカルプレビューを表示できる
- [ ] 公開 API 面（`MediaDevices` の新規メソッド、公開エラーコード）に追加がない

### エラーとライフサイクル

- [ ] 画面収録権限が拒否された場合、利用者が原因を判別できるエラーを返す
- [ ] 選択したウィンドウがキャプチャ開始前に存在しなくなった場合、適切なエラーを返す
- [ ] キャプチャ中にウィンドウが閉じられた場合、アプリへ終了またはエラーが通知される
- [ ] `LocalVideoTrack.dispose()` により ScreenCaptureKit のストリームとネイティブリソースが解放される
- [ ] キャプチャの開始と終了を繰り返しても、ストリームや Texture が残存しない
- [ ] `replaceVideoTrack()` の失敗時に `window` の停止経路が実行される

### テストと動作確認

- [ ] ウィンドウ情報とキャプチャ設定に対する unit test が追加されている
- [ ] macOS 15 以上でウィンドウ列挙、キャプチャ開始、プレビュー、停止を確認できる
- [ ] 2 クライアント間でウィンドウ映像を Sora 経由で送受信できる
- [ ] 画面収録権限の許可と拒否の両方を手動確認できる
- [ ] macOS 実機でウィンドウ列挙から送受信までの一連の動作を手動確認できる
- [ ] `flutter analyze --fatal-infos` が成功する
- [ ] `flutter test` が成功する
- [ ] macOS debug build が成功する

### ドキュメント

- [ ] 内部実装であることと macOS で必要となる画面収録権限・アプリ側の設定がコードコメントに記載されている
- [ ] 公開 API の DartDoc は追加していない（公開 API を増やさないため）

## 関連

- `issues/closed/0069-add-ios-screen-capture.md`（画面キャプチャを内部検証実装として維持する方針と、capture type 分岐・start / stop 分離の共通構造）
- `issues/0111-refactor-connection-video-capture-controller.md`（`_applyVideoCaptureBackend` / `_stopVideoCaptureBackend` / `_emitVideoCaptureBackendError` を別クラスへ移すリファクタ。実装順序の調整が必要）
