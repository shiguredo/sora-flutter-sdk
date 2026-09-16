# 複数 signaling URL のフェイルオーバー E2E テストを追加する

- Priority: High
- Created: 2026-06-03
- Model: GPT-5 Codex
- Branch: feature/add-signaling-failover-e2e-coverage
- Polished: 2026-06-03
- Completed: 2026-06-23

## 目的

`signalingUrls` に複数 URL を指定したとき、先頭候補の失敗後に後続候補へフェイルオーバーできることを E2E で確認する。

## 優先度根拠

- `signalingUrls` は `List<String>` として公開されており、フェイルオーバーが重要な契約になっている
- failover は timeout や cleanup を含み、壊れやすい
- 単体テストより実ネットワーク条件に近い E2E の価値が高いため High とする

## 現状

- `lib/src/sora_connection_signaling.dart` は `config.signalingUrls` を順に試す実装になっている
- `README.md` と `SoraConnectionConfig` の dartdoc でも複数 URL 指定を案内している
- 既存 E2E は 1 URL のみを前提としている
- 先頭候補の `TimeoutException` や接続失敗は内部で握りつぶして次候補へ進み、全候補失敗時だけ最終エラーになる実装である

## 設計方針

- 1 件目を意図的に失敗する URL、2 件目を正しい URL にする
- 失敗側で中間 `SoraConnectionErrorEvent` や `SoraTimeoutEvent` を全体失敗として emit しないことも併せて確認する
- テスト時間を抑えるため `signalingCandidateTimeout` を短めに設定する
- 失敗 URL は必ず「すぐ失敗する」か「短時間で timeout する」値に固定し、DNS 依存や長時間待ちを避ける

## 完了条件

- 先頭 URL 失敗後に後続 URL で接続成功する E2E がある
- 全体失敗ではなく failover success として扱われることを確認している
- 1 件目の失敗だけで `SoraConnectionErrorEvent` / `SoraTimeoutEvent` が即 fail として観測されないことを確認している
- 失敗時ログやイベントが後続接続を壊さないことを確認している

## 解決方法

1. failover 用の複数 URL 環境変数仕様を `e2e_test_app` に追加する
2. 先頭 URL には不達または意図的失敗 URL を入れる
3. 2 件目で接続成功することを確認する
4. 1 件目失敗の時点では `SoraConnectionErrorEvent` / `SoraTimeoutEvent` を全体失敗として扱わず、後続 URL へ進めることを確認する
5. receiver なしの単一接続 smoke でもよいが、必要なら `0010` helper を流用して connected / disconnected まで確認する
6. README に failover テストの前提を追記する
