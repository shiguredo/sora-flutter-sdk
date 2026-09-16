# `DataChannelController.customChannelCompress` を private + 非変更 getter 化する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-custom-channel-compress-private
- Polished: 2026-09-07

## 目的

`customChannelCompress` が `@visibleForTesting` の付いた public フィールドとして外部から Map 内容を変更できる状態を解消する。private フィールド + 非変更 Map を返す getter に分けて、テスト以外の経路で誤って touch されないようにする。

## 現状

`lib/src/sora_data_channel_controller.dart` の `DataChannelController.customChannelCompress` は `@visibleForTesting` 付きの `final Map<String, bool>` フィールド (124-125 行目) として宣言されている。`final` のため再代入は不可だが、同一 Map インスタンスへの `addAll` / `clear` / `[]=` による内容変更は外部から可能である。

本番コードの書き込みは `updateCustomChannelCompress` の `addAll` (208 行目) と `clear` (244 行目) の 2 箇所、読み取りは `_resolveCompressForLabel` 等の 3 箇所 (300, 359, 619 行目) である。`test/` からの直接参照は 0 件である。

当該クラスは `@internal` かつ `lib/sora_sdk.dart` から export されていないため、公開 API への影響は無い。`src/` 直接利用者には破壊的名称変更になるが、正式リリース前のため直接変更する。`CHANGELOG.md` への記載は行わない (`CODEBASE.md` の「正式リリース前」節に従う)。

## 設計方針

- private フィールド `_customChannelCompress` を定義し、public には `@visibleForTesting Map<String, bool> get customChannelCompress => UnmodifiableMapView(_customChannelCompress);` として公開する (`dart:collection` を import する)。単純な同一参照返却ではなく非変更 view とすることで、getter 経由の内容変更を防ぐ。
- setter は追加しない (`test/` からの直接参照が 0 件のため不要)。
- 本番コードの読み書きは private フィールド経由に統一する。
- 挙動変更なし。内部 API 面の整理のみ。

## 完了条件

- [ ] `customChannelCompress` が private フィールド + 非変更 view を返す `@visibleForTesting` getter に分離されている。
- [ ] 本番コードが private フィールド経由に統一され、外部から内容変更できる経路が無い (`grep customChannelCompress lib/ test/` で確認する)。
- [ ] `flutter analyze` と `flutter test test/sora_data_channel_controller_test.dart` が成功する。
