# RPC の正常系と異常系を確認する E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-rpc-e2e-coverage
- Polished: 2026-11-11
- Refreshed: 2026-11-11

## 目的

`rpc()` の正常応答、timeout、切断時キャンセル、notification、error response を E2E で確認し、JSON-RPC 経路のローカル検証手順を確立する。RPC E2E は CI では実行しないため、自動回帰検出は対象外とする。

## 優先度根拠

- `rpc()` は SDK の差別化要素でもあり、利用者の業務ロジックが直接依存する
- 正常系だけでなく timeout と disconnect cancel を保証しないと運用障害につながる
- `DataChannelController` の内部状態管理が複雑なため High とする

## 現状

- `lib/src/sora_connection.dart` は `rpc()` を `DataChannelController.rpc()` へ委譲している
- `rpc()` の契約は `SoraConnection.rpc` の dartdoc に notification 時の `null`、`SoraRpcError`、`TimeoutException`、dispose 後の `StateError` として記載され、`skills/sora-flutter-sdk/SKILL.md` にも request / response と timeout の記載がある。ルート `README.md` は「RPC に対応」のみで、disconnect 時の `SoraRpcError(code: -1, message: 'Disconnected')` はドキュメントになく `DataChannelController.clear()` の実装のみが根拠である
- 既存 E2E に RPC のプロトコル検証は存在しない（`dispose_api_guard_e2e_test.dart` は dispose 後の `StateError` 確認のみで、正常応答・timeout・切断は検証していない）
- `DataChannelController.rpc()` は notification なら `null` を返して即完了し、通常 request は timeout 時に `TimeoutException`、error response 時に `SoraRpcError`、切断時に `SoraRpcError(code: -1, message: 'Disconnected')` で完了する
- `lib/src/ffi/webrtc_client.dart` の `_onDataChannelFromBridge` は offer で払い出された `rpc` ラベルを `_setupRpcDataChannel` に振り分け、`_rpcDc.dc` が null の間は `sendRpcMessage` が送信を行わない。`rpc_methods` の内容は SDK の有効化判定には使われておらず、払い出しのゲートは Sora サーバー側の挙動である
- 既存の `ObservedConnection` は `SoraDataChannelOpenEvent` を保持するが `SoraSignalingMessageEvent` は保持しない。offer の `rpc_methods` を見るには signaling event の記録を追加する必要がある

## 環境前提

RPC 機能は認証成功時に `rpc_methods` を払い出す必要がある。js-sdk の E2E (`e2e-tests/rpc/main.ts` の `privateClaims`) では、**テストサーバー固有の機能**として JWT の private claims に `rpc_methods` を埋め込み、サーバー側がこれを検証して認証成功時の払い出しに反映している。iOS SDK / Android SDK の RPC E2E も同じ JWT 方式であり、本 issue もこれに倣う。Flutter の E2E は iOS SDK の RPC E2E と同じテストサーバーと `TEST_SECRET_KEY` を使う (ユーザー確認済み)。**通常の Sora では本テストは動作しない**。

- `rpc_methods`: テスト対象メソッドの一覧 (既定例: `["2025.2.0/PutSignalingNotifyMetadata"]`)
- `2025.2.0/PutSignalingNotifyMetadata` は追加 claims 不要。`2025.2.0/RequestSimulcastRid` を使う場合のみ、`simulcast` と `simulcast_rpc_rids` (初期 rid を固定するなら `simulcast_request_rid`) が必要で、simulcast sendonly (external video track で映像を送る) + recvonly の 2 接続構成にする
- 接続先 Sora の `sora.conf` で `data_channel_rpc` が有効 (既定 true) であること。DataChannel シグナリングは RPC JWT を使う test でクライアントが `SoraConnectionConfig(dataChannelSignaling: true, ignoreDisconnectWebSocket: true)` で要求する (`sora.conf` の `default_data_channel_signaling` は既定 false)。`ignoreDisconnectWebSocket` は iOS の RPC E2E と同じく、DataChannel シグナリング切替後の WebSocket 切断で接続が終了しないようにするため
- 接続先テストサーバーと `TEST_SECRET_KEY` は iOS SDK の RPC E2E と同一である (ユーザー確認済み)。iOS の `buildJWTAccessToken` が `TEST_SECRET_KEY` を HS256 の署名鍵として使っているため、本 issue でも同じ値を署名鍵として使う。JWT の private claims を検証して `rpc_methods` を払い出すテストサーバー固有の機能も iOS と同様に前提とする
- `TEST_SECRET_KEY` は全 test で必須とする。disconnect test では `metadata: {'access_token': TEST_SECRET_KEY}` を接続 metadata として使い、RPC JWT を使う test では HS256 の署名鍵として使う。既存 E2E の `metadataFromSecretKey()` は JWT 風の値を裸の文字列で返すため、RPC E2E では流用しない
- 生成した JWT は `metadata: {'access_token': <JWT>}` として設定する。テストサーバーの認証契約は `metadata.access_token` であり、裸の JWT 文字列を `metadata` に設定しない

