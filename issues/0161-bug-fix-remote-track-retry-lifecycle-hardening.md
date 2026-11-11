# `RemoteTrackManager` の retry 機構と世代・並行制御の相互作用を硬化する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-remote-track-retry-lifecycle-hardening
- Polished: 2026-11-11

## 目的

`RemoteTrackManager` の retry 機構、世代切り替え、並行 `detachAll`、`clear` の相互作用を硬化し、entry・native 参照・renderer が漏れる経路と、意図しない remove イベントの混同・欠落をなくすこと。0156 の再試行契約と 0073 の add / remove 参照収支は変えない。

## 現状

`lib/src/sora_remote_track_manager.dart` の `RemoteTrackManager._disposeRetryEntries` は `disposeRemoteVideoRenderer` 失敗時に entry を保持し、次回 `detachAllRemoteVideoTracks` または個別 `detachRemoteVideoTrack` で回収する。現行実装では次の相互作用が未整理で、回収漏れや通知の混同が生じ得る。

- 同一 `trackAddress` の再利用時に旧 retry entry と新 `_RemoteTrackEntry` が併存できる。`detachAllRemoteVideoTracks` は `_remoteTracks.keys` と `_disposeRetryEntries.keys` の和集合を重複排除して `_detachRemoteVideoTrackUnsafe` に渡し、同関数は retry entry を優先するため、新 entry は処理されず `_remoteTracks` に残る。teardown 後の `clear` は `_remoteTracks` を消すため、新 entry の add 分の参照・sink・renderer が回収されない。新 entry の remove イベントも旧 entry の後始末に消費され、新 entry の `onRemoveTrackEvent` が発火しない。`trackAddress` はネイティブポインタ由来で再利用され得る。
- `_removedBeforeAttach` は `detachAllRemoteVideoTracks` が `_pendingAttach` を追加する一方、`invalidateGeneration` が全消去する。`attachRemoteVideoTrack` が世代不一致または `_ongoingDetachAll` で打ち切られる経路は `_removedBeforeAttach` を消費しないため、`detachAll` と `invalidateGeneration` の順序によっては該当アドレスが残留する。残留したアドレスに対する後続の attach は、`_removedBeforeAttach.contains` で add 分を返却して早期 return し、renderer を作らない。
- 並行 `detachAllRemoteVideoTracks` は先行呼び出しの `_ongoingDetachAll` を await して return するだけで、再走査しない。先行呼び出しが `disposeRemoteVideoRenderer` 失敗で退避した retry entry は、次の `detachAll` 呼び出しまで回収されない。
- `_detachRemoteVideoTrackUnsafe` は retry entry でない場合、`_remoteTracks.remove` の後、`_removeSinkFromTrack` と `_releaseTrackRef` を実行する。`_removeSinkFromTrack` が例外を投げると entry はどちらの map にも残らず、add 分の参照も返却されない。`clear` は `_remoteTracks` を消すため、entry を `_remoteTracks` に残すだけでは teardown 後の clear で失われる。`_releaseTrackRef` は throw しない前提である。
- `clear` は `_remoteMediaStreams` を消すが `_disposeRetryEntries` は残す。clear 後の再試行で破棄に成功すると、旧 `connectionId` の entry について `onRemoveTrackEvent` が遅延発火する。この遅延通知の意味づけ（発火するか、`_remoteMediaStreams` を更新するか）が未定義である。

## 設計方針

- 変更対象は `lib/src/sora_remote_track_manager.dart` と `test/sora_remote_track_manager_test.dart` に限定する。`lib/src/sora_connection.dart` の `invalidateGeneration` → `_teardownNativeSession` → `_resetConnectionSessionState`（`clear`）の呼び出し順序は変えない。
- retry entry には attach 時の世代と release 済みかどうかの状態を持たせ、同一 `trackAddress` で世代の異なる entry が併存しても別 entry として扱う。`detachAll` はアドレス集合ではなく entry 単位で反復し、開始時点の `_remoteTracks` と `_disposeRetryEntries` の全 entry を同じ呼び出しで個別に処理する。個別 `detachRemoteVideoTrack` は `_remoteTracks` に現行 entry があればそれを優先し、旧 retry entry は `detachAll` で回収する。
- `clear` と `invalidateGeneration` は retry entry を消さない。`clear` は `_remoteMediaStreams` と `_remoteTracks` を消すが、再試行 map は保持する。`invalidateGeneration` は `_removedBeforeAttach` を消すが、再試行 map は保持する。
- `attachRemoteVideoTrack` の全打ち切り経路（世代不一致、`_ongoingDetachAll`、`response == null`、catch）で `_removedBeforeAttach` の該当アドレスを除去する。`detachAll` が追加したアドレスは、待機完了後に未消費分を掃除する。これにより `detachAll` と `invalidateGeneration` の順序に依存した残留をなくす。
- 並行 `detachAll` は先行呼び出しの完了後に `_disposeRetryEntries` が残っていれば 1 回だけ再走査する。失敗が続く場合は次の呼び出しに委ね、無限ループしない。
- retry entry でない場合に `_removeSinkFromTrack` が例外を投げたら、entry を `_remoteTracks` から再試行 map に移し、release 前の失敗として sink 解除と release を再試行する。`_removeSinkFromTrack` と `_releaseTrackRef` が成功した後だけ entry を `_remoteTracks` から除去し、`disposeRemoteVideoRenderer` 失敗時は release 済みの retry entry として保持する。0156 の再試行契約に従い、release 済み entry の再試行では release を skip する。
- `clear` 後の再試行で破棄に成功した場合は、旧 `connectionId` の entry について `onRemoveTrackEvent` を 1 回発火する。`clear` 済みのため `_remoteMediaStreams` の更新は行わない（旧 `connectionId` の stream が残っていても触らない）。この遅延通知を意図的な仕様としてコードコメントとテストで固定する。
- 0156 の再試行契約（add 分は返却済み、再試行で release しない）と、0073 で確定した add / remove の参照収支を変えない。0175 が `_disposeRetryEntries` を再利用する前提を壊さない。

## 完了条件

- [ ] 上記 5 件の相互作用それぞれについて、望ましい挙動がコードコメントとテストで定義され、entry・native 参照・renderer の回収漏れがない。
- [ ] 同一 `trackAddress` の新旧 entry 併存、`_removedBeforeAttach` の順序依存、並行 `detachAll`、`_removeSinkFromTrack` 失敗、clear 後の遅延 remove 通知を exercise するユニットテストを `test/sora_remote_track_manager_test.dart` に追加する。テスト名とログメッセージは日本語にする（`AGENTS.md`）。
- [ ] `flutter analyze --fatal-infos lib test` と `flutter test test/sora_remote_track_manager_test.dart` が成功する。
- [ ] 0156 と同様、正式リリース前のため `CHANGELOG.md` には記載しない。

## 関連

- `issues/closed/0156-bug-fix-remote-track-manager-clear-leak.md` (retry 機構の導入)
- `issues/closed/0073-bug-fix-remote-video-track-refcount-leak.md` (add / remove の参照収支)
- `issues/0175-bug-fix-rejected-video-track-resource-retention.md` (`_disposeRetryEntries` を再利用する後続 issue)
