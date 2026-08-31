# `test/` の `src/` 直下 import による `@internal` API 依存を `internal` / `public` に分離する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-test-directory-split
- Polished: {YYYY-MM-DD}

## 目的

`test/` 配下の 9 ファイルが `package:sora_sdk/src/*` を直接 import し、`@internal` の実装詳細に密着している状態を整理する。公開 API テスト（`sora_sdk.dart` 経由）と内部実装テストをディレクトリ分離してリファクタリング耐性を上げる。

## 現状

以下のテストが `src/` 直下 import で `@internal` API を触っている:

- `test/sora_connect_message_test.dart`
- `test/sora_data_channel_controller_test.dart`
- `test/sdp_negotiation_test.dart`
- `test/simulcast_video_encoder_factory_test.dart`
- `test/webrtc_client_test.dart`
- `test/sora_media_stream_test.dart`
- `test/sora_screen_capture_test.dart`
- `test/sora_signaling_session_state_test.dart`
- `test/sora_validator_test.dart`

同一パッケージ内テストなので Dart 的には合法だが、実装詳細に密着しリファクタリング時にテストが連鎖破損する構造。

## 設計方針

- `test/` を以下のように分割する:
  - `test/public/` — `package:sora_sdk/sora_sdk.dart` 経由で公開 API のみを触るテスト
  - `test/internal/` — `package:sora_sdk/src/*` を触る内部実装テスト
- 各テストを内容に応じて振り分ける。公開 API で検証できるものは `public/` に、実装詳細（`@internal`）に依存するものは `internal/` に置く。
- CI 側で `public/` と `internal/` を別ジョブに分けるか、そのままフラットに扱うかは決める。
- テスト名は日本語。
- `internal/` のテストは refactor が入るたびに更新される前提であることを明記する。

## 完了条件

- [ ] `test/` が `public/` と `internal/` に分割されている。
- [ ] 各テストが適切に振り分けられている。
- [ ] `flutter analyze` と関連テストが成功する。
