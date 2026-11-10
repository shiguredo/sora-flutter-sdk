# pubspec.yaml に topics を定義する

- Created: 2026-08-13
- Completed: 2026-08-20
- Branch: feature/change-add-pubspec-topics
- Polished: {YYYY-MM-DD}

## 目的

pub.dev でのパッケージの検索性を向上させるため、pubspec.yaml に `topics` を定義する。

pub.dev では `topics` で定義したキーワードによる検索ができる。現在の pubspec.yaml には `topics` が存在しないため、技術分野 (WebRTC) やプラットフォーム (Flutter) での検索にヒットしにくい。

## 現状

- pubspec.yaml には `topics` が未定義
- 他 SDK (sora-ios-sdk は Swift Package Manager、sora-android-sdk は Gradle / JitPack) には topics に相当する概念がなく、前例がない
- `sora` を topics に入れると、pub.dev 検索で Sorani Kurdish (クルド語) や OpenAI Sora 関連の無関係なパッケージと混同されるため、含めない

## 設計方針

- 以下の topics を定義する
  - `webrtc`: 技術分野での検索にヒットさせる
  - `flutter`: プラットフォームでの検索にヒットさせる

## 完了条件

- pubspec.yaml に `topics` が定義されている
- topics に `sora` が含まれていない
- `flutter pub publish --dry-run` の出力にエラーや警告がない

## 解決方法

- pubspec.yaml の `homepage` の直後に以下の `topics` を定義した
  - `webrtc`: 技術分野での検索にヒットさせる
  - `flutter`: プラットフォームでの検索にヒットさせる
- topics に `sora` は含めなかった (Sorani Kurdish や OpenAI Sora 関連のパッケージと混同されるため)
- `flutter pub publish --dry-run` で topics に関する警告が出ないことを確認した
  - 残る警告は CHANGELOG.md のバージョン言及のみであり、これは 0063 で扱う (公開時に pubspec.yaml のバージョンを `2026.1.0` へ変更することで解消する)
