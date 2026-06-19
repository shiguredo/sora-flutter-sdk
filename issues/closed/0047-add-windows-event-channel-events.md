# Windows EventChannel イベント送出を実装する

- Priority: Medium
- Created: 2026-06-19
- Completed: 2026-06-19
- Model: DeepSeek V4 Pro
- Branch: feature/add-windows-event-channel-events
- Polished: 2026-06-19

## 目的

Windows プラグインの EventChannel が listen / cancel ライフサイクルに応答するだけで、実際のイベント（`camera_open_error`、`audio_init_failed` 等）を Dart 側へ一切送出していない問題を解決する。カメラや音声の初期化失敗をアプリケーションが検知できず、エラーハンドリングが機能しない。

## 優先度根拠

- Medium: カメラ・音声の初期化失敗がアプリケーションに通知されないため、ユーザーへのフィードバックが不可能。正常系では問題ないが、異常系の UX が損なわれる。Windows 版の製品品質に影響するため中期的に対応が必要。

## 現状

`windows/sora_sdk_plugin.cpp:115-133` の EventChannel ハンドラは listen / cancel のみに応答し、BinaryMessenger 経由のイベント送出機構を持たない。

```cpp
messenger_->SetMessageHandler(
    event_channel_name,
    [](const uint8_t* data, size_t size, flutter::BinaryReply reply) {
      // listen / cancel に応答するが、イベント送出は行わない
    });
```

`windows/sora_sdk_plugin.h:30-33` の `ClientWrapper` は `client_id` と `event_channel_name` しか持たず、イベント送出用のハンドルが存在しない。

他プラットフォームとの比較:
- Android: `SoraClientWrapper.eventSink` (EventChannel.EventSink) を持ち、`camera_open_error` を送出可能
- iOS: `SoraClientWrapper.eventSink` (FlutterEventSink) を持ち、`audio_init_failed` を送出可能（`emitAudioInitError()`）

## 設計方針

### 実装方針

flutter::EventChannel クラスは Windows C++ ラッパーに存在しないため、BinaryMessenger の `Send()` メソッドを直接使用する。Dart 側の `EventChannel.receiveBroadcastStream()` は BinaryMessenger のバイナリメッセージを `StandardMethodCodec` でデコードする。従ってネイティブ側も `StandardMethodCodec::EncodeSuccessEnvelope()` でエンコードしたデータを `BinaryMessenger::Send()` で送信することで、Dart 側の StreamHandler が正しくイベントを受信できる。

`BinaryMessenger::Send()` はスレッドセーフに設計されており、プラットフォームスレッド以外からも呼び出し可能である。プロジェクトの Flutter SDK 要件（`>=3.44.0`）において `BinaryMessenger::Send()` は安定した API であり、バージョン間のシグネチャ変更は確認されていない。

### ClientWrapper にイベント送出機構を追加する

`ClientWrapper` に以下のメンバを追加する:

1. `flutter::BinaryMessenger* messenger` — イベント送出先のメッセンジャー。コンストラクタで受け取る。
2. `void sendEvent(flutter::EncodableMap event)` — `StandardMethodCodec::EncodeSuccessEnvelope()` でエンコードし、`messenger_->Send(event_channel_name_, data, size, nullptr)` で fire-and-forget 送信する。reply には `nullptr` を渡す（Dart 側は応答を期待しない）。
3. `std::atomic<bool> event_sink_active` — listen/cancel 状態を管理するアトミックフラグ。

`event_sink_active` は `std::atomic<bool>` とし、プラットフォームスレッドとカメラ/audio スレッドの間でデータ競合を起こさないようにする。

### イベントフォーマット

Dart 側 `sora_connection.dart` の `_handlePlatformEvent` が受け取る Map と一貫性を持たせるため、以下の形式で送出する:

```
{
  "type": "camera_open_error",
  "errorCode": <int>,
  "attempts": <int>
}
```

```
{
  "type": "audio_init_failed",
  "code": "audio_input_initialization_failed",
  "message": "<error description>"
}
```

本 issue のスコープは送出インターフェースの実装までとし、`camera_open_error` の実際の送出は 0050 で対応する。`audio_init_failed` の実際の送出は windows_bridge.c 連携が必要なため後続対応とする。

