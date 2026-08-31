# `PushAudio.pushPcm` の引数検証を `pullPcm` と対称に追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-push-audio-argument-validation
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`PushAudio.pushPcm` に引数検証がなく、`channels == 0` で `IntegerDivisionByZeroException` が発生する、`sampleRate <= 0` や `channels < 0` で native 未定義動作に至る、といった問題を解消する。`pullPcm` が持つ検証との対称性を確保する。

## 現状

`lib/src/sora_push_audio.dart` の `PushAudio.pullPcm` は `sampleRate` / `channels` / `durationMs` をすべて `ArgumentError` で検証する（positive 検証）。`PushAudio.pushPcm` は検証が一切なく、以下の問題を起こす:

- `channels == 0` の場合、`length ~/ channels` が Dart 側の `IntegerDivisionByZeroException` で crash する。
- `channels < 0` / `sampleRate <= 0` が native 側の `soraPushAudioOnData` に渡り、libwebrtc-c の PushAudioDevice で未定義動作になる可能性がある。

## 設計方針

- `PushAudio.pushPcm` に `pullPcm` と同等の `ArgumentError.value` チェック（`sampleRate > 0`、`channels > 0`）を追加する。
- 引数検証はメソッド冒頭で行い、`WebrtcClient.sharedLib` アクセス（native ライブラリのロード）と `_ensureBuffer(length)` のどちらより先に fail-fast する。これにより native ライブラリがロードできない環境（CI の `flutter test` など）でも検証テストが実行可能になる。
- 検証メッセージは英語で統一する（規約準拠）。dartdoc は日本語で範囲・単位を明記する。

## 完了条件

- [ ] `pushPcm(sampleRate: 0)` / `pushPcm(channels: 0)` などが `ArgumentError` で拒否される。
- [ ] `pullPcm` と同種の検証がすべての PushAudio API で対称に揃う。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。
