cmake_minimum_required(VERSION 3.10)
project(sora_sdk LANGUAGES C CXX)

set(PLUGIN_NAME "sora_sdk_plugin")

# ネイティブ依存のインストール先パス
get_filename_component(SORA_SDK_ROOT "${CMAKE_CURRENT_LIST_DIR}" REALPATH)
set(LIBWEBRTC_C_DIR "${SORA_SDK_ROOT}/../third_party/libwebrtc-c")
set(LIBWEBRTC_C_BUILD_DIR "${LIBWEBRTC_C_DIR}/build-linux_ubuntu_24_04_x86_64")
set(WEBRTC_INCLUDE_DIR "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include")
set(LIBWEBRTC_C_LIB "${LIBWEBRTC_C_BUILD_DIR}/libwebrtc-c.a")
set(WEBRTC_LIB "${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/lib/libwebrtc.a")

# === libsora_sdk.so (MethodChannel + dart:ffi 統合) ===
# 他プラットフォーム (Windows/macOS/iOS/Android) と同様に、
# MethodChannel プラグインコードと dart:ffi C ブリッジを
# 単一の共有ライブラリに統合する。

add_library(${PLUGIN_NAME} SHARED
  "push_audio_device.cc"
  "sora_audio_devices.cc"
  "sora_camera_capturer.cc"
  "sora_sdk_plugin.cc"
  "linux_bridge.c"
)

apply_standard_settings(${PLUGIN_NAME})
set_target_properties(${PLUGIN_NAME} PROPERTIES CXX_VISIBILITY_PRESET hidden)
# dart:ffi の DynamicLibrary.open('libsora_sdk.so') に合わせて出力名を設定する
set_target_properties(${PLUGIN_NAME} PROPERTIES OUTPUT_NAME sora_sdk)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} PUBLIC
  "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_include_directories(${PLUGIN_NAME} PRIVATE
  "${LIBWEBRTC_C_DIR}/include"
  "${WEBRTC_INCLUDE_DIR}"
)
# X11 は libwebrtc の内部実装要素 (キー入力シミュレーション) が参照する
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(X11 x11 IMPORTED_TARGET)
  # libjpeg-turbo: V4L2 MJPEG デコード用
  pkg_check_modules(JPEG libjpeg IMPORTED_TARGET)
  # PulseAudio: 音声デバイス列挙用
  pkg_check_modules(PULSEAUDIO libpulse IMPORTED_TARGET)
endif()
if(X11_FOUND)
  target_link_libraries(${PLUGIN_NAME} PRIVATE flutter dl pthread PkgConfig::X11)
else()
  target_link_libraries(${PLUGIN_NAME} PRIVATE flutter dl pthread X11)
endif()
# libjpeg リンク (MJPEG 対応)
if(JPEG_FOUND)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::JPEG)
else()
  target_link_libraries(${PLUGIN_NAME} PRIVATE jpeg)
endif()
# PulseAudio リンク (音声デバイス列挙用)
if(PULSEAUDIO_FOUND)
  target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::PULSEAUDIO)
else()
  target_link_libraries(${PLUGIN_NAME} PRIVATE pulse)
endif()

# cmake configure 時にネイティブ依存を自動取得する。
# add_custom_target ではビルド時にしか実行されず、
# その後に target_link_libraries でリンク対象を決めても反映されないため、
# configure 時に execute_process で実行する。
find_program(DART_EXECUTABLE dart)
if(DART_EXECUTABLE)
  execute_process(
    COMMAND "${DART_EXECUTABLE}" run
      "${SORA_SDK_ROOT}/../scripts/fetch_native_deps.dart"
      linux_ubuntu_24_04_x86_64
    WORKING_DIRECTORY "${SORA_SDK_ROOT}/.."
  )
endif()

# execute_process で依存取得済みのため LIBWEBRTC_C_LIB / WEBRTC_LIB は必ず存在する。
target_link_libraries(${PLUGIN_NAME} PRIVATE "${LIBWEBRTC_C_LIB}")
target_link_libraries(${PLUGIN_NAME} PRIVATE "${WEBRTC_LIB}")

# libwebrtc_c_api.ldflags で dart:ffi から参照する C API シンボルを保持する
set(LIBWEBRTC_C_API_LDFLAGS "${CMAKE_CURRENT_SOURCE_DIR}/libwebrtc_c_api.ldflags")
if(EXISTS "${LIBWEBRTC_C_API_LDFLAGS}")
  target_link_options(${PLUGIN_NAME} PRIVATE "@${LIBWEBRTC_C_API_LDFLAGS}")
endif()

# dart:ffi コードはプラグイン共有ライブラリに統合済みのため、
# 追加のバンドルライブラリは不要。
set(sora_sdk_bundled_libraries
  ""
  PARENT_SCOPE
)
