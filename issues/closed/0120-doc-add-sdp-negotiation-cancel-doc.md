# `SdpNegotiationCallbacks` の cancel 時の解放責務を調査して dartdoc に明記する

- Created: 2026-08-27
- Completed: 2026-09-10
- Branch: feature/doc-add-sdp-negotiation-cancel-doc
- Polished: 2026-09-07
- Milestone: 2026.1.0

## 目的

`SdpNegotiationCallbacks` の各 callback で `_cancelled` チェックはあるが、`SetRemoteDescription` / `CreateAnswer` / `SetLocalDescription` のチェーンで cancel された場合の native リソース解放責務が dartdoc に明記されていない。解放有無の調査を先行した上で、読み手が「cancel 時に何を解放すべきか」を推測しなくて済む状態にする。

## 現状

`lib/src/ffi/callback_handlers.dart` の以下 4 callback は `_cancelled` を確認する (`@visibleForTesting` の public メンバー):

- `onSetRemoteDescriptionComplete` cancel 時: `return` のみで何も解放しない
- `onCreateAnswerSuccess` cancel 時: `sessionDescriptionUniqueDelete(desc)` を呼ぶ
- `onCreateAnswerFailure` cancel 時: `return` のみで何もしない
- `onSetLocalDescriptionComplete` cancel 時: `return` のみで何もしない

cancel 時の早期 `return` は `rtcErrorMessage` (`lib/src/ffi/memory.dart`、成功・失敗いずれも末尾で `rtcErrorUniqueDelete` まで行う) に到達しないため、`RTCError_unique` の解放有無は未解明である。`desc` は `pcSetRemoteDescription` / `_setLocalDescription` 成功時に所有権が移譲される (115-116 行目相当のコメント)。`_setLocalDescription` は `_pcRef == null` 時に `sessionDescriptionUniqueDelete(desc)` して `return` する。

対象ファイルは `// ignore_for_file: public_member_api_docs` であり、対象クラス・メソッドの説明は `//` で書かれている。

## 設計方針

- `0085` / `0086` は対応不要として closed 済み (挙動変更なし確定) のため、本 issue は単独で実施する。待機条件は設けない。
- まず cancel 時の `RTCError_unique` の解放有無を調査する。リークが確認された場合は挙動修正を別 issue に分離し、本 issue は調査結果の dartdoc 反映に留める。
- `SdpNegotiationCallbacks` の class に `///` の dartdoc を新設し、リソースごとの責務を区別して明記する (`desc` は移譲済み / 明示 delete、`RTCError_unique` は調査結果に従う)。`onCreateAnswerSuccess` の明示解放を例外扱いとせず、リソースごとの一覧として書く。
- 上記 4 callback に `///` の dartdoc を新設し、「cancel 時に何を解放するか / 解放しないか」を 1 行ずつ書く。`_createAnswer` / `_setLocalDescription` (private) には触れない。
- `// ignore_for_file: public_member_api_docs` はファイル全体のため維持する。
- 挙動変更は本 issue に含めない。調査 + ドキュメントのみ。

## 完了条件

- [ ] cancel 時の `RTCError_unique` の解放有無の調査結果が issue または dartdoc に反映されている。
- [ ] `SdpNegotiationCallbacks` の class dartdoc に cancel 時の解放責務方針が書かれている。
- [ ] 上記 4 callback の dartdoc に cancel 時挙動が 1 行ずつ書かれている。
- [ ] `flutter analyze` と `flutter test test/sdp_negotiation_test.dart` が成功する。

## 解決方法

- `SdpNegotiationCallbacks` の class に `///` dartdoc を追加し、cancel 時のリソース解放責務を明記した。
- 対象 4 callback に `///` dartdoc を追加し、cancel 時の解放有無を 1 行ずつ記載した。
  - `onSetRemoteDescriptionComplete` / `onCreateAnswerFailure` / `onSetLocalDescriptionComplete` は `error` を解放しない。
  - `onCreateAnswerSuccess` は `desc` を `sessionDescriptionUniqueDelete` で解放する。
- 調査結果: `RTCError_unique` は `WEBRTC_DECLARE_UNIQUE` の `_unique_delete` と observer ヘッダの `webrtc_RTCError_unique*` 引数、`rtcErrorMessage` が常に delete することから、所有権は callback 側にある。cancel による早期 return では `rtcErrorMessage` を通らないため `RTCError_unique` が解放されず、解放漏れとなる。
- 挙動修正は本 issue に含めず、別途対応する。
- `flutter analyze --fatal-infos lib test` 成功、`flutter test` 156 件成功 (`sdp_negotiation_test.dart` は FFI 依存のためローカルでは skip、CI の Linux で実行)。
