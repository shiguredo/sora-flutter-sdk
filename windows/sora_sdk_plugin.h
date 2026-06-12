#ifndef FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_
#define FLUTTER_PLUGIN_SORA_SDK_PLUGIN_H_

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/texture_registrar.h>

#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

class SoraCameraCapturer;
struct WindowsRenderingSink;

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

  struct RemoteVideoRendererContext {
    int64_t renderer_id;
    WindowsRenderingSink* sink;
    int64_t texture_id;
    flutter::TextureRegistrar* texture_registrar;
    std::unique_ptr<flutter::TextureVariant> texture_variant;
    std::vector<uint8_t> buffer;
    int width;
    int height;
    std::mutex mutex;
    FlutterDesktopPixelBuffer pixel_buffer{};
  };

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

  void HandleEnumerateAudioInputDevices(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleEnumerateAudioOutputDevices(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleCreateRemoteVideoRenderer(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleDisposeRemoteVideoRenderer(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void HandleGetDefaultAudioInputDevice(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  static int64_t GetIntValue(const flutter::EncodableValue& value,
                             int64_t default_value);

  static std::string GetStringValue(const flutter::EncodableValue& value,
                                    const std::string& default_value);

  flutter::BinaryMessenger* messenger_;
  flutter::TextureRegistrar* texture_registrar_;
  int64_t next_client_id_ = 1;
  int64_t next_renderer_id_ = 1;
  std::map<int64_t, std::unique_ptr<ClientWrapper>> clients_;
  std::map<int64_t, std::unique_ptr<SoraCameraCapturer>> capturers_;
  std::map<int64_t, std::unique_ptr<RemoteVideoRendererContext>>
      remote_renderers_;
};

#endif
