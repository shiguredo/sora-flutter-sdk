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
- `codec_type: OPUS` の併記、`audio: false` の扱い、`ptime` の非検証、DartDoc の実験的機能の明記、README の設定例への追記などは Opus 詳細パラメーターの既存実装に合わせる

## 完了条件

- [ ] `audioOpusParamsMaxaveragebitrate` を指定できる
- [ ] 指定時に connect メッセージの `audio.opus_params.maxaveragebitrate` へ反映される
- [ ] 6000-510000 の境界値と範囲外を検証するテストが追加されている
- [ ] 対象の Sora バージョンで connect メッセージの `audio.opus_params.maxaveragebitrate` が (1) 検証を通過し、(2) `convert_opus_params` で `#opus_params` に取り込まれ、(3) 生成 SDP の `maxaveragebitrate` に反映されることを確認している
- [ ] 追加したオプションの DartDoc に実験的機能であること（事前にサポートへの連絡が必要、`role` が `sendrecv` / `sendonly` の場合のみ有効）が記載されている
- [ ] `README.md` の「SoraConnectionConfig の設定」セクションの設定例に `audioOpusParamsMaxaveragebitrate` が追加されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する

## pending にする理由

Sora 実装が connect メッセージの `opus_params` で `maxaveragebitrate` を受理していないため、SDK 側を実装しても接続が拒否される。`sora/src/sora_media_audio_opus.erl` の `validate_param` に `maxaveragebitrate` の節が無く、Sora 2025.1.0 / 2026.1.2 / 2026.2.0-canary のいずれでも同じである。加えて `convert_opus_params` も `maxaveragebitrate` を取り込まず、`sora_sdp.erl` は SDP の `maxaveragebitrate` を `bit_rate` から生成するため、仮に検証を通過しても指定が反映されない。

Sora 実装が connect メッセージの `maxaveragebitrate` を検証・反映するようになり、対象バージョンで確認できた時点で reopened にして対応する。

## 関連

- `issues/closed/0060-add-opus-parameters.md`（Opus 詳細パラメーター本体の対応。`maxaveragebitrate` は Sora 実装が受理しないため切り出した）
