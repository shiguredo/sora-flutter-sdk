# Windows に DataChannel Observer ブリッジを実装する

- Priority: Medium
- Created: 2026-06-18
- Completed: {YYYY-MM-DD}
- Model: DeepSeek V4 Pro
- Branch: feature/add-windows-dc-observer-bridge
- Polished: 2026-06-18

## 目的

`windows_bridge.c` の `sora_observer_bridge_setup_dc` / `sora_observer_bridge_destroy_dc` の noop スタブを
macOS/iOS 版 (`apple_bridge.c`) と同等の本実装に置き換える。

## 優先度根拠

- Medium: 0045 で `OnDataChannel` コールバックは本実装化されたが、DataChannel の state change / message を Dart 側に通知するには本 issue の完了が必須。ただし devtools の sendrecv 動作には不要であり、blocker ではない。

## 現状

`windows_bridge.c` の `sora_observer_bridge_setup_dc` と `sora_observer_bridge_destroy_dc` は noop スタブであり、
呼び出されても何もせず NULL を返す／何も解放しない。

macOS 版 (`apple_bridge.c:992-1061`) と比較して以下の不足がある:

- `DcBridgeContext` 構造体が未定義（Windows 版には存在しない）
- CRITICAL_SECTION + CONDITION_VARIABLE による同期機構がない
- `DataChannelObserver` の生成・登録・解除・解放がない
- `bridge_on_datachannel` は本実装済みだが、受け取った DataChannel を購読するための仕組みがない

## 設計方針

macOS 版 (`apple_bridge.c:787-893, 992-1061`) の実装を Windows に移植する。
ただし pthread の代わりに CRITICAL_SECTION + CONDITION_VARIABLE を使用する（0045 と同じ方針）。

### 追加するもの

- `DcBridgeContext` 構造体（macOS `apple_bridge.c:806-820` 相当）
  - `SoraObserverBridge* bridge`
  - `struct webrtc_DataChannelInterface* dc`
  - `char* label`
  - `struct webrtc_DataChannelObserver* observer`
  - `dart_on_dc_state_fn on_state_change`
  - `dart_on_dc_message_fn on_message`
  - `void* dart_user_data`
  - `CRITICAL_SECTION lock`
  - `CONDITION_VARIABLE inflight_cond`
  - `int disposed`
  - `int inflight_count`
- `dc_bridge_begin_use` / `dc_bridge_end_use` ヘルパー
- `bridge_dc_on_state_change` コールバック（macOS `apple_bridge.c:845-860` 相当）
  - 注意: state の実値を Dart 側に渡さず、「変化があった」ことのみ通知する。
    Dart 側は必要に応じて別途 `webrtc_DataChannelInterface_state()` をクエリする設計
- `bridge_dc_on_message` コールバック（macOS `apple_bridge.c:862-893` 相当）
- `datachannel_state_to_string` ユーティリティ

### `sora_observer_bridge_setup_dc` の実装

macOS `apple_bridge.c:992-1024` 相当。戻り値は `DcBridgeContext*`（現状の `void*` スタブから具体型に変更するが、
Dart FFI バインディングは `Pointer<Void>` で受けるため ABI 互換性に影響はない）。

引数:
- `SoraObserverBridge*`
- `struct webrtc_DataChannelInterface*`（Dart 側から渡されたポインタ、既に AddRef 済み）
- `dart_on_dc_state_fn`
- `dart_on_dc_message_fn`
- `void* dart_user_data`

`DataChannelObserver_cbs.OnDestroy` には既存の `noop_destroy`（`windows_bridge.c:448`）を再利用する。

### `sora_observer_bridge_destroy_dc` の実装

macOS `apple_bridge.c:1028-1061` 相当。安全な 4 段階破棄手順:
1. `disposed = 1` で新規コールバック抑止
2. lock 解放後に `UnregisterObserver`
3. `inflight_count == 0` まで `SleepConditionVariableCS` で待機
4. `webrtc_DataChannelObserver_delete` → `DeleteCriticalSection` → `free(ctx->label)` → `free(ctx)`

注意: `ctx->label` は `strdup_safe` で確保されるため、`free(ctx)` の前に明示的に解放すること。

`bridge_on_datachannel`（既存の DataChannel 受信コールバック）は修正不要。
Dart 側が受け取った DataChannel ポインタを後で `sora_observer_bridge_setup_dc` に渡す設計のため、現状の実装を維持する。

