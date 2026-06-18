# Windows observer コールバックの noop スタブを本実装に置き換える

- Priority: Medium
- Created: 2026-06-18
- Completed: {YYYY-MM-DD}
- Model: DeepSeek V4 Pro
- Branch: feature/add-windows-observer-callbacks
- Polished: 2026-06-18

## 目的

`windows_bridge.c` の `webrtc_PeerConnectionObserver_cbs` に設定している 8 つの noop スタブを
macOS/iOS 版 (`apple_bridge.c`) および Android 版 (`jni_onload.c`) と同等の本実装に置き換える。

## 優先度根拠

- Medium: リモート映像・音声の受信が不可であり、DevTools の Windows 版が sendrecv 動作できない。
  ただし片方向配信（sendonly）の動作確認は可能であり、接続自体は成功する。
  0044 (devtools Windows 対応) の完了後に sendrecv テストを行うには本 issue の完了が必須となる依存関係がある。

## 現状

`windows_bridge.c` では Observer Bridge の全コールバックを noop スタブに設定している。
`OnConnectionChange` のみ本実装があるが、これも inflight 保護を備えていない。

さらに以下の点で macOS 版とギャップがある:

- `SoraObserverBridge` 構造体に同期用フィールド (`lock`, `inflight_cond`, `disposed`, `inflight_count`) が無い
- `observer_bridge_begin_use` / `observer_bridge_end_use` が無い（コールバック発火中の destroy による use-after-free の危険）
- `sora_observer_bridge_destroy` が inflight 完了待ちをせず即座に `free` する
- コールバックフィールド (`on_track` 等) が `void*` 型で定義されており、適切な関数ポインタ型がない
- `strdup_safe` / `bridge_emit_debug` 等のユーティリティ関数が無い
- `sora_observer_bridge_create` の引数 a2〜a8 が破棄されており、コールバックが保存されていない

### 現在の noop スタブ一覧

| noop 関数 | macOS 版相当 |
|---|---|
| `noop_OnStandardizedIceConnectionChange` | `bridge_on_ice_connection_change` |
| `noop_OnIceCandidate` | `bridge_on_ice_candidate` |
| `noop_OnIceCandidateError` | `bridge_on_ice_candidate_error` |
| `noop_OnTrack` | `bridge_on_track` |
| `noop_OnRemoveTrack` | `bridge_on_remove_track` |
| `noop_OnDataChannel` | `bridge_on_datachannel` |
| `noop_OnDestroy` | `noop_destroy`（macOS 版も noop のまま） |
| `noop_OnIceGatheringChange` | `bridge_on_ice_gathering_change` |

## 設計方針

### スレッド安全な Observer Bridge の構築

macOS 版の inflight 保護パターンを Windows 版に移植する。Windows では pthread が標準で利用できないため、
`CRITICAL_SECTION` + `CONDITION_VARIABLE` を使用する。

`SoraObserverBridge` に以下を追加する:

- `CRITICAL_SECTION lock`
- `CONDITION_VARIABLE inflight_cond`
- `int disposed`
- `int inflight_count`

以下のヘルパー関数を実装する:

- `observer_bridge_begin_use` — lock 取得 → disposed チェック → inflight_count 加算
- `observer_bridge_end_use` — inflight_count 減算 → disposed && count==0 なら WakeConditionVariable

### 型定義の追加

macOS 版 (`apple_bridge.c:389-405`) に合わせ、以下の typedef を追加する:

- `dart_on_state_fn`（既存）
- `dart_on_ice_candidate_fn`
- `dart_on_track_fn`
- `dart_on_remove_track_fn`
- `dart_on_datachannel_fn`
- `dart_on_debug_fn`

`SoraObserverBridge` の該当フィールドを `void*` からこれらの型に変更する。

### ユーティリティ関数の追加

- `strdup_safe` — `malloc` で文字列を複製。NULL 入力時は空文字列 `""` を返す（Dart 側で `free`）
- `bridge_emit_debug` — `on_debug` が設定されていれば Dart 側へログを送信

### コールバックの本実装化

| noop | 置換先 | 参考行 |
|---|---|---|
| `noop_OnStandardizedIceConnectionChange` | `bridge_on_ice_connection_change` | `apple_bridge.c:484-495` |
| `noop_OnIceCandidate` | `bridge_on_ice_candidate` | `apple_bridge.c:509-545` |
| `noop_OnIceCandidateError` | `bridge_on_ice_candidate_error` | `apple_bridge.c:547-571` |
| `noop_OnTrack` | `bridge_on_track` | `apple_bridge.c:573-679` |
| `noop_OnRemoveTrack` | `bridge_on_remove_track` | `apple_bridge.c:681-739` |
| `noop_OnDataChannel` | `bridge_on_datachannel` | `apple_bridge.c:900-937` |
| `noop_OnDestroy` | `noop_destroy` | `apple_bridge.c:213-215`（macOS 版同様 noop 維持） |
| `noop_OnIceGatheringChange` | `bridge_on_ice_gathering_change` | `apple_bridge.c:497-507` |
| （既存）`on_connection_change` | `bridge_on_connection_change` | `apple_bridge.c:472-482` |

