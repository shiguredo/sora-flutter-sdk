# `SoraErrorCode` に SDP / トラック追加系のエラーコードを追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/add-sora-error-code-sdp-track
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

`SoraErrorCode` に SDP ネゴシエーション / トラック追加の失敗コードが定義されておらず、リテラル文字列で emit されているため、利用者が `switch (event.code)` で分岐すると SDK 内部リテラルに依存する状況を解消する。

## 現状

`lib/src/sora_error_code.dart` の `SoraErrorCode` には SDK 内部エラーコードの一部しか定義されていない。以下は現状リテラル文字列で emit されている（SDP / トラック追加系に限らず、リテラルで emit されているエラーコードを列挙する）:

- `set_remote_description_failed`
- `set_local_description_failed`
- `create_answer_failed`
- `create_peer_connection_failed`
- `add_audio_track_failed`
- `add_video_track_failed`
- `reoffer_invalid`
- `offer_invalid`
- `candidate_parse_failed`（`WebrtcClient.handleCandidate` 内のリテラル emit。本 issue のスコープ外とするが、定数化の候補として記録する）

emit 箇所は `lib/src/ffi/webrtc_client.dart` の SDP / PC 生成 / トラック追加 / candidate 経路と `lib/src/ffi/callback_handlers.dart` の複数箇所。

利用者が `SoraConnectionErrorEvent.code` に対して switch する場合、SDK 内部のリテラル文字列に依存することになる。将来のリファクタや rename でリテラルが変わると利用者コードが黙って壊れる。

## 設計方針

- 上記 8 種類のエラーコード（`candidate_parse_failed` はスコープ外）を `SoraErrorCode` に定数として追加する（例: `SoraErrorCode.setRemoteDescriptionFailed = 'set_remote_description_failed'`）。命名は既存の camelCase 命名慣習に従う。
- emit 箇所（`webrtc_client.dart` / `callback_handlers.dart`）をリテラルから `SoraErrorCode` 経由に置き換える。
- 追加した定数の dartdoc に「Sora クライアントが SDP ネゴシエーションで失敗した際に emit される」等の意味を明記する。
- 追加するかどうか未定のエラーコード（`unexpected_native_event` 等）も設計時に洗い直す。ただし本 issue のスコープは上記 8 種類に限る。`unexpectedNativeEvent` は 0075 で追加が決定済みのため本 issue では扱わない。

## 完了条件

- [ ] `SoraErrorCode` に上記 8 種類の定数が定義されている。
- [ ] 上記 8 種類のリテラル文字列での emit が `SoraErrorCode` 経由に置き換わっている。
- [ ] 追加した定数の dartdoc が書かれている。
- [ ] `flutter analyze` と関連テストが成功する。
