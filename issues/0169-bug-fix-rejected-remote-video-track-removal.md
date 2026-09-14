# 非対応コーデックで answer が拒否したリモートビデオトラックが残り続けるバグを修正する

- Created: 2026-09-14
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-rejected-remote-video-track-removal
- Polished: {YYYY-MM-DD}

## 目的

受信側が対応していないコーデック（例: Linux + H.264）の m-line を Sora が送信側から受けた場合、SDK は answer で m-line を拒否するにもかかわらず、そのリモートビデオトラックを表示し続ける。相手端末が切断しても `OnRemoveTrack` が発火しないため `SoraRemoveTrackEvent` が届かず、devtools では黒画面のセルが残り続ける。この残留を解消する。

## 現状

再現環境は Linux の devtools（recvonly、多人数チャネル接続）と、H.264 を送信する sendrecv クライアントの組み合わせ。`skills/sora-flutter-sdk/SKILL.md` の対応コーデック表のとおり、Linux はソフトウェアコーデック（VP8 / VP9 / AV1）のみで H.264 はデコードできない。実ログでの流れは次のとおり。

1. Sora から re-offer が届き、相手の video m-line に H.264 のみが含まれる（`a=rtpmap:35 H264/90000`、sendonly）。
2. `native: ontrack kind=video` が発火し、Dart 側が `RemoteTrackManager.attachRemoteVideoTrack` で renderer / texture を生成し `remote_track_attached` を emit する。これが黒画面の実体（フレームは届かないため黒表示になる）。
3. 続く CreateAnswer では、H.264 非対応のため該当 video m-line が `m=video 0`（port 0）として拒否される。libwebrtc は拒否時に receiver の track を内部で取り除くが、これはローカル answer に起因する除去であり、`OnRemoveTrack`（`linux/linux_bridge.c` の `bridge_on_remove_track` → `remote_video_track_removed`）は発火しない。
4. 相手端末切断時に Sora が通知と再ネゴシエーションを送る。実ログでは `native: onremovetrack kind=audio` のみ発火し、video の `onremovetrack` は来ない（track は既に libwebrtc 内部で消えているため）。
5. Dart 側は attach 済みの track と texture を保持し続け、`SoraRemoveTrackEvent` は発生しない。切断後の再ネゴシエーションで同じ track が再度 offer されると、同様に拒否され続けるが打ち消し経路もない。

SDK 側の要因は、リモートトラック削除イベントが「リモート SDP 由来の track 除去（OnRemoveTrack）」だけに依存しており、**自 answer が拒否した m-line の track はこの経路に載らない**こと。`lib/src/ffi/callback_handlers.dart` の `SdpNegotiationCallbacks` は生成した answer SDP（`_pendingAnswerSdp`）を保持しているが、answer 内の port 0 m-line は一切検査していない。`lib/src/sora_remote_track_manager.dart` も trackAddress 単位の管理のみで、trackId 単位の拒否を扱う機構はない。

同様の状況は他プラットフォームでも、受信側デコーダーが未対応のコーデック（例: 旧 Android 端末での AV1 等）を受けた場合に起こり得る。

## 設計方針

- 自 answer SDP から `m=<media> <port>` が port 0（拒否）の m-line を検出する。検出時点は `onCreateAnswerSuccess`（answer SDP 確定時）で、answer をシグナリング送信する前に行う。
- 拒否された m-line の mid に対し、**offer SDP** を突き合わせて trackId を特定する。offer の該当 m-line の `a=msid:<stream id> <track id>` の track id（`{connection_id}-video` 形式）を使う。`setRemoteDescription` は offer SDP を引数に受けるが現状保持していないため、`SdpNegotiationCallbacks` にフィールドとして保持する。
- 特定した拒否 trackId を `RemoteTrackManager` に伝え、次の 2 経路を確立する。
  - **attach 済み**: trackId で該当エントリを探し、通常の detach と同じ後始末（sink 解除、add 分 ref 返却、renderer 破棄、`_remoteMediaStreams` 更新、`onRemoveTrackEvent` 発火）を行う。renderer 破棄失敗時は既存の `_disposeRetryEntries` を再利用して次回の `detachAllRemoteVideoTracks` で回収する。
  - **attach 未了 / 追加前**: 拒否済み trackId の集合を `RemoteTrackManager` が保持し、`attachRemoteVideoTrack` の入口と renderer 作成後の確認の両方で打ち消す（add 分の参照を返却）。これは trackAddress に依存する既存の `_removedBeforeAttach` ではカバーできないレース（answer 確定前後に attach が進行するケース）への対処。
  - 後続 re-offer で同じ trackId が再 offer された場合も同じ集合で打ち消す。
- audio m-line の拒否（port 0）も対称に処理し、`RemoteTrackManager.handleRemoteAudioTrackRemoved` を trackId のみで呼ぶ（audio は trackAddress を持たないため）。
- 通知経路は `SdpNegotiationCallbacks` → `WebrtcClient` の内部イベント（例: `remote_rejected_tracks`、trackId 一覧を載せる）→ `SoraConnection._handleWebrtcEvent` → `RemoteTrackManager`。
- 既存の参照収支（`issues/closed/0073-bug-fix-remote-video-track-refcount-leak.md` で確定した add / remove イベント分の ref 収支）は維持する。本 issue の打ち消しは「add 分の返却」のみで完結させ、除去イベントは重複発火させない。

## 完了条件

- [ ] Linux + H.264 のシナリオ（多人数チャネル、recvonly）で、非対応コーデックの映像が黒画面として表示されず、相手端末の切断後に映像トラックが残らない（devtools の Video タブからセルが消える）。
- [ ] `native: onremovetrack` が発火しない場合でも、拒否された video track について `SoraRemoveTrackEvent` が 1 回だけ発火し、`RemoteMediaStream` からも除去される。
- [ ] 対応コーデック（VP8 / VP9 / AV1）の通常受信では挙動が変わらず、既存 E2E（`e2e_test_app/integration_test/remote_media_stream_e2e_test.dart` 等）が通る。
- [ ] offer / answer のペアから拒否 trackId を正しく抽出するユニットテストと、attach 済み / attach 未了の両レースを exercise するユニットテストが追加され、FFI 依存テスト（Linux CI）が成功する。
- [ ] `flutter analyze --fatal-infos` が成功する。

## 解決方法

- `lib/src/ffi/callback_handlers.dart`: offer SDP の保持、answer SDP の port 0 m-line 検出、拒否 trackId の抽出と通知。
- `lib/src/ffi/webrtc_client.dart`: `SdpNegotiationCallbacks` からの拒否通知を `_onEvent` 経由で `SoraConnection` へ流す wiring。
- `lib/src/sora_connection.dart`: `_handleWebrtcEvent` での拒否イベント処理（`_emitRemoveTrackEvent` 経由のイベント発火を含む）。
- `lib/src/sora_remote_track_manager.dart`: 拒否済み trackId 集合の保持、`attachRemoteVideoTrack` の打ち消し、trackId 指定の detach と `_disposeRetryEntries` の連携。
- ユニットテストの追加と、`CHANGES.md` への Fix 追記（`shiguredo-changelog` スキルの規約に従う）。

## 関連

- `issues/0161-bug-fix-remote-track-retry-lifecycle-hardening.md`（破棄失敗時の再試行機構との相互作用を確認する必要がある）
- `issues/closed/0073-bug-fix-remote-video-track-refcount-leak.md`（ref 収支の確定。本 issue の打ち消しはここに従う）
- `issues/closed/0012-test-add-remote-media-streams-e2e-coverage.md`（相手切断時の `RemoteMediaStream` 除去の既存 E2E）
