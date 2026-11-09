# 変更履歴

- CHANGE
  - 下位互換のない変更
- ADD
  - 下位互換がある追加
- UPDATE
  - 下位互換がある変更
- FIX
  - バグ修正

## 2026.2.0

**リリース日**: 2026-11-09

- [ADD] iOS の PrivacyInfo.xcprivacy を同梱する
  - Sora Flutter SDK 内の Required Reason API の利用理由を SDK 側で宣言する
  - @zztkm
- [UPDATE] iOS の画面キャプチャの時刻取得を `CACurrentMediaTime()` に変更する
  - Required Reason API に分類される `ProcessInfo.processInfo.systemUptime` の利用をなくすため
  - 公開 API と Dart 側の挙動は変わらない
  - @zztkm
- [FIX] redirect 直後に WebSocket が close されると接続に失敗するバグを修正する
  - @zztkm

### misc

- [ADD] E2E テストの結果を Slack に通知するジョブを追加する
  - @zztkm
- [UPDATE] WebRTC client の worker thread を network thread に統一する
  - @melpon
- [UPDATE] Required Reason API の再導入を検出する CI 検査を追加する
  - @zztkm

## 2026.1.0

**リリース日**: 2026-09-16
