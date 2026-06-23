# CHANGES

## develop

### misc

- [ADD] devtools を Windows でも使えるようにする
  - @zztkm

- [ADD] Windows に DataChannel Observer ブリッジを実装する
  - @zztkm

- [ADD] Windows に EventChannel イベント送出機構を実装する
  - @zztkm

- [ADD] Windows にカメラキャプチャ失敗時のエラー通知を実装する
  - @zztkm

- [ADD] replaceVideoTrack の E2E テストを追加する
  - @zztkm

- [ADD] messaging 専用接続の E2E テストを追加する
  - @zztkm

- [ADD] ユーザー定義 DataChannel の送受信 E2E テストを追加する
  - @zztkm

- [FIX] Windows の VideoFormat 重複除去を汎用的な実装に修正する
  - @zztkm

- [FIX] re-offer 受信経路に応じて re-answer の送信先を切り替えるよう修正する
  - @zztkm

- [ADD] 接続失敗系の E2E テストを追加する
  - @zztkm

- [ADD] dispose 後の API 拒否を確認する E2E テストを追加する
  - @zztkm
