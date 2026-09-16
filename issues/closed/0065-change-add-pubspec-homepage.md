# ドキュメント公開後に pubspec.yaml の homepage を追加する

- Created: 2026-08-13
- Completed: 2026-08-20
- Branch: feature/change-add-pubspec-homepage
- Polished: {YYYY-MM-DD}

## 目的

pub.dev のパッケージページからドキュメントへアクセスできるよう、pubspec.yaml に `homepage` を追加する。

現在の pubspec.yaml には `repository` のみ定義されており、`homepage` が存在しない。pub.dev のパッケージページにはリポジトリとドキュメントへのリンクが別々に表示されるため、ドキュメントへの導線を用意する必要がある。

## 現状

- pubspec.yaml には `repository: https://github.com/shiguredo/sora-flutter-sdk` のみ定義
- `homepage` は未定義

## 設計方針

- `homepage` はドキュメントを Web 上で公開してから追加する
- 公開先は GitHub Pages などの静的サイトホスティングを利用する

## 完了条件

- ドキュメントが Web 上で公開されている
- pubspec.yaml に `homepage` が追加され、公開済みドキュメントの URL を指している
- `flutter pub publish --dry-run` の出力にエラーや警告がない

## 解決方法

- pubspec.yaml の `repository` の直後に `homepage: https://sora-flutter-sdk.shiguredo.jp/` を追加した
- `flutter pub publish --dry-run` で pubspec.yaml に関する警告が出ないことを確認した
  - 残る警告は CHANGELOG.md のバージョン言及のみであり、これは 0063 で扱う (公開時に pubspec.yaml のバージョンを `2026.1.0` へ変更することで解消する)
