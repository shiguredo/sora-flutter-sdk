---
name: sora-flutter-sdk
description: >
  時雨堂の WebRTC SFU Sora 向け Flutter SDK (sora_sdk) の利用ガイド。
  Sora サーバーと接続する Flutter クライアントアプリ開発時に使う。
  トリガー: WebRTC 接続、映像・音声送受信、DataChannel メッセージング、
  RPC、カメラ制御、リモートトラック表示、シグナリング設定。
---

# Sora Flutter SDK

WebRTC SFU Sora 向け Flutter SDK。WebRTC のコアロジックは `dart:ffi` 経由で
libwebrtc を直接呼び出す Dart 側に実装し、カメラキャプチャと映像レンダリングは
プラットフォーム側が担当する。

- パッケージ: `sora_sdk` 2026.1.0
- 対応 Sora: 2025.2.0+
- 環境: Flutter 3.44.0+ / Dart SDK 3.10.0+

## 対応プラットフォーム

| プラットフォーム | 最小バージョン |
| --- | --- |
| iOS | 16.0+ |
| macOS | 15.0+ |
| Android | API 29+ (Android 10) |
| Windows | 10 20H2+ (x86_64) |
| Linux | Ubuntu 24.04 (x86_64) |

## 対応コーデック

ハードウェアエンコード / デコードの実際の可否は端末・OS バージョンに依存する。

| バックエンド | 対応プラットフォーム | エンコード | デコード |
| --- | --- | --- | --- |
| ソフトウェア | 全プラットフォーム | VP8 / VP9 / AV1 | VP8 / VP9 / AV1 |
| Apple VideoToolbox | iOS / macOS | H.264 / H.265 | H.264 / H.265 |
| Android MediaCodec | Android | H.264 / H.265 / VP8 / VP9 / AV1 | H.264 / H.265 / VP8 / VP9 / AV1 |

## エントリポイント

```dart
import 'package:sora_sdk/sora_sdk.dart';

final connection = await Sora.createConnection(config);
final codecs = Sora.supportedVideoCodecTypes; // List<VideoCodecType>
```

## 基本的な接続

```dart
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
  if (event is SoraConnectionStateChangedEvent) {
    // event.state: SoraConnectingState / SoraConnectedState / SoraDisconnectedState
  } else if (event is SoraTrackEvent) {
    // event.track: 到着した RemoteMediaStreamTrack
  } else if (event is SoraConnectionErrorEvent) {
    // event.code / event.message
  }
});
await connection.connect(stream);

// 4. 切断・破棄
await connection.disconnect();
await connection.dispose();
```

recvonly では `connect()` に `stream` を渡さない。メッセージング専用は
`audio: false, video: false, dataChannelSignaling: true, dataChannels: [...]` で構成する。

## コア API

### SoraConnectionConfig (主要)

`const` コンストラクタを維持するため、フィールドの検証は
`SoraConnectionConfig.toMap()` の実行時 (接続生成時) に行う。

| プロパティ | 型 | 説明 |
| --- | --- | --- |
| `signalingUrls` | `List<String>` | シグナリング URL (フェイルオーバー対応) |
| `channelId` | `String` | チャネル ID |
| `role` | `SoraRole` | sendrecv / sendonly / recvonly |
| `audio` / `video` | `bool?` | 送受信フラグ (null は Sora の既定に委ねる) |
| `audioStreamingLanguageCode` | `String?` | 音声ストリーミングの言語コード |
| `useAudioDevice` | `bool` | 既定 `true`。`false` は音声デバイスを掴まず kDummyAudio ADM を使う (Android では無視され常に実デバイス) |
| `clientId` / `bundleId` | `String?` | クライアント ID / バンドル ID |
| `metadata` / `signalingNotifyMetadata` | `Object?` | 認証用メタデータ / シグナリング通知メタデータ |
| `dataChannelSignaling` | `bool?` | DataChannel シグナリング有効化 |
| `ignoreDisconnectWebSocket` | `bool?` | WS 切断後も DC で継続 |
| `dataChannels` | `List<Map<String, Object?>>?` | `#` プレフィックスのユーザー定義 DC |
| `simulcast` / `simulcastRequestRid` | `bool?` / `SimulcastRequestRid?` | サイマルキャスト |
| `spotlight` / `spotlightFocusRid` / `spotlightUnfocusRid` | `bool?` / `SpotlightRid?` | スポットライト |
| `audioCodecType` / `videoCodecType` | `AudioCodecType?` / `VideoCodecType?` | OPUS / VP8 / VP9 / AV1 / H264 / H265 |
| `audioBitRate` / `videoBitRate` | `int?` | 6〜510 kbps / 1〜50000 kbps |
| `videoVp9Params` / `videoH264Params` / `videoH265Params` / `videoAv1Params` | `Map<String, Object?>?` | コーデック個別パラメーター |
| `forwardingFilters` | `List<Map<String, Object?>>?` | 転送フィルター |
| `timeoutOptions` | `SoraTimeoutOptions` | 接続 30s / 切断 10s / 候補 5s |

