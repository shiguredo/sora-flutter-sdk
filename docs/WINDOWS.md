# Windows

## 対応アーキテクチャ

| アーキテクチャ | 状態 |
| --- | --- |
| x86_64 | 対応 |

## システム要件

- Windows 10 20H2 以上 (または Windows Server 2022 以上)
- Visual Studio 2022 (MSVC v143) または [Build Tools for Visual Studio 2022](https://visualstudio.microsoft.com/downloads/#build-tools-for-visual-studio-2022)
  - 「C++ によるデスクトップ開発」ワークロードが必要
- Windows SDK (10.0.26100 以上)
- Flutter 3.44.0 以上

## 対応 WebRTC SFU Sora

- Sora 2025.1.0 以降

## 依存関係

Sora Flutter SDK はネイティブ依存として以下を必要とします。

- **libwebrtc-c** — WebRTC の C API ラッパー
- **webrtc** — WebRTC ネイティブライブラリ

依存取得の設定は [`../scripts/native_deps.json`](../scripts/native_deps.json) で管理しています。

これらの依存は CMake ビルド時に自動的にダウンロード・展開されます。
`windows/CMakeLists.txt` の `fetch_native_deps_windows` カスタムターゲットが `dart` コマンド経由で
`fetch_native_deps.dart windows_x86_64` を実行するため、利用者が手動で依存を用意する必要はありません。

CMake を経由せずに手動で依存を取得する場合のみ、以下のコマンドを実行してください。
依存の展開には `archive` パッケージが必要なため、初回実行前に `dart pub get` を実行する必要があります。

```bash
cd <プロジェクトルート>
dart pub get
dart run scripts/fetch_native_deps.dart windows_x86_64
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
flutter build windows --debug
```

またはリリースビルド:

```bash
flutter build windows --release
```

## ビルドディレクトリ構成

`third_party/libwebrtc-c/` 以下にネイティブ依存が配置されます。

```text
third_party/libwebrtc-c/
├── include/                        # ヘッダファイル (webrtc_c.h)
├── build-windows_x86_64/           # ビルド出力
│   ├── libwebrtc-c.lib             # libwebrtc-c 静的ライブラリ
│   ├── _deps/webrtc/               # WebRTC 依存 (fetch_native_deps.dart により配置)
│   │   ├── include/                # WebRTC ヘッダ
│   │   └── lib/webrtc.lib          # WebRTC 静的ライブラリ
└── .state.json                     # 取得済みバージョン管理ファイル
```

`flutter build windows` の出力は `build/windows/` に配置されます。

## 備考

- 音声デバイスは WASAPI 経由で入出力を処理します。
- カメラキャプチャは Media Foundation 経由で動作します。
- リモート映像は libyuv で I420 から BGRA に変換し、ピクセルバッファ経由で Flutter Texture に描画されます。
