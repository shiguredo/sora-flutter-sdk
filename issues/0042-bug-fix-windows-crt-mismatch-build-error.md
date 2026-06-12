# Windows の CRT 不整合により Debug / Release 両方でビルドが失敗する

- Priority: High
- Created: 2026-06-12
- Completed: {YYYY-MM-DD}
- Model: DeepSeek V4 Pro
- Branch: feature/fix-windows-crt-mismatch-build-error
- Polished: 2026-06-12

## 目的

CRT 不整合により Debug / Release 両方で Windows ビルドが失敗する問題を修正する。

## 優先度根拠

Windows の e2e テストおよび Windows 向けビルドが一切成功しない。全 Windows ユーザーに影響する致命的なビルドエラーのため High。

## 前提条件

本 issue の実装には `libwebrtc-c.lib` を `/MD`（動的 CRT）でビルドした版が配布されていることが必要。これは `shiguredo/webrtc-rs` リポジトリ側の対応となる。

**webrtc-rs 側に必要な対応**:

`webrtc/CMakeLists.txt` に CRT 選択オプションを追加し、`/MD` ビルドを可能にする。`WEBRTC_CPP_TARGETS` ループ（`webrtc_c`、`whip_cpp`、`whep_cpp`）のすべてに適用される。

```cmake
# webrtc/CMakeLists.txt:519 の直後に追加
option(WEBRTC_C_USE_STATIC_CRT "Use static CRT (/MT) instead of dynamic CRT (/MD)" ON)
if(WEBRTC_C_USE_STATIC_CRT)
  set(WEBRTC_C_MSVC_RUNTIME "MultiThreaded$<$<CONFIG:Debug>:Debug>")
else()
  set(WEBRTC_C_MSVC_RUNTIME "MultiThreaded$<$<CONFIG:Debug>:Debug>DLL")
endif()

# 既存の行 528 を以下のように変更（修正前: ハードコードされた /MT 設定）
# 修正後: WEBRTC_C_MSVC_RUNTIME 変数を使用
MSVC_RUNTIME_LIBRARY "${WEBRTC_C_MSVC_RUNTIME}"
```

`build.rs` では Cargo feature `static-crt`（デフォルト有効）を追加し、無効時に `-DWEBRTC_C_USE_STATIC_CRT=OFF` を渡す。これにより `cargo build --features source-build --no-default-features` で `/MD` ビルドが可能になる（`static-crt` 以外のデフォルト feature が存在しないことを前提とする）。

`/MD` ビルド版は既存の `/MT` 版と別アーカイブ（`libwebrtc_c-windows_x86_64-md.tar.gz`）として GitHub Releases に配布する。`libwebrtc-c.lib` は `bundle_static_library` により `webrtc.lib` の全オブジェクトを包含しているため、sora-flutter-sdk 側の `webrtc.lib` 直接リンクは冗長であり除去可能（後述）。

**sora-flutter-sdk 側の本 issue のスコープ**: webrtc-rs 側の対応が完了し `/MD` 版がリリースされた後、sora-flutter-sdk 側で `/MD` 版を取得・使用するよう変更する。

## 関連 issue

- 0034: 設計方針で CRT 整合の検討を挙げていた。Flutter の Windows ツールチェーンが CRT を `/MD` に強制する制約を考慮しておらず、当時は `/MT` への統一が実現不可能だった。本 issue では `/MD` に揃える方針で解決する。
- 0038: CI に Windows ビルドジョブを追加する。本 issue の修正が CI 上でも検証されるには 0038 の完了が必要。

## 現状

### 不整合の構造

`third_party/libwebrtc-c/build-windows_x86_64/libwebrtc-c.lib` は `/MT`（静的 CRT）でビルドされている。`dumpbin /DIRECTIVES` で `RuntimeLibrary=MT_StaticRelease` を確認済み。`webrtc.lib` も同一ビルドプロセスで生成され、同一 CRT 設定を持つ。

一方、Flutter の Windows ビルドは CMake デフォルトの `/MD`（動的 CRT）を使用する。`sora_sdk_plugin`、`sora_sdk`、および PRIVATE リンクされる `flutter_wrapper_plugin` のすべてが `/MD` でコンパイルされるため、リンク時に LNK2038（RuntimeLibrary 不一致）、LNK2005（シンボル重複）、LNK1169（fatal error）が発生する。

### sora-flutter-sdk 側での CRT 上書きが不可能であること（検証済み）

以下のアプローチを実機で検証したが、いずれも Flutter のビルドシステムによって vcxproj 生成時に上書きされ、CRT を `/MT` に変更できなかった:

1. `set_target_properties(... MSVC_RUNTIME_LIBRARY "MultiThreaded")` — vcxproj の `<RuntimeLibrary>` に反映されない
2. `CMAKE_CXX_FLAGS_DEBUG` の `/MDd` を `/MT` に置換し CACHE FORCE — CMakeCache は更新されるが vcxproj 生成時に元の値で上書きされる
3. プロジェクトレベルの `CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded"` — 完全に無視される

