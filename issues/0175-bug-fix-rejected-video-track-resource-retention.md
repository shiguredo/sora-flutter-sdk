# answer で拒否されたリモートビデオトラックが残すリソースがセッション中に蓄積するバグを修正する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-rejected-video-track-resource-retention
- Polished: 2026-11-11

## 目的

SDK 内部の調査により、非対応コーデック（例: Linux + H.264）の m-line が answer で拒否された場合、libwebrtc の `OnRemoveTrack` が発火しないため、SDK のリソースがセッション終了まで保持され続けることが分かった。非対応コーデックの送信クライアントが複数存在する、または入退室を繰り返すチャネルでは、リソース（native 参照、renderer、Flutter Texture）が無上限に蓄積する。この蓄積を SDK 側で解消する。

## 現状

- 事象の起点（`issues/closed/0169-bug-fix-rejected-remote-video-track-removal.md` で確定）: 受信側が対応していないコーデックの m-line は offer 適用時に libwebrtc が OnTrack を発火し、SDK が `RemoteTrackManager.attachRemoteVideoTrack` で attach する。しかし CreateAnswer で該当 m-line を port 0 として拒否したとき、libwebrtc は OnRemoveTrack を発火しない（リモート SDP 由来の除去のみ報告する仕様）。
- これによりセッション中は次のリソースが解放されず保持される。
  - `RemoteTrackManager._remoteTracks` の `_RemoteTrackEntry`（trackId、rendererId、videoSinkPtr、textureId を持つ）
  - add イベントで AddRef された native `VideoTrackInterface` 参照（entry が保持。正常な所有関係だが返却のきっかけがない）
  - プラットフォーム側の renderer（Linux では `createRemoteVideoRenderer` で生成、`client_renderers` に登録）
  - Flutter Texture（Linux では `FlPixelBufferTexture` の登録。フレーム未到着のため 2x2 黒画像として残る）
- 蓄積の条件: attach 済みの同一 trackAddress の再通知は既存ガード（`_remoteTracks.containsKey` → add 分 ref を返却して attach しない）で二重 attach にはならない。ただし**別クライアント / 別 m-line** が非対応コーデックで追加されるたびに 1 セットずつ蓄積し、セッション中の上限はない。
- 回収経路は存在する（恒久リークではない）: 自分の接続切断時は `_teardownNativeSession` → `detachAllRemoteVideoTracks`（sink 解除、add 分 ref 返却、`disposeRemoteVideoRenderer`）で回収され、`dispose()` 時は `disposeClient`（`stop_client_renderers`）でも回収される。attach 済みトラックの renderer 破棄失敗時は `_disposeRetryEntries` で次回回収。
- 影響: 長時間接続の多人数チャネルで texture 数・メモリが増加し続ける。UI 側の黒画面残留は 0169（devtools 側対応）で解消されるが、SDK 内部の蓄積は 0169 のスコープ外であり残る（0169 の設計方針のとおり `lib/` は変更しない）。

## 設計方針

- 0169 の本審で検討し見送られた「answer SDP の port 0 m-line 検出 → トラックを SDK 側で回収する」案を実装する。
- answer 確定時に自 answer SDP を検査する。検出ポイントは `lib/src/ffi/callback_handlers.dart` の `onCreateAnswerSuccess`（answer SDP 確定時、シグナリング送信前）。
- 拒否された video m-line の mid に対し、offer SDP の `a=msid:<stream id> <track id>` の track id（`{connection_id}-video` 形式）からトラックを特定する。`setRemoteDescription` は offer SDP を引数で受け取るが現状保持していないため、`SdpNegotiationCallbacks` にフィールドとして保持する。
- 拒否 trackId は `RemoteTrackManager` に通知し、次の 2 経路で回収する。
  - **attach 済み**: `_remoteTracks` から trackId が一致するすべてのエントリを探し、`_detachRemoteVideoTrackUnsafe` と同じ後始末（sink 解除、add 分 ref 返却、renderer 破棄、`_remoteMediaStreams` 更新、`onRemoveTrackEvent`）を行う。`detachRemoteVideoTrack` は remove イベント分の参照を入口で返却するため使わない（拒否では remove イベントが発火していない）。renderer 破棄失敗時は既存の `_disposeRetryEntries` を再利用する（0161 参照）。
  - **attach 未了 / 追加前**: 拒否済み trackId の集合を保持し、`attachRemoteVideoTrack` の入口と renderer 作成後の確認の両方で打ち消す（add 分の参照を返却）。これは trackAddress に依存する既存の `_removedBeforeAttach` ではカバーできないレース（answer 確定前後に attach が進行するケース）への対処。既存の `_removedBeforeAttach` に同じ trackAddress が残っている場合は二重に release しないよう、拒否判定と `_removedBeforeAttach` の消費を排他する。後続 re-offer で同じ trackId が再 offer された場合も同じ集合で打ち消す。拒否済み trackId 集合はセッション終了時の `clear()` で消す（再接続時に同じ trackId を誤って打ち消さない）。
