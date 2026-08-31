# CODEBASE

## 変更履歴

変更履歴は **`CHANGELOG.md` のみ** を使う。

時雨堂の規約 (`shiguredo-changelog`) は `CHANGES.md` を標準とするが、pub.dev は `CHANGELOG.md` だけを Changelog タブ表示とバージョン言及チェックに使う。このリポジトリは pub.dev 公開パッケージのため、ファイル名は `CHANGELOG.md` に統一する。

### 編集ルール

- 変更履歴の追記・リリース確定は **`CHANGELOG.md` に対して行う**
- 形式は `shiguredo-changelog` スキルの記法（`[CHANGE]` / `[ADD]` / `[UPDATE]` / `[FIX]`、`## develop` など）に従う
- pub.dev 公開時は、`pubspec.yaml` の `version` と **同じ文字列** が `CHANGELOG.md` 内に含まれている必要がある

## pub.dev 公開

タグ push で `.github/workflows/publish.yml` が pub.dev に公開する。canary 版タグ（`-canary.N` 付き）のみ CHANGELOG 未記載の警告を無視する。

- canary 版: `canary.py` でバージョン更新とタグ push
- 安定版: git flow release でバージョン確定とタグ push

## 正式リリース前

**正式リリース前**

- 正式リリース前は変更履歴を `CHANGELOG.md` に残さないこと
