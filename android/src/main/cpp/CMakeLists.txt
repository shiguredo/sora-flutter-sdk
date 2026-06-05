cmake_minimum_required(VERSION 3.22)

set(LIBWEBRTC_C_DIR "" CACHE PATH "libwebrtc-c のソースディレクトリ")
set(LIBWEBRTC_C_BUILD_DIR "" CACHE PATH "libwebrtc-c のビルドディレクトリ")
set(WEBRTC_LDFLAGS_FILE "" CACHE FILEPATH "WebRTC の追加リンクオプションファイル")

project(sora_sdk C)

add_library(sora_sdk SHARED
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
