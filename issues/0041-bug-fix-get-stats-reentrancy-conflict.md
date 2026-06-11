# getStats の再入競合で StateError が送出される問題の修正

- Priority: High
- Created: 2026-06-11
- Branch: feature/fix-get-stats-reentrancy-conflict
- Polished: 2026-06-11

## 目的

同一 `SoraConnection` 上で public API の `getStats()` と SDK 内部の stats 応答処理が競合した場合でも、`StateError('getStats() is already in progress.')` が送出されないようにする。接続そのものは切断されず継続するが、`StateError` が E2E テストのアサーション失敗や unhandled exception の原因となっている。

## 優先度根拠

- 2026-06-09 の GitHub Actions run `27199543723`（macOS 環境）において、`local media toggle` の `Run integration test` が `Bad state: getStats() is already in progress.` で失敗した
- 失敗は `setVideoEnabled()` 自体ではなく、SDK の内部処理と public API の競合で発生しており、通常の接続継続中にも再現しうる
- `getStats()` は E2E、デバッグ、状態監視で広く使う API であり、同一接続上の競合で簡単に落ちる状態は回帰監視と利用者双方に影響が大きいため High
- 注意: この競合はタイミング依存であり常時再現するわけではない。再現確率はサーバーからの `ping(stats: true)` 間隔と public API の呼び出しタイミングに依存する

## 現状

- `SoraConnection.getStats()` は `WebrtcClient.getStats()` に委譲している（`lib/src/sora_connection.dart:662`）
- `lib/src/ffi/webrtc_client.dart:709-781` の `getStats()` は `_pendingStatsCompleter`、`_pendingStatsCbsPtr`、`_pendingStatsNativeCallable` を使って単一進行中スロットを管理しており、進行中に再度呼ばれると `StateError('getStats() is already in progress.')` を投げる
- SDK 内部でも同じ `WebrtcClient.getStats()` を呼ぶ経路がある
  - `lib/src/sora_connection_signaling.dart:120` の WebSocket `ping` with stats 応答（try-catch なし。`StateError` は unhandled exception となり、Dart の `Stream.listen` 経由でテスト失敗に直結する）
  - `lib/src/sora_data_channel_controller.dart:581` の stats DataChannel `req-stats` 応答（広い `catch` で握るが競合解消はしていない。catch 対象も `json decode failed` というラベルが不正確）
- そのため、同一 `SoraConnection` で以下の順序が起こると競合する
  1. public API の `connection.getStats()` が進行中
  2. その間に内部の ping / req-stats 応答が `getStats()` を呼ぶ
  3. あるいは内部 `getStats()` が進行中の間に public API が `getStats()` を呼ぶ
  4. 後から呼ばれた側が `StateError` で失敗する
- GitHub Actions の失敗ログでは `e2e_test_app/integration_test/local_media_toggle_e2e_test.dart` の video test で `sender.connection.getStats()` が失敗している
- 現状の内部ハンドリングは不十分
  - WebSocket `ping(stats: true)` 経路は try-catch がなく、`StateError` が unhandled になる
  - stats DataChannel `req-stats` 経路は広い `catch` で握るが、待ち合わせ、再試行、stats なし応答などの競合解消を行っていない

## 設計方針

- 問題の本質は E2E テストではなく、同一 `WebrtcClient` に対して `getStats()` を多重実行できないことにある。そのため、テスト側の回避ではなく SDK 側で吸収する
- 少なくとも同一 `WebrtcClient` に対する複数 `getStats()` 要求を `StateError` で即失敗させる挙動をやめる
- **Future 共有方式を採用する**: 進行中の `getStats()` がある場合、新規要求は進行中の Future を共有して同じ結果を await する。直列化方式は以下の理由で採用しない
  - 直列化方式は timeout 後の callback 未到達期間（`cleanupPendingStatsRequest()` の制約により `_pendingStatsCbsPtr` / `_pendingStatsNativeCallable` が残ったままになる期間）中にキューが詰まる問題がある
  - 複数の `RTCStatsCollectorCallbackCbs` と `NativeCallable` の同時管理が必要になり、既存の単一スロット設計からの変更範囲が大きい
  - `closePeerConnection()` での後始末が複雑になる（キュー内の全要求を error completion する処理が必要）
