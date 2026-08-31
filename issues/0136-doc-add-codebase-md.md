# `CODEBASE.md` を追加してリポジトリ固有規約と方針を明文化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-codebase-md
- Polished: {YYYY-MM-DD}

## 目的

AGENTS.md line 20「リポジトリ固有の規約・設定がある場合は `CODEBASE.md` を参照すること」に沿って、リポジトリ固有の方針を明文化する `CODEBASE.md` を追加する。annotation ポリシー、export 方針、CHANGELOG のファイル名扱いなど、既存コードに散在する暗黙ルールを一元化する。

## 現状

`CODEBASE.md` は未作成。以下の方針がどこにも文書化されておらず、レビュー・修正時に判断根拠を推測することになる:

- 公開 data class の `@immutable` / `final class` 付与方針
- `///` と `//` の使い分け（dartdoc は `///` のみ、混在させない）
- コンストラクタで `@nodoc` を使わず `@internal` またはドキュメントで扱う方針
- `sora_sdk.dart` の export 方針（`show` 方式 vs `hide` 方式）
- `CHANGELOG.md` のファイル名扱い（`shiguredo-changelog` は `CHANGES.md` を要求するが pub.dev 表示都合で `CHANGELOG.md` を使う）
- Test の日本語名徹底
- `test/` の `public/` `internal/` 分離方針

## 設計方針

- リポジトリルートに `CODEBASE.md` を新規作成する。
- 上記の各ポリシーを節に分けて記述する。日本語で書く。
- 「なぜ」の根拠（過去の経緯、pub.dev の制約、レビュー結果など）を各節に付ける。
- 将来の追加ポリシーを想定した節構成にする（Style / Testing / API Compatibility / CHANGELOG / Third-party Dependency 等）。
- 参照方向: `AGENTS.md` は既に `CODEBASE.md` への言及があるためそのまま。`CODEBASE.md` から具体的な例（別 issue で扱う `@internal` 付与 / export 方式）を参照する。
- 挙動変更なし。ドキュメント追加のみ。

## 完了条件

- [ ] `CODEBASE.md` がリポジトリルートに存在する。
- [ ] 現時点で決まっている全ポリシーが明文化されている。
- [ ] AGENTS.md からの参照が有効に機能している。