## 着手時の確認タスク

1. Flutter には JWT 生成機能がないため、テストコード内で HS256 JWT を生成する実装が必要。JWT 専用ライブラリは追加しない。既に transitive 依存で導入済みの `crypto` パッケージを利用し (`e2e_test_app` の dev_dependencies へ直接依存として明示)、Hmac 署名で JWT を生成する。署名鍵は `TEST_SECRET_KEY` を使い、`buildChannelId` で生成したチャンネル ID を payload の `channel_id` に埋め込む。生成した JWT は `metadata: {'access_token': <JWT>}` として設定する
2. 既定の成功系メソッド `2025.2.0/PutSignalingNotifyMetadata` を `rpc_methods` に含めて接続し、テストサーバーで利用できること、params と期待 result が `TEST_RPC_SUCCESS_*` で与えられることを確認する。`RequestSimulcastRid` を使う場合は simulcast sendonly + recvonly の 2 接続と claims を用意でき、対象 rid が送信側で立ち上がることを確認する

## 設計方針

- この issue は **server との RPC DataChannel 契約** に限定する。クライアント間のユーザー定義 DataChannel（Sora 経由で中継される）の基本疎通は `0016`（2026-06-23 closed、`e2e_test_app/integration_test/custom_data_channel_e2e_test.dart` で実装済み）で完了しており、本 issue では扱わない
- RPC は server 実装依存が強いため、メソッド名や params、期待レスポンスを環境変数で注入する方針を固定する
- 次の環境変数を `e2e_test_app/README.md` に定義し、テストコードへベタ書きしない
  - `TEST_SECRET_KEY`: 認証 metadata と HS256 JWT の署名鍵。iOS RPC E2E と同じテストサーバー/secret を使う。既存の `metadataFromSecretKey()` は流用しない
  - `TEST_RPC_SUCCESS_METHOD` / `TEST_RPC_SUCCESS_PARAMS_JSON` / `TEST_RPC_SUCCESS_EXPECTED_JSON`: 正常応答用。既定メソッドは `2025.2.0/PutSignalingNotifyMetadata`
  - `TEST_RPC_ERROR_PARAMS_JSON`: error response 用の params。未指定時は success params に不正なキーを足したものを使う
  - `TEST_RPC_ERROR_EXPECTED_CODE` / `TEST_RPC_ERROR_EXPECTED_MESSAGE` / `TEST_RPC_ERROR_EXPECTED_DATA_JSON`: error response の期待値 (任意)。message の完全一致は指定時のみ行い、未指定時は非空だけを確認する
