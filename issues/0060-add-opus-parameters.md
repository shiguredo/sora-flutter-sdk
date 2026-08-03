# Opus 詳細パラメーターを指定できるようにする

- Created: 2026-08-03
- Completed: {YYYY-MM-DD}
- Branch: feature/add-opus-parameters
- Polished: 2026-08-03

## 目的

Sora Flutter SDK の接続設定から Opus の詳細パラメーターを指定し、connect メッセージの `audio.opus_params` へ反映できるようにする。

[Sora のシグナリング型定義](https://sora-doc.shiguredo.jp/SIGNALING_TYPE) では、`channels`、`maxplaybackrate`、`maxaveragebitrate`、`minptime`、`ptime`、`stereo`、`sprop_stereo`、`useinbandfec`、`usedtx` を指定できる。

## 現状

- `SoraConnectionConfig` には `audioCodecType` と `audioBitRate` しかなく、Opus 詳細パラメーターの指定経路がない
- `lib/src/sora_connection_signaling.dart` の `_optionalAudioConnectValue` と `_audioConnectValueWhenExplicitlyOn` は `codec_type` と `bit_rate` だけを生成する
- `README.md` では `audioOpusParamsChannels`、`audioOpusParamsStereo`、`audioOpusParamsUseinbandfec` などを優先実装が可能な機能として記載している
- 認証ウェブフックから値を払い出せない環境では、クライアントから Opus の動作を調整できない

## 設計方針

- `SoraConnectionConfig` に次の型付きオプションを追加する
  - `audioOpusParamsChannels` (int)
  - `audioOpusParamsMaxplaybackrate` (int)
  - `audioOpusParamsMaxaveragebitrate` (int)
  - `audioOpusParamsMinptime` (int)
  - `audioOpusParamsPtime` (int)
  - `audioOpusParamsStereo` (bool)
  - `audioOpusParamsSpropStereo` (bool)
  - `audioOpusParamsUseinbandfec` (bool)
  - `audioOpusParamsUsedtx` (bool)
- 指定された項目だけを `audio.opus_params` に含める
- 全項目が未指定の場合は `opus_params` を送信せず、既存の connect メッセージを維持する
- `audio: false` の場合は従来どおり `audio: false` を優先し、`opus_params` は送信しない。範囲検証は 0057 の `audioBitRate` / `videoBitRate` と同様に、`audio: false` でも行う（無効時でも不正な値を検出することで、設定の意図しない誤指定を防ぐ）
- `audio: true` 明示時も未指定時も、Opus パラメーターが指定されていれば `audio` オブジェクトを生成して `opus_params` を含める
- 数値項目は WEBSOCKET_SIGNALING の「オーディオの Opus 設定指定」または SIGNALING_TYPE の型定義に定義されている範囲に基づいて、connect メッセージ送信前に検証する
  - `channels`: 1-8
  - `maxplaybackrate`: 8000-48000 (Hz)
  - `maxaveragebitrate`: 6000-510000 (bps)。SIGNALING_TYPE の型定義にのみ範囲が定義されている
  - `minptime`: 3-120 (ms)
  - `ptime`: WEBSOCKET_SIGNALING の opus_params 一覧に含まれず、SIGNALING_TYPE にも範囲の定義がないため、範囲検証しない
- 検証ロジックは `lib/src/sora_validator.dart` にテスト可能な関数として追加し、connect メッセージの構築時に呼び出す。範囲外の値は `ArgumentError` を送出する
- 不正な値を黙って無視せず、利用者が原因を特定できる例外にする
- Sora の仕様では `role` が `sendrecv` または `sendonly` の場合のみ Opus の設定を指定できる。`recvonly` では Sora 側で無視されるため、SDK 側では制限せずそのまま送信する（既存の `audioCodecType` / `audioBitRate` と同じ扱い）
- `SoraConnectionConfig.toMap` に各設定値を含める（ネイティブ側への設定伝達とテストで使用される）。キーは既存の `audioBitRate` 等と同じフラットキー（`audioOpusParamsChannels` 等）で追加する
- 追加したオプションの DartDoc に実験的機能であることを明記する
- 実験的機能であること、Sora 側の対応状況、利用には事前にサポートへの連絡が必要であること、`usedtx` 有効時に録画がおかしくなること、`role` が `sendrecv` / `sendonly` の場合のみ有効であることを `README.md` の「SoraConnectionConfig の設定」セクションの設定例コードに明記し、優先実装一覧から削除する

## 完了条件

- [ ] 9 種類の Opus 詳細パラメーターを `SoraConnectionConfig` から指定できる
- [ ] 指定した項目だけが connect メッセージの `audio.opus_params` に含まれる
- [ ] 全項目が未指定の場合は `opus_params` が含まれない
- [ ] `audio` が未指定でも Opus パラメーターを指定した場合は `audio` オブジェクトが生成される
- [ ] `audio: true` を明示した場合も `opus_params` が含まれる
- [ ] `audio: false` の場合は `audio: false` が維持される
- [ ] `audio: false` でも範囲検証が有効である
- [ ] 範囲が定義されている数値項目 (`channels` / `maxplaybackrate` / `maxaveragebitrate` / `minptime`) の境界値と範囲外を検証するテストが追加されている
- [ ] 範囲外の `ptime` が例外にならず送信されるテストが追加されている
- [ ] boolean 項目の `true` と `false` が欠落せず送信される
- [ ] redirect 後の connect メッセージでも設定が維持される
- [ ] `SoraConnectionConfig.toMap` の既存テストの期待値が更新されている
- [ ] 追加したオプションの DartDoc に実験的機能であることが記載されている
- [ ] `README.md` の「SoraConnectionConfig の設定」セクションの設定例コードに設定方法と実験的機能であることが記載されている
- [ ] モックやスタブを使用していない
- [ ] `flutter analyze` と関連するテストが成功する
