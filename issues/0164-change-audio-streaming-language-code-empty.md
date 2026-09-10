# 空文字列の audioStreamingLanguageCode の扱いを確定する

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/change-audio-streaming-language-code-empty
- Polished: {YYYY-MM-DD}

## 目的

`SoraConnectionConfig.audioStreamingLanguageCode` に空文字列が指定された場合の挙動を確定し、実装と DartDoc を一致させる。

## 現状

- `lib/src/sora_connection_signaling.dart` の `_buildConnectMessage` は、`config.audioStreamingLanguageCode` が非 null であれば connect メッセージの `audio_streaming_language_code` を設定する。空文字列も非 null のため、`''` がそのまま送信される。
- Sora の仕様は「指定するのは文字列であればなんでもかまいません」としており、空文字列を「指定あり」と扱うか「未指定」と同義に扱うかは明記されていない。
- `lib/src/sora_connection_config.dart` の DartDoc は「未指定の場合はキーを送信しない」と説明するが、空文字列の扱いには触れていない。

## 設計方針

- 空文字列を「未指定」と同義に扱いキーを送らないか、指定どおり送るかを確定する。
- 確定した挙動を `audioStreamingLanguageCode` の DartDoc とテストへ反映する。
- 空文字列以外（空白のみの文字列等）の扱いは変更しない。
- ソースコード本体・コメント・テスト名に issue 番号を持ち込まない。

## 完了条件

- [ ] 空文字列の扱いが決定されている。
- [ ] 決定した挙動が `audioStreamingLanguageCode` の DartDoc に記載されている。
- [ ] 決定した挙動を検証するテストが追加されている。
- [ ] モックやスタブを使用していない。
- [ ] `flutter analyze` と関連するテストが成功する。
