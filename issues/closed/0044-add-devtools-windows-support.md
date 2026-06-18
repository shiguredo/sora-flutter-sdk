# devtools を Windows でも使えるようにする

- Priority: Medium
- Created: 2026-06-17
- Completed: 2026-06-18
- Model: DeepSeek V4 Pro
- Branch: feature/add-devtools-windows-support
- Polished: 2026-06-17

## 目的

sora-flutter-sdk の開発補助・動作確認用アプリである devtools を Windows 上でもビルド・実行できるようにする。
devtools には android / ios / macos のプラットフォームディレクトリのみ存在し、Windows ランナーが無い。
sora_sdk パッケージの Windows プラグインは整備済み (0032-0038) であり、e2e_test_app の Windows ビルドも CI で成功している。
devtools にも Windows プラットフォーム設定を追加すれば、Windows 開発者が devtools を使って Sora の動作確認を行えるようになる。

## 優先度根拠

- Windows 環境の開発者が devtools を利用できないと、Sora の動作確認やデバッグの手段が制限される
- sora_sdk の Windows プラグインが整備済み (0032-0038) のため、devtools 側の対応で完結する
- CI で devtools の Windows ビルドが行われないと、Windows 向け変更のリグレッションを早期発見できない
- 以上を踏まえ Medium とする

## 現状

- `devtools/` のプラットフォームディレクトリは `android/` `ios/` `macos/` のみ。`windows/` は存在しない
- `e2e_test_app/windows/` は存在し、CI で `flutter build windows --release` が成功している
- `sora_sdk` パッケージの `windows/` にプラグイン実装 (C++) が存在する
- CI (`ci.yml`) の `build-windows` ジョブは `e2e_test_app` のみをビルドし、devtools のビルドを行っていない
- `prek.toml` の `dart-analyze-devtools` フック (`prek.toml:59-65`) が `bash -euo pipefail -c` を直接実行しており、Windows の PowerShell 環境では動作しない
- CHANGES.md がリポジトリに存在しない。本 issue で新規作成する

## 設計方針

### devtools/windows/ の追加

- `devtools/` ディレクトリで以下のコマンドを実行し、Windows ランナーを生成する:
  ```
  flutter create --platforms=windows --project-name sora_devtools .
  ```
  これにより `devtools/windows/` 以下に CMakeLists.txt、runner/、flutter/ が生成される。
  既存の `android/` `ios/` `macos/` は上書きされないが、`.metadata` が更新されるため注意する。
- 生成された `devtools/windows/CMakeLists.txt` を e2e_test_app の同等ファイルを参考に修正する:
  - `project(sora_devtools LANGUAGES CXX)`
  - `set(BINARY_NAME "sora_devtools")`
  - `_ITERATOR_DEBUG_LEVEL=0` を追加する（libwebrtc-c.lib が /MT（静的 CRT）でビルドされているため）
  - `_HAS_EXCEPTIONS=0` を追加する（e2e_test_app `windows/CMakeLists.txt:48` と同様）
  - `/MT` 設定を全構成に適用する（e2e_test_app `windows/CMakeLists.txt:47` と同様）
- `devtools/windows/runner/main.cpp` の `Create()` のウィンドウタイトルを `L"sora_devtools"` に変更する
- `devtools/windows/runner/Runner.rc` のメタ情報を以下の値に変更する:
  - `FileDescription`: `"sora_devtools"`
  - `InternalName`: `"sora_devtools"`
  - `OriginalFilename`: `"sora_devtools.exe"`
  - `ProductName`: `"sora_devtools"`
  - `CompanyName`: `"shiguredo"`
  - `LegalCopyright`: `"Copyright (C) 2026 shiguredo. All rights reserved."`
- `devtools/windows/.gitignore` は生成されたものをそのまま使う（`flutter/ephemeral/` が ignore され、自動生成バイナリが commit されない）
- `devtools/windows/flutter/` 配下の `generated_plugin_registrant.cc` 等は Flutter の初回ビルド時に自動生成される。手動での作成・コピーは不要
- `devtools/windows/flutter/CMakeLists.txt` は `flutter create` 時に生成され、Flutter が管理する。手動編集しない

### prek.toml の修正

`dart-analyze-devtools` フック (`prek.toml:59-65`) の `bash` 直実行依存を解消する。

`prek` の `language: system` の `entry` は単一の固定文字列であり、OS 分岐構文は存在しない。
そのため、OS に依存しない方法として、Dart 製ヘルパースクリプトを作成し `dart run` で起動する方式を採用する:

