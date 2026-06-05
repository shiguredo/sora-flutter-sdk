#include "sora_sdk_plugin.h"

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

SoraSdkPlugin::SoraSdkPlugin() = default;
SoraSdkPlugin::~SoraSdkPlugin() = default;

void SoraSdkPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "sora_sdk/method",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SoraSdkPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void SoraSdkPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  result->Error("unimplemented", "Windows implementation is not wired yet.");
}