`audioOpusParams*` (channels / maxplaybackrate / minptime / ptime / stereo など) は
Sora の実験的機能で、利用には事前にサポートへの連絡が必要。

### MediaDevices

| メソッド | 説明 |
| --- | --- |
| `getUserMedia(options)` | ローカルメディア取得 |
| `createMediaStream()` | 空の LocalMediaStream 生成 |
| `createAudioTrack({audioDeviceId})` | local audio track 生成 |
| `createCameraVideoTrack({videoDeviceId, videoWidth, videoHeight, videoFrameRate})` | カメラの local video track 生成 |
| `createExternalVideoTrack()` | 外部映像トラック (I420 フレーム投入用) |
| `enumerateVideoInputDevices()` | 映像入力デバイス一覧 |
| `enumerateAudioInputDevices()` | 音声入力デバイス一覧 |
| `enumerateAudioOutputDevices()` | 音声出力デバイス一覧 |
| `setUseAudioDevice(bool)` | 共有 factory の音声デバイス使用設定 (メディア生成前に指定する) |

`GetUserMediaOptions`: `audio` / `video` (既定 `true`), `audioDeviceId`,
`videoDeviceId`, `videoWidth` (既定 640), `videoHeight` (既定 480),
`videoFrameRate` (既定 30)。`audio` と `video` を両方 `false` にすると `StateError`。

`enumerateVideoInputDevices()` が返す `VideoInputDevice` は
`supportedFormats()` で `VideoInputFormat` (`width` / `height` / `maxFrameRate`)
の一覧を取得できる。

### SoraConnection

| メンバー | 説明 |
| --- | --- |
| `connect([stream])` | 接続開始 (recvonly は stream なし) |
| `disconnect()` / `dispose()` | 切断 / リソース解放 (`dispose()` は内部で `disconnect()` を実行) |
| `events` | 統合イベント Stream |
| `debugEvents` | デバッグイベント Stream (log / timeline) |
| `debugMessages` | デバッグメッセージ Stream (`Stream<String>`) |
| `localVideo` | ローカル映像ハンドル Stream (`Stream<SoraLocalVideoHandle>`) |
| `connectionId` / `serverClientId` / `bundleId` / `sessionId` | サーバー割り当て ID |
| `remoteMediaStreams` | `Map<String, RemoteMediaStream>` (connectionId ごとの audio / video track) |
| `isAudioEnabled` / `isVideoEnabled` | トラックの有効状態 |
| `setAudioEnabled(bool)` / `setVideoEnabled(bool)` | トラック有効 / 無効 |
| `replaceAudioTrack(stream, track)` / `replaceVideoTrack(stream, track)` | トラック置換 |
| `removeAudioTrack(stream)` / `removeVideoTrack(stream)` | トラック削除 |
| `sendDataChannelMessage(label, data)` | DC メッセージ送信 |
| `rpc(method, params, options)` | JSON-RPC リクエスト |
| `getStats()` | WebRTC 統計情報 (JSON 文字列、PC 未生成時は `null`) |

`replaceAudioTrack` / `replaceVideoTrack` / `removeAudioTrack` / `removeVideoTrack` は
PeerConnection が connected であること、`stream` が接続にアタッチされていることが
前提。それ以外は `StateError`。`setAudioEnabled` / `setVideoEnabled` はトラックが
未取得の場合は何もしない。

### 映像 Widget

`SoraConnection.localVideo` と `RemoteMediaStreamTrack.textureId` をそのまま
`Texture` に渡すこともできるが、標準で次の Widget が用意されている。

```dart
SoraRemoteVideoWidget(track: remoteVideoTrack, fit: BoxFit.contain, mirror: false)
SoraLocalVideoWidget(textureId: localTextureId, mirror: true)
```

どちらも `placeholder` に `textureId` が無い間の代替 Widget を指定できる。
`SoraLocalVideoWidget` は `textureId` が null または負値のとき `placeholder` を表示し、
0 は有効な texture id として扱う。

### PushAudio (上級者向け)

`PushAudioDevice` (カスタム ADM) で PCM を送受信する。

- `PushAudio.pushPcm(Int16List data, int sampleRate, int channels)` — 10 ms 分の PCM を注入
- `PushAudio.pullPcm(int sampleRate, int channels, {int durationMs = 10})` — 受信 PCM を取得
- `PushAudio.dispose()` — ネイティブバッファを解放

## イベント体系

`connection.events` (`Stream<SoraConnectionEvent>`) で統合購読する。

