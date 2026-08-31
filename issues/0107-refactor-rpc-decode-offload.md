# rpc DataChannel の受信 decode を isolate offload に統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-rpc-decode-offload
- Polished: {YYYY-MM-DD}

## 目的

`SoraDataChannelController` の rpc ラベル受信で `jsonDecode` を同期呼びしているため、大きな RPC レスポンスで UI thread の jank が発生する。他のラベル（notify / push / stats / signaling）と同じく `decodeJson` の isolate offload 経由に統一する。

## 現状

`lib/src/sora_data_channel_controller.dart` の `SoraDataChannelController._handleRpcDataChannelMessage` は `jsonDecode(text)` を同期呼びしている。他のラベル handler（`_handleNotifyDataChannelText`, `_handlePushDataChannelText`, `_handleStatsDataChannelMessage`, `_handleSignalingDataChannelMessage`）は `decodeJsonMap` / `decodeJson`（32KiB 以上を isolate offload）を通す。

RPC のペイロードは通常小さいと想定されるが、レスポンス側の JSON が大きくなる可能性を考えると、他 handler と挙動が違うことは以下の理由で望ましくない:

- 大きなレスポンスで UI thread が block されるリスク。
- 他 handler と挙動対称性が薄く、書き分け意図がコードから読み取れない。

## 設計方針

- `_handleRpcDataChannelMessage` の `jsonDecode(text)` を `decodeJson(text)` / `decodeJsonMap(text)` に置き換える。他 handler と同じ offload しきい値（32KiB）を採用する。
- offload しない設計を維持する場合は「rpc は小さいペイロード想定」等の意図をコメントで明示する（第一案は統一する側）。
- WebSocket 順序保証の別 issue との整合を確認する（tail 直列化と offload は独立に効く）。

## 完了条件

- [ ] `_handleRpcDataChannelMessage` の decode が他 handler と対称に統一されている、または意図がコメントで明示されている。
- [ ] 大きな RPC レスポンスで UI thread が block されないことを（現実的な範囲で）テストで確認する。
- [ ] `flutter analyze` と関連テストが成功する。
