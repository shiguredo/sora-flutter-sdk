# 単一呼び出しの private ヘルパーを inline 化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-inline-single-call-helpers
- Polished: 2026-09-07

## 目的

呼び出し箇所が 1 か所しかない thin wrapper 相当の private ヘルパーを inline 化し、意味の薄い間接層を除く。

## 現状

以下の private ヘルパーはそれぞれ 1 か所からのみ呼ばれており、本体は 1〜2 行の thin wrapper:

- `lib/src/sora_connection_signaling.dart` の `_handleWebSocketTimeout()` → `_emitTimeoutEvent()` を呼ぶだけ
- `lib/src/sora_connection.dart` の `_cameraErrorCodeToName(errorCode)` → `_cameraErrorCodeNames[errorCode] ?? 'ERROR_UNKNOWN'` を返すだけ
- `lib/src/sora_connection_signaling.dart` の `_optionalAudioConnectValue()` → `buildOptionalAudioConnectValue(config)` を呼ぶだけ
- `lib/src/sora_connection_signaling.dart` の `_optionalVideoConnectValue()` → `buildOptionalVideoConnectValue(config)` を呼ぶだけ

これらは呼び出し側で inline に書いても可読性を損なわない。むしろ間接層が減って読みやすくなる。

## 設計方針

- 上記 4 ヘルパーを削除し、呼び出し側で inline に書き換える。
- inline 化と同時に呼び出し側へ短いコメントを必ず添える (意味ラベルの保持のため)。`_handleWebSocketTimeout` 呼び出し側には WebSocket タイムアウト時の処理である旨、`_optionalAudioConnectValue` / `_optionalVideoConnectValue` の doc (`connect メッセージ用の audio / video 値` 相当) は呼び出し側へ移設する。
- `0060-add-opus-parameters` と `_optionalAudioConnectValue` 等の生成内容で編集範囲が重なるため、実装時は rebase で競合を整理する。
- 挙動変更なし。API サーフェスは private なので影響なし。

## 完了条件

- [ ] 上記 4 ヘルパーが削除されている。
- [ ] 呼び出し側が inline に書き換わり、意味ラベルのコメントが残っている。
- [ ] `flutter analyze` と `flutter test test/sora_connect_message_test.dart test/sora_connection_test.dart` が成功する。