- RPC 実行権限 (`rpc_methods` 払い出し) は **JWT 発行** により解決する。テストコード内で HS256 JWT を生成し、private claims の `rpc_methods` にテスト対象メソッドを含め、対象メソッドが要求する claims (`RequestSimulcastRid` なら `simulcast` / `simulcast_rpc_rids`) も含めて接続する (iOS SDK / Android SDK の RPC E2E と同一方式)
- RPC JWT を使う test の接続は `SoraConnectionConfig(dataChannelSignaling: true, ignoreDisconnectWebSocket: true)` を指定し、接続後に `SoraSwitchedEvent` と `rpc` ラベルの `SoraDataChannelOpenEvent` を待ってから `rpc()` を呼ぶ。`sendRpcMessage` は `_rpcDc.dc` が null の間は送信しないため、open 待ちをしないと timeout と notification の test が送信なしで成功する偽陽性になる
- 正常応答は `PutSignalingNotifyMetadata` を単一接続で呼ぶ。`RequestSimulcastRid` を使う場合のみ 2 接続構成とする
- `TEST_RPC_SUCCESS_EXPECTED_JSON` は、既定の `PutSignalingNotifyMetadata` では完全一致で比較する。`RequestSimulcastRid` のように `channel_id` / `receiver_connection_id` など実行時に決まる値が result に含まれる場合は、期待 JSON に含まれるキーだけを比較する
- 正常応答、timeout、切断時キャンセル、notification、error response を別 test case として分ける
- timeout は `SoraRpcOptions(timeout: 1)` (ミリ秒) を success method に指定して `TimeoutException` を確認する。Sora には「応答しないメソッド」が存在しないため、timeout test 用の専用メソッドは設けない。待機側のタイムアウトは 10 秒など RPC timeout より十分大きくする
- 切断時キャンセルは、`dataChannelSignaling: false` で接続し、offer に `rpc` ラベルまたは `rpc_methods` がないことを確認してから `rpc()` を発行して pending を作り、`disconnect()` で `SoraRpcError(code: -1, message: 'Disconnected')` になることを確認する。metadata は `metadata: {'access_token': TEST_SECRET_KEY}` を使い、RPC 用 JWT は使わない。`sendRpcMessage` は送信しないためサーバー応答とのレースがなく、決定的に検証できる。送信済みリクエストの終端はこの test の対象外とし、RPC の timeout は設定しない。`expectLater` は `disconnect()` より先に設定する
- 送信済み RPC と `disconnect()` の競合 test を追加する。`rpc` DataChannel の open 後に `SoraRpcOptions(timeout: 5)` 付きで `rpc()` を発行し、即 `disconnect()` して、Future が 10 秒以内に終端することを確認する。終端理由は問わない (iOS の `testRPCRaceWithDisconnectTerminatesAll` と同じ方針)
- notification は success method と success params に `SoraRpcOptions(notification: true)` を指定し、戻り値が `null` で即完了することを確認する。専用メソッドは設けない
- error response は success method に `TEST_RPC_ERROR_PARAMS_JSON` (不正な params) を渡し、`SoraRpcError` の `code` が 0 以外、`message` が非空であることを確認する。`TEST_RPC_ERROR_EXPECTED_*` が設定されている場合はその値と比較する。サーバーが不正 params を拒否せず成功応答を返した場合は、理由を残してスキップする (iOS と同じ)
- スキップ判定は test ごとに分ける
  - 共通: `TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX` が未設定の場合は接続前にスキップする
  - RPC JWT を使う test (正常応答 / timeout / notification / error): `TEST_RPC_SUCCESS_METHOD` / `TEST_RPC_SUCCESS_PARAMS_JSON` / `TEST_RPC_SUCCESS_EXPECTED_JSON` も必須とし、欠けている場合はスキップする。接続後、offer の `data_channels` に `rpc` ラベルがない場合、または `rpc_methods` にテスト対象メソッドが含まれない場合は `markTestSkipped` でスキップする
  - disconnect test: 共通変数のみ必須とし、`TEST_RPC_SUCCESS_*` は要求しない。接続後、offer に `rpc` ラベルまたは `rpc_methods` がある場合は、pending とサーバー応答のレースを避けられないため `markTestSkipped` でスキップする
- RPC E2E は CI では実行せず、`TEST_RPC_*` を設定したローカル検証に限定する。`e2e-test.yml` の matrix には登録しない。`0181` で E2E Test が pub.dev 公開の前提になっても、RPC 用 secrets を matrix に追加しない

## 完了条件

- RPC JWT を使う test で、`rpc` DataChannel の open を待ってから `rpc()` を呼ぶ E2E がある
- `rpc()` 正常応答の E2E がある。`TEST_RPC_SUCCESS_EXPECTED_JSON` との比較は、動的な値を含む result では期待キーの部分一致で行う
- `timeout` 指定時に `TimeoutException` を返す E2E がある
- 待機中 RPC が `disconnect()` で `SoraRpcError(code: -1, message: 'Disconnected')` として失敗完了する E2E がある。`dataChannelSignaling: false` で rpc DataChannel を払い出さず、サーバー応答とのレースを避ける
- 送信済み RPC を `disconnect()` と競合させても Future が 10 秒以内に終端する E2E がある。終端理由は問わない
- notification が `null` を返して即完了する smoke test がある
- 不正な params に対して `SoraRpcError` が返り、`code` が 0 以外、`message` が非空であることを確認する E2E がある。サーバーがエラーを返さない場合は理由を残してスキップする
- 切断時の `SoraRpcError(code: -1, message: 'Disconnected')` が `SoraConnection.rpc` の dartdoc に記載されている
- 前提条件 (`TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX`、RPC JWT を使う test では `TEST_RPC_SUCCESS_*`、JWT private claims による `rpc_methods` 払い出し、offer の `rpc` ラベルと `rpc_methods`) を満たさない環境では test ごとにスキップされること。disconnect test は `rpc` ラベルまたは `rpc_methods` がない場合のみ実行する
- 環境変数の定義は `e2e_test_app/README.md` に集約されていること

## pending 理由

本 issue の E2E テストは実サーバーの RPC 契約と認証情報が必要で、CI では実行せずローカル検証に限定する方針となった。認証情報 (RPC 実行権限) は JWT 発行により解決する見込みであり、テストサーバーの private claims 検証対応が確認でき次第、自動実行できる検証基盤の整備に合わせて reopened する。（この再開条件は `## reopened 理由` で撤回し、CI 登録は行わない方針に変更した）

## reopened 理由

pending としていた理由のうち「実装方法が未確定」が解決したため、open に戻す。

