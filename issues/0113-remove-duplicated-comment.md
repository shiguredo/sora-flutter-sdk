# `sora_media_devices.dart` の重複コメントを削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-duplicated-comment
- Polished: 2026-09-07

## 目的

`lib/src/sora_media_devices.dart` で `getUserMedia` に関するコメントが定数宣言の直前と `getUserMedia` メソッド本体直前の 2 箇所に重複しているため、定数宣言側の重複を削除する。

## 現状

`lib/src/sora_media_devices.dart` の `_defaultVideoWidth` 等の定数宣言の直前に「`getUserMedia()` は W3C ... の API 名に合わせるため、`get` をあえて残している。」というコメントが置かれている。

同じ趣旨のコメントは `MediaDevices.getUserMedia` メソッド本体の直前にもある。定数宣言側のコメントは対象が「W3C API 命名理由」ではなく「デフォルト値の説明」のはずで、内容と対象が食い違っている。

## 設計方針

- 定数宣言直前の W3C API 命名理由コメント (`getUserMedia()` に関する説明) 2 行 (`lib/src/sora_media_devices.dart` の 60-61 行目相当) を削除する。
- `_defaultVideoWidth` 等の定数群の直前にあるデフォルト値説明の 2 行 (62-63 行目相当「映像サイズ / フレームレートが省略されたときに使うデフォルト値。ブラウザの getUserMedia({ video: true }) と合わせている。」) は維持する。新規コメントの追加は行わない。
- `getUserMedia` メソッド本体直前のコメント (120-121 行目相当) はそのまま維持する。`0095-fix-dartdoc-broken-by-line-comment` が同箇所の `///` 統一を行う場合は、0095 側の修正を優先し、本 issue は定数側 2 行の削除のみに留めて競合を避ける。
- 挙動変更なし。コメントのみの修正。

## 完了条件

- [ ] 定数宣言直前の W3C API 命名理由の 2 行 (60-61 行目相当) が削除されている。
- [ ] `getUserMedia` メソッド直前のコメント (120-121 行目相当) は維持されている。
- [ ] 定数群の直前にデフォルト値説明のコメント (62-63 行目相当) が残っている。
- [ ] `flutter analyze` が成功する。コメントのみの変更のため専用の関連テストはなし。
