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

1. `TCC` に登録するため、アプリの `Info.plist` に以下を設定します。

```xml
<key>NSAppleEventsUsageDescription</key>
<string>ウィンドウ共有のために画面収録権限を使用します。</string>
```

2. システム設定の「プライバシーとセキュリティ」→「画面収録」で、
   アプリの画面収録権限を許可します。

3. 権限を変更した後は、アプリを再起動してください。

画面収録権限の付与中にウィンドウキャプチャを開始すると、
`SoraErrorCode.windowCaptureError` のエラーイベントが通知されます。
