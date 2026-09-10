# RPC の正常系と異常系を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-rpc-e2e-coverage
- Polished: 2026-09-10

## 目的

`rpc()` の正常応答、timeout、切断時キャンセルを E2E で確認し、JSON-RPC 経路の回帰を早期検出できるようにする。

## 優先度根拠

- `rpc()` は SDK の差別化要素でもあり、利用者の業務ロジックが直接依存する
- 正常系だけでなく timeout と disconnect cancel を保証しないと運用障害につながる
- `DataChannelController` の内部状態管理が複雑なため High とする

## 現状

- `lib/src/sora_connection.dart` は `rpc()` を `DataChannelController.rpc()` へ委譲している
- README では request / response、notification、`SoraRpcError`、disconnect 時 cancel を明記している
- 既存 E2E に RPC のプロトコル検証は存在しない（`dispose_api_guard_e2e_test.dart` は dispose 後の `StateError` 確認のみで、正常応答・timeout・切断は検証していない）
- `DataChannelController.rpc()` は notification なら `null` を返して即完了し、通常 request は timeout 時に `TimeoutException`、error response 時に `SoraRpcError`、切断時に `SoraRpcError(code: -1, message: 'Disconnected')` で完了する
- `lib/src/ffi/webrtc_client.dart` の `_onDataChannelFromBridge` は offer で払い出された `rpc` ラベルを `_setupRpcDataChannel` に振り分け、`_rpcDc.dc` が null の間は `sendRpcMessage` が送信を行わない。`rpc_methods` の内容は SDK の有効化判定には使われておらず、払い出しのゲートは Sora サーバー側の挙動である

## 環境前提

RPC 機能は認証成功時に `rpc_methods` を払い出す必要がある。js-sdk の E2E (`e2e-tests/rpc/main.ts` の `privateClaims`) では、**テストサーバー固有の機能**として JWT の private claims に `rpc_methods` を埋め込み、サーバー側がこれを検証して認証成功時の払い出しに反映している。iOS SDK / Android SDK の RPC E2E も同一方式であり、本 issue もこれに倣う。**通常の Sora では本テストは動作しない**。

- `rpc_methods`: テスト対象メソッドの一覧 (例: `["2025.2.0/RequestSimulcastRid"]`)
- テスト対象メソッドが必要とする claims (例: `simulcast`、`simulcast_request_rid`、`simulcast_rpc_rids`)

また、接続先 Sora の設定で `data_channel_signaling` と `data_channel_rpc` が有効であること。

## 着手時の確認タスク

1. 接続先サーバーが JWT の private claims を検証し、認証成功時の `rpc_methods` 払い出しに反映するか確認する。iOS SDK / Android SDK の RPC E2E が使うテストサーバーと同じであることを確認し、対応済みならそのまま利用する
2. Flutter には JWT 生成機能がないため、テストコード内で HS256 JWT を生成する実装が必要。既に transitive 依存で導入済みの `crypto` パッケージを利用し (`e2e_test_app` の dev_dependencies へ直接依存として明示)、Hmac 署名で JWT を生成する。署名鍵は専用の `TEST_RPC_SECRET_KEY` を使い、`buildChannelId` で生成したチャンネル ID を payload の `channel_id` に埋め込む。生成した JWT は `metadata` に直接設定する（既存 E2E の `metadataFromSecretKey` は `TEST_SECRET_KEY` を metadata 値として扱うため流用しない）

## 設計方針

- この issue は **server との RPC DataChannel 契約** に限定する。peer-to-peer DataChannel の基本疎通は `0016` に委譲する
- RPC は server 実装依存が強いため、メソッド名や期待レスポンスを環境変数で注入する方針を固定する
- 次の環境変数を `e2e_test_app/README.md` に定義し、テストコードへベタ書きしない
  - `TEST_RPC_SECRET_KEY`: HS256 JWT の署名鍵。既存 E2E が metadata 値として使う `TEST_SECRET_KEY` とは別にする
  - `TEST_RPC_SUCCESS_METHOD` / `TEST_RPC_SUCCESS_PARAMS_JSON` / `TEST_RPC_SUCCESS_EXPECTED_JSON`: 正常応答用
  - `TEST_RPC_TIMEOUT_METHOD`: 応答しないメソッド。サーバー側で応答しない契約にすること
  - `TEST_RPC_NOTIFICATION_METHOD`: notification 用
  - `TEST_RPC_ERROR_METHOD` / `TEST_RPC_ERROR_EXPECTED_CODE` / `TEST_RPC_ERROR_EXPECTED_MESSAGE` / `TEST_RPC_ERROR_EXPECTED_DATA_JSON`: error response 用（任意）
