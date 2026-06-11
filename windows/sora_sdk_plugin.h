#ifndef FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_
#define FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <map>
#include <memory>
#include <string>

class SoraCameraCapturer;

class SoraSdkPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  SoraSdkPlugin(flutter::BinaryMessenger* messenger,
                flutter::TextureRegistrar* texture_registrar);
  ~SoraSdkPlugin() override;

  SoraSdkPlugin(const SoraSdkPlugin&) = delete;
  SoraSdkPlugin& operator=(const SoraSdkPlugin&) = delete;

 private:
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

  void HandleEnumerateVideoInputDevices(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleGetVideoInputFormats(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleEnsureLocalVideoTrackTexture(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleDisposeLocalVideoTrackTexture(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleStopCameraCapturer(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static int64_t GetIntValue(const flutter::EncodableValue& value,
                             int64_t default_value);

  static std::string GetStringValue(const flutter::EncodableValue& value,
                                    const std::string& default_value);

  flutter::BinaryMessenger* messenger_;
  flutter::TextureRegistrar* texture_registrar_;
  int64_t next_client_id_ = 1;
  std::map<int64_t, std::unique_ptr<ClientWrapper>> clients_;
  std::map<int64_t, std::unique_ptr<SoraCameraCapturer>> capturers_;
};

#endif
