#ifndef FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_
#define FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_

#include <flutter/plugin_registrar_windows.h>

#include <memory>

class SoraSdkPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  SoraSdkPlugin();
  ~SoraSdkPlugin() override;

  SoraSdkPlugin(const SoraSdkPlugin&) = delete;
  SoraSdkPlugin& operator=(const SoraSdkPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
};

#endif
