# `sora_signaling_session_state_test.dart` の `resetSession()` 全フィールド検証を追加する

- Created: 2026-08-27
- Completed: {YYYY-MM-DD}
- Branch: feature/test-signaling-session-state-reset
- Polished: {YYYY-MM-DD}

## 目的

`SignalingSessionState.resetSession()` のテストが `hasActiveTransport` と `ignoreDisconnectWebSocket` の default / reset のみを検証しており、他のフィールド（connectionId / serverClientId / bundleId / sessionId / pendingDisconnectCloseInfo / emittedDisconnectedWithCloseInfo）のリセットが担保されていない状態を解消する。

## 現状

`test/sora_signaling_session_state_test.dart` は `hasActiveTransport` と `ignoreDisconnectWebSocket` の初期値・リセット後値のみを検証する。

`SignalingSessionState` の他のフィールド（例: `connectionId` / `serverClientId` / `bundleId` / `sessionId` / `pendingDisconnectCloseInfo` / `emittedDisconnectedWithCloseInfo` など）が `resetSession()` で正しくリセットされるかは検証されていない。

## 設計方針

- `SignalingSessionState` の全フィールドを列挙し、各フィールドについて「初期値」「set 後」「resetSession 後」の 3 状態をテストで担保する。
- テスト名は日本語（AGENTS.md 規約）。
- モック / スタブは使わない。
- 既存の 2 フィールドテストと同じスタイルで追加する。

## 完了条件

- [ ] `SignalingSessionState` の全フィールドに対する resetSession テストがある。
- [ ] テスト名が日本語で書かれている。
- [ ] `flutter analyze` と関連テストが成功する。
