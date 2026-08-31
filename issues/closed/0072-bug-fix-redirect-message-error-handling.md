# `_handleRedirectMessage` のシグナリング接続失敗で state 破壊と zone unhandled error が発生する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-redirect-message-error-handling
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

Sora から送られてくる `type: redirect` メッセージの処理で、サーバー由来の `location` 文字列に対する接続失敗が catch されずに zone unhandled error になり、かつ `SignalingSessionState` が中途半端な破壊状態で残るバグを修正する。

## 現状

`lib/src/sora_connection_signaling.dart` の `_SoraConnectionSignaling._handleRedirectMessage` は以下の問題を持つ。

- サーバー由来の `location` を `parseSignalingUrl()` で検証せずに `Uri.parse(location)` と `WebSocketChannel.connect(...)` へ渡す。`Uri.parse` は不正入力で `FormatException`、`WebSocketChannel.connect` は非 ws/wss スキームで `ArgumentError` を投げる。
- 例外を捕捉する try/catch は `on TimeoutException catch` のみで、上記例外は catch を素通りする。`_handleWebSocketMessage` の `await _handleRedirectMessage(payload)` から `channel.stream.listen((message) => _handleWebSocketMessage(message))` に戻るが、`listen` はコールバックが返す `Future` を discard するため、例外は Zone unhandled error として上がる。
- 例外時点で `_signalingState.webSocketChannel` / `webSocketSubscription` / `oldChannel.sink.close()` はすでに完了しており、SoraConnection は「WebSocket なし・abnormalTermination 未起動・signalingSwitched=false」の孤立状態で hang する。

比較として `_connectWebSocket` は `on TimeoutException catch` と `catch (error)` の 2 段構成で全例外を後始末し、次の URL 候補へフェイルオーバーする実装になっている。

## 設計方針

- `_handleRedirectMessage` の冒頭で `parseSignalingUrl(location)` により URL を検証し、`null` なら `_emitConnectionErrorEvent(code: SoraErrorCode.websocketError, ...)` と `_handleAbnormalTermination()` を発火して return する。
- `WebSocketChannel.connect(...)` を含む redirect 接続確立の全体を try/catch で包む。catch 節は `on TimeoutException catch` と `catch (error, stackTrace)` の 2 段構成にし、失敗時は次を保証する:
  - `_signalingState.webSocketChannel = null` / `webSocketClosedCompleter = null` の復元
  - `newChannel.sink.close()` によるチャネル解放
  - `_emitConnectionErrorEvent(code: ..., ...)` によるアプリ側への通知。タイムアウト時は既存の `SoraErrorCode.signalingCandidateTimeout`、それ以外の接続失敗は既存の `SoraErrorCode.websocketError` を使う（`signalingError` のような新規定数は追加せず、既存コードで表現する）
  - `_handleAbnormalTermination()` の起動（redirect 中の切断は異常終了として扱う）
- redirect 中の並行メッセージハンドリングは別 issue（WebSocket シグナリング順序保証）で扱う。

## 完了条件

- [x] 不正な `location`（空文字列、非 ws/wss スキーム、`Uri.parse` が throw する文字列、到達不能ホスト等）を受信しても Zone unhandled error が発生しない。
- [x] 上記シナリオで `_signalingState` が中途半端な破壊状態で残らない。
- [x] 上記シナリオで `SoraConnectionErrorEvent` が発火し、`_handleAbnormalTermination` 経由で `SoraDisconnectedState` に至る。
- [x] `_handleRedirectMessage` を exercise するユニットテストを追加する。テストは dart:io の `HttpServer` + `WebSocketTransformer` で実 WebSocket サーバーを立て、不正な `location` を送り込んで異常終了経路を検証する。テストから `_handleRedirectMessage` を呼ぶ手段が必要なら、テスト専用の公開ラッパーを `@visibleForTesting` で追加する（モックやスタブは使わない）。
- [x] `flutter analyze` と関連テストが成功する。

## 解決方法

`lib/src/sora_connection_signaling.dart` の `_handleRedirectMessage` を以下の方針で書き換えた。

- `payload['location']` を `Object?` として先に取り出し、非 String は `as String?` の同期 throw で zone unhandled error にならないよう型ガードで拒否する。
- サーバー由来の location を `parseSignalingUrl(location)` で先に検証し、`null`（空文字列 / 非 ws/wss スキーム / `Uri.tryParse` が拒否する文字列）ならその場でエラー通知して return する。型ガードと URL 検証は共通ヘルパ `_failRedirect` に集約し、`SoraConnectionErrorEvent`（`SoraErrorCode.websocketError`）発火、旧 subscription の cancel、旧 channel の `_closeFailedSignalingCandidate` による fire-and-forget close、`_completeWebSocketClosedCompleter(null)` による completer 完了、`_failConnectReady` による connect() 呼び出し側への具体的原因通知、`_handleAbnormalTermination()` の fire-and-forget 起動をまとめて行う。cancel と close は try/catch で保護し、失敗しても `_handleAbnormalTermination` に必ず到達させる。
- redirect 正常パス冒頭の「既存の WebSocket を閉じる」処理でも `cancel()` と `sink.close()` を try/catch で保護し、同期 throw で zone unhandled error が漏れることを防ぐ。
- `WebSocketChannel.connect(redirectUrl)` を含む接続確立部分の全体を try/catch で包み、`on TimeoutException` と `catch (error, stackTrace)` の 2 段構成で例外を捕捉する。共通後処理はヘルパ `_finalizeRedirectFailure` に集約し、`_signalingState.webSocketChannel` の null 化、`_completeWebSocketClosedCompleter(null)` による completer 完了と null 化、未確立 channel を hang させないよう既存 `_closeFailedSignalingCandidate`（fire-and-forget）による close、`_handleAbnormalTermination` の起動を実施する。timeout は `SoraErrorCode.signalingCandidateTimeout`、それ以外の接続失敗は `SoraErrorCode.websocketError` を使い、`signalingError` のような新規定数は追加しない。
- `_completeWebSocketClosedCompleter(null)` を先に呼ぶことで、redirect 進行中に `disconnect()` が並行して `_waitForWebSocketCloseInfo` で completer.future を握った場合でも hang しないようにする（`_connectWebSocket` の failure 経路と同じ規約）。

テストは `test/sora_connection_test.dart` に `SoraConnection._handleRedirectMessage の異常終了処理` group を追加。`dart:io` の `HttpServer` + `WebSocketTransformer` で実 WebSocket サーバー（accept / reject / hang）を立て、`SoraConnection.injectSignalingWebSocketForTest`（新規 `@visibleForTesting` ヘルパ）で redirect 起動前の実 channel を注入する。次の 6 ケースで「zone unhandled error なし」「エラーイベントが 1 件だけ」「`signalingHasActiveTransportForTest == false`」「`SoraDisconnectedState` に到達」を検証する。

- 非 String location（`42`）
- 空文字列 location
- 非 ws/wss スキーム（`http://example.com/signaling`）
- `Uri.tryParse` の scheme 判定で拒否される malformed（`:::`）
- WebSocket upgrade を 400 で拒否するサーバーへの redirect（`catch (error)` 経路）
- WebSocket upgrade に応答しないハングサーバーへの redirect（`on TimeoutException` 経路、`signalingCandidateTimeout: 500ms`）

`SoraConnection` には `handleRedirectMessageForTest`、`injectSignalingWebSocketForTest`、`signalingHasActiveTransportForTest` を `@visibleForTesting` で追加した。
