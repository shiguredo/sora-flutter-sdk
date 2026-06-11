#ifndef FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_
#define FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <string>

class SoraSdkPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  SoraSdkPlugin(flutter::BinaryMessenger* messenger,
                flutter::TextureRegistrar* texture_registrar);
  ~SoraSdkPlugin() override;

  SoraSdkPlugin(const SoraSdkPlugin&) = delete;
  SoraSdkPlugin& operator=(const SoraSdkPlugin&) = delete;

 private:
  // クライアント単位の情報を保持する。
  // event_channel_name は Dart 側が EventChannel を購読するために使う。
  struct ClientWrapper {
    int64_t client_id;
    std::string event_channel_name;
  };

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleCreateClient(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleDisposeClient(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static int64_t GetIntValue(const flutter::EncodableValue& value,
                             int64_t default_value);

  // 後続 issue で Texture 登録・EventChannel 経由のイベント送信に使う
  flutter::BinaryMessenger* messenger_;
  flutter::TextureRegistrar* texture_registrar_;
  int64_t next_client_id_ = 1;
  std::map<int64_t, std::unique_ptr<ClientWrapper>> clients_;
};

#endif