| イベント型 | 説明 |
| --- | --- |
| `SoraConnectionStateChangedEvent` | 状態変化 (`SoraConnectingState` / `SoraConnectedState` / `SoraDisconnectedState`) |
| `SoraConnectionErrorEvent` | エラー (`code` / `message` / `retriable` / `details`) |
| `SoraNotifyEvent` / `SoraPushEvent` / `SoraSwitchedEvent` | サーバーメッセージ (`message`) |
| `SoraSignalingMessageEvent` | シグナリング送受信 (`SoraSignalingEvent`) |
| `SoraDataChannelOpenEvent` | DataChannel open (`SoraDataChannelEvent`) |
| `SoraDataChannelMessageEvent` | DC メッセージ (`SoraDataChannelMessage`) |
| `SoraTrackEvent` / `SoraRemoveTrackEvent` | リモートトラック追加 / 削除 |
| `SoraTimeoutEvent` | タイムアウト |

- `SoraDisconnectedState.closeInfo` に `SoraDisconnectCloseInfo` (`code` / `reason`) を保持する
- `SoraConnectionErrorEvent.details` は `SoraConnectionErrorDetails` (`attempts` / `platformError`)
- `connection.debugEvents` (`Stream<SoraDebugEvent>`) は `SoraLogDebugEvent` と
  `SoraTimelineDebugEvent` を流す

## エラーコードと切断理由

- `SoraConnectionErrorEvent.code` は `SoraErrorCode` の定数値。`connectionTimeout`、
  `disconnectTimeout`、`signalingCandidateTimeout`、`offerInvalid`、`reofferInvalid`、
  `setRemoteDescriptionFailed`、`createAnswerFailed`、`setLocalDescriptionFailed`、
  `createPeerConnectionFailed`、`addAudioTrackFailed`、`addVideoTrackFailed`、
  `cameraOpenError`、`unexpectedNativeEvent` など
- `SoraDisconnectReason` は切断理由コード。送信側 (`noError` / `websocketOnClose` /
  `websocketOnError`) と、native から受信する分類タグ (`serverDisconnect` /
  `peerConnectionFailed` / `peerConnectionClosed`) を含む

## 主なユースケース

### リモート映像表示

```dart
connection.events.listen((event) {
  if (event is SoraTrackEvent &&
      event.track.kind == 'video' &&
      event.track.textureId != null) {
    setState(() {
      remoteVideoTrack = event.track;
    });
  }
});

// build 内
SoraRemoteVideoWidget(track: remoteVideoTrack!)
```

`connection.remoteMediaStreams` から `connectionId` ごとに `audioTrack` /
`videoTrack` を取得してもよい。

### ローカル映像プレビュー

```dart
connection.localVideo.listen((handle) {
  setState(() {
    localTextureId = handle.textureId;
  });
});

// build 内
SoraLocalVideoWidget(textureId: localTextureId, mirror: true)
```

### DataChannel メッセージング

```dart
connection.sendDataChannelMessage('#my-channel', data);
connection.events.listen((event) {
  if (event is SoraDataChannelMessageEvent) {
    // event.message.label / event.message.data (Uint8List)
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

`SoraRpcOptions.timeout` を指定して応答が無い場合は `TimeoutException`、
Sora がエラーを返した場合は `SoraRpcError` になる。

### 外部映像トラック

```dart
final track = MediaDevices.createExternalVideoTrack();
final stream = MediaDevices.createMediaStream();
stream.addTrack(track);
track.writeFrame(ExternalVideoFrame(
  width: 640, height: 480,
  yPlane: y, uPlane: u, vPlane: v,
  yStride: 640, uStride: 320, vStride: 320,
  rotation: 0, // 0 / 90 / 180 / 270
));
await connection.connect(stream);
```

external video track を使う接続では `connection.localVideo` は emit されない。

### デバイス列挙と選択

```dart
final cameras = await MediaDevices.enumerateVideoInputDevices();
final formats = await cameras.first.supportedFormats();
final stream = await MediaDevices.getUserMedia(
  GetUserMediaOptions(videoDeviceId: cameras.first.deviceId),
);
```

## ライフサイクル

`createConnection` → `events.listen` → `getUserMedia` → `connect` → 操作中 → `disconnect` → `dispose`

- `dispose` 後の操作系メソッド呼び出しは `StateError` で拒否される (`disconnect()` と `dispose()` は例外を投げない)
- `connect()` の `stream` は role / `audio` / `video` と整合していること。整合しない場合は `StateError`
- `disconnect()` は同時呼び出しを共有 Future で直列化する
- `dispose()` は内部で `disconnect()` を実行し、失敗しても cleanup を継続する
- Android の runtime permission 取得はアプリ層の責務
- 音声デバイスの使用設定 (`MediaDevices.setUseAudioDevice`) はメディア生成前に指定する
- カメラ指定は `MediaDevices.getUserMedia(GetUserMediaOptions(videoDeviceId: ...))` で行う
