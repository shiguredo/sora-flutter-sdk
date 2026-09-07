# `RemoteTrackManager.clear` 単独呼び出し時の参照リークをなくす

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-remote-track-manager-clear-leak
- Polished: {YYYY-MM-DD}

## 目的

切断後始末の失敗残存時に native 参照と platform renderer が漏れる経路をなくすこと。

## 現状

`lib/src/sora_remote_track_manager.dart` の `RemoteTrackManager.clear` は `_remoteTracks` と `_remoteMediaStreams` を単に `clear` し、`videoTrackRelease` や `disposeRemoteVideoRenderer` を呼ばない。前提は呼び出し元の `lib/src/sora_connection.dart` の `SoraConnection._teardownNativeSession` が先に `RemoteTrackManager.detachAllRemoteVideoTracks` を完走することだが、同処理は個別失敗を catch して継続するため、残存エントリがあるまま `clear` されると native 参照と `textureId` がリークする。`SoraConnection._resetConnectionSessionState` 経路でも同じ組み合わせである。

## 設計方針

- `detachAll` 失敗残存時の扱いを明確化し、`clear` 単独呼び出しでリークしない契約にするか、残存がある場合は debug ログを残す。
- `RemoteTrackManager._detachRemoteVideoTrackUnsafe` と `RemoteTrackManager._releaseTrackRef` の責務分担は変えず、後始末の順序保証に絞る。

## 完了条件

- [ ] `detachAll` 失敗残存があっても native 参照と renderer が漏れないか、漏れる場合は検出可能である。
- [ ] `flutter analyze` と関連テストが成功する。
