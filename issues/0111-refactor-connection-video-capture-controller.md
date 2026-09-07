# `SoraConnection` から映像キャプチャ切替ロジックを `LocalVideoCaptureController` に分割する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-connection-video-capture-controller
- Polished: 2026-09-07

## 目的

`SoraConnection` 本体（`sora_connection.dart` 2506 行、`sora_connection_signaling.dart` と合わせ 3202 行）が「ライフサイクル管理 / 映像キャプチャ切替 / シグナリング橋渡し / native イベント dispatch」を単一クラスに詰め込んでおり、`_videoCaptureOperationGeneration` / `_skipVideoCaptureStopInTeardown` / `_pendingVideoCaptureOperation` など映像キャプチャ切替専用のフラグが独立に散在している。他の副責務がすでに `DataChannelController` / `RemoteTrackManager` / `SignalingSessionState` に切り出せているのに対し、映像キャプチャ切替だけがコントローラ化されずに残っている。分離することで単一責務化とテスト容易性を改善する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection` は以下の映像キャプチャ関連の状態と処理を単一クラスで保持している:

- 状態: `_videoCaptureOperationGeneration`, `_pendingVideoCaptureOperation`, `_skipVideoCaptureStopInTeardown`
- メソッド: `_beginVideoCaptureOperation`, `_stopPendingVideoCaptureOperation`, `_invalidateVideoCaptureOperation`, `_isCurrentVideoCaptureOperation`, `_finishVideoCaptureOperation`, `_stopVideoCaptureBackendIfOwned`, `_applyVideoCaptureBackend`, `_stopVideoCaptureBackend`, `_emitVideoCaptureBackendError`
- 直接の呼び出し元: `connect` / `_connect` / `disconnect` / `_teardownNativeSession` (teardown 経由) / `replaceVideoTrack` / `_replaceVideoTrackInternal` / `removeVideoTrack` / `_removeVideoTrackInternal`

`_replaceVideoTrackInternal` は 224 行を単一メソッドで扱っており、状態遷移が読み取りにくい (`replaceVideoTrack` 自体は `_runVideoMutation` への委譲のみの 6 行)。

## 設計方針

- `LocalVideoCaptureController` クラスを新設し、上記の状態 3 件とメソッド 9 件を移す。`_runVideoMutation` / `_videoMutationLockTail` (変異直列化) は `SoraConnection` に残す。
- コントローラは `SoraConnection` 本体への参照を持たず、必要最小の callback 群を受け取る (`id`、`_emitLocalVideo`、`_emitConnectionErrorEvent` を含み、disposed 判定・接続状態・`_localStream` / `_currentVideoTrack` 参照・sender 操作・track capture 開始停止・timeout 設定の伝達手段を過不足なく定める)。
- `SoraConnection.replaceVideoTrack` / `_replaceVideoTrackInternal` / `removeVideoTrack` 系と `_connect` / 停止系はコントローラの API を呼ぶ形にする。
- `0074` は closed 済みであり `_applyVideoCaptureBackend` の rethrow 化は適用済みのため、順序制約は設けない。
- `0147` との結合点 (`_emitLocalVideo` の null skip) は変更しない。
- 挙動変更はしない。単純な責務移動。

## 完了条件

- [ ] `LocalVideoCaptureController` が新設され、上記の状態 3 件とメソッド 9 件が移されている。
- [ ] `SoraConnection` から該当フラグ / メソッドが消えている。
- [ ] 既存テスト (`test/sora_connection_test.dart` 等) と `flutter analyze` が成功し、キャプチャ切替経路の挙動が変わらない。
