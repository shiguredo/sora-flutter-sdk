cmake_minimum_required(VERSION 3.10)

set(WEBRTC_INCLUDE_DIR "" CACHE PATH "WebRTC のインクルードディレクトリ")
set(WEBRTC_LIBRARY_DIR "" CACHE PATH "WebRTC のライブラリディレクトリ")
set(WEBRTC_LIBRARY_NAME "webrtc" CACHE STRING "WebRTC のライブラリ名")
set(LIBCXX_INCLUDE_DIR "" CACHE PATH "libc++ を使う場合の libc++ のインクルードディレクトリ\n空文字だった場合はデフォルト検索パスの libc++ を利用する")
set(SORA_DIR "" CACHE PATH "Sora のルートディレクトリ")

project(sora_flutter_sdk C CXX)

list(APPEND CMAKE_PREFIX_PATH ${SORA_DIR})
list(APPEND CMAKE_MODULE_PATH ${SORA_DIR}/share/cmake)

set(Boost_USE_STATIC_LIBS ON)

# ローカルマシンにインストールされた Boost を参照しない設定
# 以下リンクの stack overflow の内容を参考にしている
# https://stackoverflow.com/questions/3016448/how-can-i-get-cmake-to-find-my-alternative-boost-installation
set(Boost_NO_BOOST_CMAKE ON)
set(Boost_NO_SYSTEM_PATHS ON)
set(BOOST_LIBRARYDIR ${BOOST_ROOT}/lib)

set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE NEVER)

find_package(Boost REQUIRED COMPONENTS json filesystem)
find_package(WebRTC REQUIRED)
find_package(Sora REQUIRED)
find_package(Lyra REQUIRED)
find_package(Threads REQUIRED)

set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

add_library(sora_flutter_sdk
  SHARED
    jni_onload.cpp
    native-lib.cpp
    ../../../../src/sora_client.cpp
    ../../../../src/sora_renderer.cpp
    ../../../../src/device_list.cpp
)

target_include_directories(sora_flutter_sdk PRIVATE "../../../../src")
target_link_libraries(sora_flutter_sdk PRIVATE Sora::sora)

target_compile_options(sora_flutter_sdk
  PRIVATE
    "$<$<COMPILE_LANGUAGE:CXX>:-nostdinc++>"
    "$<$<COMPILE_LANGUAGE:CXX>:-isystem${LIBCXX_INCLUDE_DIR}>"
)

target_compile_definitions(sora_flutter_sdk PRIVATE HELLO_ANDROID)

find_library(ANDROID_LIB_LOG log)
find_library(ANDROID_LIB_ANDROID android)
find_library(ANDROID_LIB_OPENSLES OpenSLES)
find_library(ANDROID_LIB_EGL EGL)

target_link_libraries(sora_flutter_sdk
  PRIVATE
    ${ANDROID_LIB_LOG}
    ${ANDROID_LIB_ANDROID}
    ${ANDROID_LIB_OPENSLES}
    ${ANDROID_LIB_EGL}
)

#file(READ ${SORA_DIR}/share/webrtc.ldflags _WEBRTC_ANDROID_LDFLAGS)
#string(REGEX REPLACE "\n" ";" _WEBRTC_ANDROID_LDFLAGS "${_WEBRTC_ANDROID_LDFLAGS}")
target_link_options(sora_flutter_sdk
  PRIVATE
    "@${SORA_DIR}/share/webrtc.ldflags"
)

# Lyra のモデルファイルをアセットにコピーする
set(LYRA_MODEL_FILES
        lyra_config.binarypb
        lyragan.tflite
        quantizer.tflite
        soundstream_encoder.tflite
        test_playback.wav)
file(MAKE_DIRECTORY "${ASSET_LYRA_DIR}")
foreach (FILE ${LYRA_MODEL_FILES})
    # ダミーファイルを消す
    file(REMOVE "${ASSET_LYRA_DIR}/${FILE}")
    file(COPY "${Lyra_SHARE_DIR}/model_coeffs/${FILE}" DESTINATION "${ASSET_LYRA_DIR}")
endforeach ()