- RPC 実行権限 (`rpc_methods` 払い出し) は、テストコード内で HS256 JWT を生成し private claims に `rpc_methods` を含めて接続することで実装する。sora-ios-sdk の RPC E2E と同じ方式を採る
- JWT 生成に必要な `crypto` パッケージは追加の依存導入なしで使える
- E2E は CI では実行せず、`TEST_RPC_*` を設定したローカル検証に限定する。pending 理由の「自動実行できる検証基盤の整備」は再開条件から外し、CI への登録は行わない
- 接続先テストサーバーと `TEST_SECRET_KEY` は iOS SDK の RPC E2E と同一であり、JWT の private claims 検証、`rpc_methods` 払い出し、HMAC 署名鍵としての利用は iOS と同様に前提とする

## 解決方法

1. 検証環境の RPC 用メソッド名、params、期待レスポンス、error params を環境変数として定義する
2. `crypto` を `e2e_test_app` の dev_dependencies へ直接依存として明示し、HS256 JWT を生成するヘルパーを追加する。JWT 専用ライブラリは追加せず、`crypto` の HMAC-SHA256 と `dart:convert` の base64Url で header / payload / signature を組み立てる。署名鍵は `TEST_SECRET_KEY` を使い、payload は `channel_id` と `rpc_methods`、および対象メソッドが要求する claims。生成した JWT は `metadata: {'access_token': <JWT>}` に設定する。既存の `metadataFromSecretKey()` は使わない
3. 共通変数 (`TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX`) を検査する `loadRpcE2eEnvironment()` を新設し、欠けている場合は `testWidgets(..., skip: ...)` でスキップする。RPC JWT を使う test では、さらに `TEST_RPC_SUCCESS_METHOD` / `TEST_RPC_SUCCESS_PARAMS_JSON` / `TEST_RPC_SUCCESS_EXPECTED_JSON` を検査する。既存の `loadE2eEnvironment()` の挙動は変えない
4. `ObservedConnection` に `SoraSignalingMessageEvent` を蓄積する field を追加し、`connection.events` の購読を `connect()` より前に開始する。RPC JWT を使う test では、offer の `data_channels` に `rpc` ラベルがあること、`rpc_methods` にテスト対象メソッドがあることを確認し、満たさない場合は `markTestSkipped` でスキップする。disconnect test では逆に、offer に `rpc` ラベルまたは `rpc_methods` がある場合に `markTestSkipped` でスキップする
5. RPC JWT を使う test の接続は `SoraConnectionConfig(dataChannelSignaling: true, ignoreDisconnectWebSocket: true)` とし、接続後に `SoraSwitchedEvent` と `rpc` ラベルの `SoraDataChannelOpenEvent` を待つ
6. 正常系 test で `rpc()` の結果を `TEST_RPC_SUCCESS_EXPECTED_JSON` と比較する。動的な値を含む result では期待キーの部分一致にする
7. timeout 用 test で success method を `SoraRpcOptions(timeout: 1)` (ミリ秒) 付きで呼び、`TimeoutException` を確認する。待機側は 10 秒で打ち切る
8. disconnect cancel 用 test は `dataChannelSignaling: false` で接続し、offer に `rpc` ラベルまたは `rpc_methods` がないことを確認してから `rpc()` を発行して pending を作る。metadata は `metadata: {'access_token': TEST_SECRET_KEY}` を使い、RPC 用 JWT は使わない。`expectLater` を先に設定してから `disconnect()` し、`SoraRpcError(code: -1, message: 'Disconnected')` を確認する。10 秒で打ち切る。この test では step 5 の open 待ちと RPC timeout を行わない
9. 送信済み RPC と `disconnect()` の競合 test を追加する。`rpc` DataChannel の open 後に `SoraRpcOptions(timeout: 5)` 付きで `rpc()` を発行し、即 `disconnect()` して、`expectLater` で 10 秒以内に終端することを確認する。終端理由は問わない
10. notification 用 test で success method と success params に `SoraRpcOptions(notification: true)` を指定し、戻り値が `null` で即完了することを確認する
11. error response 用 test で success method に `TEST_RPC_ERROR_PARAMS_JSON` を渡し、`SoraRpcError` の `code` が 0 以外、`message` が非空であることを確認する。`TEST_RPC_ERROR_EXPECTED_*` が設定されている場合はその値と比較する。サーバーがエラーを返さない場合は `markTestSkipped` で理由を残す
12. `SoraConnection.rpc` の dartdoc に切断時の `SoraRpcError(code: -1, message: 'Disconnected')` を追記する
13. `e2e_test_app/README.md` に RPC 用環境変数と検証前提を追記する（環境変数の定義は同ファイルに集約し、ルート `README.md` へは追記しない）
