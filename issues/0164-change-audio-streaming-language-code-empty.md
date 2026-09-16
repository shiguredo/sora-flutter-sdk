# 空文字列の audioStreamingLanguageCode の扱いを確定する

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/change-audio-streaming-language-code-empty
- Polished: 2026-09-10

## 目的

`SoraConnectionConfig.audioStreamingLanguageCode` に空文字列が指定された場合の挙動を確定し、実装と DartDoc を一致させる。

## 現状

- `lib/src/sora_connection_signaling.dart` の `_buildConnectMessage` は、`config.audio != false` かつ `config.audioStreamingLanguageCode` が非 null の場合に connect メッセージの `audio_streaming_language_code` を設定する。空文字列も非 null のため、`audio` が `false` でない既定状態では `''` がそのまま送信される。
- Sora の仕様 ([AUDIO_STREAMING](https://sora-doc.shiguredo.jp/AUDIO_STREAMING) の「言語コードの指定」) は「指定するのは文字列であればなんでもかまいません」としており、空文字列を「指定あり」と扱うか「未指定」と同義に扱うかは明記されていない。
- `lib/src/sora_connection_config.dart` の DartDoc は「未指定の場合はキーを送信しない」と説明するが、空文字列の扱いには触れていない。
- 他の `String?` フィールド (`clientId` / `bundleId`) と sora-js-sdk は空文字列をそのまま送る。

## 設計方針

- 空文字列は「指定あり」と同義に扱い、そのまま送る（現状の挙動を維持する）。`null` のみを未指定としてキーを送らない。
- 根拠: Sora は言語コードを任意の文字列として扱う (`AUDIO_STREAMING`)。他の `String?` フィールド (`clientId` / `bundleId`) と sora-js-sdk も空文字列をそのまま送る。空文字列だけを特別扱いすると一貫性が崩れる。
- 確定した挙動を `audioStreamingLanguageCode` の DartDoc に反映する（`null` は未指定としてキーを送らない、`''` は指定ありとしてそのまま送る）。`_buildConnectMessage` の実装は変更しない。
- 空文字列以外（空白のみの文字列等）の扱いは変更しない（値を trim しない）。空白のみの正規化は devtools 側の UI 層で行う。
- `SoraConnectionConfig.toMap()` は従来どおり `audioStreamingLanguageCode` をそのまま含む。
- テストは `test/sora_connect_message_test.dart`（`_buildConnectMessage` が純関数化された場合は純関数側）へ追加し、`''` が設定されることと `null` でキーが含まれないことを検証する。
- ソースコード本体・コメント・テスト名に issue 番号を持ち込まない。

## 完了条件

- [ ] 空文字列を「指定あり」と同義に扱い、そのまま送ることが DartDoc に記載されている。
- [ ] `audioStreamingLanguageCode: ''` のとき connect メッセージに `audio_streaming_language_code: ''` が含まれることを検証するテストが追加されている。
- [ ] `audioStreamingLanguageCode: null` のときキーが含まれないことを検証するテストがある。
- [ ] `audio` が `false` のとき、空文字列でもキーが含まれないことを検証するテストがある。
- [ ] モックやスタブを使用していない。
- [ ] `flutter analyze` と関連するテストが成功する。

## 関連

- `issues/0162-refactor-connect-message-pure-function.md`（`_buildConnectMessage` を純関数化する。先にマージされた場合は純関数側と `test/sora_connect_message_test.dart` へ反映する）
- `issues/0163-add-devtools-audio-streaming-language-code.md`（UI 層で `''` を null に正規化するため、本 issue の決定に影響されない）
