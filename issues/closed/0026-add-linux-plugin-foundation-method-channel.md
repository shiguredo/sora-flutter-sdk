# Linux ネイティブプラグイン基盤と MethodChannel ハンドラを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-25
- Model: Opus 4.8
- Branch: feature/add-linux-plugin-foundation
- Polished: 2026-06-03

## 目的

Linux の Flutter プラグイン (`linux/sora_sdk_plugin.cc`) は現在スケルトンで、すべての MethodChannel 呼び出しに `"unimplemented"` を返すだけである。Dart 側 (`lib/`) は MethodChannel 経由でクライアント生成・デバイス列挙・キャプチャ・レンダリングを要求するため、Linux のネイティブ側ハンドラ基盤を実装する。

本 issue は Linux の「土台」を担う:
1. libwebrtc-c をリンクし dart:ffi が開く共有ライブラリ `libsora_sdk.so` を生成する CMake 構成
2. FFI 公開 C API シンボルの保持
3. MethodChannel ディスパッチとクライアント管理 (`createClient` / `disposeClient`)
4. EventChannel のセットアップ (Dart 側へのイベント通知経路)
5. C ブリッジの土台 (スタブ実装)

カメラ・音声・レンダリングの実体は後続 issue (0027-0029) に分離する。本 issue はそれらが「未実装でもクラッシュしない」スタブの提供までを責務とし、実装は後続に委ねる。

本 issue は 0024 (Linux ネイティブ依存取得) の完了に依存する。0024 の成果物 (`third_party/libwebrtc-c/build-linux_x86_64/` 以下の `libwebrtc-c.a`、`_deps/webrtc/`、`include/webrtc_c.h`) を前提とする。

## 優先度根拠

- Linux のカメラ・音声・レンダリング各 issue の共通土台であり、これが無いと各機能が載らず、`libsora_sdk.so` も生成されないため dart:ffi が一切動かない
- High とする

## 現状

- `library_loader.dart` には `Platform.isLinux → DynamicLibrary.open('libsora_sdk.so')` が既に実装済み。しかし CMake には `libsora_sdk.so` を生成するターゲットが存在しない
- `linux/sora_sdk_plugin.cc` の `handle_method_call` は全メソッドに `"unimplemented"` を返す
- `linux/CMakeLists.txt` の `sora_sdk_plugin` ターゲットは `flutter` のみリンク。`sora_sdk_bundled_libraries` は空
- Dart 側の MethodChannel (`sora_sdk/method`) で要求されるメソッド一覧:
  - `createClient` / `disposeClient` — 戻り値: `{'clientId': int, 'eventChannelName': String}`
  - `enumerateVideoInputDevices` / `enumerateAudioInputDevices` / `enumerateAudioOutputDevices` — 本 issue では空リストを返すスタブ
  - `getVideoInputFormats` — 本 issue では空リストを返すスタブ
  - `setAudioInputDevice` / `getDefaultAudioInputDevice` — 本 issue では `FlMethodNotImplemented` を返す
  - `ensureLocalVideoTrackTexture` / `disposeLocalVideoTrackTexture` / `stopCameraCapturer` — 本 issue では `FlMethodNotImplemented` を返す
  - `createRemoteVideoRenderer` / `disposeRemoteVideoRenderer` — 本 issue では `FlMethodNotImplemented` を返す
- Dart 側は `eventChannelName` で EventChannel を購読する (`SoraConnection._()` の `_eventSubscription`)。
  macOS の EventChannel パターン: `"sora_sdk/event/{clientId}"`
- Android の参照実装 `android/src/main/cpp/CMakeLists.txt` は、C ブリッジと libwebrtc-c.a / libwebrtc.a をリンクした共有ライブラリ `sora_sdk` を生成し、`libwebrtc_c_api.ldflags` 経由で C API シンボルを `--undefined=sora_*` で保持している
- macOS の `SoraFlutterMessageHandler.swift` (314 行) が MethodChannel / EventChannel ディスパッチの参照実装

## 設計方針

### CMake 構成

- `libsora_sdk.so` を生成する共有ライブラリターゲットを `linux/CMakeLists.txt` に新設する。出力名は `libsora_sdk.so` (dart:ffi のロード名と一致)
- Linux 版 C ブリッジソース (`linux/linux_bridge.c`) を新規作成し、このターゲットに含める
- リンク: `libwebrtc-c.a` と `libwebrtc.a` の実パス (0024 の成果物パス、実展開で確定)
- include パス: `third_party/libwebrtc-c/include` と `third_party/libwebrtc-c/build-linux_x86_64/_deps/webrtc/include` (Android `CMakeLists.txt:13-19` と同様)
- FFI シンボル保持: `libwebrtc_c_api.ldflags` (`-Wl,--undefined=sora_*`) を `target_link_options` で適用。ldflags ファイルは Android と共有する (内容は同一のため)
- システムライブラリ: `dl` と `pthread` は必須。その他はリンクエラーで不足が判明したものを追加する
- ビルド時依存取得: `add_custom_command` で `dart run scripts/fetch_native_deps.dart linux_x86_64` を起動する
- `sora_sdk_bundled_libraries` に `libsora_sdk.so` を含める

