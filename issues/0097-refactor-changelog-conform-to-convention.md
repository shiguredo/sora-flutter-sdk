# `CHANGELOG.md` を `shiguredo-changelog` 規約に準拠させる

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-changelog-conform-to-convention
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`CHANGELOG.md` が `shiguredo-changelog` スキルの規約に準拠していないため、規約準拠の形式に整備する。

## 現状

- ファイル名が `CHANGES.md` ではなく `CHANGELOG.md`。`shiguredo-changelog` の規約は `CHANGES.md` を要求する。
- 冒頭に「凡例ブロック」（`- CHANGE / - ADD / - UPDATE / - FIX`）を書いているが、規約にはない。
- `## 2026.1.0` セクションが `- [ADD] ...` 相当のエントリを 1 件も含まず、散文 1 行（「Sora Flutter SDK の最初のリリースです。」）のみ。

## 設計方針

以下のいずれかを選ぶ:

**A. ファイル名を `CHANGES.md` に統一する**
- `git mv CHANGELOG.md CHANGES.md`
- pubspec.yaml の `homepage` などから CHANGELOG を参照している箇所を確認して修正する。
- pub.dev の CHANGELOG 表示ルール（`CHANGELOG.md` が固定）との整合を確認する。ここで `CHANGES.md` に変えると pub.dev のパッケージページで changelog が表示されなくなる可能性があるため、シンボリックリンクや別途対応が必要か検討する。

**B. ファイル名は `CHANGELOG.md` のまま、リポジトリ固有規約として `CODEBASE.md` に例外を明記する**
- `CODEBASE.md`（未作成）を追加して「pub.dev 掲載都合で `CHANGELOG.md` を使う」旨を残す。
- 内容の形式（`- [ADD] ...` 相当）は `shiguredo-changelog` の規約に揃える。

現時点では pub.dev への公開を継続する前提から **B 案を推奨**。ただし `A / B` の選択と `CODEBASE.md` の運用は別途ユーザー確認が必要。

いずれの案でも以下を実施する:

- 冒頭の凡例ブロックを削除する。
- `## 2026.1.0` セクションに最低 1 件 `- [ADD] Sora Flutter SDK の最初のリリース` 相当を追加する。
- `## develop` セクションに 0070 挙動緩和の `UPDATE` エントリを追加する（別 issue で扱う）。

## 完了条件

- [ ] ファイル名の扱いが `CODEBASE.md` の方針として明記されている（または `CHANGES.md` にリネームされている）。
- [ ] 冒頭の凡例ブロックが削除されている。
- [ ] `## 2026.1.0` に少なくとも 1 件のエントリがある。
- [ ] `shiguredo-changelog` 規約に沿ったエントリ記法で書かれている。
