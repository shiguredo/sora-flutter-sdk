# `SdpNegotiationCallbacks.emitState` に sessionGeneration を渡していない

- Created: 2026-08-27
- Completed: 2026-08-27
- Branch: feature/fix-sdp-negotiation-session-generation
- Polished: {YYYY-MM-DD}

## 目的

`SdpNegotiationCallbacks.emitState` の型が 3 引数 `void Function(String, String?, String?)` で、`WebrtcClient._emitState` が持つ optional な `sessionGeneration` を渡せないため、SDP ネゴシエーション経由の `state = 'error'` イベントが `session_generation` を伴わず、`SoraConnection._handleWebrtcEvent` の「旧世代の遅延イベントを捨てる」ガードから漏れているバグを修正する。

## 現状

`lib/src/ffi/callback_handlers.dart` の `SdpNegotiationCallbacks.emitState` は `void Function(String, String?, String?)` として型付けされ、`WebrtcClient._emitState(..., {int? sessionGeneration})` の named 引数が常に省略される。

- `SoraConnection._handleWebrtcEvent` の `state_changed` 分岐は `data['session_generation']` を見て旧世代の PC イベントを捨てる設計になっているが、SDP エラー経由の event はこの key が付かないため、ガードから漏れる。
- 実運用では `_sdpCallbacks?.cancel()`、`_cancelled` フラグ、`_failConnectReady` 側の世代再チェックで概ね塞げているが、名前一致で気付きにくい潜在的ずれである。

## 設計方針

- `SdpNegotiationCallbacks.emitState` の型を named 引数版に変更（例: `void Function(String type, String? reason, String? message, {int? sessionGeneration})`）し、SDP callback 生成時に `_sessionGeneration` をキャプチャして毎回渡す。
- `WebrtcClient._emitState` 側は既存のシグネチャを維持し、SDP 側からの `sessionGeneration` 引数を受け取る。
- 挙動変更が入るため、旧世代 SDP エラーが `_handleWebrtcEvent` の世代フィルタで確実に捨てられることをテストで担保する。

## 完了条件

- [ ] SDP ネゴシエーション経由の `state_changed` エラーイベントに `session_generation` が乗る。
- [ ] 旧世代 SDP エラーが `_handleWebrtcEvent` の世代フィルタで silent drop される（既存 `_handleWebrtcEvent` の想定通り動く）。
- [ ] 上記を exercise するユニットテストを追加する。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

polish-issue の本審で、前提となるバグが production では発生しないことが判明したため、closed にする（0085 と同様の結論）。

- SDP ネゴシエーション経由の `state = 'error'` イベントに `session_generation` が付かない事実は正しい。しかし、`SdpNegotiationCallbacks` の `emitState` 呼び出し（`onSetRemoteDescriptionComplete` / `onCreateAnswerFailure` / `onSetLocalDescriptionComplete` の error 分岐）は、いずれも `_cancelled` チェックの後にある（callback_handlers.dart:152, 249, 346 行）。cancel 済みのインスタンスからはエラーイベントが emit されない。
- `_sdpCallbacks?.cancel()` は `handleOffer` / `handleReOffer` の新規生成直前（webrtc_client.dart:697, 739 行）と `closePeerConnection`（640 行）で必ず実行される。世代切替（新 connect）は既存 transport があれば必ず `disconnect()` → `closePeerConnection()` に至り、そこで旧 `SdpNegotiationCallbacks` が cancel される。
- したがって「旧世代の SDP エラーが cancel を抜けて emit され、世代フィルタから漏れる」シナリオは構造的に発生しない。現在進行中のネゴシエーションの失敗は現在の世代のエラーとして emit されるのが正しい挙動であり、フィルタを通過してよい。
- 実装しても production で発火しない変更になるため、issue として成立しない。
