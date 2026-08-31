# `SoraLocalVideoHandle` に `==` / `hashCode` を override する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-sora-local-video-handle-equality
- Polished: {YYYY-MM-DD}

## 目的

`SoraLocalVideoHandle` は公開の `@immutable` value class として宣言されているが、
`==` / `hashCode` を override していないため、`textureId` が同じ 2 つのハンドルは
identity 比較で別物と判定される。`@immutable` 契約と挙動を合わせ、value equality
に依存する使い方 (`Stream.distinct()` などの de-duplication、`Set` 格納、テスト
での value 比較) を安全にする。

## 現状

`lib/src/sora_local_video_handle.dart` の `SoraLocalVideoHandle` は
`@immutable` かつ単一 field (`textureId: int`) の value class として export
されている (`lib/sora_sdk.dart` から export)。しかし `==` と `hashCode` は
override されていないため、Dart のデフォルト実装 (identity 比較) が使われる。

`SoraConnection.localVideo` (`lib/src/sora_connection.dart`) は broadcast
`StreamController` で毎回新しい `SoraLocalVideoHandle(textureId: ...)`
インスタンスを生成して emit するため、同じ `textureId` でも都度別インスタンス
になり、消費側で value 比較を期待する API (`Stream.distinct()`) が意図通りに
働かない。

## 設計方針

- `SoraLocalVideoHandle` に `operator ==` と `hashCode` を override し、
  `textureId` を根拠とした value equality にする。
- 実装は Dart の慣用に沿い、`other is SoraLocalVideoHandle && other.textureId == textureId`
  と `textureId.hashCode` の形にする。
- `@immutable` value class としての契約を明示するため `toString()` の追加も
  検討する (デバッグログでの可読性向上目的。必須ではない)。

## 完了条件

- [ ] `SoraLocalVideoHandle` が value equality (`textureId` 基準) を持つ。
- [ ] `test/` に `==` / `hashCode` の対応テストを追加する (同一 textureId で
      `==` が true、異なる textureId で false、`Set` に重複が入らないこと)。
- [ ] `flutter analyze` と関連テストが成功する。
