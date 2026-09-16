# Windows ネイティブプラグイン基盤と MethodChannel ハンドラを追加する

- Priority: Medium
- Created: 2026-06-03
- Completed: 2026-06-11
- Model: Opus 4.8
- Branch: feature/add-windows-plugin-foundation
- Polished: 2026-06-03

## 目的

Windows の Flutter プラグイン (`windows/sora_sdk_plugin.cpp`) は現在スケルトンで、すべての MethodChannel 呼び出しに `"unimplemented"` を返すだけである。Dart 側 (`lib/`) は MethodChannel 経由でクライアント生成・デバイス列挙・キャプチャ・レンダリングを要求するため、Windows のネイティブ側ハンドラ基盤を実装する。

本 issue は Windows の「土台」を担う。具体的には (1) libwebrtc-c をリンクし dart:ffi が開く `sora_sdk.dll` を生成する CMake 構成 (MSVC)、(2) FFI 公開 C API シンボルのエクスポート保持、(3) Windows desktop ランナーの用意、(4) MethodChannel ディスパッチとクライアント管理、(5) C ブリッジの土台、を含む。カメラ・音声・レンダリングの実体は後続 issue (0035-0037) に分離する。

本 issue は 0032 (Windows ネイティブ依存取得) の完了に依存する。Linux 系 (0026) の MethodChannel ディスパッチ・クライアント管理の知見を流用するが、CMake / リンク / シンボル保持は MSVC 固有で Linux とは別設計になる。

## 優先度根拠

- Windows のカメラ・音声・レンダリング各 issue の共通土台。これが無いと各機能が載らず、`sora_sdk.dll` も生成されないため dart:ffi が動かない
- Linux 先行のため Medium とする

## 現状

- `windows/sora_sdk_plugin.cpp:29` の `HandleMethodCall` は `"unimplemented"` / `"Windows implementation is not wired yet."` を返すのみ。
- `windows/CMakeLists.txt:18-23` は `sora_sdk_plugin` ターゲットを `flutter flutter_wrapper_plugin` のみリンクし、libwebrtc-c を参照していない。`sora_sdk_bundled_libraries` は空。
- dart:ffi は `DynamicLibrary.open('sora_sdk.dll')` を呼ぶ (`lib/src/ffi/library_loader.dart:24-26`) が、現状の CMake には `sora_sdk.dll` を生成するターゲットが存在しない。
- Android の参照実装 `android/src/main/cpp/CMakeLists.txt:58-69` は `-Wl,--undefined` (GNU ld 構文) で C API シンボルを保持しているが、**Windows は MSVC リンカ (link.exe) であり `--undefined` も `.a` 前提も成立しない**。MSVC では `/INCLUDE:symbol`、`.def` ファイル、または C API 側の `__declspec(dllexport)` でエクスポートを制御する。
- **Windows desktop ランナーがリポジトリに存在しない**。`e2e_test_app/` には `linux/` ランナーはあるが `windows/` が無く、`devtools/` にも windows ランナーが無い。`flutter build windows` を実行する対象が無い。
- Dart 側が要求する MethodChannel メソッドは 0026 (Linux) と同一:
  - `createClient` / `disposeClient`、`enumerate*`、`getVideoInputFormats`、`setAudioInputDevice` / `getDefaultAudioInputDevice`、`ensureLocalVideoTrackTexture` / `disposeLocalVideoTrackTexture` / `stopCameraCapturer`、`createRemoteVideoRenderer` / `disposeRemoteVideoRenderer`。
- macOS の `SoraFlutterMessageHandler.swift` (314 行)、Android `SoraSdkPlugin.kt` (536 行) が参照実装。

## 設計方針

### CMake / ターゲット構成 (MSVC、FFI が動く土台)

- C ブリッジソースと libwebrtc-c をリンクした **`sora_sdk.dll`** を生成するターゲットを `windows/CMakeLists.txt` に新設する。出力名は dart:ffi のロード名 (`sora_sdk.dll`) と一致させる。
- リンクするライブラリは 0032 が `build-windows_x86_64/` に配置した `.lib` (libwebrtc-c の `libwebrtc-c.lib` 相当と `_deps/webrtc/lib/webrtc.lib`、0032 が確定した実パス・実名)。
- FFI 公開 C API シンボルのエクスポート: `--undefined` は使えない。次のいずれかを選び実装する。
  - libwebrtc-c の C API ヘッダが `__declspec(dllexport)` 注釈を持つならそれを利用する。
  - 持たない場合は、公開 C API シンボル一覧から `.def` ファイル (Android の `libwebrtc_c_api.ldflags` のシンボル列を変換) を生成して `link.exe /DEF:` で渡す、または `/INCLUDE:` でルートシンボルを残す。
  - どの方式を採るかを実装時に確定し、`nm`/`dumpbin /EXPORTS` で `sora_*` がエクスポートされることを確認する。
