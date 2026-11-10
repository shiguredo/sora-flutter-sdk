# `SoraLocalVideoHandle` に `==` / `hashCode` を override する

- Created: 2026-08-31
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-sora-local-video-handle-equality
- Polished: 2026-09-07

## 目的

`SoraLocalVideoHandle` は公開の `@immutable` かつ単一 field (`textureId: int`) の値オブジェクトとして宣言されているが、
`==` / `hashCode` を override していないため、`textureId` が同じ 2 つのハンドルは
identity 比較で別物と判定される。値オブジェクトとしての用法に合わせ、value equality
に依存する想定の使い方 (`Stream.distinct()` などの de-duplication、`Set` 格納、テスト
での value 比較。いずれも現行コード内の実使用は無い) を安全にする。

## 現状

`lib/src/sora_local_video_handle.dart` の `SoraLocalVideoHandle` は
`@immutable` かつ単一 field (`textureId: int`) の value class として export
されている (`lib/sora_sdk.dart` から export)。しかし `==` と `hashCode` は
override されていないため、Dart のデフォルト実装 (identity 比較) が使われる。

`SoraConnection.localVideo` (`lib/src/sora_connection.dart`) は broadcast
`StreamController` で毎回新しい `SoraLocalVideoHandle(textureId: ...)`
インスタンスを生成して emit するため、同じ `textureId` でも都度別インスタンス
になる (再接続・再 replace で同一 `textureId` が再 emit されうる)。

## 関連

- `issues/0147-refactor-texture-id-semantics.md`
- `issues/0149-add-local-video-release-notification.md`
- `issues/closed/0078-bug-fix-external-video-texture-id-leak.md`

## 設計方針

- `SoraLocalVideoHandle` に `operator ==` と `hashCode` を override し、
  `textureId` を根拠とした value equality にする。現行の `int` 契約を前提とし、`0147` / `0149` の契約確定時は本設計を見直す。
- 実装は Dart の慣用に沿い、`other is SoraLocalVideoHandle && other.textureId == textureId`
  と `textureId.hashCode` の形にする。
- 挙動変更なし。`toString()` の追加は行わない (必要になった場合は別 issue で扱う)。

## 完了条件

- [ ] `SoraLocalVideoHandle` が value equality (`textureId` 基準) を持つ。
- [ ] `test/sora_local_video_handle_test.dart` を新規作成し、`==` / `hashCode` を検証する (同一 textureId で `==` が true、異なる textureId で false、同一 textureId 2 件 add 後の `Set` length が 1)。
- [ ] `flutter analyze` と `flutter test test/sora_local_video_handle_test.dart` が成功する。
