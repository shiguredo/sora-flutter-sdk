# Opus の maxaveragebitrate を指定できるようにする

- Created: 2026-09-10
- Completed: {YYYY-MM-DD}
- Branch: feature/add-opus-maxaveragebitrate
- Polished: {YYYY-MM-DD}

## 目的

Sora Flutter SDK の接続設定から Opus の `maxaveragebitrate` を指定し、connect メッセージの `audio.opus_params` へ反映できるようにする。

[Sora のシグナリング型定義](https://sora-doc.shiguredo.jp/SIGNALING_TYPE) の `OpusParams` には `maxaveragebitrate` (6000..510000) が定義されている。現在の Sora 実装の connect メッセージ検証がこの項目を受理しないため、Opus 詳細パラメーターの対応からは切り出して別 issue とする。

## 現状

- `SoraConnectionConfig` には Opus 詳細パラメーターの型付きオプションがあるが、`maxaveragebitrate` は含まれていない
- Sora 実装の connect メッセージ検証 (`sora/src/sora_media_audio_opus.erl` の `validate_param`) は `maxaveragebitrate` の節を持たず、指定すると `UNKNOWN-OPUS-PARAM` として `error` を返す
- Sora 2025.1.0 / 2026.1.2 / 2026.2.0-canary のいずれでも同じで、現時点で `maxaveragebitrate` を送ると接続が `invalid_audio_format` で拒否される

## 設計方針

- Sora 実装が connect メッセージの `opus_params` で `maxaveragebitrate` を受理するようになった時点で対応する
- `SoraConnectionConfig` に `audioOpusParamsMaxaveragebitrate` (int?) を追加し、connect メッセージの `audio.opus_params.maxaveragebitrate` へ反映する
- 範囲は SIGNALING_TYPE に合わせて 6000-510000 (bps) とし、`SoraConnectionConfig.toMap()` の実行時に検証する
- `codec_type: OPUS` の併記、`audio: false` の扱い、`ptime` の非検証などは Opus 詳細パラメーターの既存実装に合わせる

## 完了条件

- [ ] `audioOpusParamsMaxaveragebitrate` を指定できる
- [ ] 指定時に connect メッセージの `audio.opus_params.maxaveragebitrate` へ反映される
- [ ] 6000-510000 の境界値と範囲外を検証するテストが追加されている
- [ ] 対象の Sora バージョンが connect メッセージの `maxaveragebitrate` を受理することを確認している
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する

## 関連

- `issues/closed/0060-add-opus-parameters.md`（Opus 詳細パラメーター本体の対応。`maxaveragebitrate` は Sora 実装が受理しないため切り出した）
