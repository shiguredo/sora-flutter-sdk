# `sora_data_channel_controller_test.dart` の `applyOfferMessage 回帰シナリオ` group を実 API 検証に置き換える

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/test-apply-offer-message
- Polished: {YYYY-MM-DD}

## 目的

`test/sora_data_channel_controller_test.dart` の `applyOfferMessage 回帰シナリオ` group が実際には `applyOfferMessage` を呼んでおらず、`updateCompressFlagIfPresent` 相当の静的関数だけを exercise している状態を解消する。instance method の実 API を検証する形に置き換える。

## 現状

`test/sora_data_channel_controller_test.dart` の group `applyOfferMessage 回帰シナリオ` は、静的関数 `updateCompressFlagIfPresent(payload, label, (v) => flag = v)` をローカル `var flag` に対して駆動しているだけ。実 instance method `applyOfferMessage` の副作用（5 つの `_*DataChannelCompress` 更新 + `updateCustomChannelCompress` + `deflateraw` 差分）を検証していない。

instance 挙動のカバレッジは同ファイル別 group の FFI-gated テスト 1 件に依存しており、FFI が利用不可な環境ではカバーが消える。

## 設計方針

- 静的関数（`updateCompressFlagIfPresent` 等）のテストは別 group に切り出し、名前も「静的関数 XXX の挙動」等に変える。
- `applyOfferMessage` の instance テストを、FFI 依存を切り離してテスト可能にする形で追加する。`SoraDataChannelController` の抽象化が必要になる可能性があるため、テスト向けの hook / factory 引数を検討する。
- モックとスタブは使わない。
- FFI 依存を切り離せない場合は理由を明示する（`if (!ffiAvailable) return;` は使わない、`test(..., skip: ...)` を使う）。
- テスト名は日本語。

## 完了条件

- [ ] `applyOfferMessage` の instance テストが FFI ロード不可でも意味のある形で走る、またはロード必須の理由が skip 理由で明示されている。
- [ ] 静的関数のテストが group として明示分離されている。
- [ ] テスト名が日本語で書かれている。
- [ ] `flutter analyze` と関連テストが成功する。