各 `bridge_on_*` 関数は以下のパターンに従う:

1. `observer_bridge_begin_use` で inflight 開始、disposed なら即 return
2. webrtc_c API からデータを抽出
3. `bridge_emit_debug` でログ出力
4. 対応する Dart コールバックが設定されていれば呼び出し
5. `observer_bridge_end_use` で inflight 終了

既存の `on_connection_change` も `bridge_on_connection_change` にリネームし、
上記の inflight 保護パターンに沿って書き換える。

### `bridge_on_track` の特記事項

映像トラックと音声トラックで処理を分岐する:

- `webrtc_MediaStreamTrackInterface_kind` で kind を取得
- kind == "video" の場合: `AddRef` してビデオトラックを Dart に渡す。callback 未登録時は C 側で `Release`
- kind == "audio" の場合: track_ref=NULL で Dart に通知
- それ以外の kind: 通知せず debug ログのみ出力
- `strdup_safe` で複製した文字列は Dart 側に所有権移譲、Dart 側で `free`。callback 未登録時は C 側で `free`

### `OnDataChannel` と DataChannel Observer

`OnDataChannel` コールバックは本実装するが、**DataChannel の state change / message の購読に必要な `sora_observer_bridge_setup_dc` と `sora_observer_bridge_destroy_dc` の本実装は本 issue のスコープ外**とする。DataChannel の受信機能は後続 issue で対応する。

### `sora_observer_bridge_create` の変更

- 引数 a1 〜 a9 を適切な型に変更し、`(void)` キャストで破棄せず全引数を Bridge 構造体に保存する
- cbs の各フィールドを対応する `bridge_on_*` 関数に設定する

### `sora_observer_bridge_destroy` の変更

macOS 版 (`apple_bridge.c:1063-1091`) と同様の 4 段階の破棄手順に書き換える:

1. `disposed` フラグを立て、新規コールバックの進入を阻止
2. lock を解放後に `webrtc_PeerConnectionObserver_delete` を呼び出す（デッドロック回避）
3. `inflight_count` が 0 になるまで `SleepConditionVariableCS` で待機
4. `DeleteCriticalSection` で mutex/cond を破棄し `free(b)`

### 対応しないもの

- `sora_observer_bridge_setup_dc` / `sora_observer_bridge_destroy_dc` の本実装（後続 issue）
- `DcBridgeContext` 構造体とその同期機構（後続 issue）

## 完了条件

- `windows_bridge.c` の全 noop スタブが macOS 版相当の `bridge_on_*` に置き換わること
- `SoraObserverBridge` に同期フィールドが追加され、全コールバックが inflight 保護されること
- `sora_observer_bridge_destroy` が inflight 完了待ちを行う安全な破棄手順に変更されること
- `sora_observer_bridge_create` が全引数を適切な型で受け取り保存すること
- `strdup_safe` / `bridge_emit_debug` / `observer_bridge_begin_use` / `observer_bridge_end_use` が実装されること
- `flutter build windows --release` が成功すること
- devtools の Release ビルドで Connect 後にリモート映像を受信できること（実機または仮想カメラで確認）

## 解決方法

### 変更対象

- `windows/windows_bridge.c`

### 参考実装

- `macos/sora_sdk/Sources/CWebrtc/apple_bridge.c`
  - 型定義: L389-405
  - `noop_destroy`: L213-215
  - `observer_bridge_begin_use` / `_end_use`: L430-450
  - `strdup_safe`: L453-461
  - `bridge_emit_debug`: L464-468
  - `bridge_on_connection_change`: L472-482
  - `bridge_on_ice_connection_change`: L484-495
  - `bridge_on_ice_gathering_change`: L497-507
  - `bridge_on_ice_candidate`: L509-545
  - `bridge_on_ice_candidate_error`: L547-571
  - `bridge_on_track`: L573-679
  - `bridge_on_remove_track`: L681-739
  - `bridge_on_datachannel`: L900-937
  - `sora_observer_bridge_create`: L943-985
  - `sora_observer_bridge_destroy`: L1063-1091
- `android/src/main/cpp/jni_onload.c` — 同一パターンの Android 実装
