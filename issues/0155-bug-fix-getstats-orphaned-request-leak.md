# `getStats` 孤立 request の無制限滞留を解消する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/fix-getstats-orphaned-request-leak
- Polished: 2026-09-07

## 目的

`getStats` の異常系で native コールバック資源が無制限に滞留する経路を有界にし、長時間運用でのメモリ増加を抑えること。use-after-free 回避のための孤立保持自体は維持する。

## 現状

`lib/src/ffi/webrtc_client.dart` の `WebrtcClient.cleanupPendingStatsRequest` と `WebrtcClient._detachStatsRequestDartSide` は、切断時と `getStats` のタイムアウト時に Dart 側の待ち合わせだけを外し、`cbsPtr` と `NativeCallable` を `_orphanedStatsRequests` に孤立 request として保持する。解放は `WebrtcClient._takeStatsRequestForCallback` と `WebrtcClient._releaseStatsRequestNativeResources` によるコールバック到着時のみであり、コールバックが到達しない場合は蓄積する。上限や `dispose` 時の掃除がなく、観測手段は `WebrtcClient.orphanedStatsRequestCountForTest` のみである。蓄積はタイムアウトまたは切断のサイクルごとに最大 1 件に rate limit される（`getStats` の多重発行抑止のため）。

`WebrtcClient.closePeerConnection` は `pcRelease` 後に callback が必ず到達する契約を確認できないため、解放済みメモリ参照の回避を優先して孤立保持を意図的に許容している。`dispose` 時の即時解放は遅延コールバック到着時の native クラッシュを再発させる恐れがある。

## 設計方針

- 孤立保持によるクラッシュ回避は維持し、無制限の増加を背圧で抑える。`_orphanedStatsRequests` の上限値を定数として定義し、上限を超えた新規 `getStats` は `StateError` で拒否し、孤立側の即時解放は行わない。テストは定数を参照する。
- `dispose` 時の孤立掃除は行わず、`WebrtcClient.dispose` と `WebrtcClient.closePeerConnection` の docstring に理由（遅延コールバック到着時の native クラッシュ回避）と上限による有界性を明記する。
- 統計取得の正常系（`_handleStatsDelivered` の成功パス）は変えない。対象は切断時とタイムアウト時の孤立化経路である。

## 完了条件

- [ ] 孤立 request が上限を超えて増えず、超過時の新規 `getStats` が `StateError` で拒否されることをユニットテストで確認する（切断サイクルとタイムアウト経路の両方を exercise する）。
- [ ] `dispose` 時に孤立を即時解放しない理由と上限による有界性が `WebrtcClient.dispose` と `WebrtcClient.closePeerConnection` の docstring に明記される。
- [ ] `flutter analyze` と関連テストが成功する。
