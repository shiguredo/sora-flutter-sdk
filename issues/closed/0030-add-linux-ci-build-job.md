# CI に Linux ビルドジョブを追加する

- Priority: Medium
- Created: 2026-06-03
- Completed: 2026-06-29
- Model: Opus 4.8
- Branch: feature/add-linux-ci-build-job
- Polished: 2026-06-03

## 目的

Linux 対応の回帰を防ぐため、CI に Linux のビルド (および MethodChannel が揃った段階で E2E テスト) ジョブを追加する。現状 CI は Android (ubuntu) / iOS (macOS) のみで、Linux のビルドが壊れても検知できない。

本 issue は 0024 (Linux ネイティブ依存取得) 完了後に着手でき、Linux の各機能実装 (0026-0029) と並行・追従して整備する。Windows の CI ジョブは 0038 で扱う。

## 優先度根拠

- Linux 対応の品質維持に必要
- 機能実装が先行するため Medium とする

## 現状

- `.github/workflows/ci.yml` のジョブは `build-android` (ubuntu-24.04) と `build-ios` (macos-26) のみ (`:52-417`)。Linux ジョブは無い。
- CI は `fetch_native_deps.dart` を直接呼んでいない。Android は Gradle task (`fetchNativeDeps`)、iOS は SPM 経由で取得する。Linux は Gradle / SPM を介さないため、CI ステップで直接 `dart run scripts/fetch_native_deps.dart linux_x86_64` を呼ぶ新規経路になる (0026 が CMake からの自動取得を配線するなら、CI でも `flutter build linux` 経由で取得が走る)。
- ネイティブ依存は `scripts/native_deps.json` の hash をキーにキャッシュしている (`:150-155`, `:380-385`)。
- `.github/workflows/e2e-test.yml:1-3` に「Linux 向け MethodChannel が未実装のため macOS デスクトップで実行する。将来 Linux が揃ったら matrix で ubuntu + `flutter test ... -d linux` を追加する」とのコメントがある。
- AGENTS.md「GitHub Actions は公式以外は利用しないこと」。

## 設計方針

- `ci.yml` に `build-linux` (ubuntu-24.04) ジョブを追加する。`flutter build linux` で `e2e_test_app` (linux ランナー) をビルドする。0026 が CMake から `fetch_native_deps.dart linux_x86_64` を起動する配線を入れているなら、ビルド前に依存取得が走る。配線が無い場合は明示的な取得ステップを入れる。
- `flutter build linux` には GTK / ninja / clang など Linux デスクトップビルドの依存が要る。`apt-get` で導入する (公式ランナーの標準手段)。
- Dart / C / C++ の lint も Linux ジョブの対象に含める (Android ジョブと同水準)。
- ネイティブ依存キャッシュを Android / iOS と同じ `native_deps.json` hash 方式で Linux にも適用する。
- E2E テスト (`e2e-test.yml`) は、Linux の MethodChannel (0026-0029) が揃った段階で matrix に ubuntu + `-d linux` を追加する。揃っていなければ本 issue では `build-linux` のビルドジョブ追加のみとし、E2E Linux 追加は追従とする。
- 公式 Action のみ使用する。

## 完了条件

- `ci.yml` に `build-linux` ジョブが追加され、PR で Linux のビルドが実行される。
- ネイティブ依存キャッシュが Linux でも効く。
- (Linux MethodChannel 完了後) E2E テストの Linux ジョブが追加される。
- `CHANGES.md` の `## develop` の `### misc` セクションに以下の `[ADD]` エントリを追記する:
  ```
  - [ADD] CI に Linux ビルドジョブを追加する
    - `ci.yml` に `build-linux` ジョブを追加し、PR で Linux ビルドを実行する
    - @{実装者のユーザー名}
  ```

## 解決方法

1. `.github/workflows/ci.yml` に `build-linux` ジョブ (ubuntu-24.04、GTK 等の apt 導入、依存取得、`flutter build linux`、lint) を追加する。
2. ネイティブ依存キャッシュを Linux に適用する。
3. Linux MethodChannel 完了後、`e2e-test.yml` に Linux ジョブを追加する。
4. `CHANGES.md` にエントリを追記する。
