#include "sora_sdk_plugin.h"

#include <flutter/standard_method_codec.h>

#include "sora_audio_devices.h"
#include "sora_camera_capturer.h"

SoraSdkPlugin::SoraSdkPlugin(flutter::BinaryMessenger* messenger,
                             flutter::TextureRegistrar* texture_registrar)
    : messenger_(messenger), texture_registrar_(texture_registrar) {}

SoraSdkPlugin::~SoraSdkPlugin() = default;

void SoraSdkPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "sora_sdk/method",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SoraSdkPlugin>(
      registrar->messenger(), registrar->texture_registrar());

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void SoraSdkPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "createClient") {
    HandleCreateClient(method_call, std::move(result));
    return;
  }
  if (method == "disposeClient") {
    HandleDisposeClient(method_call, std::move(result));
    return;
  }
  if (method == "enumerateVideoInputDevices") {
    HandleEnumerateVideoInputDevices(method_call, std::move(result));
    return;
  }
  if (method == "enumerateAudioInputDevices") {
    HandleEnumerateAudioInputDevices(method_call, std::move(result));
    return;
  }
  if (method == "enumerateAudioOutputDevices") {
    HandleEnumerateAudioOutputDevices(method_call, std::move(result));
    return;
  }
  if (method == "getDefaultAudioInputDevice") {
    HandleGetDefaultAudioInputDevice(method_call, std::move(result));
    return;
  }
  if (method == "getVideoInputFormats") {
    HandleGetVideoInputFormats(method_call, std::move(result));
    return;
  }
  if (method == "ensureLocalVideoTrackTexture") {
    HandleEnsureLocalVideoTrackTexture(method_call, std::move(result));
    return;
  }
  if (method == "disposeLocalVideoTrackTexture") {
    HandleDisposeLocalVideoTrackTexture(method_call, std::move(result));
    return;
  }
  if (method == "stopCameraCapturer") {
    HandleStopCameraCapturer(method_call, std::move(result));
    return;
  }
  result->NotImplemented();
}

void SoraSdkPlugin::HandleCreateClient(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // config の解析は後続 issue (0035-0037) で実装する
  (void)method_call;

  auto client_id = next_client_id_++;
  auto event_channel_name = "sora_sdk/event/" + std::to_string(client_id);

  auto wrapper = std::make_unique<ClientWrapper>();
  wrapper->client_id = client_id;
  wrapper->event_channel_name = event_channel_name;

  // EventChannel の listen / cancel に応答するハンドラを登録する。
  // 後続 issue でカメラ・音声・レンダリングのイベントを送信するための基盤。
  // flutter::EventChannel は Windows C++ ラッパーに存在しないため、
  // BinaryMessenger の生のメッセージハンドラで代用する。
  messenger_->SetMessageHandler(
      event_channel_name,
      [](const uint8_t* data, size_t size,
         flutter::BinaryReply reply) {
        auto& codec = flutter::StandardMethodCodec::GetInstance();
        auto call = codec.DecodeMethodCall(data, size);
        if (call->method_name() == "listen" ||
            call->method_name() == "cancel") {
          auto response = codec.EncodeSuccessEnvelope(nullptr);
          reply(response->data(), response->size());
        } else {
          auto response = codec.EncodeErrorEnvelope(
              "error", "Not implemented", nullptr);
          reply(response->data(), response->size());
        }
      });

  clients_[client_id] = std::move(wrapper);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("clientId")] =
      flutter::EncodableValue(client_id);
  response[flutter::EncodableValue("eventChannelName")] =
      flutter::EncodableValue(event_channel_name);
  result->Success(flutter::EncodableValue(response));
}

void SoraSdkPlugin::HandleDisposeClient(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }
  auto it = args->find(flutter::EncodableValue("clientId"));
  if (it == args->end()) {
    result->Error("invalid_argument", "clientId is required.");
    return;
  }
  auto client_id = GetIntValue(it->second, -1);
  if (client_id < 0) {
    result->Error("invalid_argument", "clientId must be an integer.");
    return;
  }
  auto wrapper_it = clients_.find(client_id);
  if (wrapper_it == clients_.end()) {
    result->Error("client_not_found", "Client not found.");
    return;
  }
  // EventChannel のハンドラを解除してからクライアントを削除する
  messenger_->SetMessageHandler(wrapper_it->second->event_channel_name,
                                nullptr);
  clients_.erase(wrapper_it);
  result->Success();
}

int64_t SoraSdkPlugin::GetIntValue(const flutter::EncodableValue& value,
                                   int64_t default_value) {
  if (auto* v = std::get_if<int32_t>(&value)) {
    return static_cast<int64_t>(*v);
  }
  if (auto* v = std::get_if<int64_t>(&value)) {
    return *v;
  }
  return default_value;
}