Flutter の Windows ツールチェーン（`tool_backend.bat` 経由で起動される CMake）が CRT 設定を `/MD` に固定しているため、sora-flutter-sdk 側での CRT 変更は現状のツールチェーンでは不可能。

### webrtc-rs 側の CRT 設定

`shiguredo/webrtc-rs` リポジトリの `webrtc/CMakeLists.txt:528` で `/MT` にハードコードされている:

```cmake
MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
```

CRT 選択を変更するオプションは存在しない。

## 再現手順

1. `dart run scripts/fetch_native_deps.dart windows_x86_64` を実行し、ネイティブ依存を取得する
2. `e2e_test_app` ディレクトリで `flutter build windows --debug` を実行する
3. または `flutter test integration_test\recvonly_e2e_test.dart -d windows` を実行する
4. いずれも LNK2038 でビルドが失敗する

## 設計方針

sora-flutter-sdk 側での CRT 上書きが不可能であるため、`libwebrtc-c.lib` 側を `/MD` でビルドした版を取得・使用する方針を採用する。Flutter のデフォルト CRT (`/MD`) と一致させることで、sora-flutter-sdk 側の CMake 変更は不要になる。

### 採用するアプローチ

1. webrtc-rs 側で `/MD` ビルドを可能にする（前提条件セクション参照）
2. sora-flutter-sdk 側で `/MD` 版の `libwebrtc-c.lib` を取得するよう `native_deps.json` を変更する
3. Windows ビルド時の `CMAKE_CXX_FLAGS_DEBUG` と `libwebrtc-c.lib` の CRT が一致し、リンクが成功する

### 採用しないアプローチと理由

- **sora-flutter-sdk 側で `/MT` に揃える**: 前述の通り Flutter のビルドシステムが `/MD` を強制するため不可能（検証済み）
- **既存の `/MT` 版を使い続ける**: 不整合が解消されず、根本的な解決にならない

## 完了条件

- `scripts/native_deps.json` の `windows_x86_64` エントリが `/MD` ビルド版のアーカイブを参照していること
- `dart run scripts/fetch_native_deps.dart windows_x86_64` で `/MD` 版の `libwebrtc-c.lib` が正しく取得され、`dumpbin /DIRECTIVES` で `RuntimeLibrary=MD_DynamicRelease` であること
- `e2e_test_app` ディレクトリで `flutter build windows --debug` が LNK2038 なしでビルドに成功すること
- `e2e_test_app` ディレクトリで `flutter build windows --release` が LNK2038 なしでビルドに成功すること
- 上記ビルド成功を以て、e2e テストのコンパイルも可能になったとみなす。CI 上での Windows ビルド検証は 0038 の完了後に可能になる
- Android / macOS / Linux / iOS のビルドに影響がないこと

## 解決方法

### 1. `scripts/native_deps.json` の変更

`windows_x86_64` エントリの `file` と `sha256` を `/MD` ビルド版に差し替える。アーカイブ内部構造が同一（`lib/webrtc_c.lib`）であれば `fetch_native_deps.dart` の既存ロジックで自動処理される。

```json
// archives.libwebrtc_c 内の windows_x86_64 エントリを変更
"windows_x86_64": {
  "file": "libwebrtc_c-windows_x86_64-md.tar.gz",
  "sha256": "<webrtc-rs リリース時に確定>"
}
```

既存の `build-windows_x86_64` 配下のファイルは `cleanPlatform` により削除され、新たに `/MD` 版が展開されるため、`.state.json` の後方互換性は保たれる。`webrtc` エントリ（`webrtc-build` 配布物）は変更不要（後述の理由 3 による）。

### 2. `scripts/fetch_native_deps.dart` の変更

`installLibwebrtcC` 関数の Windows 向け処理で、`webrtc_c.lib` を `libwebrtc-c.lib` にリネームする既存ロジック（`staticLibraryCandidates` に `webrtc_c.lib` が含まれていること）が `/MD` 版でも同様に動作することを確認する。アーカイブ構造が変わらない限り、コード変更は不要。

### 3. CMake 設定の変更

`windows/CMakeLists.txt` で直接リンクされている `webrtc.lib` は、`libwebrtc-c.lib` が `bundle_static_library` により `webrtc.lib` の全オブジェクトを包含しているため冗長である。両 DLL（`sora_sdk_plugin`、`sora_sdk`）から `"${WEBRTC_LIB}"` のリンクを削除する。

```cmake
# 修正前: sora_sdk_plugin の target_link_libraries (45-46 行目付近)
  "${LIBWEBRTC_C_LIB}"
  "${WEBRTC_LIB}"

# 修正後: webrtc.lib の直接リンクを削除
  "${LIBWEBRTC_C_LIB}"
```

同様に `sora_sdk` ターゲットの `target_link_libraries`（87 行目付近）からも `"${WEBRTC_LIB}"` を削除する。`libwebrtc-c.lib` のみのリンクで全シンボルが解決されることを確認する。

これにより、`webrtc.lib` の CRT 設定を気にする必要がなくなり、`libwebrtc-c.lib` のみ `/MD` にすれば CRT 不整合が解消される。

`e2e_test_app/windows/CMakeLists.txt` の変更は不要。
