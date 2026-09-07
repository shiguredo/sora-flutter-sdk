# `sora_data_channel_controller_test.dart` の `applyOfferMessage 回帰シナリオ` group を整理し実 API 検証を拡充する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/test-apply-offer-message
- Polished: 2026-09-07

## 目的

`test/sora_data_channel_controller_test.dart` の `applyOfferMessage 回帰シナリオ` group が実際には `applyOfferMessage` を呼んでおらず、`updateCompressFlagIfPresent` 相当の静的関数だけを exercise している状態を解消する。重複 group を整理し、instance method の実 API 検証を拡充する。

## 現状

`test/sora_data_channel_controller_test.dart` の group `applyOfferMessage 回帰シナリオ` (224-323 行目) は、静的関数 `updateCompressFlagIfPresent(payload, label, (v) => flag = v)` をローカル `var flag` に対して駆動しているだけ。同ファイル 146-196 行目に `updateCompressFlagIfPresent` の独立 group が既に存在するため重複している。実 instance method `applyOfferMessage` の副作用（5 つの compress フラグ更新 + `updateCustomChannelCompress` + `deflateraw` 差分 + `emitDataChannelAvailable` 連携）を検証していない。

instance 挙動のカバレッジは同ファイル別 group の FFI-gated テスト 1 件 (`applyOfferMessage → emitDataChannelAvailable (FFI)`、325-372 行目) に依存しており、FFI が利用不可な環境では `skip: ffiTestEnvironment.skipReason` で skip される。

`applyOfferMessage` 本体は `webrtcClient` を触らないが、コンストラクタが具象 `WebrtcClient` を要求し、生成経路が FFI ロード必須のため、非 FFI 環境での instance 生成はできない。抽象化 (interface 抽出等) は本 issue の範囲外とする。

## 設計方針

- `applyOfferMessage 回帰シナリオ` group を削除し、静的関数の検証は既存の `updateCompressFlagIfPresent` group に集約する (切り出しではなく削除+集約)。
- FFI-gated の instance テストを拡充し、5 フラグ全て + `updateCustomChannelCompress` + `deflateraw` 差分 + `emitDataChannelAvailable` 連携を検証する。skip 理由は既存 helper (`prepareFfiTestEnvironment()` + `skip:`) を再利用し、`if (!ffiAvailable) return;` 相当の silent skip は使わない。
- モックとスタブは使わない。
- `0118-refactor-custom-channel-compress-private` と assert 対象が重なるため、`0118` の完了後に実施する。`0135` 確定までは現行の `test/` 配置に従う。
- テスト名は日本語。

## 完了条件

- [ ] `applyOfferMessage 回帰シナリオ` group が削除され、静的関数の検証が既存 group に集約されている。
- [ ] instance テストが 5 フラグ + custom + `deflateraw` + emit 連携を検証している。
- [ ] テスト名が日本語で書かれている。
- [ ] `flutter analyze` と `flutter test test/sora_data_channel_controller_test.dart` が成功する。
