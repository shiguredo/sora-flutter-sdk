# Windows のドキュメントを追加し README のサポート OS を更新する

- Priority: Low
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-windows-docs
- Polished: 2026-06-03

## 目的

Windows 対応に合わせ、ビルド手順・対応バージョン・依存関係を記したドキュメントを追加し、README の対応プラットフォーム表の Windows 行を更新する。

本 issue は Windows の実装 (0032-0038) の完了に追従して整備する。Linux のドキュメントは 0031 で扱う。

## 優先度根拠

- 利用者向けの案内に必要だが、実装が前提
- Low とする

## 現状

- `README.md:414-421` の対応プラットフォーム表は Windows を「未対応」と記載している。
- `docs/` には `ANDROID.md` / `IOS.md` / `MACOS.md` / `WEBRTC_BUILD.md` があるが、`WINDOWS.md` は無い。
- `README.md:384-407` にプラットフォーム別ビルド方法が記載されている。

## 設計方針

- `docs/WINDOWS.md` を追加する。以下を記載する。
  - 対応アーキテクチャ (第一弾: x86_64)
  - 必要な前提 (Visual Studio / Build Tools、Media Foundation、WASAPI など。0034-0036 で確定したリンク依存に合わせる)
  - `fetch_native_deps.dart windows_x86_64` を使った依存取得とビルド手順 (zip 展開のため `archive` 依存が必要な点、0034 で CMake からの自動取得を配線した場合はその旨も)
  - `build-windows_x86_64/` のレイアウト
- `README.md` の対応プラットフォーム表の Windows 行を実態に合わせて更新する (対応 / 一部対応など、実装状況に即した表記)。
- ビルド方法セクションに Windows の取得手順を追記する。
- 既存の `docs/ANDROID.md` / `docs/MACOS.md` の記述スタイルに合わせる。

## 完了条件

- `docs/WINDOWS.md` が追加されている。
- `README.md` の対応プラットフォーム表とビルド方法が Windows の実態を反映している。
- markdownlint が通過する。
- `CHANGES.md` の `## develop` の `### misc` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] Windows のドキュメントを追加し README のサポート OS を更新する
    - `docs/WINDOWS.md` を追加し、README の対応プラットフォーム表に Windows を反映する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `docs/WINDOWS.md` を作成し、システム要件・依存パッケージ・ビルド手順を記載する
2. `README.md` の対応プラットフォーム表の Windows 行とビルド方法を更新する
