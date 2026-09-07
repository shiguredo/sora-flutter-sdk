# README に `archive` / `hooks` のビルド用依存の説明を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-readme-build-dependencies
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`README.md` の「Dart パッケージ(ビルド・スクリプト用)」節が `crypto` と `path` のみを列挙しており、`archive` と `hooks` が抜けている。`pubspec.yaml` の dependencies と整合しない状態を解消する。

## 現状

`pubspec.yaml` はビルド用の以下 4 パッケージを dependencies に置く (25-28 行目。`flutter` / `ffi` / `meta` / `web_socket_channel` とは別枠):

- `archive: ^4.0.2`
- `crypto: ^3.0.6`
- `hooks: ^2.0.2`
- `path: ^1.9.0`

コメントによれば「Build hook / CMake から実行されるスクリプトが参照するため dependencies に置く（`dev_dependencies` は SDK 利用者のビルドでは解決されない）」。

`README.md` の「### Dart パッケージ(ビルド・スクリプト用)」(87-95 行目) は `crypto` と `path` のみ紹介しており、`archive`（ネイティブ依存の `.tar.gz` / `.zip` 展開用）と `hooks`（`hook/build.dart` の build hook 実行基盤用）の説明が無い。

## 設計方針

- README の当該節に `archive` と `hooks` の項目を追加する。既存 2 項目と同じ構成 (`####` 見出し + 用途説明 + 参照スクリプト) で書く。完成形は以下相当とする:
  - `archive`: 「アーカイブ展開パッケージ。依存取得スクリプト (`scripts/fetch_native_deps.dart`) でネイティブ依存の `.tar.gz` / `.zip` 展開に利用する。」
  - `hooks`: 「Dart build hooks の実行基盤パッケージ。`hook/build.dart` でバージョン生成スクリプト等を実行するために利用する。」
- バージョン番号 (`^4.0.2` 等) の転記は行わない (既存 2 項目と同様)。
- `0152-add-pubdev-examples` と同一 `README.md` への並行編集になるため、実装時は rebase で競合を整理する。
- 説明は日本語。挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] README の「Dart パッケージ(ビルド・スクリプト用)」節に `archive` と `hooks` の項目が追加されている。
- [ ] 当該節がビルド用の 4 件 (`archive` / `crypto` / `hooks` / `path`) の名前と用途を過不足なく記載している (バージョン番号の転記は行わない)。
