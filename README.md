# Sora Flutter SDK

[![pub.dev](https://img.shields.io/pub/v/sora_sdk.svg)](https://pub.dev/packages/sora_sdk)
[![libwebrtc](https://img.shields.io/badge/libwebrtc-150.7871-blue.svg)](https://chromium.googlesource.com/external/webrtc/+/branch-heads/7871)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![GitHub Actions](https://github.com/shiguredo/sora-flutter-sdk/actions/workflows/ci.yml/badge.svg)](https://github.com/shiguredo/sora-flutter-sdk/actions/workflows/ci.yml)
[![Discord](https://img.shields.io/badge/Discord-%235865F2.svg?logo=discord&logoColor=white)](https://discord.gg/shiguredo)

Sora Flutter SDK は [WebRTC SFU Sora](https://sora.shiguredo.jp/) の Flutter クライアントアプリケーションを開発するためのライブラリです。

## About Shiguredo's open source software

We will not respond to PRs or issues that have not been discussed on Discord. Also, Discord is only available in Japanese.

Please read <https://github.com/shiguredo/oss/blob/master/README.en.md> before use.

## 時雨堂のオープンソースソフトウェアについて

利用前に <https://github.com/shiguredo/oss> をお読みください。

## 特徴

- [libwebrtc](https://webrtc.googlesource.com/src/) を利用し、 iOS / macOS / Android / Windows / Linux に対応
  - WebRTC のコアロジック (PeerConnection、SDP 処理、ICE、DataChannel) は `dart:ffi` 経由で libwebrtc を直接呼び出す Dart 側実装
  - プラットフォーム側はカメラキャプチャと映像レンダリングを担当
- マルチストリームに対応
- サイマルキャストに対応
- スポットライトに対応
- 転送フィルターに対応
- DataChannel シグナリングに対応
- リアルタイムメッセージングに対応
- RPC に対応
- シグナリング通知に対応
- シグナリングリダイレクトに対応
- 複数シグナリング URL に対応 (フェイルオーバー)
- メタデータ認証に対応
- シグナリング通知メタデータに対応
- 接続・切断・シグナリングの各種タイムアウトに対応
- 映像コーデック `VP8` / `VP9` / `AV1` / `H.264` / `H.265` に対応
  - ソフトウェアコーデックで `VP8` / `VP9` / `AV1` に対応
  - `H.264` / `H.265` は Apple Video Toolbox (iOS / macOS) と Android MediaCodec のハードウェアコーデックを利用
  - Android では対応端末で `VP8` / `VP9` / `AV1` のハードウェアコーデックも利用可能
  - ハードウェアコーデックの利用可否は端末・OS バージョンに依存
- [WebRTC 統計情報](https://www.w3.org/TR/webrtc-stats/) の取得に対応
- Flutter Texture によるローカル / リモート映像レンダリングに対応
- カメラデバイスの選択、解像度・フレームレートの指定、カメラ切り替え (`replaceVideoTrack`) に対応
- 音声入力デバイス / 音声出力デバイスの列挙に対応
- カメラ以外の映像フレームを送信する外部映像入力に対応
- 受信 PCM の取得と PCM の送信 (`PushAudio`) に対応

## 条件

- WebRTC SFU Sora 2025.2.0 以降
- Flutter 3.44.0 以上
- Dart SDK 3.10.0 以上
- iOS 16.0 以上
- macOS 15 以上
- Android 10 (API 29) 以上
- Windows 10 20H2 以上 (x86_64)
- Linux Ubuntu 24.04 (x86_64)

## 使い方

使い方は [Sora Flutter SDK ドキュメント](https://sora-flutter-sdk.shiguredo.jp/) を参照してください。

## サンプル

サンプルは [devtools](https://github.com/shiguredo/sora-flutter-sdk/tree/develop/devtools) を参照してください。

## インストール

```bash
flutter pub add sora_sdk
```

## E2E (End to End) テスト

`integration_test` を利用した E2E テストを実行できます。
詳細は [e2e_test_app/README.md](https://github.com/shiguredo/sora-flutter-sdk/blob/develop/e2e_test_app/README.md) を参照してください。

## 優先実装

優先実装とは Sora のライセンスを契約頂いているお客様限定で Sora Flutter SDK の実装予定機能を有償にて前倒しで実装することです。

**詳細は Discord やメールなどでお気軽にお問い合わせください**

## ライセンス

Apache License 2.0

```text
Copyright 2026 Shiguredo Inc.

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

## リンク

### 商用製品

- [WebRTC SFU Sora](https://sora.shiguredo.jp)
  - [WebRTC SFU Sora ドキュメント](https://sora-doc.shiguredo.jp)
- [Sora Cloud](https://sora-cloud.shiguredo.jp)
  - [Sora Cloud ドキュメント](https://doc.sora-cloud.shiguredo.app)

### 無料検証サービス

- [Sora Labo](https://sora-labo.shiguredo.app)
  - [Sora Labo ドキュメント](https://github.com/shiguredo/sora-labo-doc)

### クライアント SDK

- [Sora JavaScript SDK](https://github.com/shiguredo/sora-js-sdk)
  - [Sora JavaScript SDK ドキュメント](https://sora-js-sdk.shiguredo.jp/)
- [Sora iOS SDK](https://github.com/shiguredo/sora-ios-sdk)
  - [Sora iOS SDK ドキュメント](https://sora-ios-sdk.shiguredo.jp/)
  - [Sora iOS SDK クイックスタート](https://github.com/shiguredo/sora-ios-sdk-quickstart)
  - [Sora iOS SDK サンプル集](https://github.com/shiguredo/sora-ios-sdk-samples)
- [Sora Android SDK](https://github.com/shiguredo/sora-android-sdk)
  - [Sora Android SDK ドキュメント](https://sora-android-sdk.shiguredo.jp/)
  - [Sora Android SDK クイックスタート](https://github.com/shiguredo/sora-android-sdk-quickstart)
  - [Sora Android SDK サンプル集](https://github.com/shiguredo/sora-android-sdk-samples)
- [Sora Unity SDK](https://github.com/shiguredo/sora-unity-sdk)
  - [Sora Unity SDK ドキュメント](https://sora-unity-sdk.shiguredo.jp/)
  - [Sora Unity SDK サンプル集](https://github.com/shiguredo/sora-unity-sdk-samples)
- [Sora Python SDK](https://github.com/shiguredo/sora-python-sdk)
  - [Sora Python SDK ドキュメント](https://sora-python-sdk.shiguredo.jp/)
  - [Sora Python SDK サンプル集](https://github.com/shiguredo/sora-python-sdk-samples)
- [Sora C++ SDK](https://github.com/shiguredo/sora-cpp-sdk)
- [Sora Rust SDK](https://github.com/shiguredo/sora-rust-sdk)
- [Sora Flutter SDK](https://github.com/shiguredo/sora-flutter-sdk)

### クライアントツール

- [Sora DevTools](https://github.com/shiguredo/sora-devtools)
- [Media Processors](https://github.com/shiguredo/media-processors)
- [WebRTC Native Client Momo](https://github.com/shiguredo/momo)

### サーバーツール

- [WebRTC Load Testing Tool Zakuro](https://github.com/shiguredo/zakuro)
  - Sora 専用負荷試験ツール
- [WebRTC Stats Analyzer Kohaku](https://github.com/shiguredo/kohaku)
  - Sora 専用統計解析ツール
- [Recording Composition Tool Hisui](https://github.com/shiguredo/hisui)
  - Sora 専用録画ファイル合成ツール
- [Audio Streaming Gateway Suzu](https://github.com/shiguredo/suzu)
  - Sora 専用音声解析ゲートウェイ
- [Sora Archive Uploader](https://github.com/shiguredo/sora-archive-uploader)
  - Sora 専用録画ファイル S3 互換オブジェクトストレージアップロードツール
- [Prometheus exporter for WebRTC SFU Sora metrics](https://github.com/shiguredo/sora_exporter)
  - Sora 専用 OpenMetrics 形式エクスポーター
