# `///` に続く `//` で dartdoc が公開ドキュメントから落ちる 7 箇所を修正する

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/fix-dartdoc-broken-by-line-comment
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`///` の後に `//` で書かれた「なぜ」の説明が `dart doc` の出力から落ちる 7 箇所を修正する。ローカルソースは読めるが、生成される公開 dartdoc では冒頭のみ (または dartdoc 自体が無い箇所は 0 行) で補足が消える。

## 現状

W3C API 命名理由の「名前をそろえるため、`get` をあえて残している。」相当の補足が `//` で書かれている箇所が 7 ブロックある:

1. `lib/src/sora_media_stream_track_base.dart` 13-16 行目 (`MediaStream.getTracks()` 前、`///` + 空 `///` + `//` 2 行)
2. `lib/src/sora_media_stream.dart` 49-52 行目 (`LocalMediaStream.getTracks()` 前、同構造)
3. `lib/src/sora_media_stream.dart` 59-62 行目 (`getAudioTracks()` 前、同構造)
4. `lib/src/sora_media_stream.dart` 91-94 行目 (`getVideoTracks()` 前、同構造)
5. `lib/src/sora_media_devices.dart` 118-121 行目 (`MediaDevices.getUserMedia()` 前、同構造。定数側 60-61 行目は `0113-remove-duplicated-comment` の範囲で対象外)
6. `lib/src/sora_connection.dart` 1136-1138 行目 (`SoraConnection.getStats()` 前、`///` 1 行 + `//` 2 行で空 `///` なし)
7. `lib/src/sora_remote_media_stream.dart` 59-60 行目 (`RemoteMediaStream.getTracks()` 前、`//` 2 行のみで `///` 自体が無い。dartdoc を新規追加する扱い)

## 設計方針

- 1-5 は 4 行とも `///` に統一する。例:
  ```dart
  /// 現在の audio track 一覧を snapshot として返す。
  ///
  /// W3C Media Capture and Streams の `MediaStream.getAudioTracks()` と
  /// 名前をそろえるため、`get` をあえて残している。
  ```
- 6 は 3 行とも `///` に統一する。`getStats()` 前は `0094-doc-add-public-api-throws-dartdoc` の例外追記範囲と重なるため、本 issue を先に実施し、`0094` は例外追記のみ行う (`0094` 側と一致)。
- 7 は他と同文言の公開 dartdoc を新規追加する (2 行の `//` を `///` 3 行相当に置き換える)。
- 7 箇所とも補足を残す。削除する選択肢は取らない (W3C 命名理由は有用な「なぜ」の説明のため)。
- `sora_media_devices.dart` の定数側 60-61 行目は `0113` が削除を所有するため、本 issue では触れない。メソッド側 118-121 行目のみ `///` 化する。
- 挙動変更なし。コメント / dartdoc のみの修正。

## 完了条件

- [ ] 上記 7 箇所すべてで補足が `///` のみで構成されている。
- [ ] `///` の直後行または空 `///` の次行に `//` が続く箇所が `lib/` 配下に残っていない。
- [ ] `flutter analyze` が成功する。コメントのみの変更のため専用の関連テストはなし。

## 解決方法

- `lib/src/sora_media_stream_track_base.dart` / `sora_media_stream.dart` / `sora_media_devices.dart` / `sora_connection.dart` / `sora_remote_media_stream.dart` の 7 箇所で `//` の補足を `///` に統一した。
- `sora_remote_media_stream.dart` の `getTracks()` には `MediaStream.getTracks()` と同文言の dartdoc を新規追加した。
- 完了条件「`///` の直後行または空 `///` の次行に `//` が続く箇所が `lib/` 配下に残っていない」を満たすため、`lib/src/ffi/webrtc_client.dart` の `getStats()` に残っていた同パターン (0155 で追加された説明) も `///` に統一した。
- `flutter analyze --fatal-infos lib test` 成功、`flutter test` 156 件成功 (FFI 依存は環境変数未指定で skip)。