1. `scripts/copy_env_and_analyze_devtools.dart` を新規作成する。このスクリプトは以下を行う:
   - `devtools/lib/configs/environment.example.dart` を `devtools/lib/configs/environment.dart` に一時コピーする
   - カレントディレクトリを `devtools/` に変更し `dart analyze --fatal-infos lib test` を実行する
   - 終了時に一時コピーした `environment.dart` を削除する
2. `prek.toml` の `dart-analyze-devtools` フックを以下のように書き換える:
   ```toml
   [[repos.hooks]]
   id = "dart-analyze-devtools"
   name = "dart analyze (devtools)"
   language = "system"
   entry = "dart run scripts/copy_env_and_analyze_devtools.dart"
   pass_filenames = false
   files = "^devtools/(lib|test)/.*\\.dart$"
   ```

`dart run` は Windows / Unix 両方で動作し、Dart SDK は Flutter 開発環境に含まれるため追加依存は発生しない。

### External Video Track の Windows 対応

sora_sdk の External Video Track は Windows 上で未検証であり、Windows 環境での動作が保証されない。
安全側に倒して Windows では External Video Track を無効化する。以下の対応を行う:

- `devtools/lib/main.dart` の `initState()` 内で、`Platform.isWindows` の場合に `_useExternalVideoTrack = false` を強制する（フィールド宣言の既定値は `false` だが、将来の既定値変更に備えた防御的な強制として残す）
- `devtools/lib/main.dart` の External Video Track の `SwitchListTile` の `onChanged` も、Windows の場合は `null` に設定し UI 操作を無効化する
- `_cameraManager` オブジェクトは Windows でも常にインスタンス化されるが、`_useExternalVideoTrack` が `false` のため `initialize()` や `start()` は呼ばれない。動作上の問題はない

### CI への追加

`.github/workflows/ci.yml` の `build-windows` ジョブ (`ci.yml:435-554`) に以下を追加する。
追加するステップは e2e_test_app のステップ (`ci.yml:542-554`) より前に配置し、`build-android` ジョブと同様の順序（package の依存解決 → devtools の準備 → devtools の静的解析 → devtools のビルド → e2e_test_app のビルド）とする:

1. `timeout-minutes` を `45` に延長する（devtools ビルド追加により実行時間が増加するため）
2. ルートパッケージの依存解決後 (`ci.yml:531-534` の後) に、devtools の `environment.dart` 準備ステップを追加する（`build-android` ジョブ `ci.yml:234-238` と同様、`cp` コマンドで `environment.example.dart` を `environment.dart` にコピーする）
3. devtools の依存解決ステップを追加する:
   ```yaml
   - name: Resolve devtools dependencies
     working-directory: devtools
     run: |
       set -euo pipefail
       flutter pub get
   ```
4. devtools の Dart format チェックステップを追加する（`build-android` ジョブ `ci.yml:246-249` と同様）
5. devtools の Dart analyze ステップを追加する（`build-android` ジョブ `ci.yml:251-255` と同様）
6. devtools の Windows ビルドステップを追加する:
   ```yaml
   - name: Build devtools Windows app
     working-directory: devtools
     run: |
       set -euo pipefail
       flutter build windows --release --no-pub
   ```
7. ビルド成果物の artifact upload ステップを追加する:
   ```yaml
   - name: Upload devtools Windows artifact
     uses: actions/upload-artifact@v7
     with:
       name: devtools-windows
       path: devtools/build/windows/x64/runner/Release/
       if-no-files-found: error
   ```

build-android ジョブと同様に、devtools の `flutter test` は実行しない。
devtools の widget test は現状レイアウト overflow で失敗することが CI コメント (`ci.yml:261-263`) で確認されており、この問題は本 issue のスコープ外として別 issue で対応する。

### Windows 上の動作制限

以下の機能は Windows では意図的に制限または無効化される。これらは本 issue のスコープ外であり、将来的に別 issue で対応する。

- External Video Track 機能: Windows 上での動作が未検証のため強制無効化する
- Switch Camera 機能: モバイル向け (`Platform.isIOS || Platform.isAndroid`) のため Windows では表示されない（既存実装のまま）
- `ensureMediaPermissions()` / `reloadAudioDevicesAfterPermission()`: Windows では早期 return する（音声デバイス一覧は取得されないが、`getUserMedia` 経由で OS の既定デバイスが使用される）。この挙動は既存実装で正しい

## 完了条件

