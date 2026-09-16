# `dispose` と後始末のベストエフォート catch に debug 記録を追加する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/refactor-dispose-teardown-debug-logging
- Polished: 2026-09-10

## 目的

切断後始末の継続性を保ったまま、握りつぶされている失敗を調査可能にすること。

## 現状

`lib/src/sora_connection.dart` の `SoraConnection.dispose` は `disconnect` 失敗と `detachAllRemoteVideoTracks` 失敗を捕捉して継続するが、`_emitDebugMessage` への記録が無い。`_subscription?.cancel` 失敗は `_emitDebugMessage` を呼ぶが、`_debugMessages.close()` より後で emit するため破棄される。同ファイルの `SoraConnection._teardownNativeSession` 内の `detachAllRemoteVideoTracks` 失敗時の catch も継続理由のコメントのみで記録がない。

`RemoteTrackManager.detachAllRemoteVideoTracks` は per-track の detach 失敗を内部で `onDebugMessage` に記録済みであり、外側 catch に到達するのは集約失敗（`Future.wait` 経由）のみである。リリース後の不具合調査で集約失敗の原因が追えない。

## 設計方針

- 継続する振る舞いは変えず、対象のベストエフォート catch で捕捉した例外を `_emitDebugMessage` に残す。
- 対象は `SoraConnection.dispose` と `SoraConnection._teardownNativeSession` 内の次の catch とする。これ以外のベストエフォート catch（映像キャプチャ停止系など、既に `SoraConnectionErrorEvent` を出しているものを含む）は対象外とする。
  - `SoraConnection.dispose` の `disconnect()` 失敗 catch
  - `SoraConnection.dispose` の `detachAllRemoteVideoTracks()` 失敗 catch
  - `SoraConnection.dispose` の `_subscription?.cancel()` 失敗 catch
  - `SoraConnection._teardownNativeSession` の `detachAllRemoteVideoTracks()` 失敗 catch
- `_debugMessages` が close 済みのタイミングでは記録しない。`SoraConnection.dispose` の `_subscription?.cancel()` 失敗記録は現状 `_debugMessages.close()` より後に emit されて破棄されるため、記録が残るよう emit を close より前に移す。teardown の処理順序（停止・切断の順番）は変えない。
- `RemoteTrackManager.detachAllRemoteVideoTracks` の per-track 失敗は同メソッド内で既に `onDebugMessage` 済みである。外側 catch の記録は集約失敗（`Future.wait` 経由）を対象にする。
- 取得や停止の再試行は行わない。

## 完了条件

- [ ] 対象 catch（`SoraConnection.dispose` の `disconnect()` / `detachAllRemoteVideoTracks()` / `_subscription?.cancel()` 失敗、`SoraConnection._teardownNativeSession` の `detachAllRemoteVideoTracks()` 失敗）で継続しつつ `_emitDebugMessage` が呼ばれる。
- [ ] `SoraConnection.dispose` の `_subscription?.cancel()` 失敗記録が `_debugMessages.close()` より前に emit され、購読側で観測できる。
- [ ] 追加した各記録を検証するテストが、既存の `@visibleForTesting` フック（`teardownFailureForTest` 等）で注入して追加されている（モックやスタブを使用しない）。
- [ ] `flutter analyze` と関連テストが成功する。
