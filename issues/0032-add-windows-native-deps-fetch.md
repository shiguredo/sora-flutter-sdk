# Windows 向けネイティブ依存取得を追加する

- Priority: Medium
- Created: 2026-06-03
- Model: Opus 4.8
- Branch: feature/add-windows-native-deps-fetch
- Polished: 2026-06-03

## 目的

Sora Flutter SDK の Windows 対応の起点として、ネイティブ依存 (libwebrtc-c / webrtc) を Windows 向けに取得・展開・配置できるよう `scripts/native_deps.json` と `scripts/fetch_native_deps.dart` を拡張する。Windows は libwebrtc-c が tar.gz、webrtc が zip と形式が混在し、静的ライブラリも MSVC の `.lib` であるため、Linux 取得 (0024) には無い zip 展開対応と `.lib` 対応を本 issue が担う。

本 issue のスコープは「Windows 依存の取得・展開・配置」に限定する。CMake でのリンク設定・シンボルエクスポート・ターゲット構成・システムライブラリのリンク・ビルド検証は Windows プラグイン基盤 issue (0034) に委ねる。これにより本 issue は実機 Windows を必要とせず、取得スクリプトの成功と `required_paths` の充足だけで完了判定できる (zip/tar 展開と検証は macOS ホストでも可能)。

## 優先度根拠

- 後続の Windows 対応タスク (0034-0039) はすべて本 issue が配置するライブラリを前提とする
- 配布元は既に Windows x86_64 バイナリをリリース済みで、SDK 側の取得対応のみが不足している
- Linux 先行のため Medium とする

## 現状

- `scripts/native_deps.json` の `archives` は `android_arm64` のみ。0024 (Linux) が `linux_x86_64` を追加する。本 issue は同ファイルに `windows_x86_64` を追加する。0024 と同じファイルを触るため、片方が先にマージされたらもう片方は rebase する。
- `extractArchive` は `tar -xzf` 固定で gzip 圧縮 tar しか展開できない。webrtc の Windows アーカイブは `.zip` のため、このままでは展開不能。
- `installLibwebrtcC` の `staticLibraryCandidates` は `lib/libwebrtc_c.a` / `lib/libwebrtc-c.a` のみ。Windows 実アーカイブの静的ライブラリ名は **`webrtc_c.lib`** (libwebrtc-c 側) と **`webrtc.lib`** (webrtc 側) で、いずれも `lib` プレフィックスが無く拡張子も `.lib`。現候補にマッチしない。
- `installLibwebrtcC` のコピー先は `libwebrtc-c.a` 固定名。`.lib` を渡しても `.a` 拡張子にリネームされて配置されるため、MSVC リンク (0034) で扱えない。
- `cleanPlatform` は `extract_paths` を無条件参照するため、追加エントリにも 3 フィールド (`build_dir` / `extract_paths` / `required_paths`) 必須。
- `closed/0048` は除外事項として「Windows / Linux の配布構成」を挙げており、本 issue はその Windows 部分を定義する。

## 設計方針

### key とアーカイブ

- platform key を **`windows_x86_64`** に確定する (後続 0038 の CI が `fetch_native_deps.dart windows_x86_64` を呼ぶ)。
- `file` 値は配布元の実名:
  - libwebrtc_c: `libwebrtc_c-windows_x86_64.tar.gz` (tar.gz)
  - webrtc: `webrtc.windows_x86_64.zip` (zip)
- 新エントリは `archives` マップ内に置く (`apple_xcframework` と並列にしない)。

### zip 展開対応 (本 issue の中核)

