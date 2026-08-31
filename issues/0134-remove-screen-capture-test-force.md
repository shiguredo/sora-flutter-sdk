# `test/sora_screen_capture_test.dart` の `force` パラメータ dead code を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-screen-capture-test-force
- Polished: {YYYY-MM-DD}

## 目的

`buildLocalVideoCaptureArguments(force: true)` の分岐がテストに存在するが、production コードから `force: true` を渡す箇所が存在しない dead code を整理する。

## 現状

- `test/sora_screen_capture_test.dart` に `buildLocalVideoCaptureArguments(force: true)` を使う分岐テストがある。
- `lib/src/media/sora_media_device_platform.dart` の `buildLocalVideoCaptureArguments` は `force` パラメータを受け取り分岐を持つ。
- `grep -rn "force: true" lib/` の結果、production コードから `force: true` を渡す箇所が 1 つも存在しない。

現状では実装・テスト・引数のいずれも dead。将来必要になったら意図的に追加する方が意図が明確。

## 設計方針

- `buildLocalVideoCaptureArguments` から `force` パラメータを削除する（実装・呼び出し元・テスト全て）。
- 将来必要になった場合の意図をコメントで残す必要は無い（`create-issue` で新規追加する運用に統一）。
- 挙動変更なし。使われていない実装の削除。

## 完了条件

- [ ] `buildLocalVideoCaptureArguments` の `force` パラメータが削除されている。
- [ ] 関連テストが削除または書き換えられている。
- [ ] `flutter analyze` と関連テストが成功する。
