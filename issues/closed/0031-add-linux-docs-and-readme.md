# Linux のドキュメントを追加し README のサポート OS を更新する

- Priority: Low
- Created: 2026-06-03
- Completed: 2026-07-14
- Model: Opus 4.8
- Branch: feature/add-linux-docs
- Polished: 2026-06-03

## 目的

Linux 対応に合わせ、ビルド手順・対応バージョン・依存関係を記したドキュメントを追加し、README の対応プラットフォーム表の Linux 行を更新する。

本 issue は Linux の実装 (0024-0030) の完了に追従して整備する。Windows のドキュメントは 0039 で扱う。

## 優先度根拠

- 利用者向けの案内に必要だが、実装が前提
- Low とする

## 現状

- `README.md:414-421` の対応プラットフォーム表は Linux を「未対応」と記載している。
- `docs/` には `ANDROID.md` / `IOS.md` / `MACOS.md` / `WEBRTC_BUILD.md` があるが、`LINUX.md` は無い。
- `README.md:384-407` にプラットフォーム別ビルド方法 (iOS/macOS は SPM 自動取得、Android は `fetchNativeDeps`) が記載されている。

## 設計方針

- `docs/LINUX.md` を追加する。以下を記載する。
  - 対応ディストリ / アーキテクチャ (第一弾: Ubuntu 24.04 x86_64)
  - 必要なシステムパッケージ (GTK 開発パッケージ、V4L2、PulseAudio など。0026-0028 で確定したリンク依存に合わせる)
  - `fetch_native_deps.dart linux_x86_64` を使った依存取得とビルド手順 (0026 で CMake からの自動取得を配線した場合はその旨も)
  - `build-linux_x86_64/` のレイアウト
- `README.md` の対応プラットフォーム表の Linux 行を実態に合わせて更新する (対応 / 一部対応など、実装状況に即した表記)。
- ビルド方法セクションに Linux の取得手順を追記する。
- 既存の `docs/ANDROID.md` / `docs/MACOS.md` の記述スタイルに合わせる。

## 完了条件

- `docs/LINUX.md` が追加されている。
- `README.md` の対応プラットフォーム表とビルド方法が Linux の実態を反映している。
- markdownlint が通過する。
- `CHANGES.md` の `## develop` の `### misc` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] Linux のドキュメントを追加し README のサポート OS を更新する
    - `docs/LINUX.md` を追加し、README の対応プラットフォーム表に Linux を反映する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `docs/LINUX.md` を作成し、システム要件・依存パッケージ・ビルド手順を記載する
2. `README.md` の対応プラットフォーム表の Linux 行とビルド方法を更新する