### C ブリッジ (`linux/linux_bridge.c`)

- ファイル配置: `linux/linux_bridge.c`
- `#include "webrtc_c.h"` で libwebrtc-c の API を利用可能にする
- FFI 公開 C API シンボル (`sora_*`) を定義する。本 issue では以下の最小シンボルをスタブ実装:
  - `sora_create_client` / `sora_dispose_client` — 実装 (後述)
  - その他の `sora_*` シンボル — スタブ (0 または nullptr を返す)
- 全シンボルが `libwebrtc_c_api.ldflags` で保持対象になるため、不足シンボルは 0027-0029 で追加する

### MethodChannel ディスパッチ

- `sora_sdk_plugin.cc` の `handle_method_call` をメソッド名による分岐に拡張
- 本 issue で実装するメソッド:
  - `createClient`: クライアント ID を採番し、EventChannel を設定。戻り値 `{'clientId': int, 'eventChannelName': 'sora_sdk/event/{clientId}'}` を返す
  - `disposeClient`: 指定 clientId のリソースを解放
  - `enumerateVideoInputDevices` / `enumerateAudioInputDevices` / `enumerateAudioOutputDevices`: 空リストを返す
  - `getVideoInputFormats`: 空リストを返す
- 本 issue では `FlMethodNotImplemented` を返すメソッド (後続で実装):
  - `setAudioInputDevice` / `getDefaultAudioInputDevice`
  - `ensureLocalVideoTrackTexture` / `disposeLocalVideoTrackTexture` / `stopCameraCapturer`
  - `createRemoteVideoRenderer` / `disposeRemoteVideoRenderer`

### EventChannel セットアップ

- `createClient` 時に `FlEventChannel` を作成し、StreamHandler を登録する
- チャネル名: `"sora_sdk/event/{clientId}"` (macOS と同一パターン)
- StreamHandler は macOS の `SoraClientStreamHandler` 相当の実装を用意する (イベントキュー管理)
- 本 issue では StreamHandler が `onListen` / `onCancel` に応答できることを確認する。イベントの発行は 0027-0029 で追加する

### クライアント管理

- クライアント ID: macOS/iOS と同様に単調増加整数で採番
- `createClient`: ID 採番 → `libsora_sdk.so` の `sora_create_client` を呼ぶ → EventChannel 作成 → `{clientId, eventChannelName}` を返す
- `disposeClient`: `sora_dispose_client` → EventChannel 解放 → 管理テーブルから削除

## 完了条件

- `flutter build linux` で `libsora_sdk.so` が生成され、`nm -D` で `sora_*` シンボルが確認できる
- `flutter run -d linux` で `e2e_test_app` が起動し、`createClient` が dart:ffi の lookup 成功を経てクライアント ID と eventChannelName を正しく返す
- `enumerateVideoInputDevices` / `enumerateAudioInputDevices` / `enumerateAudioOutputDevices` / `getVideoInputFormats` が空リストをエラーなく返す
- `disposeClient` が正常に完了する
- 未実装メソッド (`createRemoteVideoRenderer` 他) が `FlMethodNotImplemented` を返し、Dart 側でハンドリング可能なエラーになる
- CI でのビルド検証は 0030 が担う
- `CHANGES.md` の `## develop` の `### sora_sdk` セクションに `[ADD]` エントリを追記する:
  ```
  - [ADD] Linux ネイティブプラグイン基盤と MethodChannel ハンドラを追加する
    - CMake で `libsora_sdk.so` を生成し、MethodChannel / EventChannel によるクライアント管理を実装する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `linux/linux_bridge.c` を新規作成し、`sora_create_client` / `sora_dispose_client` とその他 `sora_*` シンボルのスタブを実装する
2. `linux/CMakeLists.txt` に `libsora_sdk.so` ターゲットを新設:
   - `linux_bridge.c` をソースに追加
   - `libwebrtc-c.a` と `libwebrtc.a` をリンク (0024 の成果物パス)
   - include パスを設定 (`third_party/libwebrtc-c/include`、`build-linux_x86_64/_deps/webrtc/include`)
   - `libwebrtc_c_api.ldflags` を `target_link_options` で適用
   - システムライブラリ `dl` / `pthread` をリンク。不足分はリンクエラーで追加
   - `fetch_native_deps.dart linux_x86_64` のビルド時起動を配線
   - `sora_sdk_bundled_libraries` に `libsora_sdk.so` を含める
3. `linux/sora_sdk_plugin.cc` の `handle_method_call` をメソッド名による分岐に拡張
4. `createClient` / `disposeClient` の実装 (クライアント ID 採番、`libsora_sdk.so` の呼び出し、EventChannel セットアップ)
5. `enumerate*` / `getVideoInputFormats` の空応答実装
6. 未実装メソッドの `FlMethodNotImplemented` 応答実装
7. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する