- RPC 実行権限 (`rpc_methods` 払い出し) は **JWT 発行** により解決する。テストコード内で HS256 JWT を生成し、private claims の `rpc_methods` にテスト対象メソッドを含めて接続する (iOS SDK / Android SDK の RPC E2E と同一方式)
- 正常応答、timeout、接続中断による失敗、notification を別 test case として分ける
- timeout は `TimeoutException` を主契約として扱い、error response を返す server シナリオを持てる場合のみ `SoraRpcError` の別 test を追加する
- スキップ判定: `TEST_RPC_SECRET_KEY` または `TEST_RPC_SUCCESS_METHOD` が未設定の場合は接続前にスキップする。設定済みでも offer の `rpc_methods` にテスト対象メソッドが含まれない場合はスキップする (iOS SDK の offer 判定パターン)
- E2E は CI では実行せず、`TEST_RPC_*` を設定したローカル検証に限定する。`e2e-test.yml` の matrix には登録しない

## 完了条件

- `rpc()` 正常応答の E2E がある
- `timeout` 指定時に `TimeoutException` を返す E2E がある
- 待機中 RPC が `disconnect()` で `SoraRpcError(code: -1, message: 'Disconnected')` として失敗完了する E2E がある
- notification が `null` を返して即完了する smoke test がある
- server が error response を返せる場合は `SoraRpcError` の test が追加されている
- 前提条件 (`TEST_RPC_*` の設定、JWT private claims による `rpc_methods` 払い出し) を満たさない環境ではテストがスキップされること
- 環境変数の定義は `e2e_test_app/README.md` に集約されていること

## pending 理由

本 issue の E2E テストは実サーバーの RPC 契約と認証情報が必要で、CI では実行せずローカル検証に限定する方針となった。認証情報 (RPC 実行権限) は JWT 発行により解決する見込みであり、テストサーバーの private claims 検証対応が確認でき次第、自動実行できる検証基盤の整備に合わせて reopened する。

## reopened 理由

pending としていた理由のうち「実装方法が未確定」が解決したため、open に戻す。

- RPC 実行権限 (`rpc_methods` 払い出し) は、テストコード内で HS256 JWT を生成し private claims に `rpc_methods` を含めて接続することで実装する。sora-ios-sdk の RPC E2E と同じ方式を採る
- JWT 生成に必要な `crypto` パッケージは追加の依存導入なしで使える
- E2E は CI では実行せず、`TEST_RPC_*` を設定したローカル検証に限定する。pending 理由の「自動実行できる検証基盤の整備」は再開条件から外し、CI への登録は行わない
- 接続先テストサーバーが JWT の private claims を検証し、認証成功時の `rpc_methods` 払い出しに反映することは未確認である。`## 着手時の確認タスク` に従い実装時に確認する

## 解決方法

1. 検証環境の RPC 用メソッド名、params、期待レスポンスを環境変数として定義する
2. 既に transitive 依存で導入済みの `crypto` パッケージを `e2e_test_app` の dev_dependencies へ直接依存として明示し、テストコード内で HS256 JWT を生成する。署名鍵は `TEST_RPC_SECRET_KEY` を使い、payload には `channel_id` と private claims の `rpc_methods` を含め、生成した JWT を metadata に設定して接続する
3. 正常系 test で `rpc()` の結果が `TEST_RPC_SUCCESS_EXPECTED_JSON` と一致することを確認する
4. timeout 用 test で応答しないメソッドを `SoraRpcOptions(timeout: ...)` 付きで呼び、`TimeoutException` を確認する
5. disconnect cancel 用 test で長時間待機する RPC を発行し、完了前に `disconnect()` して `SoraRpcError(code: -1, message: 'Disconnected')` を確認する
6. notification 用 test で `SoraRpcOptions(notification: true)` を使い、戻り値が `null` で即完了することを確認する
7. server が error response を返せる場合は追加 test で `SoraRpcError` の `code` / `message` / `data` を確認する
8. offer の `rpc_methods` にテスト対象メソッドが含まれない場合はスキップする判定を入れる
9. `e2e_test_app/README.md` に RPC 用環境変数と検証前提を追記する（環境変数の定義は同ファイルに集約し、ルート `README.md` へは追記しない）
