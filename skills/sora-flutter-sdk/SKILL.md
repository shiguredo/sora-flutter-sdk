---
name: sora-flutter-sdk
description: >
  時雨堂の WebRTC SFU Sora 向け Flutter SDK (sora_sdk) の利用ガイド。
  Sora サーバーと接続する Flutter クライアントアプリ開発時に使う。
  トリガー: WebRTC 接続、映像・音声送受信、DataChannel メッセージング、
  RPC、カメラ制御、リモートトラック表示、シグナリング設定。
---

# Sora Flutter SDK

WebRTC SFU Sora 向け Flutter SDK。libwebrtc を `dart:ffi` 経由で呼び出し、プラットフォーム (iOS/macOS/Android) はカメラキャプチャと映像レンダリングを担当。

- パッケージ: `sora_sdk` 2026.0.0
- 対応 Sora: 2025.1.0+
- 環境: Flutter 3.44.0+, Dart SDK 3.10.0+

## 対応プラットフォーム

| プラットフォーム | 最小バージョン |
| --- | --- |
| iOS | 16.0+ |
| macOS | 15.0+ |
| Android | API 29+ |

## 対応コーデック

| バックエンド | エンコード | デコード |
| --- | --- | --- |
| ソフトウェア | VP8 / VP9 / AV1 | VP8 / VP9 / AV1 |
| Apple VideoToolbox | H.264 / H.265 | H.264 / H.265 |
| Android MediaCodec | H.264 / H.265 / VP8 / VP9 / AV1 | H.264 / H.265 / VP8 / VP9 / AV1 |

## 基本的な接続

```yaml
dependencies:
  sora_sdk: <version>
```

```dart
import 'package:sora_sdk/sora_sdk.dart';

// 1. ローカルメディア取得
final stream = await MediaDevices.getUserMedia(
  const GetUserMediaOptions(audio: true, video: true),
);

// 2. 接続設定
final config = SoraConnectionConfig(
  signalingUrls: const ['wss://sora.example.com/signaling'],
  channelId: 'your-channel-id',
  role: SoraRole.sendrecv, // sendonly / recvonly も可
);

// 3. 接続生成・イベント購読・接続
final connection = await Sora.createConnection(config);
connection.events.listen((event) {
  switch (event) {
    case SoraConnectionStateChangedEvent():
    case SoraNotifyEvent():
    case SoraTrackEvent():
    case SoraDataChannelMessageEvent():
    case SoraConnectionErrorEvent():
  }
});
await connection.connect(stream);

// 4. 切断・破棄
await connection.disconnect();
await connection.dispose();
```

recvonly では `connect()` に `stream` を渡さない。メッセージング専用は `audio: false, video: false, dataChannelSignaling: true, dataChannels: [...]` で構成。

## コア API

### SoraConnectionConfig (主要)

| プロパティ | 型 | 説明 |
| --- | --- | --- |
| `signalingUrls` | `List<String>` | シグナリング URL (フェイルオーバー対応) |
| `channelId` | `String` | チャネル ID |
| `role` | `SoraRole` | sendrecv / sendonly / recvonly |
| `audio` / `video` | `bool?` | 送受信フラグ (既定: `null`) |
| `metadata` | `Object?` | 認証用メタデータ |
| `dataChannelSignaling` | `bool?` | DataChannel シグナリング有効化 |
| `ignoreDisconnectWebSocket` | `bool?` | WS 切断後も DC で継続 |
| `dataChannels` | `List<Map>?` | `#` プレフィックスのユーザー定義 DC |
| `simulcast` / `spotlight` | `bool?` | サイマルキャスト / スポットライト |
| `timeoutOptions` | `SoraTimeoutOptions` | 接続 30s / 切断 10s / 候補 5s |

### MediaDevices

