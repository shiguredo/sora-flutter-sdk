# `CODEBASE.md` に未文書化ポリシーを追記して節構成を再構成する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-codebase-md
- Polished: 2026-09-07

## 目的

既存 `CODEBASE.md` (変更履歴 / pub.dev 公開 / 正式リリース前の 3 節、26 行) に記載の無い確定ポリシーを追記し、節構成を再構成する。各ポリシーの内容決定は owner issue が行い、本 issue は転記と構成のみを所有する。

## 現状

`CODEBASE.md` に記載が無く、他 issue で確定済みまたは確定予定のポリシーは以下である:

- annotation 方針 (`@immutable` / `final class` / `@nodoc` / `@internal`)。内容確定は `0131-fix-annotation-policy` が所有する。
- `///` と `//` の使い分け。`0095` (7 箇所の `///` 化) と `0112` (英語見出し等) が具体箇所を所有する。
- `sora_sdk.dart` の export 方針。`0100` で `show` 許可リスト方式に解決済み (現行は素 export と `show` 2 件の混在であり、`hide` は存在しない)。
- テスト名の日本語化。`0106` が 21 件を特定済みである。
- `test/` の `public/` / `internal/` 分離方針。`0135` が振り分け表を所有する。

記載済みのため対象外とする:

- `CHANGELOG.md` のファイル名扱い (`CODEBASE.md` 5-7 行目で決着済み)。
- 「正式リリース前」節 (`0148-doc-update-codebase-md-release-flow` が更新を所有するため触れない)。

## 設計方針

- 既存 3 節 (変更履歴 / pub.dev 公開 / 正式リリース前) は維持し、新規節 (API 規約 / テスト規約) を追加する再構成とする。新規作成・上書き破棄は行わない。
- 各節の内容は owner issue (`0131` / `0095` / `0112` / `0106` / `0135` / `0100` 決着) の結論を転記する。本 issue で内容を決定しない。
- owner issue の完了後に転記する。未完了の owner がある節は空節を作らず、転記可能分のみ行う。
- 日本語で書く。

## 完了条件

- [ ] API 規約 / テスト規約の新規節が追加され、既存 3 節と統合されている。
- [ ] 各節の内容が owner issue の結論と矛盾しない。
- [ ] `AGENTS.md` からの参照が有効である (リンク切れなし)。
