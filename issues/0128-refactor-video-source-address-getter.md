# `LocalVideoTrack` の `videoSourceAddress` / `_videoSourceAddress` の 2 段 getter を整理する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-video-source-address-getter
- Polished: {YYYY-MM-DD}

## 目的

`LocalVideoTrack` の private `_videoSourceAddress` と `@internal` public `videoSourceAddress` が同じ値を返す 2 段 getter になっており冗長。統合する。

## 現状

`lib/src/sora_media_stream.dart` の `LocalVideoTrack` は同じ値を返す 2 つの getter を持つ:

- private `_videoSourceAddress`: 内部 5 箇所から使用
- `@internal` public `videoSourceAddress`: `sora_connection.dart` から 1 箇所使用

両者は同じ実装（`_videoSourceRef?.address ?? 0`）。片方を消しても機能に影響しない。

## 設計方針

- 以下のいずれか:
  - **A. private を削除**: 内部使用箇所も `videoSourceAddress` に統一する。
  - **B. public を削除**: `SoraConnection` 側は他の `@internal` メソッド経由で取得する形に置き換える。
- 推奨は A。ドット参照の一貫性が高まる。private の `_` prefix を残す理由が薄い。
- 挙動変更なし。API サーフェスの整理のみ。

## 完了条件

- [ ] `LocalVideoTrack` の getter が 1 本に統合されている。
- [ ] 内部・外部の全呼び出しが統一されている。
- [ ] `flutter analyze` と関連テストが成功する。
