# `SoraConnection` から映像キャプチャ切替ロジックを `LocalVideoCaptureController` に分割する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-connection-video-capture-controller
- Polished: {YYYY-MM-DD}

## 目的

`SoraConnection` 本体（2248 行、part 統合で 2749 行）が「ライフサイクル管理 / 映像キャプチャ切替 / シグナリング橋渡し / native イベント dispatch」を単一クラスに詰め込んでおり、`_videoCaptureOperationGeneration` / `_skipVideoCaptureStopInTeardown` / `_pendingVideoCaptureOperation` など映像キャプチャ切替専用のフラグが独立に散在している。他の副責務がすでに `DataChannelController` / `RemoteTrackManager` / `SignalingSessionState` に切り出せているのに対し、映像キャプチャ切替だけがコントローラ化されずに残っている。分離することで単一責務化とテスト容易性を改善する。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection` は以下の映像キャプチャ関連の状態と処理を単一クラスで保持している:

- 状態: `_videoCaptureOperationGeneration`, `_pendingVideoCaptureOperation`, `_skipVideoCaptureStopInTeardown`
- メソッド: `_beginVideoCaptureOperation`, `_stopPendingVideoCaptureOperation`, `_invalidateVideoCaptureOperation`, `_applyVideoCaptureBackend`, `_stopVideoCaptureBackend`, `_emitVideoCaptureBackendError`
- 呼び出し元: `connect` / `_connect` / `disconnect` / `_disconnectBody` / `_teardownNativeSession` / `replaceVideoTrack` / `_replaceVideoTrackInternal`

`replaceVideoTrack` 経路は 200 行以上を単一メソッドで扱っており、状態遷移が読み取りにくい。

## 設計方針

- `LocalVideoCaptureController` クラスを新設し、以下を移す:
  - `_beginVideoCaptureOperation` / `_stopPendingVideoCaptureOperation` / `_pendingVideoCaptureOperation` / `_videoCaptureOperationGeneration` / `_skipVideoCaptureStopInTeardown`
- コントローラは `SoraConnection` から `id` / `_dispatchLocalVideoHandle` / `_emitConnectionErrorEvent` を callback 経由で受け取る。
- `SoraConnection.replaceVideoTrack` はコントローラ経由に置き換え、`SoraConnection._connect` / `_disconnectBody` / `_teardownNativeSession` からもコントローラの API を呼ぶ形にする。
- `_applyVideoCaptureBackend` の rethrow 化（0074）と、コントローラ分離の順序は「rethrow 化を先」に進める。
- 挙動変更はしない。単純な責務移動。
- 分離した結果として `SoraConnection` の行数と状態フラグが減ることを完了条件とする。

## 完了条件

- [ ] `LocalVideoCaptureController` が新設され、映像キャプチャ切替ロジックがそこに移されている。
- [ ] `SoraConnection` の該当フラグ / メソッドが消え、行数が減る。
- [ ] `replaceVideoTrack` の実装が 300 行以下になる（目安）。
- [ ] 既存の全キャプチャ切替経路の挙動が変わらない。
- [ ] `flutter analyze` と関連テストが成功する。
