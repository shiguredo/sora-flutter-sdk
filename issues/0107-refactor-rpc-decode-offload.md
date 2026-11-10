# rpc DataChannel の受信 decode を isolate offload に統一する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-rpc-decode-offload
- Polished: 2026-09-07

## 目的

`DataChannelController` の rpc ラベル受信で `jsonDecode` を同期呼びしているため、大きな RPC レスポンスで UI thread が block される可能性がある。他のラベル（notify / push / stats / signaling）と同じく isolate offload 経由に統一する。

## 現状

`lib/src/sora_data_channel_controller.dart` の `DataChannelController._handleRpcDataChannelMessage` (void 同期メソッド) は `jsonDecode(text)` を同期呼びしている。他のラベル handler（`_handleNotifyDataChannelText`, `_handlePushDataChannelText`, `_handleStatsDataChannelMessage`, `_handleSignalingDataChannelMessage`）は `decodeJsonMap` / `decodeJson` (32KiB 超を isolate offload する `SoraConnection` 側コールバック) を通す。

RPC のペイロードは通常小さいと想定されるが、レスポンス側の JSON が大きくなる可能性を考えると、他 handler と挙動が違うことは以下の理由で望ましくない:

- 大きなレスポンスで UI thread が block されるリスク (未計測のため可能性に留める)。
- 他 handler と挙動対称性が薄く、書き分け意図がコードから読み取れない。

## 設計方針

- `_handleRpcDataChannelMessage` の `jsonDecode(text)` を `await decodeJsonMap(text)` に置き換える。後続の `is! Map` ガードは `decodeJsonMap` の null 正規化に合わせて書き換える (非 Map 時は null 扱いで return)。
- メソッドを `Future<void>` 化し、呼び出し元 `handleMessage` の rpc 分岐 (`_handleRpcDataChannelMessage(data)` 呼び捨て) に `await` を追加する。
- しきい値は `SoraConnection` 側コールバック経由で自動適用されるため、controller 側で新たな値を定めない。
- RPC 応答は id 対応のため順序要件はなく、signaling 経路の tail 直列化 (`0077` 決着) とは無関係である。
- 挙動変更は decode 経路の非同期化のみ。offload しない案は取らない。

## 完了条件

- [ ] `_handleRpcDataChannelMessage` の decode が `decodeJsonMap` 経由に統一され、`handleMessage` 側で `await` されている。
- [ ] 32KiB 超の RPC 応答メッセージで応答処理が成功するテストが追加されている (`test/sora_data_channel_controller_test.dart`)。
- [ ] `flutter analyze` と関連テストが成功する。
