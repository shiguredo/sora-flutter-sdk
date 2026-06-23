# compress: false のユーザー定義 DataChannel 送受信 E2E テストを追加する

- Priority: Low
- Created: 2026-06-23
- Model: GPT-5 Codex
- Branch: feature/add-custom-datachannel-compress-off-e2e

## 目的

`#` プレフィックス付きユーザー定義 DataChannel において `compress: false` を明示した場合の open と送受信を E2E で確認する。

## 現状

- `issues/0016` の E2E テストでは `compress: true` の 1 ケースのみカバーしている
- SDK 内部で compress 有無によるシリアライズ分岐がある場合、`compress: false` のパスは E2E で検証されていない

## 設計方針

- `issues/0016` のテストをベースに、`compress: false` に変更した派生テストとする
- compress: true のテストと同様に、open event の `compress` 値も検証する
- 双方向の送受信まで確認する

## 完了条件

- `compress: false` の DataChannel open を確認する E2E がある
- open event の `compress` が `false` であることを確認している
- バイナリ payload の送受信成功を確認している
