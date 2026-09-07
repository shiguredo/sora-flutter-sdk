# `sora_connect_message.dart` の `case true` / `case null` 分岐の重複を統合する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-connect-message-branch-dedup
- Polished: 2026-09-07

## 目的

`lib/src/sora_connect_message.dart` の `case true` に相当するブロックと `case null` の body が fallback 以外一致している 4 箇所（audio 2 か所、video 2 か所）を統合し、30 行程度削減する。

## 現状

`lib/src/sora_connect_message.dart` の audio / video 用の関数（例: `_audioConnectValueWhenExplicitlyOn` と対応する `case null` 分岐、video 側の `_videoConnectValueWhenExplicitlyOn` と対応分岐）は「空マップのときの返り値」だけが異なり、他の body が完全に一致している。同じロジックが 4 ブロックに散っている。

将来 audio / video の connect メッセージフィールドが増えたときに 4 箇所全部を揃えて直す前提が発生する。

## 設計方針

- 差分（空マップのときの fallback）だけを引数で受けとる形に、既存の audio 用・video 用 2 関数を fallback 引数付きの共通ヘルパー 2 本に改修する。例 (audio 用):
  ```dart
  Object? _audioMap(SoraConnectionConfig config, {required Object? emptyFallback}) {
    final audio = <String, Object?>{};
    if (config.audioCodecType case final v?) audio['codec_type'] = v.value;
    if (config.audioBitRate case final v?) audio['bit_rate'] = v;
    return audio.isEmpty ? emptyFallback : audio;
  }
  ```
  video 用も同型 (6 フィールド版) とする。
- `case true` / `case null` の分岐は共通ヘルパーの呼び出しに書き換える (`true` 側は `emptyFallback: true`、`null` 側は `emptyFallback: null`)。
- 新設・改修後のヘルパーには日本語コメントを付ける (AGENTS.md 準拠)。
- `0060-add-opus-parameters` は audio 側へのフィールド追加であり編集範囲が重なるため、実装時は rebase で競合を整理する。
- 挙動変更なし。

## 完了条件

- [ ] audio / video の Map 生成が共通ヘルパー 2 本経由に統合されている。
- [ ] `case true` / `case null` の重複が消えている。
- [ ] `audio: true` + 空 → `true` と `video: true` + 空 → `true` のテストが追加され、`test/sora_connect_message_test.dart` が全て通る。
- [ ] `flutter analyze` と関連テストが成功する。
