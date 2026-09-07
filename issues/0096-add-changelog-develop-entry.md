# `CHANGELOG.md` の `## develop` に 0070 の修正 (FIX) を追記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-changelog-develop-entry
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

0070 のコード修正 (`8562c85`。残り 2 commit は issue ファイル操作のみ) で完了した「audio / video 未指定時のローカル Stream 拒否を修正する」（`issues/closed/0070-*`）が、`CHANGELOG.md` の `## develop` セクションに未記載である。バグ修正 (FIX 相当。0070 が bug-fix issue のため) として追記する。

注意: `CODEBASE.md` の「正式リリース前」節は正式リリース前の `CHANGELOG.md` 記載を禁じている。本 issue の実施可否は未決着であり、末尾の保留事項を参照すること。

## 現状

`CHANGELOG.md` の `## develop` セクションは空であり、次リリースへ向けた変更がまだ集約されていない。

該当 commit は `SoraConnection._validateConnectStream` の `allowsNullStream` 判定を修正し、`audio == null && video == null` の場合に `connect()` へ stream を渡す用法を許可する修正。従来は `StateError('MediaStream must be null when audio and video are disabled.')` を投げていた。なお `null / null` + stream なし と `false / false` + stream なし は従来から許可済みであり、新規に緩和されたのは `null / null` + stream あり の許可である。

利用者から見ると「audio / video 未指定でもローカル Stream を渡して接続できる」ようになる修正。README の `sendonly` / `sendrecv` 例が接続前に失敗する不具合の修正であり、種別は FIX が相当である。

## 設計方針

- `CHANGELOG.md ## develop` に以下相当のエントリを追加する:
  - `- [FIX] audio / video 未指定時に connect() へローカル Stream を渡して接続できるよう修正する`
  - 担当者行 (`- @ユーザー名`) をエントリ末尾に付ける (`shiguredo-changelog` 規約に従う)。
- 記法は `shiguredo-changelog` スキルの規約 (`- [種別] ...` 形式、種別順序) に合わせる。表記の最終統一は `0097-refactor-changelog-conform-to-convention` の決着に従う。本 issue が `## develop` の 0070 エントリを所有し、`0097` は形式整備のみを行う (`0097` 38 行目と一致)。
- 記述に issue 番号やファイル名を書かない（shiguredo-issues 規約に準拠）。

## 保留事項

- `CODEBASE.md` の「正式リリース前」節が `CHANGELOG.md` への記載を禁じているため、本 issue は現状実施できない。正式リリース後まで pending にするかどうか、`CODEBASE.md` を改訂するかどうかが未決着である。方針決定まで着手しないこと。

## 完了条件

- [ ] `CHANGELOG.md ## develop` に該当エントリが追記されている。
- [ ] 記法が `shiguredo-changelog` の規約に沿っている。
- [ ] issue 番号への言及が本文に含まれない。

## pending にする理由

`CODEBASE.md` の「正式リリース前」節が正式リリース前の `CHANGELOG.md` 記載を禁じており、現状 (`version: 2026.1.0-canary.0`) では実施できない。正式リリース後に `## develop` への追記として実施するため、それまで pending とする。着手時は `0097` の形式決着に従うこと。
