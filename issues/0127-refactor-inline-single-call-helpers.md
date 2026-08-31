# 単一呼び出しの private ヘルパーを inline 化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-inline-single-call-helpers
- Polished: {YYYY-MM-DD}

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
- 意味付けを残したい場合は inline 化と同時に呼び出し側に短いコメントを添える。
- 挙動変更なし。API サーフェスは private なので影響なし。

## 完了条件

- [ ] 上記 4 ヘルパーが削除されている。
- [ ] 呼び出し側が inline に書き換わっている。
- [ ] `flutter analyze` と関連テストが成功する。
