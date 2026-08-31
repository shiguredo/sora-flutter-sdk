# 不要な `ignore_for_file: public_member_api_docs` を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-ignore-for-file-cleanup
- Polished: {YYYY-MM-DD}

## 目的

`analysis_options.yaml` で `public_member_api_docs: true` を有効化しているが、複数ファイルで `// ignore_for_file: public_member_api_docs` を使って一律無効化している。うち一部のファイルはすでに公開メンバーに dartdoc が書かれているため ignore が不要になっている可能性がある。不要な ignore を削除して lint が本来の目的で機能するようにする。

## 現状

以下のファイルが `// ignore_for_file: public_member_api_docs` を持つ:

- `lib/src/sora_debug_event.dart`
- `lib/src/sora_media_stream.dart`
- `lib/src/sora_signaling_option.dart`
- `lib/src/sora_connect_message.dart`
- `lib/src/sora_connection_signaling.dart`
- `lib/src/sora_data_channel_controller.dart`
- `lib/src/sora_method_channels.dart`
- `lib/src/sora_remote_track_manager.dart`
- `lib/src/sora_signaling_session_state.dart`
- `lib/src/sora_validator.dart`
- `lib/src/ffi/library_loader.dart`
- `lib/src/ffi/callback_handlers.dart`
- `lib/src/ffi/bindings.dart`
- `lib/src/ffi/webrtc_client.dart`
- `lib/src/ffi/simulcast_video_encoder_factory.dart`
- `lib/src/ffi/memory.dart`

このうち以下は既に `///` dartdoc が付いており、ignore を外して analyzer が clean のままの可能性がある:

- `lib/src/sora_method_channels.dart` — 唯一の公開シンボル `soraMethodChannel` は `///` dartdoc あり、`@internal`
- `lib/src/sora_validator.dart` — 公開関数 `parseSignalingUrl`, `validateAudioBitRate`, `validateVideoBitRate` はすべて `///` dartdoc あり

## 設計方針

- 上記 2 ファイルの `ignore_for_file: public_member_api_docs` を試験的に削除し、`flutter analyze` が clean のままか確認する。
- clean であれば削除確定。lint 違反が出るなら、違反しているメンバーに dartdoc を追加してから削除する（追加が本 issue のスコープに入るか別 issue にするかを判断）。
- 他のファイル（`sora_debug_event.dart`, `sora_media_stream.dart`, `sora_signaling_option.dart` など）は別 issue（`@internal` 付与漏れ・export 整理）で扱う。
- 挙動変更なし。lint 設定のみの整理。

## 完了条件

- [ ] `sora_method_channels.dart` / `sora_validator.dart` の `ignore_for_file` が削除されている。
- [ ] `flutter analyze` が clean である。
