# `sora_connect_message.dart` の `case true` / `case null` 分岐の重複を統合する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-connect-message-branch-dedup
- Polished: {YYYY-MM-DD}

## 目的

`lib/src/sora_connect_message.dart` の `case true` に相当するブロックと `case null` の body が完全に一致している 4 箇所（audio 2 か所、video 2 か所）を統合し、30 行程度削減する。

## 現状

`lib/src/sora_connect_message.dart` の audio / video 用の関数（例: `_audioWhenExplicitlyOn` と対応する `case null` 分岐、video 側同種）は「空マップのときの返り値」だけが異なり、他の body が完全に一致している。同じロジックが 4 ブロックに散っている。

将来 audio / video の connect メッセージフィールドが増えたときに 4 箇所全部を揃えて直す前提が発生する。

## 設計方針

- 差分（空マップのときの fallback）だけを引数で受けとる形の共通ヘルパーに統合する。例:
  ```dart
  Object? _audioMap(SoraConnectionConfig config, {required Object emptyFallback}) {
    final audio = <String, Object?>{};
    if (config.audioCodecType case final v?) audio['codec_type'] = v.value;
    if (config.audioBitRate case final v?) audio['bit_rate'] = v;
    return audio.isEmpty ? emptyFallback : audio;
  }
  ```
- `case true` / `case null` の分岐は共通ヘルパーの呼び出しに書き換える。
- video 側も同種の統合を行う。
- 挙動変更なし。既存のテストで担保する。

## 完了条件

- [ ] audio / video の連想メッセージ生成が共通ヘルパー経由に統合されている。
- [ ] `case true` / `case null` の重複が消えている。
- [ ] 既存の `test/sora_connect_message_test.dart` が全て通る。
- [ ] `flutter analyze` と関連テストが成功する。
