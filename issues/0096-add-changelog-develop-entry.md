# `CHANGELOG.md` の `## develop` に 0070 の挙動緩和 (UPDATE) を追記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-changelog-develop-entry
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

直近 3 commit（`862c9b4`, `7f90749`, `8562c85`）で完了した「audio / video 未指定時のローカル Stream 拒否を修正する」（`issues/closed/0070-*`）が、`CHANGELOG.md` の `## develop` セクションに未記載である。後方互換のある挙動緩和（UPDATE 相当）として追記する。

## 現状

`CHANGELOG.md` の `## develop` セクションは空。`## 2026.1.0` の直上に位置し、次リリースへ向けた変更がまだ集約されていない。

該当 commit は `SoraConnection._validateConnectStream` の `allowsNullStream` 判定を修正し、audio / video の両方が未指定の場合、または明示的に無効化された場合に `connect()` へ stream を渡さない用法を許容する挙動緩和。

利用者から見ると「audio / video 未指定でも stream 不要で接続できる」ようになる後方互換のある変更。従来は `StateError('MediaStream is required when sending audio or video.')` を投げていた。

## 設計方針

- `CHANGELOG.md ## develop` に以下相当のエントリを追加する:
  - `- UPDATE audio / video 未指定時に connect() へローカル Stream を渡さない接続を許可する`
- 分類文言・記号形式（`[UPDATE]` / `- UPDATE` 等）は `shiguredo-changelog` スキルの規約に合わせる。別 issue で CHANGELOG 全体を規約準拠に整備する予定なので、そちらの決着に応じて表記を統一する。
- 記述に issue 番号やファイル名を書かない（shiguredo-issues 規約に準拠）。

## 完了条件

- [ ] `CHANGELOG.md ## develop` に該当エントリが追記されている。
- [ ] 記法が `shiguredo-changelog` の規約に沿っている。
- [ ] issue 番号への言及が本文に含まれない。
