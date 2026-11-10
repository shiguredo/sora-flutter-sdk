# pub.dev 公開を CI と E2E Test の成功後に実行する

- Created: 2026-11-10
- Completed: {YYYY-MM-DD}
- Branch: feature/change-publish-after-ci-and-e2e
- Polished: {YYYY-MM-DD}

## 目的

タグ push で pub.dev に公開されるバージョンが、CI と E2E Test の結果に関係なく公開されてしまう状態を解消する。CI (`.github/workflows/ci.yml`) と E2E Test (`.github/workflows/e2e-test.yml`) の両方が成功したときだけ公開し、壊れたビルドのバージョンが pub.dev に残らないようにする。

## 現状

タグ push に対して次の 3 つのワークフローが同時に起動し、互いに依存関係がない。

- `.github/workflows/ci.yml` (CI): `on.push.paths` と `workflow_dispatch` で起動する。タグ push では `paths` フィルタは評価されないため、`build-android` / `build-apple` / `build-windows` / `build-linux` と `slack_notify` が実行される
- `.github/workflows/e2e-test.yml` (E2E Test): 同じくタグ push で起動し、`integration-test-macos` / `integration-test-windows` / `integration-test-linux` と `slack_notify` を実行する。`TEST_SECRET_KEY` / `TEST_SIGNALING_URLS` / `TEST_CHANNEL_ID_PREFIX` の secrets が必要
- `.github/workflows/publish.yml` (pub.dev に公開): `on.push.tags` で起動し、CI と E2E Test の結果を待たずに公開する

`2026.2.0` タグを push したとき (2026-11-10T07:24:43Z) の実績は次のとおり。

- `pub.dev に公開` のラン 42775101171 は `Publish to pub.dev` ジョブが 07:25:42 に完了した
- `E2E Test` のラン 42775100998 は 07:33:04 に完了した
- `CI` のラン 42775101190 は 07:35:33 に完了した

公開は CI の完了より約 10 分、E2E Test の完了より約 7 分早く終わっており、どちらの結果も公開に影響しない。pub.dev は公開の取り消しを原則認めておらず、できるのは公開から 7 日以内の retract だけである。retract は削除ではなく、バージョンは Retracted として一覧に残る。そのため、壊れたビルドのバージョンが公開されると、利用者に配布したままになる。

## 設計方針

`publish.yml` から CI と E2E Test を再利用可能ワークフローとして呼び、両方の成功を `needs` で待ってから公開する。同一イベントで起動する別ワークフロー間の順序は GitHub Actions では保証できないため、`workflow_run` で CI や E2E Test の完了を拾うのではなく、呼び出し関係を明示する。

1. `.github/workflows/publish.yml` のジョブ構成を次のようにする。`on.push.tags` のタグ形式の制限と `environment: pub.dev` は維持する。
   - `ci` ジョブ: `uses: ./.github/workflows/ci.yml`、入力 `skip_slack: true`、`permissions: contents: read` と `actions: read`
   - `e2e` ジョブ: `uses: ./.github/workflows/e2e-test.yml`、入力 `skip_slack: true`、`secrets: inherit`、`permissions: contents: read` と `actions: read`
   - `publish` ジョブ: `needs: [ci, e2e]`、`permissions: contents: read` と `id-token: write`。公開手順 (`dart pub token add` と `dart pub publish`) は変更しない
2. `.github/workflows/ci.yml` と `.github/workflows/e2e-test.yml` の `on` に `workflow_call` を追加し、`skip_slack` (boolean) 入力を宣言する。`slack_notify` の `if` に `!inputs.skip_slack` を加え、呼び出された実行では Slack 通知を送らない。単独実行では `inputs` が空になり `!inputs.skip_slack` が真になるため、従来どおり通知される。
3. `GITHUB_TOKEN` の権限は呼び出し元を超えられないため、呼び出し側ジョブに `contents: read` と `actions: read` を明示する。`e2e` の `secrets: inherit` は `TEST_*` の secrets を渡すために必要。
4. 呼び出されたワークフローの `github` コンテキストは呼び出し元のものになり、`github.workflow` は `pub.dev に公開`、`github.ref` はタグになる。既存の `concurrency` グループは単独実行と別になるため互いをキャンセルしないが、`publish.yml` 側に同じグループ値の `concurrency` を追加しないこと。
5. `CODEBASE.md` の「pub.dev 公開」節と `.github/workflows/publish.yml` 冒頭のコメントを新しいフローに合わせる。

タグ push では `ci.yml` と `e2e-test.yml` が単独でも起動するため、CI と E2E Test は 2 回ずつ実行される。公開までの待ち時間は並列実行のため増えないが、runner の消費は倍になる。壊れたバージョンの公開を防ぐことを優先し、この多重実行は許容する。

## 完了条件

- [ ] タグ push で `ci.yml` と `e2e-test.yml` が `publish.yml` から呼ばれ、両方が成功したときだけ pub.dev に公開される
- [ ] CI または E2E Test が失敗したタグ push では `publish` ジョブがスキップされ、pub.dev に公開されない
- [ ] 呼び出された側の CI / E2E Test では Slack 通知が送られず、単独実行では従来どおり送られる
- [ ] 公開対象のタグ形式に一致しないタグでは起動しない (`on.push.tags` が維持されている)
- [ ] `CODEBASE.md` と `.github/workflows/publish.yml` のコメントが新しいフローと一致している
- [ ] canary タグを push し、CI と E2E Test の成功後に pub.dev へ公開されることを確認する

## 対象外

- タグ push 時の CI / E2E Test の単独実行の抑制。`on.push.tags-ignore` で重複を消せるが、多重実行を許容する方針とする
- 公開失敗時の Slack 通知の追加。現状も `publish.yml` に通知ジョブはなく、本 issue では変更しない
