# devtools から音声ストリーミングの言語コードを指定できるようにする

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/add-devtools-audio-streaming-language-code
- Polished: {YYYY-MM-DD}

## 目的

devtools から音声ストリーミングの言語コードを指定して接続を試せるようにし、SDK の `SoraConnectionConfig.audioStreamingLanguageCode` を手元で確認できるようにする。

## 現状

- `devtools/lib/src/devtools_connection_controller.dart` の `DevToolsConnectRequest` に音声ストリーミングの言語コードを受け取るフィールドがない。
- 同じファイルの `buildSoraConnectionConfig` は `SoraConnectionConfig` を構築するが、`audioStreamingLanguageCode` を渡す経路がない。
- `devtools/lib/src/devtools_settings_sections.dart` の接続設定 UI にも言語コードの入力欄がない。
- SDK 側には `SoraConnectionConfig.audioStreamingLanguageCode` が追加済みである。

## 設計方針

- `DevToolsConnectRequest` に `String? audioStreamingLanguageCode` を追加する。
- `buildSoraConnectionConfig` で `SoraConnectionConfig.audioStreamingLanguageCode` へそのまま渡す。
- 接続設定 UI に言語コードの入力欄を追加する。未入力時は null とし、connect メッセージへキーを送らない。
- 入力値の形式検証は行わない（Sora は任意の文字列を言語コードとして扱う）。
- 既存の接続設定 UI の構成・スタイルと、既存フィールドの受け渡し方に合わせる。
- ソースコード本体・コメント・テスト名に issue 番号を持ち込まない。

## 完了条件

- [ ] devtools の接続設定 UI から音声ストリーミングの言語コードを指定できる。
- [ ] 指定値が `SoraConnectionConfig.audioStreamingLanguageCode` へ渡る。
- [ ] 未入力時は `SoraConnectionConfig.audioStreamingLanguageCode` が null になる。
- [ ] 既存の接続設定 UI の構成・スタイルと一致している。
- [ ] `flutter analyze` と関連するビルドが成功する。