| メソッド | 説明 |
| --- | --- |
| `getUserMedia(options)` | ローカルメディア取得 |
| `enumerateVideoInputDevices()` | 映像デバイス一覧 |
| `enumerateAudioInputDevices()` | 音声入力一覧 |
| `enumerateAudioOutputDevices()` | 音声出力一覧 |
| `createExternalVideoTrack()` | 外部映像トラック (I420 フレーム投入用) |

`GetUserMediaOptions`: `audio`/`video` (既定 `true`), `audioDeviceId`, `videoDeviceId`, `videoWidth` (640), `videoHeight` (480), `videoFrameRate` (30)。

### SoraConnection

| メソッド | 説明 |
| --- | --- |
| `connect([stream])` | 接続開始 (recvonly は stream なし) |
| `disconnect()` / `dispose()` | 切断 / リソース解放 |
| `events` | 統合イベント Stream |
| `debugEvents` | デバッグイベント (log/timeline) |
| `localVideo` | ローカル映像ハンドル Stream |
| `connectionId` | サーバー割り当て接続 ID |
| `setAudioEnabled(bool)` / `setVideoEnabled(bool)` | トラック有効/無効 |
| `replaceAudioTrack(stream, track)` | トラック置換 |
| `removeAudioTrack(stream)` / `removeVideoTrack(stream)` | トラック削除 |
| `sendDataChannelMessage(label, data)` | DC メッセージ送信 |
| `rpc(method, params, options)` | JSON-RPC リクエスト |
| `getStats()` | WebRTC 統計情報 (JSON) |
| `switchCamera()` | カメラ切り替え |

## イベント体系

`connection.events` (`Stream<SoraConnectionEvent>`) で統合購読。

| イベント型 | 説明 |
| --- | --- |
| `SoraConnectionStateChangedEvent` | 状態変化 (`SoraConnectingState` / `SoraConnectedState` / `SoraDisconnectedState`) |
| `SoraConnectionErrorEvent` | エラー (`code`, `message`) |
| `SoraNotifyEvent` / `SoraPushEvent` / `SoraSwitchedEvent` | サーバーメッセージ |
| `SoraSignalingMessageEvent` | シグナリング送受信 |
| `SoraDataChannelOpenEvent` / `SoraDataChannelMessageEvent` | DC イベント |
| `SoraTrackEvent` / `SoraRemoveTrackEvent` | リモートトラック追加/削除 |
| `SoraTimeoutEvent` | タイムアウト |

`SoraDisconnectedState.closeInfo` に WebSocket close code/reason を保持。

## 主なユースケース

### リモート映像表示

```dart
connection.events.listen((event) {
  if (event is SoraTrackEvent &&
      event.track.kind == 'video' &&
      event.track.textureId != null) {
    // Texture(textureId: event.track.textureId!)
  }
});
```

### DataChannel メッセージング

```dart
connection.sendDataChannelMessage('#my-channel', data);
connection.events.listen((event) {
  if (event is SoraDataChannelMessageEvent) {
    // event.message.label, event.message.data
  }
});
```

### RPC

```dart
final result = await connection.rpc('method',
  params: {'key': 'value'},
  options: const SoraRpcOptions(timeout: 5000),
);
// notification: const SoraRpcOptions(notification: true)
```

### 外部映像トラック

```dart
final track = MediaDevices.createExternalVideoTrack();
final stream = MediaDevices.createMediaStream();
stream.addTrack(track);
track.writeFrame(ExternalVideoFrame(
  width: 640, height: 480,
  yPlane: y, uPlane: u, vPlane: v,
  yStride: 640, uStride: 320, vStride: 320,
));
await connection.connect(stream);
```

## ライフサイクル

`createConnection` → `events.listen` → `getUserMedia` → `connect` → 操作中 → `disconnect` → `dispose`

- `dispose` 後の API 呼び出しは `StateError` で拒否
- `disconnect()` は同時呼び出しを共有 Future で直列化
- `dispose()` は内部で `disconnect()` を実行
- Android の runtime permission 取得はアプリ層の責務
- カメラ指定は `MediaDevices.getUserMedia(GetUserMediaOptions(videoDeviceId: ...))` で行う