- audio m-line の拒否（port 0）も対称に `handleRemoteAudioTrackRemoved` を trackId のみで呼ぶ（audio は trackAddress を持たないため）。ただし `_remoteMediaStreams` に該当 audio track が存在する場合だけ呼び、同じ audio m-line が再 offer で再度拒否されても remove を重複発火しない。
- attach 済みトラックの除去時は `SoraRemoveTrackEvent` を 1 回だけ発火する。attach 未了のまま打ち消したトラックは `SoraTrackEvent` を発火していないため、`SoraRemoveTrackEvent` も発火しない。0169 の devtools 側対応（`connection.destroyed` による接続単位の削除）とは独立しており、両者が並んでも `removeWhere` は冪等で競合しない。
- 既存の参照収支（`issues/closed/0073-bug-fix-remote-video-track-refcount-leak.md` で確定した add / remove イベント分の収支）は維持する。本 issue の打ち消しは「add 分の返却」だけで完結させ、除去を二重発火させない。
- 0169 の方針（devtools 側で対処し `lib/` は変更しない）と矛盾しないよう、本 issue は「SDK 内部のリソース保持」への対応として 0169 とは独立したスコープとする。

## 完了条件

- [ ] 非対応コーデックのクライアントが入室した際、answer 確定後に当該トラックの entry / native 参照 / renderer / texture が解放され、セッション中に蓄積しない。
- [ ] `native: onremovetrack` が発火しない場合でも、attach 済みのトラックについて `SoraRemoveTrackEvent` が 1 回だけ発火し、`RemoteMediaStream` からも除去される。attach 未了のまま打ち消したトラックは `SoraRemoveTrackEvent` を発火しない。
- [ ] audio m-line の拒否でも `SoraRemoveTrackEvent` が 1 回だけ発火し、`RemoteMediaStream` から audio track が除去される。
- [ ] 対応コーデック（VP8 / VP9 / AV1）の通常受信・切断では挙動が変わらない（既存 E2E を含む）。
- [ ] offer / answer のペアから拒否 trackId を正しく抽出するユニットテストと、attach 済み / attach 未了の両レースを exercise するユニットテストが追加され、FFI 依存テスト（Linux CI）が成功する。
- [ ] `flutter analyze --fatal-infos` が成功する。
- [ ] `CHANGELOG.md` に `## develop` セクションを追加し、`[FIX]` エントリを追記する（`CODEBASE.md` と `shiguredo-changelog` の規約に従う）。

## 解決方法

- `lib/src/ffi/callback_handlers.dart`: offer SDP の保持、answer SDP の port 0 m-line 検出、拒否 trackId の抽出と通知。
- `lib/src/ffi/webrtc_client.dart`: 拒否 trackId の通知を `SoraConnection` へ流す wiring（内部イベント経由）。
- `lib/src/sora_connection.dart`: `_handleWebrtcEvent` での拒否イベント処理（`_emitRemoveTrackEvent` 経由のイベント発火を含む）。
- `lib/src/sora_remote_track_manager.dart`: 拒否済み trackId 集合の保持、`attachRemoteVideoTrack` の打ち消し、trackId 指定の detach（`_runTrackedDetach` / `_detachRemoteVideoTrackUnsafe` 経由。`detachRemoteVideoTrack` の remove 分返却は通さない）と `_disposeRetryEntries` の連携。
- ユニットテストの追加（FFI 依存分は Linux CI で実行）。

## 関連

- `issues/closed/0169-bug-fix-rejected-remote-video-track-removal.md`（devtools 側対応。本 issue の UI 側の対処）
- `issues/0161-bug-fix-remote-track-retry-lifecycle-hardening.md`（`_disposeRetryEntries` との相互作用の確認）
- `issues/closed/0073-bug-fix-remote-video-track-refcount-leak.md`（ref 収支の確定）
