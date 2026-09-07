# `getStats` 孤立 request の無制限滞留を解消する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-getstats-orphaned-request-leak
- Polished: {YYYY-MM-DD}

## 目的

`getStats` の異常系で native コールバック資源が無制限に滞留する経路をなくし、長時間運用でのメモリ増加を防ぐこと。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.cleanupPendingStatsRequest` と `WebrtcClient._detachStatsRequestDartSide` は、切断時に Dart 側の待ち合わせだけを外し、`cbsPtr` と `NativeCallable` を `_orphanedStatsRequests` に孤立 request として保持する。解放は `WebrtcClient._takeStatsRequestForCallback` と `WebrtcClient._releaseStatsRequestNativeResources` によるコールバック到着時のみであり、コールバックが到達しない場合は 1 回の `getStats` ごとに恒久リークする。上限や `dispose` 時の掃除がなく、観測手段は `WebrtcClient.orphanedStatsRequestCountForTest` のみである。

## 設計方針

- 孤立 request の上限もしくは破棄時の扱いを決め、意図的許容なら docstring に明記する。
- `dispose` 時の掃除可否を `libwebrtc-c` のコールバック保持契約と突き合わせて判断する。
- 振る舞い変更と文書化のみに絞り、統計取得の正常系は変えない。

## 完了条件

- [ ] 孤立 request が無制限に増えないこと (上限もしくは破棄方針のいずれかで担保される)。
- [ ] `dispose` 時の扱いが docstring またはコードで明示される。
- [ ] `flutter analyze` と関連テストが成功する。
