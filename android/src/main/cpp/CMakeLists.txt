cmake_minimum_required(VERSION 3.22)

set(LIBWEBRTC_C_DIR "" CACHE PATH "libwebrtc-c のソースディレクトリ")
set(LIBWEBRTC_C_BUILD_DIR "" CACHE PATH "libwebrtc-c のビルドディレクトリ")
set(WEBRTC_LDFLAGS_FILE "" CACHE FILEPATH "WebRTC の追加リンクオプションファイル")

project(sora_sdk C)

# HWAddressSanitizer / UndefinedBehaviorSanitizer のビルドオプション
# 既定 OFF 。Gradle から -DSORA_SDK_ENABLE_HWASAN=ON / -DSORA_SDK_ENABLE_UBSAN=ON で有効化する。
option(SORA_SDK_ENABLE_HWASAN "HWAddressSanitizer を有効化する (use-after-free, 境界外アクセス)" OFF)
option(SORA_SDK_ENABLE_UBSAN "UndefinedBehaviorSanitizer を有効化する (signed integer overflow, trap モード)" OFF)

add_library(sora_sdk SHARED
  push_audio_device.cpp
  jni_onload.c
)

target_include_directories(sora_sdk PRIVATE
  ${LIBWEBRTC_C_DIR}/include
  ${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include
  ${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include/third_party/abseil-cpp
  # libyuv ヘッダー用
  ${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include/third_party/boringssl/src/include
  ${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/include/third_party/libyuv/include
)

set_target_properties(sora_sdk PROPERTIES
  C_STANDARD 11
  C_STANDARD_REQUIRED YES
  C_EXTENSIONS NO
)

find_library(ANDROID_LIB_LOG log)
find_library(ANDROID_LIB_OPENSLES OpenSLES)
find_library(ANDROID_LIB_ANDROID android)
find_library(ANDROID_LIB_EGL EGL)

# Android では libwebrtc-c.a だけでは足りず、
# WebRTC 本体の実装シンボル解決のために libwebrtc.a もリンク対象にする。
target_link_libraries(sora_sdk PRIVATE
  ${LIBWEBRTC_C_BUILD_DIR}/libwebrtc-c.a
  ${LIBWEBRTC_C_BUILD_DIR}/_deps/webrtc/lib/${CMAKE_ANDROID_ARCH_ABI}/libwebrtc.a
  ${ANDROID_LIB_LOG}
  ${ANDROID_LIB_OPENSLES}
  ${ANDROID_LIB_ANDROID}
  ${ANDROID_LIB_EGL}
)

if(SORA_SDK_ENABLE_HWASAN)
  target_compile_options(sora_sdk PRIVATE -fsanitize=hwaddress -fno-omit-frame-pointer)
  target_link_options(sora_sdk PRIVATE -fsanitize=hwaddress)
endif()

if(SORA_SDK_ENABLE_UBSAN)
  target_compile_options(sora_sdk PRIVATE -fsanitize=signed-integer-overflow -fsanitize-trap=signed-integer-overflow)
  target_link_options(sora_sdk PRIVATE -fsanitize=signed-integer-overflow -fsanitize-trap=signed-integer-overflow)
endif()

# 既定では SDK 管理下の webrtc.ldflags を利用する
set(_DEFAULT_WEBRTC_LDFLAGS_FILE
  "${CMAKE_CURRENT_SOURCE_DIR}/webrtc.ldflags"
)
set(_DEFAULT_LIBWEBRTC_C_API_LDFLAGS_FILE
  "${CMAKE_CURRENT_SOURCE_DIR}/libwebrtc_c_api.ldflags"
)

if(WEBRTC_LDFLAGS_FILE STREQUAL "")
  set(_WEBRTC_LDFLAGS_FILE "${_DEFAULT_WEBRTC_LDFLAGS_FILE}")
else()
  set(_WEBRTC_LDFLAGS_FILE "${WEBRTC_LDFLAGS_FILE}")
endif()

if(EXISTS "${_WEBRTC_LDFLAGS_FILE}")
  target_link_options(sora_sdk PRIVATE "@${_WEBRTC_LDFLAGS_FILE}")
endif()

if(EXISTS "${_DEFAULT_LIBWEBRTC_C_API_LDFLAGS_FILE}")
  # --whole-archive は不要なオブジェクトまで取り込んで競合を起こすため使わない。
  # その代わり dart:ffi から参照する libwebrtc-c の公開 C API だけを
  # --undefined で明示してリンク対象に残す。
  target_link_options(
    sora_sdk PRIVATE "@${_DEFAULT_LIBWEBRTC_C_API_LDFLAGS_FILE}"
  )
endif()
