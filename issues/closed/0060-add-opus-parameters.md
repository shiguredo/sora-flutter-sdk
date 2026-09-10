# Opus 詳細パラメーターを指定できるようにする

- Created: 2026-08-03
- Completed: 2026-09-10
- Branch: feature/add-opus-parameters
- Polished: 2026-09-10

## 目的

Sora Flutter SDK の接続設定から Opus の詳細パラメーターを指定し、connect メッセージの `audio.opus_params` へ反映できるようにする。

[Sora のシグナリング型定義](https://sora-doc.shiguredo.jp/SIGNALING_TYPE) では、`channels`、`maxplaybackrate`、`minptime`、`ptime`、`stereo`、`sprop_stereo`、`useinbandfec`、`usedtx` を指定できる。`maxaveragebitrate` も型定義にあるが、Sora 実装の connect メッセージ検証が受理しないため本 issue の対象から外す。

本機能は `README.md` の優先実装一覧に記載されている優先実装が可能な機能である。

## 現状

- `SoraConnectionConfig` には `audioCodecType` と `audioBitRate` しかなく、Opus 詳細パラメーターの指定経路がない
- `lib/src/sora_connect_message.dart` の `buildOptionalAudioConnectValue` と `_audioConnectValueWhenExplicitlyOn` は `codec_type` と `bit_rate` だけを生成する。`lib/src/sora_connection_signaling.dart` の `_optionalAudioConnectValue` は `buildOptionalAudioConnectValue` へ委譲するだけである
- `README.md` では `audioOpusParamsChannels`、`audioOpusParamsStereo`、`audioOpusParamsUseinbandfec` などを優先実装が可能な機能として記載している
- 認証ウェブフックから値を払い出せない環境では、クライアントから Opus の動作を調整できない

## 設計方針

- `SoraConnectionConfig` に次の nullable な型付きオプションを追加する。未指定は null として扱い、`audio.opus_params` へ含めない
  - `audioOpusParamsChannels` (int?)
  - `audioOpusParamsMaxplaybackrate` (int?)
  - `audioOpusParamsMinptime` (int?)
  - `audioOpusParamsPtime` (int?)
  - `audioOpusParamsStereo` (bool?)
  - `audioOpusParamsSpropStereo` (bool?)
  - `audioOpusParamsUseinbandfec` (bool?)
  - `audioOpusParamsUsedtx` (bool?)
- 指定された項目だけを `audio.opus_params` に含める。`audio.opus_params` の構築は `lib/src/sora_connect_message.dart` の `buildOptionalAudioConnectValue` と `_audioConnectValueWhenExplicitlyOn` に追加し、`test/sora_connect_message_test.dart` で検証する
- 全項目が未指定の場合は `opus_params` を送信せず、既存の connect メッセージを維持する
- `audio: false` の場合は従来どおり `audio: false` を優先し、`opus_params` は送信しない。範囲検証は 0057 の `audioBitRate` / `videoBitRate` と同様に、`audio: false` でも行う（無効時でも不正な値を検出することで、設定の意図しない誤指定を防ぐ）
- `audio: true` 明示時も未指定時も、Opus パラメーターが指定されていれば `audio` オブジェクトを生成して `opus_params` を含める。`opus_params` は `codec_type: OPUS` と併記しないと Sora が `invalid_audio_format` で接続を拒否するため、Opus パラメーター指定時は `codec_type: OPUS` を必ず含める（`AudioCodecType` は opus のみのため衝突しない）
- 数値項目は WEBSOCKET_SIGNALING の「オーディオの Opus 設定指定」または SIGNALING_TYPE の型定義に定義されている範囲に基づいて、connect メッセージ送信前に検証する
  - `channels`: 1-8
  - `maxplaybackrate`: 8000-48000 (Hz)
  - `minptime`: 3-120 (ms)
  - `ptime`: WEBSOCKET_SIGNALING の opus_params 一覧に含まれず、SIGNALING_TYPE にも範囲の定義がないため、範囲検証しない
- 検証ロジックは `lib/src/sora_validator.dart` にテスト可能な関数として追加し、`SoraConnectionConfig.toMap()` の実行時に呼び出す（0057 のビットレート検証と 0091 の「検証場所は `toMap()` に統一する」方針に合わせ、ネイティブへ渡す前に fail-fast する）。範囲外の値は既存の `_validateOptionalIntInRange` と同じく `RangeError` を送出する
- 不正な値を黙って無視せず、利用者が原因を特定できる例外にする
- Sora の仕様では `role` が `sendrecv` または `sendonly` の場合のみ Opus の設定を指定できると記載されている。`recvonly` 時の挙動は一次資料に記載がないため、既存の `audioCodecType` / `audioBitRate` と同じく SDK 側では制限せずそのまま送信する（`recvonly` で Sora が受理するかは実機確認していない）
- `SoraConnectionConfig.toMap` に各設定値を含める（ネイティブ側への設定伝達とテストで使用される）。キーは既存の `audioBitRate` 等と同じフラットキー（`audioOpusParamsChannels` 等）で追加する
- 追加したオプションの DartDoc に実験的機能であることを明記する
- 実験的機能であること、Sora 側の対応状況、利用には事前にサポートへの連絡が必要であること、`usedtx` 有効時に録画がおかしくなること、`role` が `sendrecv` / `sendonly` の場合のみ有効であることを `README.md` の「SoraConnectionConfig の設定」セクションの設定例コードに明記し、優先実装一覧から削除する

## 完了条件

- [ ] 8 種類の Opus 詳細パラメーターを `SoraConnectionConfig` から指定できる
- [ ] 指定した項目だけが connect メッセージの `audio.opus_params` に含まれる
- [ ] Opus パラメーターを指定した場合、connect メッセージの `audio.codec_type` に `OPUS` が併記される
- [ ] 全項目が未指定の場合は `opus_params` が含まれない
- [ ] `audio` が未指定でも Opus パラメーターを指定した場合は `audio` オブジェクトが生成される
- [ ] `audio: true` を明示した場合も `opus_params` が含まれる
- [ ] `audio: false` の場合は `audio: false` が維持される
- [ ] `audio: false` でも範囲検証が有効である
- [ ] 範囲が定義されている数値項目 (`channels` / `maxplaybackrate` / `minptime`) の境界値と範囲外を検証するテストが追加されている
- [ ] 範囲が定義されていない `ptime` に任意の値を指定しても例外にならず送信されるテストが追加されている
- [ ] boolean 項目の `true` と `false` が欠落せず送信される
- [ ] redirect 後の connect メッセージでも設定が維持される
- [ ] `SoraConnectionConfig.toMap` の既存テストの期待値が更新されている
- [ ] 追加したオプションの DartDoc に実験的機能であることが記載されている
- [ ] `README.md` の「SoraConnectionConfig の設定」セクションの設定例コードに設定方法と実験的機能であることが記載されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する

## 解決方法

- `SoraConnectionConfig` に Opus の詳細パラメーター 8 種類 (`audioOpusParamsChannels` / `Maxplaybackrate` / `Minptime` / `Ptime` / `Stereo` / `SpropStereo` / `Useinbandfec` / `Usedtx`) を追加した
- `lib/src/sora_validator.dart` に `validateAudioOpusParams` を追加し、`SoraConnectionConfig.toMap()` で範囲検証するようにした
- `lib/src/sora_connect_message.dart` で `audio.opus_params` を構築し、`codec_type: OPUS` を併記するようにした
- `README.md` の設定例と優先実装一覧を更新した
- `maxaveragebitrate` は Sora 実装の connect メッセージ検証が受理しないため本 issue の対象から外した
