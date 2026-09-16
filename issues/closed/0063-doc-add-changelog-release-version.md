# 公開時に CHANGELOG.md へリリースバージョンの節を追加する

- Created: 2026-08-13
- Completed: 2026-08-20
- Branch: feature/doc-add-changelog-release-version
- Polished: {YYYY-MM-DD}

## 目的

pub.dev に公開する際、`flutter pub publish` のバリデーションを通過できるよう、CHANGELOG.md に公開するバージョンの節を追加する。

現状の CHANGELOG.md は `## develop` の見出しだけで、リリースバージョン (例: `2026.1.0`) の節が存在しない。このまま公開すると `flutter pub publish --dry-run` で次の警告が出て、公開が妨げられる。

- `CHANGELOG.md doesn't mention current version (2026.1.0-canary.0)`

## 現状

- `CHANGELOG.md` の先頭は `## develop` で、develop ブランチで蓄積された変更が列挙されている
- pub.dev は CHANGELOG.md を Changelog タブとして表示するため、リリースごとにバージョン見出しが必要 (pub の package layout 規約: バージョン番号を含む見出しで各リリースの節を作る)
- pubspec.yaml の `version` は `2026.1.0-canary.0`

## 設計方針

- リリース時に `## develop` の節を `## 2026.1.0` (公開するバージョン) にリネームして確定する
- `## develop` は新しい節として再度追加し、次の開発サイクルの変更を蓄積する
- CHANGELOG.md の形式は現在のまま維持する

## 完了条件

- `flutter pub publish --dry-run` で CHANGELOG.md のバージョン言及に関する警告が出なくなる
- CHANGELOG.md に `## 2026.1.0` の節と、それ以降の変更を蓄積する `## develop` の節が存在する

## 解決方法

- CHANGELOG.md に `## 2026.1.0` の節を追加し、`Sora Flutter SDK の最初のリリースです。` と記載した
- 従来 `## develop` に蓄積されていた変更内容は初回リリースに含めないため削除し、`## develop` は空のまま次の開発サイクルの変更を蓄積する状態にした
- 注: pub のバージョン言及チェックは pubspec.yaml のバージョンと CHANGELOG.md 内の文字列を完全一致で比較する。現時点の pubspec.yaml (`2026.1.0-canary.0`) のままだと `## 2026.1.0` 節では警告が消えないため、公開時には pubspec.yaml を `2026.1.0` に変更してから公開すること
