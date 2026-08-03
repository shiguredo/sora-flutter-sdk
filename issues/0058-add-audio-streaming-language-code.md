# 音声ストリーミングの言語コード指定に対応する

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/add-audio-streaming-language-code
- Polished: 2026-08-03

## 目的

Sora Flutter SDK の接続設定から `audio_streaming_language_code` を指定できるようにし、認証ウェブフックからの払い出しに依らず、クライアント側からも音声ストリーミングを利用できるようにする。

[Sora の音声ストリーミング機能](https://sora-doc.shiguredo.jp/AUDIO_STREAMING) では、シグナリング接続時または認証成功時の払い出しで言語コードを指定する必要がある。言語コードが指定されていない接続は音声ストリーミングの対象にならない。

## 現状

- `lib/src/sora_connection_config.dart` の `SoraConnectionConfig` に音声ストリーミングの言語コードを指定するフィールドがない
- `lib/src/sora_connection_signaling.dart` の `_buildConnectMessage` は `audio_streaming_language_code` を生成しない
- `README.md` では `audioStreamingLanguageCode` 対応を優先実装が可能な機能として記載している
- 認証ウェブフックから値を払い出せない環境では、クライアントから音声ストリーミング対象の接続を指定できない

## 設計方針

- `SoraConnectionConfig` に `String? audioStreamingLanguageCode` を追加する。`audioStreamingLanguageCode` の DartDoc も追記する
- `SoraConnectionConfig.toMap` に `audioStreamingLanguageCode` を追加する。これはネイティブ側（MethodChannel / FFI）への設定伝達に使われる
- `_buildConnectMessage` 内で、`config.audioStreamingLanguageCode` が非 null の場合に `message['audio_streaming_language_code']` を設定する。`toMap()` と `_buildConnectMessage()` の両方を変更する必要がある
- `audio: false` が設定されている場合、音声が無効であるため `audio_streaming_language_code` を connect メッセージに含めない
- 値が未指定の場合はキーを送信せず、既存の接続動作を維持する
- Sora は言語コードを任意の文字列として扱うため、SDK 独自の言語コード形式検証や長さ制限は追加しない
- `README.md` の接続設定例へ追加し、優先実装一覧から削除する
- 既存の `toMap()` テスト（`test/sora_connection_config_test.dart`）の期待値を更新する

## 完了条件

- [ ] `SoraConnectionConfig.audioStreamingLanguageCode` が公開されており、DartDoc が付与されている
- [ ] 指定値が `SoraConnectionConfig.toMap` に含まれる
- [ ] `_buildConnectMessage` で指定時に connect メッセージへ `audio_streaming_language_code` が設定される
- [ ] `audio: false` の場合は `audio_streaming_language_code` が connect メッセージに含まれない
- [ ] 未指定時に connect メッセージへキーが含まれない
- [ ] redirect 後の connect メッセージでも同じ値が維持される
- [ ] `README.md` に設定方法が記載され、優先実装一覧から削除されている
- [ ] `test/sora_connection_config_test.dart` の既存テストの期待値が更新されている
- [ ] 設定値のシリアライズと connect メッセージを検証するテストが追加されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
