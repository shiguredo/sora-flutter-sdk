# `sora_media_devices.dart` の重複コメントを削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-duplicated-comment
- Polished: {YYYY-MM-DD}

## 目的

`lib/src/sora_media_devices.dart` で `getUserMedia` に関するコメントが定数宣言の直前と `getUserMedia` メソッド本体直前の 2 箇所に重複しているため、定数宣言側の重複を削除する。

## 現状

`lib/src/sora_media_devices.dart` の `_defaultVideoWidth` 等の定数宣言の直前に「`getUserMedia()` は W3C ... の API 名に合わせるため、`get` をあえて残している。」というコメントが置かれている。

同じ趣旨のコメントは `MediaDevices.getUserMedia` メソッド本体の直前にもある。定数宣言側のコメントは対象が「W3C API 命名理由」ではなく「デフォルト値の説明」のはずで、内容と対象が食い違っている。

## 設計方針

- 定数宣言直前の W3C API 命名理由コメント（`getUserMedia()` に関する説明）2 行を削除する。
- `_defaultVideoWidth` 等の定数群には別途「映像サイズ / フレームレートが省略されたときに使うデフォルト値。ブラウザの getUserMedia({ video: true }) と合わせている。」相当のコメントを残す（既にある場合はそのまま）。
- `getUserMedia` メソッド本体直前のコメントはそのまま維持する。
- 挙動変更なし。コメントのみの修正。

## 完了条件

- [ ] 定数宣言直前の重複コメントが削除されている。
- [ ] `getUserMedia` メソッド直前のコメントは維持されている。
- [ ] 定数群には dark / defaults の意図が伝わる別コメントが残っている。
- [ ] `flutter analyze` と関連テストが成功する。
