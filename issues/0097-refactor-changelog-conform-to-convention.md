# `CHANGELOG.md` を `shiguredo-changelog` 規約に準拠させる

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-changelog-conform-to-convention
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`CHANGELOG.md` が `shiguredo-changelog` スキルの規約に準拠していないため、規約準拠の形式に整備する。ファイル名は `CODEBASE.md` の例外 (pub.dev 掲載都合で `CHANGELOG.md` を使う) により維持するため、本 issue は内容の形式整備のみを扱う。

## 現状

- ファイル名は `CHANGELOG.md`。`shiguredo-changelog` の規約は `CHANGES.md` を要求するが、`CODEBASE.md` 5-7 行目で pub.dev 掲載都合の例外として `CHANGELOG.md` 統一が決着済みである。リネーム案は採用しない。
- 冒頭に「凡例ブロック」（`- CHANGE / - ADD / - UPDATE / - FIX`、`CHANGELOG.md` 3-10 行目）を書いているが、規約にはない。
- エントリは 0 件である (`## develop` のみが空で存在し、`## 2026.1.0` セクション自体が存在しない)。
- `## develop` の 0070 エントリは `0096-add-changelog-develop-entry` (pending) が所有するため、本 issue では扱わない。種別の判断 (FIX 相当) も `0096` に従う。

## 設計方針

- 冒頭の凡例ブロックを削除する。凡例は変更履歴ではなく規約外の記載であり、正式リリース前の `CHANGELOG.md` 不記載ルール (`CODEBASE.md` 22-26 行目) に触れない。
- 将来エントリの記法を確定する (`shiguredo-changelog` 規約に従う):
  - `- [種別] 変更内容を〜する` 形式で日本語記載する。
  - 種別順序は `CHANGE` → `ADD` → `UPDATE` → `FIX` とする。
  - 各エントリの末尾に担当者行 (`- @ユーザー名`、2 文字下げ) を付ける。
- `0096` の 0070 エントリは確定した記法に従う (`0096` 所有、本 issue は形式のみ提供する)。
- 挙動変更なし。`CHANGELOG.md` のみの修正。

## 完了条件

- [ ] 冒頭の凡例ブロックが削除されている。
- [ ] 将来エントリの記法要件 (形式・種別順序・担当者行) が本 issue に明記されている。
- [ ] `0096` のエントリ記法と矛盾しない。

## 解決方法

- `CHANGELOG.md` の冒頭にあった凡例ブロック (`- CHANGE` / `- ADD` / `- UPDATE` / `- FIX` と各説明の 8 行) を削除し、`# 変更履歴` と `## develop` のみにした。
- 凡例は `shiguredo-changelog` 規約に無いリポジトリ独自の記述であり、正式リリース前の `CHANGELOG.md` 不記載ルール (`CODEBASE.md`) に触れないため削除した。
- 将来エントリの記法は本 issue の設計方針に確定させた (`- [種別] 変更内容を〜する` 形式、種別順序 CHANGE → ADD → UPDATE → FIX、エントリ末尾に 2 文字下げの担当者行)。`0070` の FIX エントリは `0096` が所有し、正式リリース後に追記する。

## reopened にする理由

maintainer の判断で `CHANGELOG.md` の冒頭凡例 (`- CHANGE` / `- ADD` / `- UPDATE` / `- FIX`) を残す方針に変わった。本 issue の解決方法 (凡例を削除する) が実態と一致しなくなったため、一度 reopened にしてから対応不要として閉じ直す。
