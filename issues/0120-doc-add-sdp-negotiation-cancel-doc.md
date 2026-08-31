# `SdpNegotiationCallbacks` の cancel 時の解放責務を dartdoc に明記する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-add-sdp-negotiation-cancel-doc
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0

## 目的

`SdpNegotiationCallbacks` の各 callback で `_cancelled` チェックはあるが、`SetRemoteDescription` / `CreateAnswer` / `SetLocalDescription` のチェーンで cancel された場合の native リソース解放責務が dartdoc に明記されていない。読み手が「cancel 時に何を解放すべきか」を推測しなければならない状態を解消する。

## 現状

`lib/src/ffi/callback_handlers.dart` の `SdpNegotiationCallbacks` の各 callback は `_cancelled` を確認する:

- `onSetRemoteDescriptionComplete` cancel 時: 何も解放しない（native 側の自動 delete を前提としている）
- `onCreateAnswerSuccess` cancel 時: `sessionDescriptionUniqueDelete(desc)` を呼ぶ
- `onCreateAnswerFailure` cancel 時: 何もしない
- `onSetLocalDescriptionComplete` cancel 時: 何もしない

「cancel 時の解放責務は native 側にある」または「Dart 側で明示解放する」の方針がまばらで、読み手が根拠を追う必要がある。

## 設計方針

- `SdpNegotiationCallbacks` の class dartdoc に「cancel 時の解放責務は基本的に native 側にある」等の全体方針を明記する。
- 各 callback の dartdoc に「cancel 時に何を解放するか / 解放しないか」を 1 行ずつ書く。
- native 側の自動 delete を前提としている箇所は、その前提の根拠（libwebrtc-c の契約）を短く明記する。
- 挙動変更なし。ドキュメントのみ。
- 別 issue の `_pcRef == null` チェック（0085）や `sessionGeneration` 追加（0086）が挙動変更を伴う場合、そちらの完了後に整合を取って dartdoc を追記する。

## 完了条件

- [ ] `SdpNegotiationCallbacks` の class dartdoc に cancel 時の解放責務方針が書かれている。
- [ ] 各 callback の dartdoc に cancel 時挙動が 1 行ずつ書かれている。
- [ ] `flutter analyze` と関連テストが成功する。
