# Linux

## 対応アーキテクチャ

| アーキテクチャ | 状態 |
| --- | --- |
| x86_64 | 対応 (Ubuntu 24.04) |

## システム要件

- Ubuntu 24.04 (x86_64)
- clang / cmake / ninja-build / pkg-config
- GTK 3 開発パッケージ
- PulseAudio 開発パッケージ
- libjpeg-turbo 開発パッケージ
- Flutter 3.44.0 以上

システムパッケージのインストール:

```bash
sudo apt-get install -y clang cmake ninja-build pkg-config \
  libgtk-3-dev liblzma-dev libpulse-dev libjpeg-dev
```

## 対応 WebRTC SFU Sora

- Sora 2025.1.0 以降

## 依存関係

Sora Flutter SDK はネイティブ依存として以下を必要とします。

- **libwebrtc-c** — WebRTC の C API ラッパー
- **webrtc** — WebRTC ネイティブライブラリ

依存取得の設定は [`../scripts/native_deps.json`](../scripts/native_deps.json) で管理しています。

これらの依存は CMake の configure 時に自動的にダウンロード・展開されます。
`linux/CMakeLists.txt` の `execute_process` が `dart` コマンド経由で
`fetch_native_deps.dart linux_ubuntu_24_04_x86_64` を実行するため、利用者が手動で依存を用意する必要はありません。

CMake を経由せずに手動で依存を取得する場合のみ、以下のコマンドを実行してください。
依存の展開には `archive` パッケージが必要なため、初回実行前に `dart pub get` を実行する必要があります。

```bash
cd <プロジェクトルート>
dart pub get
dart run scripts/fetch_native_deps.dart linux_ubuntu_24_04_x86_64
```

## ビルド手順

### 1. Flutter パッケージのセットアップ

アプリケーションディレクトリで以下のコマンドを実行してください。

```bash
flutter pub get
```

ネイティブ依存 (libwebrtc-c / webrtc) は CMake ビルド時に自動取得されるため、個別に取得する必要はありません。

### 2. アプリのビルド

```bash
flutter build linux --debug
```

またはリリースビルド:

```bash
flutter build linux --release
```

## ビルドディレクトリ構成

`third_party/libwebrtc-c/` 以下にネイティブ依存が配置されます。

```text
third_party/libwebrtc-c/
├── include/                        # ヘッダファイル (webrtc_c.h)
├── build-linux_ubuntu_24_04_x86_64/ # ビルド出力
│   ├── libwebrtc-c.a               # libwebrtc-c 静的ライブラリ
│   ├── _deps/webrtc/               # WebRTC 依存 (fetch_native_deps.dart により配置)
│   │   ├── include/                # WebRTC ヘッダ
│   │   └── lib/libwebrtc.a         # WebRTC 静的ライブラリ
└── .state.json                     # 取得済みバージョン管理ファイル
```

`flutter build linux` の出力は `build/linux/` に配置されます。

## 備考

- 音声デバイスは PulseAudio 経由で入出力を処理します。
- カメラキャプチャは V4L2 経由で動作します。
- リモート映像は libyuv で I420 から BGRA に変換し、ピクセルバッファ経由で Flutter Texture に描画されます。
