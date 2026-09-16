# `sora_method_channels` / `sora_validator` の不要な `ignore_for_file: public_member_api_docs` を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-ignore-for-file-cleanup
- Polished: 2026-09-07

## 目的

`analysis_options.yaml` で `public_member_api_docs: true` を有効化しているが、一部ファイルで不要になった `// ignore_for_file: public_member_api_docs` が残っている。不要な ignore を削除して lint が本来の目的で機能するようにする。本 issue は 2 ファイルに限定し、他ファイルは対象外とする (理由は後述)。

## 現状

`lib/` 内に `ignore_for_file: public_member_api_docs` は 17 件ある。うち `lib/src/sora_sdk_version.g.dart` (2 行目) は生成ファイル (`scripts/generate_sdk_version.dart` 生成、手編集不可) のため対象外とする。

残り 16 件のうち、以下 2 ファイルは既に公開メンバーに dartdoc が付いており、ignore を外して analyzer が clean のままの可能性がある:

- `lib/src/sora_method_channels.dart` — 唯一の公開シンボル `soraMethodChannel` は `///` dartdoc あり、`@internal`
- `lib/src/sora_validator.dart` — 公開関数 `parseSignalingUrl`, `validateAudioBitRate`, `validateVideoBitRate` はすべて `///` dartdoc あり

他ファイルの扱い:

- `sora_media_stream.dart` は `0099-fix-missing-internal-annotations` が委譲範囲として所有する。
- `ffi/callback_handlers.dart` は `0120-doc-add-sdp-negotiation-cancel-doc` が維持を宣言しているため対象外とする。
- `sora_remote_media_stream.dart` は `0129-refactor-mutable-remote-media-stream-internal` が自 issue 内で実測するため対象外とする。
- 上記以外の残件に所有者 issue は無く、本 issue でも扱わない。各ファイルの個別対応時に扱う。

## 設計方針

- 上記 2 ファイルの `ignore_for_file: public_member_api_docs` を削除し、`flutter analyze` が clean のままか確認する。
- lint 違反が出る場合は、違反しているメンバーに dartdoc を追加してから削除する (追加も本 issue のスコープに含める)。
- 挙動変更なし。lint 設定のみの整理。

## 完了条件

- [ ] `sora_method_channels.dart` / `sora_validator.dart` の `ignore_for_file` が削除されている。
- [ ] `flutter analyze` が clean である (新規警告なし)。
