# Windows カメラキャプチャ失敗時のエラー通知を実装する

- Priority: Low
- Created: 2026-06-19
- Completed: {YYYY-MM-DD}
- Model: DeepSeek V4 Pro
- Branch: feature/add-windows-camera-capturer-error-events
- Polished: 2026-06-19

## 目的

`SoraCameraCapturer::CaptureLoop()` でカメラキャプチャの初期化に失敗した場合、`running_` フラグを false に設定してスレッドが終了するだけで、Dart 側に一切エラーが通知されない。カメラが利用できない状況でユーザーに何もフィードバックがなく、サイレントに映像送信が行われない。

## 優先度根拠

- Low: カメラキャプチャの失敗は稀なケース（デバイスが存在しない、排他ロックされている等）であり、正常系のユーザー体験には影響しない。ただし異常系のデバッグを困難にするため、対応が望ましい。
- 本 issue は 0047 (Windows EventChannel イベント送出の実装) の完了後に着手可能。

## 現状

`windows/sora_camera_capturer.cpp:266-297` の `CaptureLoop()` は以下の 5 箇所でエラーが発生するが、いずれもサイレント終了する:

```cpp
if (FAILED(CoInitializeEx(...))) {  // ① COM 初期化失敗
    running_ = false; return;
}
if (FAILED(MFStartup(...))) {       // ② MF 初期化失敗
    running_ = false; return;
}
if (!CreateMediaSource()) {         // ③ メディアソース作成失敗（デバイス不在等）
    running_ = false; return;
}
if (!CreateSourceReader()) {        // ④ SourceReader 作成失敗
    running_ = false; return;
}
if (!SetCurrentMediaType()) {       // ⑤ メディアタイプ設定失敗
    running_ = false; return;
}
```

他プラットフォームとの比較:
- Android: `SoraCameraCapturer` は `onCameraOpenError` コールバックを持ち、`eventSink.success()` で `camera_open_error` イベントを送出する (`SoraSdkPlugin.kt:427-435`)

## 設計方針

### エラーコールバックの追加

`SoraCameraCapturer` にエラー通知用のコールバックフィールドを追加する。CaptureLoop 内の全 5 箇所の失敗ポイントでコールバックを呼び出す。

コールバックの型は `std::function<void(int errorCode)>` とし、`attempts` パラメータは持たない（本 issue ではリトライ機構を実装しないため、Android 互換の `attempts` は常に 1 固定になり無意味なため）。

### クライアント特定方法

`HandleEnsureLocalVideoTrackTexture()` は MethodCall の引数から `clientId` を取得する。Dart 側 `sora_media_device_platform.dart:136` は既に `clientId` を送信しているが、Windows C++ 側はこれをパースしていない。本 issue でパース処理を追加する。

コールバックの実装方針:
1. `HandleEnsureLocalVideoTrackTexture()` で `clientId` をパースする
2. コールバック内で `clients_[clientId]` を検索し、存在すれば `sendEvent()` を呼び出す
3. コールバックは `SoraCameraCapturer` の `Start()` が実行される前に設定する
4. コールバックはキャプチャスレッドから呼ばれるため、`clients_` へのアクセスは `capturers_` の生存期間に依存しない設計とする（後述のスレッド安全性参照）

### スレッド安全性

コールバックはキャプチャスレッド（`CaptureLoop` 内）から呼ばれるが、コールバック自体は `std::function` に設定されたラムダであり、ラムダ内で `clients_` にアクセスする。以下の対策が必要:

1. コールバックの設定は `Start()` の前にプラットフォームスレッドで行うため、std::function の代入とキャプチャスレッドからの読み出しにデータ競合はない（代入完了後に `Start()` を呼ぶため）
2. `ClientWrapper` の生存期間とコールバック呼び出しの間に use-after-free が発生しない設計にする。以下 2 案のいずれかを採用する:
   - **推奨: `shared_ptr` / `weak_ptr` 方式**: `ClientWrapper` を `std::enable_shared_from_this<ClientWrapper>` の派生とし、`clients_` を `std::map<int64_t, std::shared_ptr<ClientWrapper>>` に変更する。コールバックは `std::weak_ptr<ClientWrapper>` をキャプチャし、`lock()` で有効性を確認してから `sendEvent()` を呼び出す。EventChannel ハンドララムダも `weak_ptr` をキャプチャするよう変更する。
   - **代替: 明示的な停止保証方式**: `HandleDisposeClient()` 内で先に該当 `SoraCameraCapturer` を停止し、キャプチャスレッドの終了を待ってから `clients_` を削除する。`disposeClient` 時に `capturers_` の該当エントリも停止するよう設計を拡張する。
3. `event_sink_active` によるガードだけでは不十分である。`sendEvent()` 内の `load()` と `Send()` の間で `ClientWrapper` が破棄される可能性があるため、`weak_ptr::lock()` による生存確認を呼び出し側で行うこと。

### エラーハンドリングの実行順序

コールバックはリソース解放（`Cleanup()` / `MFShutdown()` / `CoUninitialize()`）の直前に呼び出す。コールバック呼び出し後にキャプチャスレッドは即座に終了するため、コールバック内で `sendEvent()` が呼ばれた後にリソース解放が行われる。

