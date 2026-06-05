# Linux 向けネイティブ依存取得を追加する

- Priority: High
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-linux-native-deps-fetch
- Polished: 2026-06-03

## 目的

Sora Flutter SDK の Linux 対応の起点として、ネイティブ依存 (libwebrtc-c / webrtc) を Linux 向けに取得・展開・配置できるよう `scripts/native_deps.json` と `scripts/fetch_native_deps.dart` を拡張する。これが無いと後続の Linux プラグイン実装が依存ライブラリを参照できない。

本 issue のスコープは「Linux 依存の取得・展開・配置」に限定する。CMake でのリンク設定・FFI シンボル保持・ターゲット構成・システムライブラリのリンク・ビルド検証は Linux プラグイン基盤 issue (0026) に委ねる。

Windows 向け取得は 0032 で扱う。Linux のアーカイブはすべて tar.gz で zip を含まないため、本 issue では zip 展開対応は不要 (zip 対応は 0032 の責務)。

**0032 との競合**: 本 issue と 0032 は同一ファイル (`native_deps.json` の `archives` マップ、`fetch_native_deps.dart` の `platformConfig` マップ) を編集する。片方が先にマージされたら、もう片方は rebase して競合を解消すること。

## 優先度根拠

- 後続の Linux 対応タスク (0026-0031) はすべて本 issue が配置するライブラリを前提とする
- 配布元 (`shiguredo/webrtc-rs`、`shiguredo-webrtc-build/webrtc-build`) は既に Linux バイナリをリリース済みで、SDK 側の取得対応のみが不足している
  - webrtc-rs リリース: `https://github.com/shiguredo/webrtc-rs/releases/tag/<version>`
  - webrtc-build リリース: `https://github.com/shiguredo-webrtc-build/webrtc-build/releases/tag/<version>`
  - アーカイブの実 URL 存在確認は Step 1 の調査で行う

## 現状

- `native_deps.json` の `libwebrtc_c.archives` と `webrtc.archives` は `android_arm64` のみ。`apple_xcframework` は `archives` の外に並列で置かれた別形式 (iOS / macOS 用、SwiftPM 経由)。
- `fetch_native_deps.dart` のファイル先頭コメント (2-3 行目) は「Android 向け」「引数でプラットフォーム名 (android_arm64) を受け取る」と固定。Linux 追加時に「Android / Linux 向け」「引数でプラットフォーム名 (android_arm64 / linux_x86_64 など) を受け取る」に更新する。
- `platformConfig` は `android_arm64` のみ定義。各エントリは `build_dir` / `extract_paths` / `required_paths` の 3 フィールドを持つ。`cleanPlatform` は `extract_paths` を無条件参照するため、追加エントリにも 3 フィールド必須。
- `extractArchive` は `tar -xzf` で gzip 圧縮 tar を展開する。Linux アーカイブは tar.gz なのでこのまま使える。
- `installLibwebrtcC` の `staticLibraryCandidates` は `lib/libwebrtc_c.a` / `lib/libwebrtc-c.a` を探索する。`includeCandidates` は `include` / `libwebrtc-c/include` を探索する（注意: `libwebrtc_c/include` は候補に無い。Linux アーカイブが `libwebrtc_c/` 構造を持つ場合は候補追加が必要）。コピー先は `libwebrtc-c.a` 固定名。
- `installWebrtc` は展開物の `webrtc/` ディレクトリまたは展開ディレクトリ直下に `include/` がある前提で探索し、`_deps/webrtc` へ丸ごとコピーする。`webrtc/` が無い場合は再帰フォールバックで `include/` を探索するが、複数の `include/` が存在すると誤検出しうる。
- `installLibwebrtcC` には再帰フォールバックが無いため、想定外のディレクトリ構造では即失敗する。Step 1 での構造確認が必須。
- `skipFetch` の `file` 比較はトリムなしで行われるため、`native_deps.json` の `file` 値に末尾空白が混入すると永続的にキャッシュが無効化される。`native_deps.json` 編集時は末尾空白に注意すること。
- 既存の `android_arm64` 取得処理は本 issue の変更による影響を受けない (キー追加のみ)。
- `cleanPlatform` は `extract_paths` 指定のディレクトリのみ削除し、共有 `include/` は削除しない。Linux を初めて追加する際、試行錯誤でバージョン変更を繰り返すと古いヘッダが `include/` に残存し、サイレントに使われ続けるリスクがある。再取得時に `rm -rf third_party/libwebrtc-c/include` を手動実行してからスクリプトを再実行すること。

## 設計方針

### key とアーカイブ

- platform key を **`linux_x86_64`** に確定する。後続 0030 の CI が `fetch_native_deps.dart linux_x86_64` を呼ぶ。
- key と実アーカイブ名は一致しない。`file` 値には配布元の実名を入れる。Ubuntu は 24.04 を採用する (`shiguredo/webrtc-rs` の Linux 配布が Ubuntu 24.04 x86_64 をターゲットとしているため)。
  - libwebrtc_c: `libwebrtc_c-ubuntu-24.04_x86_64.tar.gz`
  - webrtc: `webrtc.ubuntu-24.04_x86_64.tar.gz`
  - これらのファイル名が配布元に実在するかは Step 1 の調査で確認する
