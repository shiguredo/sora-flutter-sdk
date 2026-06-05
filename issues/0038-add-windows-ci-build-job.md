# CI に Windows ビルドジョブを追加する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-windows-ci-build-job
- Polished: 2026-06-03

## 目的

Windows 対応の回帰を防ぐため、CI に Windows のビルドジョブを追加する。現状 CI は Android (ubuntu) / iOS (macOS) のみで、Windows のビルドが壊れても検知できない。

本 issue は 0032 (Windows ネイティブ依存取得) と 0034 (Windows プラグイン基盤、Windows ランナー生成を含む) 完了後に着手できる。Linux の CI ジョブは 0030 で扱う。

## 優先度根拠

- Windows 対応の品質維持に必要
- Linux 先行のため Medium とする

## 現状

- `.github/workflows/ci.yml` のジョブは `build-android` (ubuntu-24.04) と `build-ios` (macos-26) のみ (`:52-417`)。Windows ジョブは無い。
- CI は `fetch_native_deps.dart` を直接呼んでいない。Windows は Gradle / SPM を介さないため、CI ステップで直接 `dart run scripts/fetch_native_deps.dart windows_x86_64` を呼ぶ新規経路になる (0034 が CMake からの自動取得を配線するなら `flutter build windows` 経由で取得が走る)。
- ネイティブ依存は `scripts/native_deps.json` の hash をキーにキャッシュしている (`:150-155`, `:380-385`)。
- Windows desktop ランナーは 0034 で `e2e_test_app/` に生成される。本 issue はそれが存在することを前提とする。
- AGENTS.md「GitHub Actions は公式以外は利用しないこと」。

## 設計方針

- `ci.yml` に `build-windows` ジョブを GitHub 公式の Windows ランナー (`windows-2022` 系) で追加する。`flutter build windows` で `e2e_test_app` (windows ランナー) をビルドする。
- MSVC ツールチェーン (Visual Studio Build Tools) は公式 Windows ランナーに同梱される。`flutter config --enable-windows-desktop` 相当の準備を行う。
- 0034 が CMake から `fetch_native_deps.dart windows_x86_64` を起動する配線を入れているならビルド前に依存取得が走る。無い場合は明示的な取得ステップを入れる (zip 展開のため `archive` を含む `dart pub get` 済みであること)。
- ネイティブ依存キャッシュを Android / iOS と同じ `native_deps.json` hash 方式で Windows にも適用する。
- 公式 Action のみ使用する。

## 完了条件

- `ci.yml` に `build-windows` ジョブが追加され、PR で Windows のビルドが実行される。
- ネイティブ依存キャッシュが Windows でも効く。
- `CHANGES.md` の `## develop` の `### misc` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] CI に Windows ビルドジョブを追加する
    - `ci.yml` に `build-windows` ジョブを追加し、PR で Windows ビルドを実行する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `.github/workflows/ci.yml` に `build-windows` ジョブ (windows-2022、依存取得、`flutter build windows`) を追加する。
2. ネイティブ依存キャッシュを Windows に適用する。
3. `CHANGES.md` にエントリを追記する。
