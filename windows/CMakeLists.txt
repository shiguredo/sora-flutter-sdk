cmake_minimum_required(VERSION 3.18)
project(sora_sdk LANGUAGES C CXX)

set(PLUGIN_NAME "sora_sdk_plugin")

# === Flutter プラグイン DLL (MethodChannel 処理) ===

add_library(${PLUGIN_NAME} SHARED
  "include/sora_sdk/sora_sdk_plugin_c_api.h"
  "sora_sdk_plugin_c_api.cpp"
  "sora_sdk_plugin.cpp"
  "sora_sdk_plugin.h"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# === dart:ffi C API DLL (sora_sdk.dll) ===

# ネイティブ依存 (0032) のインストール先パス
set(LIBWEBRTC_C_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libwebrtc-c")
set(LIBWEBRTC_C_BUILD_DIR "${LIBWEBRTC_C_DIR}/build-windows_x86_64")
set(WEBRTC_INCLUDE_DIR "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include")
set(LIBWEBRTC_C_LIB "${LIBWEBRTC_C_BUILD_DIR}/libwebrtc-c.lib")
set(WEBRTC_LIB "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/lib/webrtc.lib")

add_library(sora_sdk SHARED
  "windows_bridge.c"
)

target_include_directories(sora_sdk PRIVATE
  "${LIBWEBRTC_C_DIR}/include"
  "${WEBRTC_INCLUDE_DIR}"
)

# libwebrtc-c は dllexport 済みの C API シンボルを持つ静的ライブラリ。
# WHOLEARCHIVE ですべてのオブジェクトファイルを強制リンクし、
# dart:ffi から lookup される全シンボルを DLL のエクスポートテーブルに含める。
target_link_libraries(sora_sdk PRIVATE
  "${LIBWEBRTC_C_LIB}"
  "${WEBRTC_LIB}"
  # WebRTC が要求する Windows システムライブラリ
  secur32.lib
  winmm.lib
  dmoguids.lib
  msdmo.lib
  strmiids.lib
)
target_link_options(sora_sdk PRIVATE
  "/WHOLEARCHIVE:${LIBWEBRTC_C_LIB}"
)

# ビルド時にネイティブ依存を自動取得する
find_program(DART_EXECUTABLE dart)
if(DART_EXECUTABLE)
  add_custom_target(fetch_native_deps_windows
    COMMAND "${DART_EXECUTABLE}" run
      "${CMAKE_CURRENT_SOURCE_DIR}/../scripts/fetch_native_deps.dart"
      windows_x86_64
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
  )
  add_dependencies(sora_sdk fetch_native_deps_windows)
endif()

# sora_sdk.dll をバンドル対象に含める (dart:ffi の DynamicLibrary.open で読み込めるようにする)
set(sora_sdk_bundled_libraries
  "$<TARGET_FILE:sora_sdk>"
  PARENT_SCOPE
)
