# pub.dev の障害復旧後に公開ワークフローの回避策を削除する

- Created: 2026-09-11
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-publish-oidc-workaround
- Polished: {YYYY-MM-DD}

## 目的

pub.dev 側の package metadata 障害が復旧したあとに、`.github/workflows/publish.yml` に入れた暫定回避策を取り除き、検証をスキップしない元の公開フローに戻すこと。

## 現状

`.github/workflows/publish.yml` の `Publish to pub.dev` ジョブには、次の回避策が入っている。

- `dart-lang/setup-dart` が生成する OIDC トークンを `OIDC トークンを削除する` ステップで `dart pub token remove https://pub.dev` により外し、`dart pub get` と `dart pub publish --dry-run` をトークンなしで実行する
- 公開直前に `dart pub token add https://pub.dev --env-var PUB_TOKEN` でトークンを再登録し、`dart pub publish --force --skip-validation` で依存解決をスキップしてアップロードする
- ファイル冒頭に回避策の理由と復旧後に外す旨のコメントがある

これは、pub.dev の package metadata エンドポイントが `Authorization` ヘッダ付きのリクエストに 403 を返す障害 (https://github.com/dart-lang/pub-dev/issues/9576) のためである。`dart-lang/setup-dart` はトークンを `https://pub.dev` ホスト全体に登録するため、依存解決と dry-run が巻き添えで失敗していた。

障害が復旧すればこの回避策は不要になる。`--skip-validation` はクライアント側の検証と依存解決をスキップするため、恒久的に残すと公開前の検証が効かなくなる。

## 設計方針

- 回避策の `OIDC トークンを削除する` ステップを削除する。
- `Publish to pub.dev` から `dart pub token add` と `--skip-validation` を削除し、`dart pub publish --force` に戻す。
- ファイル冒頭の回避策コメントを削除する。
- `--ignore-warnings` を `--dry-run` のみに限定する形は回避策ではなく恒久修正のため、そのまま維持する。

## 完了条件

- [ ] `.github/workflows/publish.yml` からトークン削除・トークン再登録・`--skip-validation` が除去されている。
- [ ] 回避策の理由コメントが除去されている。
- [ ] タグ push による pub.dev への公開が成功する。

## 対象外

- upstream の障害 (https://github.com/dart-lang/pub-dev/issues/9576) そのものへの対応。復旧を待つ。