### errorCode の値定義

本 issue では以下の errorCode を定義する（Android のコード体系とは独立した Windows 独自のコードとする）:

| errorCode | 意味 | 発生箇所 |
|-----------|------|----------|
| 0 | COM 初期化失敗 | `CoInitializeEx` 失敗 |
| 1 | Media Foundation 初期化失敗 | `MFStartup` 失敗 |
| 2 | カメラデバイス不在またはアクセス不可 | `CreateMediaSource` 失敗 |
| 3 | SourceReader 作成失敗 | `CreateSourceReader` 失敗 |
| 4 | メディアタイプ設定失敗 | `SetCurrentMediaType` 失敗 |

Dart 側 `sora_connection.dart:1363` の `_cameraErrorCodeToName` にこれらのエラーコードの変換を追加する必要がある（ただし Dart 側の変更は本 issue のスコープ外とする）。

### 0047 との連携

0047 の `ClientWrapper::sendEvent()` を使用してイベントを送出する。コールバックでは以下の `EncodableMap` を構築して `sendEvent()` に渡す:

```cpp
flutter::EncodableMap event;
event[flutter::EncodableValue("type")] = flutter::EncodableValue("camera_open_error");
event[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
```

## 完了条件

- `SoraCameraCapturer::CaptureLoop()` の全 5 箇所の失敗ポイントで `on_camera_open_error` コールバックが呼ばれること
- コールバックの設定が `Start()` の前に行われること
- エラーイベントが正しい `errorCode` で Dart 側に到達すること
- `HandleEnsureLocalVideoTrackTexture()` が `clientId` をパースすること
- `flutter build windows --release` が成功すること
- 変更内容が `CHANGES.md` に追記されること

## 解決方法

### 変更対象

- `windows/sora_camera_capturer.h` — エラーコールバックの型定義とフィールド追加、`#include <functional>` 追加
- `windows/sora_camera_capturer.cpp` — `CaptureLoop()` 内の全失敗ポイントでコールバック呼び出し
- `windows/sora_sdk_plugin.cpp` — `HandleEnsureLocalVideoTrackTexture()` で `clientId` パースとコールバック設定
- `windows/sora_sdk_plugin.h` — `ClientWrapper` を `std::enable_shared_from_this<ClientWrapper>` に変更、`clients_` を `std::shared_ptr<ClientWrapper>` に変更、EventChannel ラムダのキャプチャを `weak_ptr` に変更
- `windows/sora_sdk_plugin.cpp` — `HandleCreateClient` / `HandleDisposeClient` / デストラクタの `clients_` 操作を `shared_ptr` 対応に修正、EventChannel ラムダで `weak_ptr::lock()` による生存確認を追加

### 変更内容

1. `sora_camera_capturer.h` に `#include <functional>` を追加する
2. `SoraCameraCapturer` に `std::function<void(int errorCode)> on_camera_open_error` フィールドを追加する（`public` セクション）
3. `CaptureLoop()` 内の 5 箇所の失敗ポイントそれぞれで、リソース解放の直前にコールバックを呼び出す（`if (on_camera_open_error) on_camera_open_error(code)`）
4. `HandleEnsureLocalVideoTrackTexture()` で `args` から `clientId` をパースする（`GetIntValue` を使用）
5. `SoraCameraCapturer` 生成後、`Start()` の前に以下のコールバックを設定する:

```cpp
int64_t client_id = GetIntValue(client_id_it->second, 0);
// clients_ は std::map<int64_t, std::shared_ptr<ClientWrapper>> に変更済みとする
capturer->on_camera_open_error = [weak_wrapper = std::weak_ptr<ClientWrapper>(clients_[client_id])](int errorCode) {
  auto wrapper = weak_wrapper.lock();
  if (!wrapper) {
    return;
  }
  flutter::EncodableMap event;
  event[flutter::EncodableValue("type")] = flutter::EncodableValue("camera_open_error");
  event[flutter::EncodableValue("errorCode")] = flutter::EncodableValue(errorCode);
  wrapper->sendEvent(event);
};
```

6. `HandleDisposeClient()` で、対象クライアントに関連する `capturers_` のエントリも停止・削除する（`video_source_ptr` から capturer を特定できるマッピングを追加する、または `capturers_` を全走査して該当 capturer を停止する）

### テスト戦略

AGENTS.md の「モックやスタブは絶対に利用しないこと」に従い、以下の方法で動作確認する:
- e2e_test_app の Windows ビルドで実際のカメラデバイスを使用した接続テストを実行
- カメラが存在しない環境では、`EnumerateDevices()` が空リストを返すため、カメラ不在時のエラーパスを暗黙的にテスト可能
- カメラを排他ロックした状態でのテストは実機での手動確認が必要
- 正常系（カメラ接続あり）でエラーイベントが送出されないことを確認

### 参考実装

- Android: `SoraSdkPlugin.kt:427-435` — `onCameraOpenError` コールバックと EventChannel 連携
