#include "include/sora_sdk/sora_sdk_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "sora_sdk_plugin.h"

void SoraSdkPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  SoraSdkPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
