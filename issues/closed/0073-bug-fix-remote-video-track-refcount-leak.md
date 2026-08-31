# RemoteTrackManager の早期 return 経路でリモートビデオトラックの refcount が leak する

- Created: 2026-08-27
- Completed: 2026-08-31
- Branch: feature/fix-remote-video-track-refcount-leak
- Polished: 2026-08-27
- Milestone: 2026.1.0

## 目的

C 側 bridge が `webrtc_VideoTrackInterface_AddRef` で 1 refcount を追加してから Dart に渡すリモートビデオトラックについて、`RemoteTrackManager` の attach / detach で参照の返却が漏れ、リモートビデオトラックの add/remove サイクル毎に refcount が leak するバグを修正する。長時間セッションや参加者の入退室が多い会議で native トラックが解放されず堆積する。

## 現状

C 側の実装（`linux/linux_bridge.c` の `bridge_on_track` / `bridge_on_remove_track` および Apple / Windows / JNI の対応関数）は、add イベントと remove イベントの**両方**で `webrtc_VideoTrackInterface_AddRef` を呼んでから Dart に渡す。

Dart 側の `lib/src/sora_remote_track_manager.dart` は、attach / detach の各経路で参照を以下のように扱う。

- add イベント（`attachRemoteVideoTrack`）: happy path では受け取った `trackAddress` を `_RemoteTrackEntry` に保持し、release しない
- remove イベント（`detachRemoteVideoTrack` → `_detachRemoteVideoTrackUnsafe`）: happy path では `entry.trackAddress` を `videoTrackRelease` で 1 回 release する

そのため、正常な add → remove のサイクルの収支は「AddRef 2 回（add + remove）に対して Release 1 回」となり、**早期 return 経路を通らない正常サイクルでも 1 refcount が残る**。`_detachRemoteVideoTrackUnsafe` の 1 回の release は add イベントで保持した entry 分の返却に相当し、remove イベントで AddRef された分を返却する経路は正常サイクルには存在しない。

さらに、`RemoteTrackManager.attachRemoteVideoTrack` と `_detachRemoteVideoTrackUnsafe` は、以下の早期 return 経路で受信した `trackAddress` を release しない。

- `attachRemoteVideoTrack` の `_remoteTracks.containsKey(trackAddress)` 経路（同一アドレスの再通知時）
- `attachRemoteVideoTrack` の `soraMethodChannel.invokeMethod` で `response == null` を受け取った経路
- `detachRemoteVideoTrack` の `_ongoingDetachAll != null` 経路
- `_detachRemoteVideoTrackUnsafe` の `entry == null` 経路（`_pendingAttach` にも `_remoteTracks` にも存在しない trackAddress の remove 通知）

一方、`attachRemoteVideoTrack` の他の早期 return 経路（`_ongoingDetachAll != null`、`_removedBeforeAttach.contains(trackAddress)`、世代変化、`_ongoingDetachAll` 途中挿入、catch 節）は `WebrtcClient.sharedLib.videoTrackRelease` を呼んでいる。

## 設計方針

参照返却の契約を「add イベントの参照（add 分）と remove イベントの参照（remove 分）を別々に 1 回ずつ返却する」に統一する。返却箇所は次のとおり一意に決める。

- **add 分**: `attachRemoteVideoTrack` の happy path では `_RemoteTrackEntry` に保持し、`_detachRemoteVideoTrackUnsafe` の happy path（既存の `entry.trackAddress` の release）で返却する。attach の各早期 return 経路ではその場で返却する。
- **remove 分**: `detachRemoteVideoTrack`（remove イベント専用ハンドラ）の入口で必ず 1 回返却する。`_detachRemoteVideoTrackUnsafe` は `detachAllRemoteVideoTracks` からも呼ばれるため remove 分の返却は行わず、add 分のみを返却する。

これにより、`detachRemoteVideoTrack` が `_ongoingDetachAll != null` で早期 return する場合や、`_pendingAttach.contains(trackAddress)` / `entry == null` で早期 return する場合でも、remove 分は入口で返却済みのため収支が 0 になる。detachAll 中に remove イベントが到達して `detachRemoteVideoTrack` が呼ばれても、入口の remove 分返却と detachAll 側の add 分返却が二重にならない。

`RemoteTrackManager.attachRemoteVideoTrack` の全早期 return 経路では、受け取った add 分を `WebrtcClient.sharedLib.videoTrackRelease(Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress))` で返却する。`_removedBeforeAttach` 経路（attach 側の release）と `_pendingAttach.contains` 経路（remove 分は入口で返却済み、add 分は attach 側が返却）の責務分担をコメントで明示する。