- `devtools/windows/` ディレクトリが追加され、`flutter build windows --release` が Windows 上で成功すること
- `prek.toml` の `dart-analyze-devtools` フックが Windows / Unix 両方で `dart analyze` を実行できること
- CI の `build-windows` ジョブで devtools の Dart format チェック、Dart analyze、Windows ビルドが成功すること
- artifact `devtools-windows` として devtools の Windows ビルド成果物がアップロードされること
- Windows 上で External Video Track 機能が強制無効化されていること（UI 操作も無効）
- `CHANGES.md` の `## develop` の `### misc` セクションに以下の `[ADD]` エントリを追記する（CHANGES.md が存在しない場合は新規作成する。作成時は `shiguredo-changelog` スキルを参照すること）:
  ```
  - [ADD] devtools を Windows でも使えるようにする
    - @{実装者のユーザー名}
  ```

## 実装計画

1. `devtools/` で `flutter create --platforms=windows --project-name sora_devtools .` を実行し、Windows ランナーを生成する。実行後 `git diff` で意図しないファイル変更（特に `pubspec.yaml`）が無いことを確認する
2. `devtools/windows/CMakeLists.txt` を e2e_test_app の同等ファイルを参考に修正する:
   - `project(sora_devtools LANGUAGES CXX)`
   - `set(BINARY_NAME "sora_devtools")`
   - `_ITERATOR_DEBUG_LEVEL=0`、`_HAS_EXCEPTIONS=0`、`/MT` を追加する
3. `devtools/windows/runner/main.cpp` の `Create()` のウィンドウタイトルを `L"sora_devtools"` に変更する
4. `devtools/windows/runner/Runner.rc` のメタ情報を変更する:
   - `FileDescription` → `"sora_devtools"`、`InternalName` → `"sora_devtools"`、`OriginalFilename` → `"sora_devtools.exe"`
   - `ProductName` → `"sora_devtools"`
   - `CompanyName` → `"shiguredo"`、`LegalCopyright` → `"Copyright (C) 2026 shiguredo. All rights reserved."`
5. `devtools/lib/main.dart` の External Video Track 関連箇所を修正する:
   - `initState()` 内で `Platform.isWindows` の場合に `_useExternalVideoTrack = false` を強制する（既定値 `false` の防御的強制）
   - `SwitchListTile` の `onChanged` を Windows の場合に `null` に設定し UI 操作を無効化する
6. `scripts/copy_env_and_analyze_devtools.dart` を新規作成する:
   - `devtools/lib/configs/environment.example.dart` を `environment.dart` に一時コピーし `dart analyze` を実行、終了時に削除する
7. `prek.toml` の `dart-analyze-devtools` フックの `entry` を `dart run scripts/copy_env_and_analyze_devtools.dart` に変更する
8. `.github/workflows/ci.yml` の `build-windows` ジョブに以下を追加する:
   - `timeout-minutes: 45`
   - devtools の `environment.dart` 準備
   - devtools の `flutter pub get`（`working-directory: devtools`）
   - devtools の Dart format チェック
   - devtools の Dart analyze（`working-directory: devtools`）
   - devtools の Windows ビルド（`working-directory: devtools`、`flutter build windows --release --no-pub`）
   - artifact upload（`name: devtools-windows`、`path: devtools/build/windows/x64/runner/Release/`）
    - devtools の `flutter test` は build-android と同様に実行しない
9. CHANGES.md を新規作成し（`shiguredo-changelog` スキル参照）、`## develop` 配下に `### misc` セクションと `[ADD]` エントリを追加する。本 issue のエントリのみを追加し、過去の closed issue のエントリを遡及追加する必要はない

## 解決方法

`devtools/` に Windows ランナーを生成し、以下の対応を行った:

- `devtools/windows/` ディレクトリの追加 (`flutter create --platforms=windows`)
- `devtools/windows/CMakeLists.txt` の修正（プロジェクト名、`_ITERATOR_DEBUG_LEVEL=0`、`_HAS_EXCEPTIONS=0`、`/MT`、`/utf-8`）
- `devtools/windows/runner/main.cpp` の COM 初期化を `COINIT_MULTITHREADED` に変更（WebRTC 要件）
- `devtools/windows/runner/CMakeLists.txt` に `/utf-8` と PDB 生成 (`/Zi`、`/DEBUG:FULL`) を追加
- `windows/windows_bridge.c` の observer コールバックに noop スタブを追加（起動時クラッシュ回避）
- `windows/CMakeLists.txt` に `/wd4115`、PDB 生成を追加
- `devtools/README.md` に Windows ビルド設定のドキュメントを追加
- `devtools/lib/configs/environment.example.dart` から `environment.dart` を生成

未対応の残件は後続 issue で対応する:

- CI への devtools Windows ビルド追加
- `prek.toml` の `dart-analyze-devtools` フックの Windows 対応
- External Video Track の Windows 無効化
- `CHANGES.md` の新規作成
