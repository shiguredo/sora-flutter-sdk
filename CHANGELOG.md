# 変更履歴

- CHANGE
  - 後方互換のない変更
- ADD
  - 後方互換がある追加
- UPDATE
  - 後方互換がある変更
- FIX
  - バグ修正

## develop

- [UPDATE] libwebrtc-c を 0.150.0 に更新する
  - @zztkm
- [UPDATE] webrtc-build を m150.7871.0.0 に更新する
  - @zztkm
- [FIX] 同一接続上で getStats() の再入競合が発生した時に StateError が送出される問題を修正する
  - @zztkm

### misc

- [ADD] remoteMediaStreams の grouping を検証する E2E テストを追加する
  - @zztkm
- [ADD] ローカル音声と映像の有効切り替えを検証する E2E テストを追加する
  - @zztkm