責務が広がるため、`Pointer<WebrtcVideoTrackInterface>` を release する専用のヘルパー（例: `_releaseTrackRef(int trackAddress)`）を追加してすべての経路から呼ぶ形に整理する。

## 完了条件

- [x] 正常な add → remove サイクルで refcount が増加しない（add 分と remove 分がそれぞれ 1 回ずつ返却される）。
- [x] `detachRemoteVideoTrack` の入口で remove 分が必ず 1 回返却される。
- [x] `RemoteTrackManager.attachRemoteVideoTrack` のすべての早期 return 経路で、受け取った add 分の release が保証される。
- [x] attach 済みトラックの重複通知、`_ongoingDetachAll` 中の attach / detach、`response == null` の防御パス、`entry == null` の遅延 remove 等を exercise するユニットテストを追加する。
- [x] refcount の絶対値は Dart 側から検証できないため、テストでは各シナリオで crash / 例外が発生せず、attach / detach の各経路で release が 1 回だけ呼ばれることを観測対象にする（可能な範囲で）。

## 解決方法

`lib/src/sora_remote_track_manager.dart` を以下の方針で書き換えた。

- `_releaseTrackRef(int trackAddress)` ヘルパを追加し、全 release 経路をこのヘルパ経由に統一する。テスト用に `@visibleForTesting void Function(int)? releaseTrackRefForTest` を追加して、ダミー trackAddress で SEGV する `videoTrackRelease` を安全に差し替え可能にする。
- attach happy path で使う `videoSinkWantsNew` / `videoTrackAddOrUpdateSink` / `videoSinkWantsDelete` を `_attachSinkToTrack` ヘルパに集約し、detach の `videoTrackRemoveSink` を `_removeSinkFromTrack` ヘルパに集約する。それぞれ `@visibleForTesting` のフックで差し替え可能にする。これによりテストは実 FFI に一切依存せず attach / detach happy path を exercise できる。
- add 分 / remove 分の返却契約を分離する:
  - **add 分**: `attachRemoteVideoTrack` の happy path で `_RemoteTrackEntry` に保持し、`_detachRemoteVideoTrackUnsafe` の happy path で 1 回返却する。attach の各早期 return 経路 (`_ongoingDetachAll` / `_remoteTracks.containsKey` / `_removedBeforeAttach` (sync) / 内側 `_ongoingDetachAll` / `_generation` 変化 / `_removedBeforeAttach` (async) / `response == null` / catch 節) では、それぞれの経路で 1 回返却する。
  - **remove 分**: `detachRemoteVideoTrack` (remove イベント専用ハンドラ) の入口で必ず 1 回返却する。`_detachRemoteVideoTrackUnsafe` は `detachAllRemoteVideoTracks` からも呼ばれるため remove 分は扱わない。
- 世代変化 / `_removedBeforeAttach` (async) の 2 経路は共通の `_cancelPendingAttach` ヘルパに集約し、renderer dispose と add 分 release をアトミックに実施する。
- catch 節では `_remoteTracks.remove(trackAddress)` を `_releaseTrackRef` の前に呼び、entry 挿入後の後段 throw で map が汚染されて次回 detach が二重 release する経路を潰す。early throw では remove は no-op。

テストは `test/sora_remote_track_manager_test.dart` を新規作成。実 FFI 依存を持たない設計にするため、`releaseTrackRefForTest` / `attachSinkToTrackForTest` / `removeSinkFromTrackForTest` の 3 フックで FFI を差し替え、`TestDefaultBinaryMessengerBinding.setMockMethodCallHandler` で `createRemoteVideoRenderer` / `disposeRemoteVideoRenderer` を応答する。11 ケース (10 経路検証 + smoke) で release 回数 / method call 回数 / sink attach/remove 記録を検証する。

- 正常な add → remove サイクル (add 分 + remove 分 = 2 回)
- attach 済み trackAddress の重複通知 (1 回)
- `_ongoingDetachAll` 中の attach (1 回)
- `_ongoingDetachAll` 中の detach (1 回)
- `response == null` の防御パス (1 回)
- `entry == null` の遅延 remove (1 回)
- attach 途中の detach (add + remove = 2 回)
- 世代変化した attach (1 回)
- attach 途中の MethodChannel 例外を catch 節が拾う (1 回)
- `detachAllRemoteVideoTracks` が pending attach を打ち消し、renderer 応答後に add 分が 1 回 release される
- smoke: 全経路 crash / 例外なし + 総 release 回数の期待値検証
