cmake_minimum_required(VERSION 3.18)
project(sora_sdk LANGUAGES CXX)

set(PLUGIN_NAME "sora_sdk_plugin")

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

set(sora_sdk_bundled_libraries
  ""
  PARENT_SCOPE
)