### エッジケースと注意点

- `bridge_dc_on_message` 内の `malloc` 失敗時は、メッセージをドロップしデバッグログを出力して return する（macOS 版 `apple_bridge.c:880-888` 相当）
- `destroy_dc` に渡される `ctx` が NULL の場合は即 return（macOS 版 `apple_bridge.c:1031` 相当）
- `destroy_dc` に渡される `dc` が NULL の場合、`UnregisterObserver` をスキップする
- `destroy_dc` 内で `ctx->observer` が NULL の場合も `UnregisterObserver` をスキップする
- 同一 `dc` に対する `setup_dc` の複数回呼び出しは想定しない（呼び出し側の Dart が二重登録を防止する）
- `sora_observer_bridge_destroy`（ブリッジ全体の破棄）が先に呼ばれた場合、`DcBridgeContext` の破棄漏れに注意する

### 型定義の追加

以下の順序で `windows_bridge.c` に追加する（macOS 版 `apple_bridge.c:787-820` の定義順に従う）:

1. `datachannel_state_to_string` ユーティリティ（`apple_bridge.c:787-798` 相当）
2. `dart_on_dc_state_fn` typedef（`apple_bridge.c:800` 相当）
3. `dart_on_dc_message_fn` typedef（`apple_bridge.c:801-804` 相当）
4. `DcBridgeContext` 構造体（`apple_bridge.c:806-820` 相当）

挿入位置は `sora_observer_bridge_create`（`windows_bridge.c:464`）の直前
（既存 observer bridge コールバック群の末尾）。
`dc_bridge_begin_use` / `dc_bridge_end_use` および各コールバック関数は
`DcBridgeContext` 構造体の直後に、macOS 版と同じ相対配置で追加する。

typedef シグネチャ:

- `dart_on_dc_state_fn`: `typedef void (*dart_on_dc_state_fn)(void* user_data);`
- `dart_on_dc_message_fn`: `typedef void (*dart_on_dc_message_fn)(const uint8_t* data_copy, int32_t len, int32_t is_binary, void* user_data);`

戻り値は既存の Windows コードスタイルに合わせ `int`（`bool` ではなく `int`）を使用し
`<stdbool.h>` は追加しない。

### 実装順序（推奨）

1. `datachannel_state_to_string` 追加
2. `dart_on_dc_state_fn` / `dart_on_dc_message_fn` typedef 追加
3. `DcBridgeContext` 構造体追加
4. `dc_bridge_begin_use` / `dc_bridge_end_use` 追加（CRITICAL_SECTION + CONDITION_VARIABLE 版）
5. `bridge_dc_on_state_change` / `bridge_dc_on_message` 追加
6. `sora_observer_bridge_setup_dc` 本実装化
7. `sora_observer_bridge_destroy_dc` 本実装化

各ステップ完了後に `flutter build windows --release` でコンパイル確認すること。

## 変更対象

- `windows/windows_bridge.c`

## 後方互換

現在の Windows 版スタブは全引数 `void*` で定義されているが、本実装後は macOS 版に合わせて具体型（`DcBridgeContext*`, `struct webrtc_DataChannelInterface*` 等）に変更する。
Dart 側の FFI バインディング（`bindings.dart:3147-3164`）は既に macOS 版のシグネチャで記述されており、ABI 互換性に問題はない。

また、Dart 側の `_cleanupSingleDataChannel`（`webrtc_client.dart:1702-1717`）は ctx が NULL の場合に `dataChannelUnregisterObserver` をフォールバックとして呼ぶが、本実装後は ctx が NULL にならないためこのパスは通らなくなる。影響はない。

## 完了条件

- `windows_bridge.c` に `DcBridgeContext` 構造体と同期機構が追加されること
- `sora_observer_bridge_setup_dc` / `sora_observer_bridge_destroy_dc` が macOS 版相当の本実装になること
- `DcBridgeContext` の label が `destroy_dc` で解放されること（メモリリーク防止）
- `flutter build windows --release` が成功すること
- Windows 版 devtools（またはサンプルアプリ）の sendrecv 動作で、DataChannel の state change 通知と message 受信が Dart 側に到達すること（手動確認で可）
  - 本条件は本 issue の完了条件とは独立しており、0016 未完了でも完了と判定してよい
  - カスタム DataChannel の E2E テスト（0016）が整備され次第、そちらでも自動検証する
