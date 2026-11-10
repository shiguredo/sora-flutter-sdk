# Windows の CRT 不整合により Debug / Release 両方でビルドが失敗する

- Priority: High
- Created: 2026-06-12
- Completed: 2026-06-15
- Model: DeepSeek V4 Pro
- Branch: feature/fix-windows-crt-mismatch-build-error
- Polished: 2026-06-15

## 目的

CRT 不整合により Debug / Release 両方で Windows ビルドが失敗する問題を修正する。

## 優先度根拠

Windows の e2e テストおよび Windows 向けビルドが一切成功しない。全 Windows ユーザーに影響する致命的なビルドエラーのため High。

## 影響範囲

`libwebrtc-c.lib` は `sora_sdk_plugin.dll` と `sora_sdk.dll` の両方にリンクされる。そのため、`sora_sdk` パッケージに依存するすべての Flutter Windows プロジェクト（`e2e_test_app`、`devtools`、ユーザーアプリ）でビルドが失敗する。

## 原因

`libwebrtc-c.lib` が `/MT`（静的 CRT）でビルドされている一方、Flutter の Windows ツールチェーンはプラグインの CRT を `/MD`（動的 CRT）に強制するため、リンク時に LNK2038 が発生する。

MSVC の `/FAILIFMISMATCH:RuntimeLibrary` 機構により、`/MT` の .obj と `/MD` の .obj を同一 DLL にリンクできない。

## 調査経緯

### sora-flutter-sdk 側での CRT 上書きが不可能であること（検証済み）

3 種類のアプローチを検証したが、いずれも Flutter のビルドシステムによって上書きされた:

1. `set_target_properties(... MSVC_RUNTIME_LIBRARY "MultiThreaded")` — 単体では効かない
2. `CMAKE_CXX_FLAGS_DEBUG` の `/MDd` → `/MT` 置換（CACHE FORCE） — CMakeCache は更新されるが vcxproj 生成時に上書き
3. `CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded"`（プロジェクト全体） — 完全に無視される

この問題は flutter/flutter#75615 として 2021 年から未解決。

### webrtc-rs 側の `/MD` ビルド（試行済み）

`shiguredo/webrtc-rs` の `webrtc/CMakeLists.txt:528` に CRT 選択オプション `WEBRTC_C_USE_STATIC_CRT` を追加し、`/MD` ビルドを試行した。ラッパー部分の `/MD` 化は成功したが、`bundle_static_library` で結合される prebuilt `webrtc.lib` が `/MT` のままであるため、ライブラリ内部で CRT 不一致が残る。このアプローチは保留。

### legacy-sora-flutter-sdk の知見（採用）

過去の C++ 実装版 SDK（`shiguredo/legacy-sora-flutter-sdk`）の CMakeLists.txt を参考に、`APPLY_STANDARD_SETTINGS` 関数内で生の `/MT` フラグを `target_compile_options` で指定する方式を発見。これにより Flutter の toolchain による上書きを回避できた。

## 解決方法

### 変更ファイル

- `e2e_test_app/windows/CMakeLists.txt` — プロジェクトレベルのビルド設定
- `windows/CMakeLists.txt` — プラグイン DLL のビルド設定

### 1. `e2e_test_app/windows/CMakeLists.txt`

```cmake
add_definitions(-DUNICODE -D_UNICODE)
# libwebrtc-c.lib が /MT（静的 CRT）でビルドされているため、イテレータデバッグを無効化する
add_definitions(-D_ITERATOR_DEBUG_LEVEL=0)

function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  # libwebrtc-c.lib が /MT（静的リリース CRT）でビルドされているため、全構成で /MT を使用する
  target_compile_options(${TARGET} PRIVATE "/MT")
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
endfunction()
```

変更点:
- `add_definitions(-D_ITERATOR_DEBUG_LEVEL=0)` を追加（libwebrtc-c.lib の `_ITERATOR_DEBUG_LEVEL=0` に合わせる）
- `APPLY_STANDARD_SETTINGS` に `target_compile_options(${TARGET} PRIVATE "/MT")` を追加（生の `/MT` フラグで CRT を強制）
- `target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")` を削除（`/MT` 使用時にデバッグ CRT シンボルが引かれるのを防止）

### 2. `windows/CMakeLists.txt`

`apply_standard_settings` の直後と `sora_sdk` ターゲットに以下を追加:

```cmake
set_target_properties(${PLUGIN_NAME} PROPERTIES
  MSVC_RUNTIME_LIBRARY "MultiThreaded")

set_target_properties(sora_sdk PROPERTIES
  MSVC_RUNTIME_LIBRARY "MultiThreaded")
```

### 修正の効果

3 つのテクニックの組み合わせ:

| # | テクニック | 役割 |
|---|---|---|
| ① | `APPLY_STANDARD_SETTINGS` で `target_compile_options(/MT)` | 生の `/MT` フラグで全ターゲットの CRT を強制 |
| ② | `MSVC_RUNTIME_LIBRARY "MultiThreaded"` | vcxproj の `<RuntimeLibrary>` も静的 CRT に設定 |
| ③ | `_ITERATOR_DEBUG_LEVEL=0` | Debug 時のイテレータデバッグ不整合を防止 |
| - | `_DEBUG` 定義を削除 | `/MT` でデバッグ CRT シンボルが引かれるのを防止 |

①のみでは Flutter の toolchain に上書きされる場合があるが、①と②の二重指定により確実に `/MT` が適用される。

## 完了条件（達成済み）

- `e2e_test_app` ディレクトリで `flutter build windows --debug` が LNK2038 なしでビルド成功 ✅
- `e2e_test_app` ディレクトリで `flutter build windows --release` が LNK2038 なしでビルド成功 ✅
- `sora_sdk_plugin.dll`、`sora_sdk.dll`、`e2e_test_app.exe` が正常に生成される ✅
