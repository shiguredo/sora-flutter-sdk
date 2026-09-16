# `detachAll` 失敗時に entry を失わず renderer を回収する

- Created: 2026-09-07
- Completed: 2026-09-07
- Branch: feature/fix-remote-track-manager-clear-leak
- Polished: 2026-09-07

## 目的

切断後始末で renderer 破棄に失敗しても platform renderer を漏らさず回収すること。native 参照は破棄失敗時点で返却済みのため対象外とする。

## 現状

`lib/src/sora_remote_track_manager.dart` の `RemoteTrackManager._detachRemoteVideoTrackUnsafe` は entry を先に `remove` してから `_releaseTrackRef` と `disposeRemoteVideoRenderer` を行うため、破棄失敗時に map 残存は生じず、renderer 未破棄と `_remoteMediaStreams` 側の後始末 skip が確定する。`RemoteTrackManager.clear` は `_remoteTracks` と `_remoteMediaStreams` を単に `clear` するため、この時点で回収の手がかりは残らない。`RemoteTrackManager.detachAllRemoteVideoTracks` は内部ループで個別失敗を catch して継続し、`lib/src/sora_connection.dart` の `SoraConnection._teardownNativeSession` は全体を await する。`RemoteTrackManager.clear` の呼び出し点は `SoraConnection._resetConnectionSessionState` の 1 箇所のみである。`_remoteMediaStreams` の audio のみ保持は正常系でも残るため、単なる map 非空では判定できない。

## 設計方針

- `RemoteTrackManager._detachRemoteVideoTrackUnsafe` の順序を見直し、`disposeRemoteVideoRenderer` 失敗時は release 済みを示す状態付きで entry を保持する。再試行では `_releaseTrackRef` を skip し、`disposeRemoteVideoRenderer` と `_remoteMediaStreams` 後始末のみ行う。二重 release は行わない。
- 保持 entry がある場合、`RemoteTrackManager.clear` は残存を消さずに検出ログに留め、次回 `detachAllRemoteVideoTracks` で回収する。`SoraConnection._resetConnectionSessionState` の順序は変えない。
- 詳細記録は manager 層に集約し、connection 層の catch 記録は `0158` が所有するため重複させない。
- 再現は `disposeRemoteVideoRenderer` 失敗を新規 `@visibleForTesting` フックで注入し、renderer 破棄呼び出し回数と video 限定の stream 残存で判定する（モックやスタブは使わない）。

## 完了条件

- [ ] `disposeRemoteVideoRenderer` 失敗時も entry が保持され、再試行で renderer が回収されることをユニットテストで確認する（判定は video 限定とし、audio のみ保持は対象外とする）。
- [ ] `flutter analyze` と関連テストが成功する。

## 解決方法

`_detachRemoteVideoTrackUnsafe` で破棄失敗時に entry を保持し、`detachAll` の反復対象に加えて再試行する。再試行では release を skip して二重解放を防ぐ。`clear` は再試行待ちを消さず検出ログに留める。破棄失敗の注入フックと再試行テスト 5 件で検証する。世代・並行相互作用の硬化は別 issue に分離する。正式リリース前のため `CHANGELOG.md` には記載しない。