- **Future 共有の詳細**: 要求到着時に進行中でなければ新しい `pcGetStats` を発行し、進行中なら `_pendingStatsCompleter.future` を返す。これにより timeout 後の callback 未到達期間中も新しい `pcGetStats` 発行は発生せず、キュー詰まりが起きない
- **競合時のフォールバック**: timeout 後に `_pendingStatsCbsPtr` / `_pendingStatsNativeCallable` が残っている状態で `_pendingStatsCompleter` が null の場合（timeout により completer が解放された後）、`getStats()` は直ちに `null` を返す（新たな `pcGetStats` を発行せず、古い callback が到着するのを待たない）
- `ping(stats: true)` と `req-stats` の内部経路は、競合時に例外で落ちるのではなく、stats なしの応答でフォールバックし、接続継続を壊さないようにする
- **内部経路ごとのフォールバック動作**:
  - `ping(stats: true)`: `getStats()` から `null` が返された場合、`stats` フィールドを含まない `pong` メッセージを送信する
  - `req-stats`: `getStats()` から `null` が返された場合、`reports` フィールドを含まない `stats` メッセージを送信する
- timeout と native callback の後始末制約は既存実装の重要条件であるため、`lib/src/ffi/webrtc_client.dart` の timeout / cleanup ロジックを壊さない設計にする。具体的には以下の方針とする
  - timeout 後も `_pendingStatsCbsPtr` / `_pendingStatsNativeCallable` は解放しない（遅延 callback 到着時の UAF 防止）
  - ただし、当該期間中に `getStats()` が呼ばれた場合は Future 共有対象となる Future がないため `null` を返すフォールバックパスを通す
- **public API の優先順位**: public API `connection.getStats()` と内部経路は Future 共有により対等に扱う。内部経路の要求が public API の応答を遅延させることはない（同じ Future を待つだけ）。public API のタイムアウトは 5 秒で切られる
- **切断との競合**: `disconnect()` / `dispose()` 中の `getStats()` は既存のガード（`_disposed || _pcRef == null`）で `null` を返す。`closePeerConnection()` は `cleanupPendingStatsRequest()` で単一 Completer のみを処理する（Future 共有方式では複数 Completer が存在しないため既存ロジックで十分）
- `SoraConnection.getStats()`（`lib/src/sora_connection.dart:660`）は `WebrtcClient.getStats()` に委譲するのみで、変更不要
- **後方互換性**: 現状 `getStats()` 進行中に呼ばれると `StateError` が送出されていたが、修正後は Future 共有または `null` 返却となる。`StateError` の try-catch に依存するコードは影響を受けるが、そのような利用パターンは SDK の想定範囲外である
- 修正後は、同一 `SoraConnection` 上で public API と内部経路が競合しても回帰しないことをテストで固定する

## 完了条件

- 同一 `SoraConnection` で `getStats()` が重なっても `StateError('getStats() is already in progress.')` が利用者へ露出しない
- public API の `connection.getStats()` 実行中に、内部の WebSocket `ping(stats: true)` または stats DataChannel `req-stats` が走っても接続処理が壊れない
- 内部の stats 応答処理（ping / req-stats）が競合時に無言で異常終了せず、設計方針に従ったフォールバック動作（stats なし pong / stats メッセージ）を行う
- `local_media_toggle_e2e_test.dart` を含む stats 利用 E2E テスト群（`recvonly_e2e_test.dart`、`sendrecv_smoke_e2e_test.dart`、`sendonly_dummy_video_e2e_test.dart`）で回帰がないこと
- 競合を再現するテストが追加され、修正前は失敗し修正後は通ることを確認できる。再現方法は以下を想定
  - `setupPendingStatsForTest()`（`webrtc_client.dart:700`）を利用し、強制的にスロット占有状態を作った上で `getStats()` を呼び出す unit test
  - unit test では `StateError` ではなく `null` または Future 共有が発生することを確認する

## 解決方法

1. `lib/src/ffi/webrtc_client.dart` の `getStats()` 実装を見直し、同一インスタンス上の複数要求を Future 共有で扱えるようにする（`_pendingStatsCompleter` が非 null の場合、新規要求はその future を返す）。timeout 後に completer が解放された後は `null` を返すフォールバックパスを追加する
2. `lib/src/sora_connection_signaling.dart` の `ping(stats: true)` 応答経路で、`getStats()` の呼び出しを try-catch で囲み、`null` が返された場合は `stats` フィールドを含まない `pong` を送信する
3. `lib/src/sora_data_channel_controller.dart` の `req-stats` 応答経路で、`getStats()` から `null` が返された場合のフォールバック処理（`reports` を含まない stats メッセージの送信）を追加する。catch 句のラベルも実態に合わせて修正する
4. `test/` 配下に unit test を追加する。`setupPendingStatsForTest()` で強制的にスロット占有状態を作り、`getStats()` が `StateError` ではなく Future 共有または `null` を返すことを確認する
5. 既存の stats 利用 E2E テスト群（`local_media_toggle_e2e_test.dart`、`recvonly_e2e_test.dart`、`sendrecv_smoke_e2e_test.dart`、`sendonly_dummy_video_e2e_test.dart`）で回帰がないことを確認する
