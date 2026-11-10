# `SdpNegotiationCallbacks.onSetLocalDescriptionComplete` が `_pcRef == null` を確認せずに answer を送信する

- Created: 2026-08-27
- Completed: 2026-08-27
- Branch: feature/fix-sdp-negotiation-pc-ref-null-check
- Polished: {YYYY-MM-DD}

## 目的

`SdpNegotiationCallbacks.onSetLocalDescriptionComplete` が `_pcRef` が既に null 化された後にコールバック到達した場合でも、`_cancelled` が false であれば `emitSignalingMessage(answer)` を送信してしまうバグを修正する。

## 現状

`lib/src/ffi/callback_handlers.dart` の `SdpNegotiationCallbacks.onSetLocalDescriptionComplete` は `_cancelled` フラグを確認するが `_pcRef == null` は確認しない。native 側で PeerConnection が既に破棄されている状況で answer 送信が走ると、SDK 側の invariant（active PC がある期間だけ answer を返す）に反する。

同じファイル内の `_setRemoteDescription` / `_createAnswer` は `_pcRef` を触る前に `_cancelled` を確認する構成だが、`_pcRef` そのものの nullability を明示的にチェックする箇所がまばら。書き方の一貫性が薄い。

## 設計方針

- `onSetLocalDescriptionComplete` の冒頭に `if (_pcRef == null) return;` を追加する。あわせて他の callback（`onSetRemoteDescriptionComplete`, `onCreateAnswerSuccess`, `onCreateAnswerFailure`）でも `_pcRef == null` を確認するかを検討し、cancel 済み / PC 破棄済みの経路で不要な副作用が走らないよう統一する。
- 検討結果は dartdoc に「cancel / dispose 済みの場合の挙動」として明記する。

## 完了条件

- [ ] `onSetLocalDescriptionComplete` が `_pcRef == null` の状態で `emitSignalingMessage` を呼ばない。
- [ ] 他の SDP callback で `_pcRef == null` チェックの方針が統一される。
- [ ] 上記シナリオを exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

polish-issue の本審で、前提となるバグが production では発生しないことが判明したため、closed にする。

- `SdpNegotiationCallbacks._pcRef` への代入はコンストラクタ（`initialPeerConnectionRef` 経由）と `setRemoteDescription` の 2 箇所のみで、クラス内で null 化する経路が存在しない。`cancel()` は `_cancelled = true` のみで `_pcRef` は null にしない。
- `WebrtcClient` 側の `_pcRef` null 化は `closePeerConnection`（`_sdpCallbacks?.cancel()` を必ず伴う）と `_ensurePeerConnection` の作成失敗パスのみで、後者は既存 `SdpNegotiationCallbacks` に影響しない。
- `onSetLocalDescriptionComplete` は `_setLocalDescription` の `pcSetLocalDescription(_pcRef!, ...)` 成功時にのみ native observer が発火するため、到達時点で `_pcRef != null` が保証されている。さらに `_setLocalDescription` は `_pcRef == null` なら早期 return する。
- したがって「`_pcRef == null` かつ `_cancelled == false` の状態で answer を送信する」シナリオは構造的に発生せず、修正対象のバグは実在しない。実装しても production で発火しない dead code になるため、issue として成立しない。