- 新エントリは `apple_xcframework` と並列にならないよう、必ず `archives` マップ内に置く (`loadManifest` が `archives` を探索するため)。

### required_paths / build_dir のレイアウト

- `build_dir` は `build-linux_x86_64` (Android 命名に倣う)。
- `extract_paths` は `['build-linux_x86_64']` (`cleanPlatform` 参照のため)。
- `required_paths` は 0048 のプラットフォーム別必須パスのパターンに従い、以下の暫定リストを設定する。Step 1 で実ファイル名・ディレクトリ構造を確認して確定する。
  - `include/webrtc_c.h` (共通必須)
  - `build-linux_x86_64/libwebrtc-c.a` (libwebrtc-c 静的ライブラリ、実名要確認)
  - `build-linux_x86_64/_deps/webrtc/include/` (webrtc ヘッダ)
  - `build-linux_x86_64/_deps/webrtc/lib/libwebrtc.a` (webrtc 静的ライブラリ、arch サブディレクトリ無し想定)

### Step 1 調査項目と影響先

各調査項目の結果によってどの実装項目を修正するかの対応表:

| 調査項目 | 影響先 |
|---|---|
| `lib/` 以下の静的ライブラリ実パス (`staticLibraryCandidates` マッチ可否) | `installLibwebrtcC` の `staticLibraryCandidates` リスト |
| `include/` の位置 (`includeCandidates` マッチ可否、`libwebrtc_c/` 構造の有無) | `installLibwebrtcC` の `includeCandidates` リスト |
| `lib/` 以下に arch サブディレクトリが存在するか | `required_paths` の `lib/libwebrtc.a` パス |
| webrtc アーカイブに `webrtc/` ディレクトリが含まれるか | `installWebrtc` の探索候補追加要否 |
| 再帰フォールバック発動時に複数の `include/` が存在しないか | 誤検出リスクの有無確認 |

### チェックサム

- `native_deps.json` は `sha256` 必須 (`ensureSha256`)。空欄不可。
- libwebrtc_c の SHA256 は webrtc-rs リリースに同梱の `.sha256` ファイルから取得する。
- webrtc の SHA256 は webrtc-build リリースに同梱の `.sha256` ファイル (あれば) から取得、またはダウンロード後に手動計算する (macOS: `shasum -a 256`、Linux: `sha256sum`)。
- バージョンが canary (`0.148.1-canary.1`) のため、リリース差し替えで SHA256 が変わりうる。`.state.json` は SHA256 を追跡しないため、同一バージョン・同一ファイル名でバイナリが差し替わった場合は `skipFetch` が通過し古いバイナリが使われ続けることに注意。差し替え発生が判明したら `.state.json` を手動削除して再取得すること。

## 完了条件

- `dart run scripts/fetch_native_deps.dart linux_x86_64` が成功し、`third_party/libwebrtc-c/` に Linux 用 `required_paths` がすべて揃う。
- 上記は macOS ホストでも実行・検証できる (実機 Linux を要しない)。
- 2 回目の実行でキャッシュ判定 (`skipFetch`) により再取得がスキップされる。
- `.state.json` 内のバージョン文字列を手動で書き換えて再実行すると、`cleanPlatform` による削除と再取得が走る。
- `CHANGES.md` の `## develop` の `### sora_sdk` セクション内、他の `[ADD]` エントリの直後に以下のエントリを追記する。既存エントリの種別順並び替えは本 issue のスコープ外のため行わない。
  ```
  - [ADD] Linux 向けネイティブ依存取得を追加する
    - `scripts/native_deps.json` と `scripts/fetch_native_deps.dart` に `linux_x86_64` を追加し、`dart run scripts/fetch_native_deps.dart linux_x86_64` で取得できるようにする
    - @{実装者のユーザー名}
  ```
- テスト方針: `required_paths` の充足確認をもってテストとする。既存の `android_arm64` と同様の方針。

## 解決方法

1. 調査: `libwebrtc_c-ubuntu-24.04_x86_64.tar.gz` と `webrtc.ubuntu-24.04_x86_64.tar.gz` を配布元リリースページから URL 実在確認の上 curl 等でダウンロードし、展開する。設計方針の「Step 1 調査項目と影響先」の表に従い、各項目の実値を確認・記録する。特に以下を確認:
   - `staticLibraryCandidates` と `includeCandidates` のマッチ可否
   - webrtc アーカイブに `webrtc/` ディレクトリが含まれるか
   - 各アーカイブの SHA256 実値
2. `scripts/fetch_native_deps.dart` のファイル先頭コメント (2-3 行目) を更新する。
3. `scripts/native_deps.json` の `libwebrtc_c.archives` / `webrtc.archives` に `linux_x86_64` エントリを追加する。エントリは既存の `android_arm64` と同じ構造 (`file` と `sha256` の 2 フィールド) で追加する。`file` 値に末尾空白を混入させないこと。
4. `scripts/fetch_native_deps.dart` の `platformConfig` に `linux_x86_64` エントリ (`build_dir`: `build-linux_x86_64`、`extract_paths`: `['build-linux_x86_64']`、`required_paths`: Step 1 の結果で確定したリスト) を追加する。`staticLibraryCandidates` または `includeCandidates` がマッチしない場合は候補を追加する。
5. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する。
