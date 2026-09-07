# 対応 Sora バージョンの検証マトリクスを文書化する

- Created: 2026-09-07
- Completed: {YYYY-MM-DD}
- Branch: feature/doc-sora-version-verification-matrix
- Polished: {YYYY-MM-DD}

## 目的

`README.md` の「Sora 2025.1.0 以降」の根拠を利用者が確認できるようにすること。

## 現状

`README.md` の対応 WebRTC SFU Sora 節はバージョン番号のみであり、E2E 検証に使った Sora バージョン、シグナリング仕様の対応範囲、非対応機能との対応関係が文書化されていない。`README.md` の優先実装節にある Opus 詳細パラメータと `audioStreamingLanguageCode` が未対応である旨も対応表にない。

## 設計方針

- 検証済み Sora バージョンと E2E 実行条件を `README.md` または `docs/` に追記する。
- 対応範囲と非対応機能の対応表に絞り、仕様本文の複写は行わない。
- 日本語で書く。

## 完了条件

- [ ] 検証済み Sora バージョンと対応範囲が文書で確認できる。
- [ ] 非対応機能への案内が対応表と矛盾しない。
