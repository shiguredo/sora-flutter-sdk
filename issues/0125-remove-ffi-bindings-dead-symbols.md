# `ffi/bindings.dart` の内部限定 dead 定数 / API を削除する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/remove-ffi-bindings-dead-symbols
- Polished: {YYYY-MM-DD}

## 目的

`lib/src/ffi/bindings.dart` に SDK 内部からも呼び出しが無い定数 / API を削除する。内部限定なので後方互換影響は無い。

## 現状

以下の定数 / API が `lib/src/ffi/bindings.dart` に存在するが、`lib/` 全体で使用箇所ゼロ:

- 定数: `kLinuxPulseAudio`, `kLinuxAlsaAudio`, `kDummyAudio`
- 定数: `sdpTypeAnswer`（`sdpTypeOffer` のみ使用）
- 定数: `videoRotation0`
- 定数: `dcStateConnecting`（Open/Closing/Closed のみ判定に使う）
- 関数: `videoFrameUniqueGet`, `videoFrameUniqueDelete`, `videoFrameVideoFrameBuffer`（Sora 独自 `SoraVideoFrame` 経路のみ使用）
- 関数: `i420BufferWidth`, `i420BufferHeight`

`kDummyAudio` は別 issue で扱う `useAudioDevice` dartdoc 誤記の温床でもある。

## 設計方針

- 上記シンボルを削除する。使う可能性がある場合はコメントで意図を残す（例: 「将来の Push 音声 API 拡張時に復活予定」）が、現時点で決まっていない場合は削除する。
- 削除に伴い `_lib.lookupFunction` の起動時 lookup 失敗を防ぐため、native ライブラリ側の symbol と対応させる。native 側で symbol 自体を消せる場合は合わせて消す。
- `bindings.dart` は自動生成的だが手書きで手を入れている前提なら差分は最小限に留める。
- 内部限定のため CHANGELOG への記載は不要（もしくは Refactor として簡潔に）。

## 完了条件

- [ ] 上記 dead シンボルが `bindings.dart` から削除されている。
- [ ] `flutter analyze` と関連テストが成功する。
- [ ] native ライブラリ側との整合が確認されている。
