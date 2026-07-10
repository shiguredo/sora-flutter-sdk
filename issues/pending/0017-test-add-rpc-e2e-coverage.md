# RPC の正常系と異常系を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-rpc-e2e-coverage
- Polished: 2026-06-03

## 目的

`rpc()` の正常応答、timeout、切断時キャンセルを E2E で確認し、JSON-RPC 経路の回帰を早期検出できるようにする。

## 優先度根拠

- `rpc()` は SDK の差別化要素でもあり、利用者の業務ロジックが直接依存する
- 正常系だけでなく timeout と disconnect cancel を保証しないと運用障害につながる
- `DataChannelController` の内部状態管理が複雑なため High とする

## 現状

- `lib/src/sora_connection.dart` は `rpc()` を `DataChannelController.rpc()` へ委譲している
- README では request / response、notification、`SoraRpcError`、disconnect 時 cancel を明記している
- 既存 E2E に RPC 検証は存在しない
- `DataChannelController.rpc()` は notification なら `null` を返して即完了し、通常 request は timeout 時に `TimeoutException`、error response 時に `SoraRpcError`、切断時に `SoraRpcError(code: -1, message: 'Disconnected')` で完了する

## 設計方針

- この issue は **server との RPC DataChannel 契約** に限定する。peer-to-peer DataChannel の基本疎通は `0016` に委譲する
- RPC は server 実装依存が強いため、メソッド名や期待レスポンスを環境変数で注入する方針を固定する
- 例として `TEST_RPC_SUCCESS_METHOD`、`TEST_RPC_SUCCESS_PARAMS_JSON`、`TEST_RPC_SUCCESS_EXPECTED_JSON`、`TEST_RPC_TIMEOUT_METHOD`、`TEST_RPC_NOTIFICATION_METHOD` のような環境変数を README に定義し、テストコードへベタ書きしない
- 正常応答、timeout、接続中断による失敗、notification を別 test case として分ける
- timeout は `TimeoutException` を主契約として扱い、error response を返す server シナリオを持てる場合のみ `SoraRpcError` の別 test を追加する

## 完了条件

- `rpc()` 正常応答の E2E がある
- `timeout` 指定時に `TimeoutException` を返す E2E がある
- 待機中 RPC が `disconnect()` で `SoraRpcError(code: -1, message: 'Disconnected')` として失敗完了する E2E がある
- notification が `null` を返して即完了する smoke test がある
- server が error response を返せる場合は `SoraRpcError` の test が追加されている

## pending 理由

本 issue の E2E テストは実サーバーの RPC 契約と認証情報が必要で、CI では実行せずローカル検証に限定する方針となった。自動実行できる検証基盤が整うまで pending とする。

## 解決方法

1. 検証環境の RPC 用メソッド名、params、期待レスポンスを環境変数として定義する
2. 正常系 test で `rpc()` の結果が `TEST_RPC_SUCCESS_EXPECTED_JSON` と一致することを確認する
3. timeout 用 test で応答しないメソッドを `SoraRpcOptions(timeout: ...)` 付きで呼び、`TimeoutException` を確認する
4. disconnect cancel 用 test で長時間待機する RPC を発行し、完了前に `disconnect()` して `SoraRpcError(code: -1, message: 'Disconnected')` を確認する
5. notification 用 test で `SoraRpcOptions(notification: true)` を使い、戻り値が `null` で即完了することを確認する
6. server が error response を返せる場合は追加 test で `SoraRpcError` の `code` / `message` / `data` を確認する
7. `e2e_test_app/README.md` とルート `README.md` に RPC 用環境変数と検証前提を追記する