### イベント購読状態の管理

Dart 側の listen / cancel に応じて `event_sink_active` を切り替える。購読開始前に届いたイベントは破棄する（iOS の pending 方式は保留 Dictionary + if-let で実装されているが、Windows では listen 開始前にイベントが発生するシナリオが現時点で想定されないため採用しない）。

### スレッド安全性

`event_sink_active` は `std::atomic<bool>` で読み書きする。`sendEvent()` 内でフラグチェックと `Send()` の呼び出しの間に競合ウィンドウが存在するが、購読 cancel 後に数フレームのイベントが消失または無視されても実用上の問題はない（Dart 側で型エラーにならない形式で送る）。

`DisposeClient` との競合については、`clients_.erase()` の前に `messenger_->SetMessageHandler(event_channel_name, nullptr)` でハンドラを解除し、その後 `clients_` から削除する。削除後に他スレッドが `sendEvent()` を呼べない設計とする（`ClientWrapper` の生存期間は `clients_` の所有権に紐づく）。

### 0048 との競合

本 issue と 0048 はともに `HandleCreateClient()` の `ClientWrapper` 初期化部分を変更する。実装順序によってマージコンフリクトが発生しうるため、先に実装された側の変更をベースに解消する想定とする。

## 完了条件

- `ClientWrapper` が BinaryMessenger 経由で StandardMethodCodec success envelope を Dart 側へ送出できること
- `audio_init_failed` イベント形式の Map を `sendEvent()` に渡したとき、Dart 側 `EventChannel` の StreamHandler が正しくイベントを受信できること
- `event_sink_active` が `std::atomic<bool>` で実装され、listen/cancel に応じて正しく切り替わること
- `DisposeClient` でハンドラ解除後に `sendEvent()` が呼ばれないこと
- `flutter build windows --release` が成功すること
- e2e_test_app の Windows ビルドでカメラまたは音声を使用した接続テストでイベントパスが動作すること（実機または仮想カメラで確認）

## 解決方法

### 変更対象

- `windows/sora_sdk_plugin.h` — `ClientWrapper` に `messenger` ポインタ、`sendEvent()`、`event_sink_active` を追加
- `windows/sora_sdk_plugin.cpp` — `HandleCreateClient` で `ClientWrapper` に `messenger` を設定、EventChannel ハンドラで listen/cancel 状態を管理、`sendEvent()` の実装

### 変更内容

1. `ClientWrapper` 構造体を拡張する:
   - `flutter::BinaryMessenger* messenger` を追加（コンストラクタで設定）
   - `std::atomic<bool> event_sink_active{false}` を追加
   - `void sendEvent(flutter::EncodableMap event)` を追加

2. `sendEvent()` の実装:
   - `event_sink_active.load()` が false なら即座に return
   - `flutter::StandardMethodCodec::GetInstance().EncodeSuccessEnvelope(event)` でバイナリデータを生成
   - `messenger_->Send(event_channel_name_, data.data(), data.size(), nullptr)` で fire-and-forget 送信

3. EventChannel ハンドラ:
   - 現在のステートレスラムダを `ClientWrapper*` をキャプチャする形に変更
   - `listen` 時に `wrapper->event_sink_active.store(true)`
   - `cancel` 時に `wrapper->event_sink_active.store(false)`
   - ハンドラ登録は `wrapper->event_channel_name` に対して行う

4. `HandleDisposeClient`:
   - `messenger_->SetMessageHandler(event_channel_name, nullptr)` で先にハンドラを解除
   - その後 `clients_.erase()` で `ClientWrapper` を破棄

### テスト戦略

AGENTS.md の「モックやスタブは絶対に利用しないこと」に従い、以下の方法で動作確認する:
- e2e_test_app の Windows ビルドで実際にカメラ/マイクを使用した接続テストを実行
- カメラが存在しない環境では仮想カメラ（OBS Virtual Camera 等）で代替
- イベント受信を確認するため、Dart 側の `_handlePlatformEvent` にログ出力を追加してデバッグビルドで検証

### 参考実装

- Android: `SoraSdkPlugin.kt:427-435` — `eventSink.success()` を使ったイベント送出
- iOS: `SoraFlutterMessageHandler.swift:150-159` — `emitAudioInitError()` の実装