- `extractArchive` をファイル拡張子で分岐させる。`.tar.gz` は従来どおり `tar -xzf`、`.zip` は pure Dart の `archive` パッケージを使う。外部 `unzip` / `Expand-Archive` はホスト依存があるため避ける。
- 自前の `ZipDecoder` + 手書き展開ではなく、`package:archive/archive_io.dart` の `extractFileToDisk` (または `extractArchiveToDisk`) を使う。これによりシンボリックリンク・パーミッション・空ディレクトリの扱いをライブラリに委ね、`_copyDirectoryRecursive` との整合も保つ。
- `extractArchive` の戻り値契約 (展開先 Directory を返す) は維持し、tar 経路と zip 経路で展開先構造を揃える (libwebrtc-c は `extracted/include`・`extracted/lib`、webrtc は `extracted/webrtc/...`)。
- `archive` パッケージは取得スクリプト専用であり SDK ランタイム (`lib/`) では使わないため、`pubspec.yaml` の **`dev_dependencies`** に追加する (通常 `dependencies` に入れると pub.dev 経由の利用者全員へ伝播するため不可)。

### .lib 対応 (本 issue の中核)

- `staticLibraryCandidates` に実名 **`webrtc_c.lib`** (および `libwebrtc_c.lib` / `libwebrtc-c.lib` も保険として) を追加する。`.a → .lib` の拡張子置換だけでは `lib` プレフィックス無しの実名にマッチしないため、プレフィックス無しを明示する。
- `installLibwebrtcC` のコピー先固定名 `libwebrtc-c.a` (`:334`) を、ソースが `.lib` の場合は拡張子を保持する形に変更する (例: `libwebrtc-c.lib`)。MSVC リンク時に拡張子が意味を持つため `.a` リネームは不可。
- webrtc 側 (`installWebrtc` は `webrtc/` を丸ごとコピー) は `webrtc.lib` がそのまま `_deps/webrtc/lib/webrtc.lib` に保たれるため install ロジックの変更は不要。`required_paths` で `.lib` 実名を要求する。

### required_paths / build_dir

- `build_dir` は `build-windows_x86_64`、`extract_paths` は `['build-windows_x86_64']`。
- `required_paths` は実展開で確定するが、以下を反映:
  - `_deps/webrtc/jar/webrtc.jar` は含めない (Android 固有)。
  - libwebrtc-c 静的ライブラリは Windows のコピー先名 (`libwebrtc-c.lib` 等、上記で確定)。
  - webrtc 静的ライブラリは `_deps/webrtc/lib/webrtc.lib` (arch サブディレクトリ無し)。
  - `include/webrtc_c.h` は共通必須。

### チェックサム

- libwebrtc_c / webrtc 各 Windows アーカイブの SHA256 実値を配布元から取得して記載する (`ensureSha256` が必須化)。canary 差し替えで変わりうるため記載時点の値で固定する。

## 完了条件

- `dart run scripts/fetch_native_deps.dart windows_x86_64` が成功し (zip 展開と `.lib` 配置を含む)、`third_party/libwebrtc-c/` に Windows 用 `required_paths` がすべて揃う。
- 上記は macOS ホストでも実行・検証できる (実機 Windows / MSVC を要しない)。
- `pubspec.yaml` の `dev_dependencies` に `archive` が追加されている。
- `CHANGES.md` の `## develop` に担当者行付きで `[ADD]` エントリを追記する。

## 解決方法

1. `libwebrtc_c-windows_x86_64.tar.gz` と `webrtc.windows_x86_64.zip` を 1 度ダウンロード・展開し、静的ライブラリ実名・配置・include 位置・SHA256 を確定する。
2. `pubspec.yaml` の `dev_dependencies` に `archive` を追加する。
3. `scripts/fetch_native_deps.dart` の `extractArchive` を拡張子分岐させ (`.zip` は `extractFileToDisk`)、`staticLibraryCandidates` に `webrtc_c.lib` 等を追加、`installLibwebrtcC` のコピー先を `.lib` 保持に変更する。
4. `platformConfig` に `windows_x86_64` (3 フィールド、jar 除外、`.lib` パス) を追加する。
5. `scripts/native_deps.json` の `archives` に `windows_x86_64` エントリ (`file` と `sha256`) を追加する。
6. `CHANGES.md` に担当者行付きで `[ADD]` エントリを追記する。
