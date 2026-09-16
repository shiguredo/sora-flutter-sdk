# `test/` の `src/` 配下 import 依存を `public` / `internal` に分離する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-test-directory-split
- Polished: 2026-09-07

## 目的

`test/` 配下の 11 ファイルが `package:sora_sdk/src/*` を直接 import し、実装詳細に密着している状態を整理する。公開 API のみを使うテスト (`test/public/`) と `src/` 直接 import が必要な内部実装テスト (`test/internal/`) にディレクトリ分離してリファクタリング耐性を上げる。振り分け基準は import 経路 (`sora_sdk.dart` 経由のみか、`src/*` 直接 import を含むか) とする。

## 現状

`src/*` を直接 import しているテストは 11 ファイルである:

- `test/sdp_negotiation_test.dart`
- `test/simulcast_video_encoder_factory_test.dart`
- `test/sora_connect_message_test.dart` (`sora_sdk.dart` との二重 import を含む)
- `test/sora_connection_test.dart`
- `test/sora_data_channel_controller_test.dart`
- `test/sora_media_stream_test.dart`
- `test/sora_remote_track_manager_test.dart`
- `test/sora_signaling_session_state_test.dart`
- `test/sora_validator_test.dart`
- `test/sora_video_capture_error_test.dart`
- `test/webrtc_client_test.dart`

`src/*` を import していないテストは 3 ファイルである (`test/sora_connection_config_test.dart` / `test/sora_error_code_test.dart` / `test/sora_video_widget_test.dart`)。

同一パッケージ内テストなので Dart 的には合法だが、実装詳細に密着しリファクタリング時にテストが連鎖破損する構造。

## 設計方針

- `test/` を以下のように分割する:
  - `test/public/` — `src/*` を import しない 3 ファイルを移動する
  - `test/internal/` — `src/*` を import する 11 ファイルを移動する
- `test/support/` は移動せず残置し、両ディレクトリから `../support/` 参照に書き換える。
- CI (`ci.yml` の `Reject silent FFI test returns` と `Run FFI-dependent package tests` のパス直書き) のパスを新配置に合わせて更新する。別ジョブ化は行わずフラット維持とする。
- 0106 / 0133 の行番号参照は移動後に無効化されるため、本 issue の作業で参照更新の要否を確認する。
- `0151` (boilerplate 整理・helper 抽出) の完了後に実施する。
- `internal/` 配下の各ファイル先頭に「内部実装テスト (リファクタリング時に更新する)」旨のコメントを付ける。
- `0104` / `0133` は本 issue 確定までは現行配置に従う。`0106` は改名のみで配置非依存のため先行可とする。

## 完了条件

- [ ] `test/public/` に 3 ファイル、`test/internal/` に 11 ファイルが配置されている。
- [ ] `test/support/` が残置され、両ディレクトリから参照できる。
- [ ] CI のパス直書きが新配置に更新されている。
- [ ] `internal/` 各ファイルに更新前提のコメントがある。
- [ ] `0106` / `0133` の行番号参照の更新要否を確認済みである。
- [ ] `flutter analyze` と `flutter test test/` が成功する。
