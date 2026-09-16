# 対応 Sora バージョンの検証マトリクスを文書化する

- Created: 2026-09-07
- Completed: 2026-09-11
- Branch: feature/doc-sora-version-verification-matrix
- Polished: {YYYY-MM-DD}
- Milestone: 2026.1.0
- Updated: 2026-09-10

## 目的

`README.md` の「Sora 2025.1.0 以降」の根拠を利用者が確認できるようにすること。

## 現状

`README.md` の対応 WebRTC SFU Sora 節はバージョン番号のみであり、E2E 検証に使った Sora バージョン、シグナリング仕様の対応範囲、非対応機能との対応関係が文書化されていない。`README.md` の優先実装節にある Opus 詳細パラメータが未対応である旨も対応表にない。

## 設計方針

- 検証済み Sora バージョンと E2E 実行条件を `README.md` または `docs/` に追記する。
- 対応範囲と非対応機能の対応表に絞り、仕様本文の複写は行わない。
- 日本語で書く。

## 完了条件

- [x] 検証済み Sora バージョンと対応範囲が文書で確認できる。
- [x] 非対応機能への案内が対応表と矛盾しない。

## 解決方法

- `README.md` の「対応 WebRTC SFU Sora」節を「Sora 2025.1.0 以降に対応しています。」に変更し、以下を追記した。
  - 「検証状況」: `e2e_test_app` の `integration_test` で検証していることと、CI (`.github/workflows/e2e-test.yml`) が macOS / Windows / Ubuntu 24.04 (x86_64) の 3 環境で `TEST_SIGNALING_URLS` の検証用 Sora に接続することを記載した。
  - 「対応範囲」: シグナリング、リアルタイムメッセージング / RPC、シグナリング通知 / リダイレクト / 複数シグナリング URL (フェイルオーバー)、メタデータ認証 / シグナリング通知メタデータ、マルチストリーム / サイマルキャスト / スポットライト、転送フィルター、各種タイムアウト、コーデック、Texture レンダリングを「対応」、Opus 詳細パラメーターを「実験的機能」として表にまとめた。
  - 「未対応」: Sora 2025.1.0 より前のバージョン、サイマルキャストマルチコーデックを列挙した。
- 記載内容が `.github/workflows/e2e-test.yml`、`lib/` の実装、既存の「対応コーデック」節と矛盾しないことを確認した。
