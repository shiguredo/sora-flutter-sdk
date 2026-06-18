cmake_minimum_required(VERSION 3.18)
project(sora_sdk LANGUAGES C CXX)

set(PLUGIN_NAME "sora_sdk_plugin")

# ネイティブ依存 (0032) のインストール先パス
# CMAKE_CURRENT_SOURCE_DIR は add_subdirectory 経由でビルドすると
# .plugin_symlinks 以下の symlink パスを指す場合があるため、
# REALPATH で実際のパスを解決してから相対パスを計算する。
get_filename_component(SORA_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
set(LIBWEBRTC_C_DIR "${SORA_SDK_ROOT}/../third_party/libwebrtc-c")
set(LIBWEBRTC_C_BUILD_DIR "${LIBWEBRTC_C_DIR}/build-windows_x86_64")
set(WEBRTC_INCLUDE_DIR "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include")
set(LIBWEBRTC_C_LIB "${LIBWEBRTC_C_BUILD_DIR}/libwebrtc-c.lib")
set(WEBRTC_LIB "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/lib/webrtc.lib")

# === sora_sdk_plugin.dll (MethodChannel + dart:ffi 統合) ===
# 他プラットフォーム (macOS/iOS/Linux/Android) と同様に、
# MethodChannel プラグインコードと dart:ffi C ブリッジを
# 単一の共有ライブラリに統合する。

add_library(${PLUGIN_NAME} SHARED
  "include/sora_sdk/sora_sdk_plugin_c_api.h"
  "sora_sdk_plugin_c_api.cpp"
  "sora_sdk_plugin.cpp"
  "sora_sdk_plugin.h"
  "sora_audio_devices.cpp"
  "sora_audio_devices.h"
  "sora_camera_capturer.cpp"
  "sora_camera_capturer.h"
  "windows_rendering_sink.h"
  "windows_rendering_sink.cpp"
  "windows_bridge.c"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
set_target_properties(${PLUGIN_NAME} PROPERTIES
  MSVC_RUNTIME_LIBRARY "MultiThreaded")
# ソースファイルが UTF-8 で保存されている場合、MSVC の Shift-JIS コードページで
# C4819 警告 → /WX でエラーになる問題を回避する。
target_compile_options(${PLUGIN_NAME} PRIVATE "/utf-8")
# libwebrtc-c のヘッダは不完全型を仮引数リストで使用しているため C4115 が発生する。
# サードパーティヘッダのため警告を抑制する。
target_compile_options(${PLUGIN_NAME} PRIVATE "/wd4115")
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${LIBWEBRTC_C_DIR}/include"
  "${WEBRTC_INCLUDE_DIR}"
)
# libwebrtc-c は dllexport 済みの C API シンボルを持つ静的ライブラリ。
# WHOLEARCHIVE ですべてのオブジェクトファイルを強制リンクし、
# dart:ffi から lookup される全シンボルを DLL のエクスポートテーブルに含める。
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  "${LIBWEBRTC_C_LIB}"
  "${WEBRTC_LIB}"
  mfplat.lib
  mf.lib
  mfreadwrite.lib
  mfuuid.lib
  secur32.lib
  winmm.lib
  dmoguids.lib
  msdmo.lib
  strmiids.lib
  ole32.lib
  oleaut32.lib
  propsys.lib
  iphlpapi.lib
  d3d11.lib
  dxgi.lib
  dwmapi.lib
  shcore.lib
  wmcodecdspuuid.lib
)
target_link_options(${PLUGIN_NAME} PRIVATE
  "/WHOLEARCHIVE:${LIBWEBRTC_C_LIB}"
)

# ビルド時にネイティブ依存を自動取得する
find_program(DART_EXECUTABLE dart)
if(DART_EXECUTABLE)
  add_custom_target(fetch_native_deps_windows
    COMMAND "${DART_EXECUTABLE}" run
      "${SORA_SDK_ROOT}/../scripts/fetch_native_deps.dart"
      windows_x86_64
    WORKING_DIRECTORY "${SORA_SDK_ROOT}/.."
  )
  add_dependencies(${PLUGIN_NAME} fetch_native_deps_windows)
endif()

# 他プラットフォームと同様に dart:ffi コードはプラグイン DLL に統合済みのため、
# 追加のバンドルライブラリは不要。
set(sora_sdk_bundled_libraries
  ""
  PARENT_SCOPE
)
