# devtools から音声ストリーミングの言語コードを指定できるようにする

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/add-devtools-audio-streaming-language-code
- Polished: 2026-09-10

## 目的

devtools から音声ストリーミングの言語コードを指定して接続を試せるようにし、SDK の `SoraConnectionConfig.audioStreamingLanguageCode` を手元で確認できるようにする。

## 現状

- `devtools/lib/src/devtools_connection_controller.dart` の `DevToolsConnectRequest` に音声ストリーミングの言語コードを受け取るフィールドがない。
- 同じファイルの `buildSoraConnectionConfig` は `SoraConnectionConfig` を構築するが、`audioStreamingLanguageCode` を渡す経路がない。
- `devtools/lib/src/devtools_settings_sections.dart` の接続設定 UI にも言語コードの入力欄がない。
- `devtools/lib/main.dart` の `_buildConnectRequest` と `_buildConnectionSettingsSection` は既存フィールド（`clientId` / `bundleId` / `audioBitRate` 等）を controller 経由で配線しているが、言語コードの controller と受け渡しがない。
- SDK 側には `SoraConnectionConfig.audioStreamingLanguageCode` が追加済みである。

## 設計方針

- `DevToolsConnectRequest` に `String? audioStreamingLanguageCode` を追加する。
- `buildSoraConnectionConfig` で `SoraConnectionConfig.audioStreamingLanguageCode` へそのまま渡す。
- `devtools/lib/main.dart` に言語コード用の `TextEditingController` を追加し、`initState` で初期化して `dispose` で破棄する。`DevToolsConnectionSettingsSection` へ受け渡し、`_buildConnectRequest` で `audioStreamingLanguageCode` へ変換して渡す。接続確認ダイアログにも `audio_streaming_language_code` を表示する。
- 接続設定 UI に言語コードの入力欄を追加する。入力欄は `Media` グループの `Audio Codec` / `Audio Bitrate (kbps)` 行の近傍に、`Client ID` / `Bundle ID` と同形（`TextFormField` + `InputDecoration(labelText: 'Audio Streaming Language Code', border: OutlineInputBorder(), isDense: true)`）で追加する。
- 入力欄の値は既存の `_optionalText` と同様に trim し、空文字列または空白のみの場合は null とする（`''` を config へ渡さない）。未入力時は connect メッセージへキーを送らない。
- SDK 側の空文字列の扱いは `0164-change-audio-streaming-language-code-empty` で確定するが、本 issue は UI 層で `''` を null に正規化するため影響を受けない。
- 入力値の形式検証は行わない（Sora は任意の文字列を言語コードとして扱う）。
- ソースコード本体・コメント・テスト名に issue 番号を持ち込まない。

## 完了条件

- [ ] `DevToolsConnectRequest` に `audioStreamingLanguageCode` が追加されている。
- [ ] `devtools/lib/main.dart` に言語コード用の `TextEditingController` が追加され、`initState` で初期化、`dispose` で破棄され、`_buildConnectRequest` と `_buildConnectionSettingsSection` に配線されている。
- [ ] devtools の接続設定 UI から音声ストリーミングの言語コードを指定できる。
- [ ] 指定値が `SoraConnectionConfig.audioStreamingLanguageCode` へ渡る。
- [ ] 未入力時および空白のみの入力時は `SoraConnectionConfig.audioStreamingLanguageCode` が null になる。
- [ ] 入力欄が `Media` グループの `Audio Codec` / `Audio Bitrate (kbps)` 行の近傍に `Client ID` / `Bundle ID` と同形で追加され、ラベルが `Audio Streaming Language Code` である。
- [ ] 接続確認ダイアログに `audio_streaming_language_code` が表示される。
- [ ] `devtools/test/devtools_connection_controller_test.dart` の `buildSoraConnectionConfig` の伝搬テストに `audioStreamingLanguageCode` が追加されている。
- [ ] `flutter analyze` と関連するビルドが成功する。

## 関連

- `issues/0164-change-audio-streaming-language-code-empty.md`（SDK 側の空文字列の扱い。本 issue は UI 層で `''` を null に正規化するため影響を受けない）
