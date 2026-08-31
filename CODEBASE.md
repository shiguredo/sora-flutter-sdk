# CODEBASE

## 変更履歴

変更履歴は **`CHANGELOG.md` のみ** を使う。

時雨堂の規約 (`shiguredo-changelog`) は `CHANGES.md` を標準とするが、pub.dev は `CHANGELOG.md` だけを Changelog タブ表示とバージョン言及チェックに使う。このリポジトリは pub.dev 公開パッケージのため、ファイル名は `CHANGELOG.md` に統一する。

### 編集ルール

- 変更履歴の追記・リリース確定は **`CHANGELOG.md` に対して行う**
- 形式は `shiguredo-changelog` スキルの記法（`[CHANGE]` / `[ADD]` / `[UPDATE]` / `[FIX]`、`## develop` など）に従う
- pub.dev 公開時は、`pubspec.yaml` の `version` と **同じ文字列** が `CHANGELOG.md` 内に含まれている必要がある

## 正式リリース前

**正式リリース前**

- 正式リリース前は変更履歴を `CHANGELOG.md` に残さないこと
- 正式リリース前は Pull-Request を作らずブランチ作成から CI が通ったら develop にコミットしていくこと
  - 1 Issue 1 コミット 1 プッシュ
