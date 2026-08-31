# `SoraDataChannelController.customChannelCompress` の `@visibleForTesting` public フィールドを private + getter 化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-custom-channel-compress-private
- Polished: {YYYY-MM-DD}

## 目的

`customChannelCompress` が `@visibleForTesting` の付いた public フィールドとして公開されているが、Dart 慣習では `_customChannelCompress` + `@visibleForTesting` getter の方が意図が伝わる。書き換え可能な public フィールドをテスト用に晒すのは避けたい。

## 現状

`lib/src/sora_data_channel_controller.dart` の `SoraDataChannelController.customChannelCompress` は `@visibleForTesting` 付きの public フィールドとして宣言されている。

- Dart で `@visibleForTesting` を付ける場合、public フィールドではなく private フィールド + public getter に分ける方が「本番コードから書き換えられない」ことを表現しやすい。
- 現状の書き方だと本番コードからも書き換え可能で、テスト以外の経路で誤って touch される余地がある。

## 設計方針

- private フィールド `_customChannelCompress` を定義し、public には `@visibleForTesting` getter として公開する。
- テストコードは getter 経由で読む。書き換えが必要なテストがある場合は setter も `@visibleForTesting` で公開するか、テスト専用のヘルパーを追加する。
- 本番コードでの参照は private フィールド経由に統一する。
- 挙動変更なし。API 面の整理のみ。

## 完了条件

- [ ] `customChannelCompress` が private + `@visibleForTesting` getter に分離されている。
- [ ] 本番コードから public フィールドに書き込む経路が消えている。
- [ ] テストコードが getter 経由で読めている。
- [ ] `flutter analyze` と関連テストが成功する。