std::string SoraSdkPlugin::GetStringValue(
    const flutter::EncodableValue& value,
    const std::string& default_value) {
  if (auto* v = std::get_if<std::string>(&value)) {
    return *v;
  }
  return default_value;
}

void SoraSdkPlugin::HandleEnumerateVideoInputDevices(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  (void)method_call;
  flutter::EncodableList devices = SoraCameraCapturer::EnumerateDevices();
  result->Success(flutter::EncodableValue(devices));
}

void SoraSdkPlugin::HandleGetVideoInputFormats(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }
  auto it = args->find(flutter::EncodableValue("deviceId"));
  if (it == args->end()) {
    result->Error("invalid_argument", "deviceId is required.");
    return;
  }
  std::string device_id = GetStringValue(it->second, "");
  if (device_id.empty()) {
    result->Error("invalid_argument", "deviceId must be a non-empty string.");
    return;
  }
  flutter::EncodableList formats = SoraCameraCapturer::GetFormats(device_id);
  result->Success(flutter::EncodableValue(formats));
}

void SoraSdkPlugin::HandleEnsureLocalVideoTrackTexture(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }

  auto video_source_it = args->find(flutter::EncodableValue("videoSourcePtr"));
  if (video_source_it == args->end()) {
    result->Error("invalid_argument", "videoSourcePtr is required.");
    return;
  }
  int64_t video_source_ptr = GetIntValue(video_source_it->second, 0);
  if (video_source_ptr == 0) {
    result->Error("invalid_argument",
                  "videoSourcePtr must be a non-zero integer.");
    return;
  }

  std::string device_id;
  auto device_id_it = args->find(flutter::EncodableValue("videoDeviceId"));
  if (device_id_it != args->end()) {
    device_id = GetStringValue(device_id_it->second, "");
  }

  int width = 640;
  auto width_it = args->find(flutter::EncodableValue("videoWidth"));
  if (width_it != args->end()) {
    int w = static_cast<int>(GetIntValue(width_it->second, 0));
    if (w > 0) width = w;
  }

  int height = 480;
  auto height_it = args->find(flutter::EncodableValue("videoHeight"));
  if (height_it != args->end()) {
    int h = static_cast<int>(GetIntValue(height_it->second, 0));
    if (h > 0) height = h;
  }

  int fps = 30;
  auto fps_it = args->find(flutter::EncodableValue("videoFrameRate"));
  if (fps_it != args->end()) {
    int f = static_cast<int>(GetIntValue(fps_it->second, 0));
    if (f > 0) fps = f;
  }

  auto capturer = std::make_unique<SoraCameraCapturer>(
      device_id, width, height, fps, texture_registrar_);
  capturer->SetVideoSourcePtr(
      reinterpret_cast<void*>(static_cast<intptr_t>(video_source_ptr)));
  capturer->Start();

  int64_t texture_id = capturer->preview_texture_id();
  capturers_[video_source_ptr] = std::move(capturer);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(texture_id);
  result->Success(flutter::EncodableValue(response));
}

void SoraSdkPlugin::HandleDisposeLocalVideoTrackTexture(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }
  auto it = args->find(flutter::EncodableValue("videoSourcePtr"));
  if (it == args->end()) {
    result->Error("invalid_argument", "videoSourcePtr is required.");
    return;
  }
  int64_t video_source_ptr = GetIntValue(it->second, 0);
  auto capturer_it = capturers_.find(video_source_ptr);
  if (capturer_it == capturers_.end()) {
    result->Success();
    return;
  }
  capturer_it->second->Stop();
  capturers_.erase(capturer_it);
  result->Success();
}

void SoraSdkPlugin::HandleStopCameraCapturer(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }
  auto it = args->find(flutter::EncodableValue("videoSourcePtr"));
  if (it == args->end()) {
    result->Error("invalid_argument", "videoSourcePtr is required.");
    return;
  }
  int64_t video_source_ptr = GetIntValue(it->second, 0);
  auto capturer_it = capturers_.find(video_source_ptr);
  if (capturer_it == capturers_.end()) {
    result->Success();
    return;
  }
  capturer_it->second->Stop();
  result->Success();
}

void SoraSdkPlugin::HandleEnumerateAudioInputDevices(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  (void)method_call;
  flutter::EncodableList devices = SoraAudioDevices::EnumerateInputDevices();
  result->Success(flutter::EncodableValue(devices));
}

void SoraSdkPlugin::HandleEnumerateAudioOutputDevices(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  (void)method_call;
  flutter::EncodableList devices = SoraAudioDevices::EnumerateOutputDevices();
  result->Success(flutter::EncodableValue(devices));
}

void SoraSdkPlugin::HandleGetDefaultAudioInputDevice(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  (void)method_call;
  std::string device_id = SoraAudioDevices::GetDefaultInputDeviceId();
  if (device_id.empty()) {
    result->Success(flutter::EncodableValue());
    return;
  }
  result->Success(flutter::EncodableValue(device_id));
}
