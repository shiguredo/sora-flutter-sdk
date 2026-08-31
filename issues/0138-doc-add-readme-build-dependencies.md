# README に `archive` / `hooks` のビルド用依存の説明を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-readme-build-dependencies
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`README.md` の「Dart パッケージ(ビルド・スクリプト用)」節が `crypto` と `path` のみを列挙しており、`archive` と `hooks` が抜けている。`pubspec.yaml` の dependencies と整合しない状態を解消する。

## 現状

`pubspec.yaml` は以下 4 パッケージを dependencies に置く:

- `archive: ^4.0.2`
- `crypto: ^3.0.6`
- `hooks: ^2.0.2`
- `path: ^1.9.0`

コメントによれば「Build hook / CMake から実行されるスクリプトが参照するため dependencies に置く（`dev_dependencies` は SDK 利用者のビルドでは解決されない）」。

`README.md` の「### Dart パッケージ(ビルド・スクリプト用)」は `crypto` と `path` のみ紹介しており、`archive`（ネイティブ依存の zip 展開用）と `hooks`（Dart build hooks 用）の説明が無い。

## 設計方針

- README に `archive` と `hooks` の項目を追加する。他の 2 項目（`crypto` / `path`）と同じスタイルで書く。
- 各項目の説明:
  - `archive`: 「ネイティブ依存の ZIP アーカイブ展開に利用する。CMake からのスクリプトが参照する。」
  - `hooks`: 「Dart build hooks で SDK 利用者のビルドフェーズにネイティブ依存を配置する。」
- 説明は日本語。既存の 2 項目と同レベルの記述に揃える。
- 挙動変更なし。ドキュメントのみ。

## 完了条件

- [ ] README の「Dart パッケージ(ビルド・スクリプト用)」節に `archive` と `hooks` の項目が追加されている。
- [ ] pubspec.yaml の dependencies と README の記述が一致する。
