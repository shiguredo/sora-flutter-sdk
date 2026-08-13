# macOS

## システム要件

- Flutter 3.44.0 以上
- macOS 15.0 以上
- Xcode (macOS 15.0 以上)

## ウィンドウキャプチャ

`MediaDevices.enumerateWindowCaptureSources()` と `MediaDevices.createWindowVideoTrack()`
でウィンドウ共有を利用できます。

### 画面収録権限

ウィンドウキャプチャを利用するには、アプリに画面収録権限が必要です。

画面収録権限はアプリ側で付与する必要があります。
SDK は権限リクエスト（`CGRequestScreenCaptureAccess()` の呼び出しと
システム設定への誘導）を行いません。

権限がない状態で `enumerateWindowCaptureSources()` を呼び出すと
`PlatformException` が返ります。

権限を付与する手順は次のとおりです。

1. システム設定の「プライバシーとセキュリティ」→「画面収録」を開きます。
2. 対象のアプリの画面収録権限を許可します。
3. 権限を変更した後は、アプリを再起動してください。

画面収録権限の付与中にウィンドウキャプチャを開始すると、
`SoraErrorCode.windowCaptureError` のエラーイベントが通知されます。

### エラーコードの判別

ウィンドウキャプチャのエラーは `SoraErrorCode` の定数値で原因を判別できます。

- `MediaDevices.enumerateWindowCaptureSources()` の失敗:
  `PlatformException.code` が `SoraErrorCode.windowCapturePermissionDenied`
  (`screen_capture_permission_denied`) になる
- キャプチャ開始時の失敗 (`SoraConnectionErrorEvent.code`):
  - `SoraErrorCode.windowCapturePermissionDenied`: 画面収録権限の拒否
  - `SoraErrorCode.windowCaptureWindowNotFound`: 選択したウィンドウが存在しない
  - `SoraErrorCode.windowCaptureStartFailed`: SCStream の開始失敗
  - `SoraErrorCode.windowCaptureStartCancelled`: 開始がキャンセルされた
  - `SoraErrorCode.windowCaptureError`: 上記以外の失敗
- キャプチャ中のエラー (ウィンドウ消失など): `SoraErrorCode.windowCaptureError`
