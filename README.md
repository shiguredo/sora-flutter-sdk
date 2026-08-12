# Sora Flutter SDK

[![pub.dev](https://img.shields.io/pub/v/sora_sdk.svg)](https://pub.dev/packages/sora_sdk)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Actions](https://github.com/shiguredo/sora-flutter-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/shiguredo/sora-flutter-sdk/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?logo=discord&logoColor=white)](https://discord.gg/shiguredo)

Sora Flutter SDK は [WebRTC SFU Sora](https://sora.shiguredo.jp/) の Flutter クライアントアプリケーションを開発するためのライブラリです。

## About Shiguredo's open source software

We will not respond to PRs or issues that have not been discussed on Discord. Also, Discord is only available in Japanese.

Please read <https://github.com/shiguredo/oss/blob/master/README.en.md> before use.

## 時雨堂のオープンソースソフトウェアについて

利用前に <https://github.com/shiguredo/oss> をお読みください。

## Sora Flutter SDK について

iOS / macOS / Android / Windows / Linux に対応した WebRTC SFU Sora 向けの Flutter SDK です。

WebRTC ライブラリには [libwebrtc](https://webrtc.googlesource.com/src/) を採用しています。
WebRTC のコアロジック (PeerConnection、SDP 処理、ICE、DataChannel) は `dart:ffi` 経由で
libwebrtc を直接呼び出して Dart 側に実装しており、プラットフォーム側 (iOS / macOS / Android / Windows) は
カメラキャプチャと映像レンダリングのみを担当します。

## 特徴

- マルチストリーム対応
- サイマルキャスト対応
- スポットライト対応
- DataChannel シグナリング対応
- リアルタイムメッセージング対応
- RPC 対応
- 転送フィルター対応
- シグナリング通知対応
- シグナリングリダイレクト対応
- 複数シグナリング URL 対応 (フェイルオーバー)
- メタデータ認証対応
- シグナリング通知メタデータ対応
- 接続・切断・シグナリングの各種タイムアウト対応
- VP8 / VP9 / AV1 / H.264 / H.265 対応
- Flutter Texture によるローカル / リモート映像レンダリング対応
- カメラデバイス選択 / 解像度・フレームレート指定対応
- カメラ切り替え (`replaceVideoTrack`) 対応

## 対応コーデック

ハードウェアエンコード/デコードの実際の対応状況は端末・OS バージョンに依存します。

| バックエンド | 対応プラットフォーム | エンコード | デコード |
| --- | --- | --- | --- |
| ソフトウェア | 全プラットフォーム | VP8 / VP9 / AV1 | VP8 / VP9 / AV1 |
| Apple VideoToolbox | iOS / macOS | H.264 / H.265 | H.264 / H.265 |
| Android MediaCodec | Android | H.264 / H.265 / VP8 / VP9 / AV1 | H.264 / H.265 / VP8 / VP9 / AV1 |

## 依存関係

### Flutter / Dart SDK

Flutter plugin 実行基盤、Dart 実行環境

### WebRTC

音声 / 映像 / DataChannel の WebRTC 通信基盤となるネイティブライブラリ

### libwebrtc-c

libwebrtc の C API ラッパーとなるネイティブライブラリ

### Dart パッケージ

#### ffi

Google Dart Team 提供の、 native API 呼び出し用パッケージ

#### meta

Google Dart Team 提供の、アノテーションや API 補助のためのパッケージ。コード中にアノテーションを記述するために利用する

#### web_socket_channel

Google Dart Team 提供の、Dart 標準の WebSocket をラップしたパッケージ

### Dart パッケージ(ビルド・スクリプト用)

#### crypto

Dart Team 提供の、暗号計算パッケージ。依存取得スクリプトで取得したネイティブ依存ライブラリのダイジェスト計算に利用する

#### path

Dart Team 提供の、ファイルパス操作用パッケージ。依存取得スクリプトでパス操作に利用する

## 使い方

### 依存関係の追加

`pubspec.yaml` に以下を追加してください。

```yaml
dependencies:
  flutter:
    sdk: flutter
  sora_sdk: <version>
```

iOS / macOS は Swift Package Manager が `libwebrtc_c.xcframework.zip` を自動取得し、Android は Gradle の `fetchNativeDeps` task が libwebrtc の配布物を自動取得するため、利用者側でネイティブ依存を手動で用意する必要はありません。

### sendrecv で接続する

映像・音声を送受信する例です。

```dart
import 'package:sora_sdk/sora_sdk.dart';

Future<void> main() async {
  // 1. ローカルメディアを取得する
  final stream = await MediaDevices.getUserMedia(
    const GetUserMediaOptions(audio: true, video: true),
  );

  // 2. SoraConnectionConfig で接続設定を組み立てる
  final config = SoraConnectionConfig(
    signalingUrls: const ['wss://sora.example.com/signaling'],
    channelId: 'your-channel-id',
    role: SoraRole.sendrecv,
  );

  // 3. SoraConnection を生成する
  final connection = await Sora.createConnection(config);

  // 4. イベントを購読する
  connection.events.listen((event) {
    switch (event) {
      case SoraConnectionStateChangedEvent():
        print('state: ${event.state}');
      case SoraNotifyEvent():
        print('notify: ${event.message}');
      case SoraTrackEvent():
        print('track added: ${event.track.trackId}');
      default:
        break;
    }
  });

  // 5. ローカルメディアを渡して接続する
  await connection.connect(stream);

  // ...

  // 6. 切断と後始末
  await connection.disconnect();
  await connection.dispose();
}
```

### sendonly で接続する

映像・音声を送信する例です。

```dart
import 'package:sora_sdk/sora_sdk.dart';

Future<void> main() async {
  final stream = await MediaDevices.getUserMedia(
    const GetUserMediaOptions(audio: true, video: true),
  );

  final connection = await Sora.createConnection(
    SoraConnectionConfig(
      signalingUrls: const ['wss://sora.example.com/signaling'],
      channelId: 'your-channel-id',
      role: SoraRole.sendonly,
    ),
  );

  await connection.connect(stream);
}
```

### recvonly で接続する

映像・音声を受信する例です。

```dart
import 'package:sora_sdk/sora_sdk.dart';

Future<void> main() async {
  final connection = await Sora.createConnection(
    SoraConnectionConfig(
      signalingUrls: const ['wss://sora.example.com/signaling'],
      channelId: 'your-channel-id',
      role: SoraRole.recvonly,
    ),
  );

  connection.events.listen((event) {
    if (event is SoraTrackEvent) {
      print('track added: ${event.track.trackId} / ${event.track.connectionId}');
    }
  });

  await connection.connect();
}
```

### SoraConnectionConfig の設定

`SoraConnectionConfig` では以下の設定が可能です。

```dart
final config = SoraConnectionConfig(
  signalingUrls: const ['wss://sora.example.com/signaling'],
  channelId: 'your-channel-id',
  role: SoraRole.sendrecv,
  // 基本オプション
  audio: true,
  video: true,
  clientId: 'client-1',
  bundleId: 'bundle-1',
  metadata: <String, Object?>{'access_token': '...'},
  signalingNotifyMetadata: <String, Object?>{},
  // DataChannel シグナリング
  dataChannelSignaling: true,
  ignoreDisconnectWebSocket: true,
  dataChannels: <Map<String, Object?>>[
    {'label': '#my-channel', 'direction': 'sendrecv', 'compress': true},
  ],
  // サイマルキャスト
  simulcast: true,
  simulcastRequestRid: SimulcastRequestRid.r0,
  // スポットライト
  spotlight: true,
  spotlightFocusRid: SpotlightRid.r1,
  spotlightUnfocusRid: SpotlightRid.r0,
  // コーデック / ビットレート
  audioCodecType: AudioCodecType.opus,
  videoCodecType: VideoCodecType.vp9,
  audioBitRate: 64,
  videoBitRate: 2500,
  videoVp9Params: <String, Object?>{},
  videoH264Params: <String, Object?>{},
  videoH265Params: <String, Object?>{},
  videoAv1Params: <String, Object?>{},
  // 転送フィルター
  forwardingFilters: <Map<String, Object?>>[],
  // タイムアウト
  timeoutOptions: const SoraTimeoutOptions(),
);
```

カメラデバイス・解像度・フレームレートは `SoraConnectionConfig` ではなく、`MediaDevices.getUserMedia(GetUserMediaOptions(...))` で指定し、得られた `MediaStream` を `connection.connect(stream)` に渡してください。

### 接続イベントの購読

`connection.events` (`Stream<SoraConnectionEvent>`) で接続・シグナリング・DataChannel・リモートトラックを一元的に受け取れます。

| イベント型 | 説明 |
| --- | --- |
| `SoraConnectionStateChangedEvent` | 接続状態変化 (connecting / connected / disconnected) |
| `SoraConnectionErrorEvent` | 接続エラー (cameraOpenError 等) |
| `SoraNotifyEvent` | notify メッセージ受信 |
| `SoraPushEvent` | push メッセージ受信 |
| `SoraSwitchedEvent` | switched メッセージ受信 (DataChannel シグナリング有効化) |
| `SoraSignalingMessageEvent` | シグナリングメッセージ送受信 |
| `SoraDataChannelOpenEvent` | DataChannel 利用可能 |
| `SoraDataChannelMessageEvent` | DataChannel メッセージ受信 |
| `SoraTrackEvent` | リモートトラック追加 |
| `SoraRemoveTrackEvent` | リモートトラック削除 |
| `SoraTimeoutEvent` | シグナリング接続タイムアウト |

### 映像の表示

リモート映像は `SoraRemoteVideoWidget`、ローカルプレビューは `SoraLocalVideoWidget` で表示します。これらの Widget は内部で `Texture` の `key` を管理するため、利用者が `key` や `textureId` を直接扱う必要はありません。

```dart
// リモート映像の表示
connection.events.listen((event) {
  if (event is SoraTrackEvent && event.track.kind == 'video') {
    // event.track を SoraRemoteVideoWidget に渡す
  }
});

// Widget ツリー内での使用例
SoraRemoteVideoWidget(track: videoTrack)

// ローカルプレビュー (mirror: true で鏡表示)
SoraLocalVideoWidget(textureId: localTextureId, mirror: true)
```

`SoraConnection.localVideo` ストリームから `textureId` を取得し、`SoraLocalVideoWidget` に渡します。`textureId` は null 許容であり、テクスチャ準備完了前から Widget を構築できます。

### 切断と統計情報の取得

`connection.disconnect()` で切断、`connection.getStats()` で WebRTC 統計情報 (JSON 文字列) を取得できます。

```dart
// 切断
await connection.disconnect();

// 統計情報を取得する
final stats = await connection.getStats();
```

`dispose` 後の API 呼び出し (`rpc` / `getStats` / `replaceVideoTrack` / `sendDataChannelMessage` / `setAudioEnabled` 等) は `StateError` で拒否されます。

### メッセージ送受信

`#` プレフィックス付きラベルのユーザー定義 DataChannel でバイナリメッセージを送受信できます。

```dart
// 送信
connection.sendDataChannelMessage('#my-channel', Uint8List.fromList([0x01, 0x02]));

// 受信
connection.events.listen((event) {
  if (event is SoraDataChannelMessageEvent) {
    print('received on ${event.message.label}: ${event.message.data.length} bytes');
  }
});
```

### RPC

`rpc` DataChannel を使って JSON-RPC 2.0 のリクエスト/レスポンスをやり取りできます。SDK が JSON-RPC メッセージの組み立てと id 採番を行います。

```dart
// リクエストを送信してレスポンスを待つ
final result = await connection.rpc(
  'method_name',
  params: <String, Object?>{'key': 'value'},
  options: const SoraRpcOptions(timeout: 5000),
);

// notification (レスポンスを待たない)
await connection.rpc(
  'method_name',
  params: <String, Object?>{'key': 'value'},
  options: const SoraRpcOptions(notification: true),
);
```

エラー時は `SoraRpcError` が throw されます。`disconnect` 時には待機中の RPC リクエストが自動でキャンセルされます。

### メッセージング専用接続

音声・映像を伴わない DataChannel メッセージング専用接続は、設定の組み合わせで実現します。

```dart
final connection = await Sora.createConnection(
  SoraConnectionConfig(
    signalingUrls: const ['wss://sora.example.com/signaling'],
    channelId: 'your-channel-id',
    role: SoraRole.sendonly,
    audio: false,
    video: false,
    dataChannelSignaling: true,
    dataChannels: const [
      {'label': '#messaging', 'direction': 'sendrecv', 'compress': true},
    ],
  ),
);

await connection.connect();
connection.sendDataChannelMessage('#messaging', Uint8List.fromList([0x01, 0x02]));
```

## 構成

```text
sora-flutter-sdk/
├── lib/                # sora_sdk パッケージ本体
├── ios/                # iOS プラグイン (Swift)
├── macos/              # macOS プラグイン (Swift)
├── android/            # Android プラグイン (Kotlin)
├── linux/              # Linux プラグイン (C++)
├── windows/            # Windows プラグイン (C++)
├── docs/               # ドキュメント
├── e2e_test_app/       # E2E テストアプリ（recvonly / sendonly / sendrecv / 2 クライアント疎通）
├── devtools/           # 開発用サンプルアプリ
└── scripts/            # ネイティブ依存取得スクリプト
```

## サンプル

### e2e_test_app

`integration_test` で recvonly / sendonly / sendrecv 接続と、2 クライアント間の
基本メディア疎通を検証する最小アプリです。2 クライアント E2E では sender / receiver が同じ
`channelId` を共有し、`bundleId` は設定しません。macOS 専用の Video Codec E2E では、VP8 / VP9 /
AV1 / H.264 / H.265 を指定した送受信を個別に検証します。詳細は [e2e_test_app/README.md](e2e_test_app/README.md) を参照してください。

```bash
cd e2e_test_app
flutter pub get
flutter test integration_test/recvonly_e2e_test.dart -d macos
flutter test integration_test/sendonly_dummy_video_e2e_test.dart -d macos
flutter test integration_test/sendrecv_smoke_e2e_test.dart -d macos
flutter test integration_test/sendrecv_bidirectional_e2e_test.dart -d macos
flutter test integration_test/connection_lifecycle_e2e_test.dart -d macos
flutter test integration_test/audio_media_e2e_test.dart -d macos
flutter test integration_test/texture_rendering_e2e_test.dart -d macos
flutter test integration_test/two_party_media_e2e_test.dart -d macos
flutter test integration_test/video_codec_e2e_test.dart -d macos
flutter test integration_test/window_capture_e2e_test.dart -d macos
```

ウィンドウキャプチャ E2E (`window_capture_e2e_test.dart`) は macOS ローカル専用です。
SCStream の開始に画面収録権限が必要なため、CI では実行できません。
システム設定の「プライバシーとセキュリティ」→「画面収録」で
e2e_test_app に権限を付与してから実行してください。

### devtools

開発時の動作確認用 Flutter アプリです。

## ビルド

### 前提条件

- Flutter 3.44.0 以上
- Dart SDK 3.10.0 以上
- iOS: Xcode (iOS 16.0 以上)
- macOS: Xcode (macOS 15.0 以上)
- Android: Android Studio / Android NDK
- Windows: Visual Studio 2022 (MSVC v143) / Build Tools for Visual Studio 2022
- Linux: clang / cmake / ninja / GTK 3 / PulseAudio / libjpeg-turbo

ネイティブ依存 (libwebrtc) は iOS / macOS では Swift Package Manager、Android では Gradle の
`fetchNativeDeps` task から自動取得されます。Android 向け取得対象のバージョン・配布元 URL・SHA-256 は
[`scripts/native_deps.json`](scripts/native_deps.json) で管理しています。

Windows では CMake ビルド時に `scripts/fetch_native_deps.dart windows_x86_64` が自動実行され、libwebrtc-c / webrtc を `third_party/libwebrtc-c/` にダウンロード・展開します。

Linux では cmake configure 時に `scripts/fetch_native_deps.dart linux_ubuntu_24_04_x86_64` が自動実行され、libwebrtc-c / webrtc を `third_party/libwebrtc-c/` にダウンロード・展開します。Ubuntu 24.04 向けのビルドに必要なシステムパッケージは以下の通りです。

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libpulse-dev libjpeg-dev
```

iOS / macOS 向けの `libwebrtc_c.xcframework.zip` の version は [`scripts/native_deps.json`](scripts/native_deps.json) の `libwebrtc_c.version`、URL / checksum は `libwebrtc_c.apple_xcframework` を正本として管理しています。

手動更新手順:

```bash
# 1. scripts/native_deps.json を手動で更新する

# 2. Package.swift へ反映する
dart run scripts/update_apple_native_binary.dart
```

更新対象は通常、`libwebrtc_c.version` と `libwebrtc_c.apple_xcframework.checksum` です。配布ファイル名や配布元を変える場合のみ `artifact` / `base_url` も更新します。

## 対応 WebRTC SFU Sora

- Sora 2025.1.0 以降

## 対応プラットフォーム

| プラットフォーム | 状態 |
| --- | --- |
| iOS | 対応 |
| macOS | 対応 |
| Android | 対応 |
| Windows | 対応 (x86_64) |
| Linux | 対応 (x86_64, Ubuntu 24.04) |

### iOS の対応バージョン

iOS 16.0 以上をサポートします。

### macOS の対応バージョン

macOS 15 以上をサポートします。

### Android の対応バージョン

Android 10 (API 29) 以上をサポートします。

### Windows の対応バージョン

Windows 10 20H2 以上 (x86_64) をサポートします。

### Linux の対応バージョン

Ubuntu 24.04 (x86_64) をサポートします。

## 優先実装

優先実装とは Sora のライセンスを契約頂いているお客様限定で Sora Flutter SDK の実装予定機能を有償にて前倒しで実装することです。

### 優先実装が可能な対応一覧

**詳細は Discord やメールなどでお気軽にお問い合わせください**

- Opus 詳細パラメータ対応 (`audioOpusParamsChannels` / `audioOpusParamsStereo` / `audioOpusParamsUseinbandfec` 等)
- `audioStreamingLanguageCode` 対応

## サポートについて

### Discord

- **サポートしません**
- アドバイスします
- フィードバック歓迎します

最新の状況などは Discord で共有しています。質問や相談も Discord でのみ受け付けています。

<https://discord.gg/shiguredo>

### バグ報告

Discord へお願いします。

## ライセンス

Apache License 2.0

```text
Copyright 2026-2026, Shiguredo Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
