# `dispose` と後始末のベストエフォート catch に debug 記録を追加する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-dispose-teardown-debug-logging
- Polished: {YYYY-MM-DD}

## 目的

切断後始末の継続性を保ったまま、握りつぶされている失敗を調査可能にすること。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection.dispose` は `disconnect` 失敗と `detachAllRemoteVideoTracks` 失敗の一部を捕捉して継続するが、`_emitDebugMessage` への記録が欠落している箇所がある。同ファイルの `SoraConnection._teardownNativeSession` 内の `RemoteTrackManager.detachAllRemoteVideoTracks` 失敗時の catch も継続理由のコメントのみで記録がない。リリース後の不具合調査で原因が追えない。

## 設計方針

- 継続する振る舞いは変えず、捕捉した例外を必ず `_emitDebugMessage` に残す。
- `_debugMessages` が close 済みの timing では記録を落とすか破棄するかを明確化する。
- 再試行や順序変更は行わない。

## 完了条件

- [ ] ベストエフォート catch の全経路で継続しつつ debug 記録が残る。
- [ ] `flutter analyze` と関連テストが成功する。
