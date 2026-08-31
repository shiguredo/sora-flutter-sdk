# sendrecv 単一接続の smoke E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Completed: 2026-06-09
- Model: GPT-5 Codex
- Branch: feature/add-sendrecv-e2e-coverage
- Polished: 2026-06-03

## 目的

既存の E2E は `recvonly` と `sendonly` のみで、`sendrecv` ロールの接続開始、送信開始、明示切断という最小経路を自動検証していない。まずは権限依存を増やさない単一接続の smoke E2E を追加し、`sendrecv` ロール固有の接続経路が壊れていないことを継続監視できるようにする。

## 優先度根拠

- `README.md` は `sendrecv` を最初の利用例として公開しているが、対応する E2E が無い
- 現在の `e2e_test_app/integration_test/` には `recvonly` と `sendonly_dummy_video` しか無く、`sendrecv` ロールで `connect(stream)` する経路が未監視である
- 2 接続の受信確認は後続 issue `0239` 以降で深掘りするが、その前に 1 接続で壊れやすい接続経路と明示切断を最小コストで監視する価値が高いため High とする

## 現状

- `e2e_test_app/integration_test/recvonly_e2e_test.dart` は `recvonly` の接続と、`getStats()` から `DTLS connected` または `ICE candidate-pair succeeded` が得られることを確認している
- `e2e_test_app/integration_test/sendonly_dummy_video_e2e_test.dart` は external video track を使った `sendonly` の送信統計増加を確認している
- `README.md` は `sendrecv` を最初の接続例として公開している
- `lib/src/sora_connection.dart` の `connect(stream)` は `audio` と `video` が両方 `null` の場合に `stream` を禁止するため、external video track を使う smoke E2E では `video: true` と `audio: false` を明示する必要がある
- `e2e_test_app/README.md` はまだ「recvonly / sendonly 接続を検証する最小アプリ」と説明しており、現在の issue 群と整合していない
- ルート `README.md` も `e2e_test_app` を `recvonly E2E テストアプリ` と説明しており、`sendrecv` smoke 追加後は更新が必要になる
- `.github/workflows/e2e-test.yml` は `recvonly` 前提の構成で、現状 `if: false` により job 自体が停止している

## 設計方針

- この issue は **単一接続の smoke E2E** に範囲を限定する。2 接続による受信成立確認、`SoraTrackEvent`、`remoteMediaStreams` の検証は `0239`、`0011`、`0012` で扱い、本 issue には含めない
- `e2e_test_app/integration_test/` に `sendrecv_smoke_e2e_test.dart` を追加する
- 送信トラックは既存の external video track ベースを使い、CI でカメラ / マイク権限依存を増やさない
- 接続設定は `role: SoraRole.sendrecv`、`video: true`、`audio: false` を明示する。`audio` / `video` を未指定にすると `connect(stream)` が失敗するため、この前提を issue に固定する
- 検証項目は `SoraConnectedState` 到達、`getStats()` の非空取得、`DTLS connected` または `ICE candidate-pair succeeded` の成立、`video outbound-rtp` の送信量増加、`disconnect()` 後の `SoraDisconnectedState` 到達とする
- `dispose()` は検証対象ではなく後始末に限定する。切断完了確認は `disconnect()` でのみ行う
- 既存の `_parseSignalingUrls`、`_buildChannelId`、`_metadataFromSecretKey`、external video source、stats 解析 helper は共通化を前提に見直す。少なくとも 3 本目の E2E で同一ロジックをさらにコピペしない
- 環境変数は既存と同じ `TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX` を使い、ローカルと CI の共通コードにする
- 公開 API の後方互換影響は無い。変更対象は `e2e_test_app/integration_test/`、必要な helper、`e2e_test_app/README.md`、ルート `README.md` に限定する
- `.github/workflows/e2e-test.yml` の修正は本 issue の対象外とする。現状 workflow 自体が停止中であり、CI 組み込みの整理は別 issue で扱う

## 完了条件

- `e2e_test_app/integration_test/sendrecv_smoke_e2e_test.dart` が追加されている
- 新規テストが `SoraConnectedState` 到達、`getStats()` 成功、`DTLS / ICE` 成立、`video outbound-rtp` の増加、`disconnect()` 後の `SoraDisconnectedState` 到達を検証している
- 切断完了を確認するまで event subscription を維持し、その後に `dispose()` している
- `e2e_test_app/README.md` の冒頭説明と実行例が `sendrecv` を含む内容へ更新されている
- ルート `README.md` の `e2e_test_app` 説明が `sendrecv` smoke 追加後の実態に合わせて更新されている
- helper 共通化を行う場合は既存 `recvonly` / `sendonly` E2E も同じ helper に揃っている
- `flutter test integration_test/sendrecv_smoke_e2e_test.dart -d macos` で新規テストが実行できる

## 解決方法

1. `e2e_test_app/integration_test/sendrecv_smoke_e2e_test.dart` を追加する
2. `sendonly_dummy_video_e2e_test.dart` の external video source と stats 解析を見直し、必要なら `integration_test/support/` 配下へ helper を切り出して再利用する
3. external video track を 1 本だけ持つ `LocalMediaStream` を生成し、`SoraConnectionConfig` は `role: SoraRole.sendrecv`、`video: true`、`audio: false` で組み立てる
4. `SoraConnection.events` を購読し、`SoraConnectedState` と `SoraDisconnectedState` を明示的に待つ。接続エラーイベントは即時失敗にする
5. 接続後にフレーム投入を開始し、`getStats()` から `DTLS connected` または `ICE candidate-pair succeeded`、および `video outbound-rtp` の送信量増加を検証する
6. `disconnect()` を呼んで `SoraDisconnectedState` 到達を確認した後で `dispose()` する
7. `e2e_test_app/README.md` の説明文と実行例を更新し、`sendrecv_smoke_e2e_test.dart` の実行手順を追加する
8. ルート `README.md` の `e2e_test_app` 説明を `sendrecv` smoke を含む記述へ更新する
9. 本 issue は単一接続 smoke に限定し、2 接続での受信成立確認は `0239` 以降に委ねることを issue 本文へ明記する
