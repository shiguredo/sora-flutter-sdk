# `///` 直後の `//` で dartdoc が公開ドキュメントから落ちる 6 箇所を修正する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-dartdoc-broken-by-line-comment
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`///` の空行の後に `//` で書かれた「なぜ」の説明が `dart doc` の出力から落ちる 6 箇所を修正する。ローカルソースは読めるが、生成される公開 dartdoc では冒頭 1 行のみで補足が消える。

## 現状

以下の宣言で dartdoc の記法が `///` + 空 `///` + `//` の構造になっており、`//` 部分が dartdoc 出力から落ちる:

- `lib/src/sora_media_stream_track_base.dart` の `MediaStreamTrackBase.getTracks()` 前後
- `lib/src/sora_media_stream.dart` の `LocalMediaStream.getAudioTracks()` / `getVideoTracks()` および付随箇所（W3C API 命名理由の説明）
- `lib/src/sora_remote_media_stream.dart` の `RemoteMediaStream.getTracks()` 相当
- `lib/src/sora_media_devices.dart` の `MediaDevices.getUserMedia()` 前
- `lib/src/sora_connection.dart` の `SoraConnection.getStats()` 前（W3C RTCPeerConnection.getStats() 命名理由）

## 設計方針

- 補足も残すなら 4 行とも `///` に統一する。例:
  ```dart
  /// 現在の audio track 一覧を snapshot として返す。
  ///
  /// W3C Media Capture and Streams の `MediaStream.getAudioTracks()` と
  /// 名前をそろえるため、`get` をあえて残している。
  ```
- 補足を消してよい箇所は空 `///` ごと削除して簡潔化する。
- 該当 6 箇所を一度に修正する。ファイルまたぎでは影響範囲を確認する。
- 別 issue で `sora_media_devices.dart` の重複コメント削除を扱っている場合、そちらとの整合を取る。

## 完了条件

- [ ] 該当 6 箇所すべてで `dart doc` の出力に「なぜ」の説明が含まれる、あるいは補足が削除されて簡潔になっている。
- [ ] 該当パターンが lib/ 配下に残っていない（`grep -nE "^\s*///\s*$" -A1 lib/` などで確認）。
- [ ] `flutter analyze` と関連テストが成功する。