- C ランタイム整合: libwebrtc-c の MSVC ビルドが `/MD` (動的 CRT) か `/MT` (静的 CRT) かを 0032 配置物から確認し、`sora_sdk.dll` のランタイムを揃える (不一致は LNK エラーや実行時クラッシュの原因)。
- システムライブラリ: libwebrtc が要求する Windows システムライブラリ (`secur32` / `winmm` / `dmoguids` / `msdmo` / `strmiids` 等、配布元 webrtc-build が要求するもの) をリンクする。カメラ (Media Foundation) / 音声 (WASAPI) 固有のライブラリは各機能 issue (0035 / 0036) でリンクする。
- ネイティブ依存のビルド時取得: Windows にも Gradle task 相当が無いため、`windows/CMakeLists.txt` から `fetch_native_deps.dart windows_x86_64` を `flutter build windows` 前に起動する配線を入れる。
- `sora_sdk.dll` を `sora_sdk_bundled_libraries` に含めて配布する。

### Windows desktop ランナーの用意

- `e2e_test_app/` に Windows ランナーを生成する (`flutter create --platforms=windows` 相当)。これにより `flutter run -d windows` / `flutter build windows` の検証対象が用意される。Linux ランナーと同じ位置付け。

### MethodChannel / クライアント管理

- `sora_sdk_plugin.cpp` の `HandleMethodCall` を、メソッド名で各ハンドラへディスパッチする構造に拡張する (`flutter::MethodChannel<flutter::EncodableValue>` ベース)。
- クライアント管理 (`createClient` / `disposeClient`) を実装し、Dart 側 `WebrtcClient` (FFI) と協調する。
- Windows 版 C ブリッジ層の土台を作る。カメラ / 音声 / レンダリングの実体は未実装スタブとし 0035-0037 で埋める。
- Texture 登録は Flutter Windows の `TextureRegistrar` を用いる。本 issue では登録機構の土台のみ。
- 未実装メソッドは `"unimplemented"` のままでよいが、`createClient` / `disposeClient` と各 `enumerate*` の空応答は基盤として通るようにする。

## 完了条件

- `flutter build windows` で `sora_sdk.dll` が libwebrtc-c をリンクして生成され、C API シンボルがエクスポートされる (`dumpbin /EXPORTS` で `sora_*` が確認できる)。
- `e2e_test_app` に Windows ランナーが追加され、`flutter run -d windows` で起動し `createClient` が dart:ffi の lookup 成功を経てクラッシュしない。
- `enumerate*` 系が (空でも) エラーを返さず応答する。
- カメラ / 音声 / レンダリングの実体は後続 issue 対象として未実装スタブで可。
- CI でのビルド検証は 0038 が担う。
- `CHANGES.md` の `## develop` に担当者行付きで `[ADD]` エントリを追記する:
  ```
  - [ADD] Windows ネイティブプラグイン基盤と MethodChannel ハンドラを追加する
    - CMake で `sora_sdk.dll` を生成し、MethodChannel / EventChannel によるクライアント管理を実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `e2e_test_app/` に Windows ランナーを生成する。
2. `windows/CMakeLists.txt` に `sora_sdk.dll` ターゲットを新設し、libwebrtc-c / webrtc の `.lib` とシステムライブラリをリンク、CRT を整合させ、C API シンボルのエクスポート (`.def` / `/INCLUDE:` / `__declspec`) を構成する。
3. `windows/CMakeLists.txt` に `fetch_native_deps.dart windows_x86_64` のビルド時起動を配線する。
4. Windows 版 C ブリッジのソースを追加し、`sora_sdk.dll` ターゲットに含める。
5. `sora_sdk_plugin.cpp` の `HandleMethodCall` をメソッド名ディスパッチに書き換え、クライアント管理を実装する。
6. `sora_sdk.dll` を `sora_sdk_bundled_libraries` に含める。
7. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する。
