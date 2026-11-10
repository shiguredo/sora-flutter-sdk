# pub.dev 公開時に不要なファイルを .pubignore で除外する

- Created: 2026-08-13
- Completed: 2026-08-20
- Branch: feature/change-add-pubignore
- Polished: {YYYY-MM-DD}

## 目的

pub.dev に公開するパッケージに、利用者にとって不要な開発用ファイルが同梱されるのを防ぐ。

`flutter pub publish --dry-run` の出力を確認したところ、公開アーカイブに以下の開発用ファイルが含まれる。これらはライブラリ利用者に不要であり、パッケージサイズの肥大と `docs` ディレクトリの pub 規約違反警告 (単数形 `doc` 推奨) の原因になっている。

- `devtools/` (検証用アプリ)
- `e2e_test_app/` (E2E テスト用アプリ)
- `issues/` (issue 管理ファイル)
- `skills/` (LLM 用スキル)
- `docs/` (開発者向けドキュメント。README と重複する)
- `prek.toml` (開発用ツール設定)

## 現状

- `.pubignore` は存在しない
- `flutter pub publish --dry-run` の警告:
  - `Rename the top-level "docs" directory to "doc". The Pub layout convention is to use singular directory names.`
  - docs を除外することでこの警告も解消できる

### 除外しないファイル

以下のファイルは SDK 利用者のビルドに必要なので除外しないこと。

- `hook/build.dart` と `scripts/` (ビルドフックが `generate_sdk_version.dart` / `update_apple_native_binary.dart` を実行する)
- 各プラットフォームのネイティブコード (`android/` / `ios/` / `macos/` / `linux/` / `windows/`)
- `third_party/libwebrtc-c` は git submodule のため、元々パッケージに含まれない

## 設計方針

- リポジトリ直下に `.pubignore` を新規作成し、上記の除外対象を記載する
- pub は `.gitignore` と `.pubignore` の両方を尊重するため、既存の `.gitignore` には追記しない
- `flutter pub publish --dry-run` で除外対象がアーカイブに含まれないことを確認する

## 完了条件

- `.pubignore` がリポジトリ直下に作成されている
- `flutter pub publish --dry-run` の出力に `devtools/` / `e2e_test_app/` / `issues/` / `skills/` / `docs/` / `prek.toml` が含まれない
- `flutter pub publish --dry-run` で `docs` ディレクトリ名に関する警告が出ない

## 解決方法

- リポジトリ直下に `.pubignore` を新規作成し、`devtools/` / `e2e_test_app/` / `issues/` / `skills/` / `docs/` / `prek.toml` を除外した
- 除外対象に `third_party/` も追加した
  - pub は `.pubignore` があると `.gitignore` を読まない
  - `.pubignore` の新設で `.gitignore` の `third_party/libwebrtc-c` 除外が失われ、`flutter pub publish --dry-run` が `third_party/` 内の壊れたシンボリックリンクでクラッシュした
  - `third_party/` を除外することでクラッシュを回避した
- `flutter pub publish --dry-run` で除外対象が含まれないことと `docs` ディレクトリ名に関する警告が出ないことを確認した
