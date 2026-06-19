#include "sora_sdk_plugin.h"

#include <flutter/standard_method_codec.h>

#include "sora_audio_devices.h"
#include "sora_camera_capturer.h"
#include "windows_rendering_sink.h"

SoraSdkPlugin::SoraSdkPlugin(flutter::BinaryMessenger* messenger,
                             flutter::TextureRegistrar* texture_registrar)
    : messenger_(messenger), texture_registrar_(texture_registrar) {}

SoraSdkPlugin::~SoraSdkPlugin() {
  // HandleDisposeClient と同様に、先に EventChannel ハンドラを解除してから
  // clients_ を破棄する。これを怠ると BinaryMessenger 経由でラムダが
  // 呼ばれた際に dangling pointer アクセスが発生する。
  for (auto& pair : clients_) {
    messenger_->SetMessageHandler(pair.second->event_channel_name, nullptr);
  }
  clients_.clear();

  for (auto& pair : remote_renderers_) {
    // テクスチャを先に登録解除してからレンダリングシンクを破棄する
    if (pair.second->texture_id >= 0 && texture_registrar_) {
      texture_registrar_->UnregisterTexture(pair.second->texture_id, nullptr);
      pair.second->texture_id = -1;
    }
    if (pair.second->sink) {
      DeleteWindowsRenderingSink(pair.second->sink);
      pair.second->sink = nullptr;
    }
  }
  remote_renderers_.clear();
}

void SoraSdkPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "sora_sdk/method",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<SoraSdkPlugin>(registrar->messenger(),
                                                registrar->texture_registrar());

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
  if (method == "createRemoteVideoRenderer") {
    HandleCreateRemoteVideoRenderer(method_call, std::move(result));
    return;
  }
  if (method == "disposeRemoteVideoRenderer") {
    HandleDisposeRemoteVideoRenderer(method_call, std::move(result));
    return;
  }
  result->NotImplemented();
}

void SoraSdkPlugin::HandleCreateClient(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // config の解析は後続の対応で実装する
  (void)method_call;

  auto client_id = next_client_id_++;
  auto event_channel_name = "sora_sdk/event/" + std::to_string(client_id);

  auto wrapper = std::make_unique<ClientWrapper>();
  wrapper->client_id = client_id;
  wrapper->event_channel_name = event_channel_name;
  wrapper->messenger = messenger_;

  // EventChannel の listen / cancel に応答し、sendEvent() 経由でイベントを送出する
  ClientWrapper* wrapper_ptr = wrapper.get();
  messenger_->SetMessageHandler(
      event_channel_name,
      [wrapper_ptr](const uint8_t* data, size_t size,
                    flutter::BinaryReply reply) {
        auto& codec = flutter::StandardMethodCodec::GetInstance();
        auto call = codec.DecodeMethodCall(data, size);
        if (call->method_name() == "listen") {
          wrapper_ptr->event_sink_active.store(true);
          auto response = codec.EncodeSuccessEnvelope(nullptr);
          reply(response->data(), response->size());
        } else if (call->method_name() == "cancel") {
          wrapper_ptr->event_sink_active.store(false);
          auto response = codec.EncodeSuccessEnvelope(nullptr);
          reply(response->data(), response->size());
        } else {
          auto response =
              codec.EncodeErrorEnvelope("error", "Not implemented", nullptr);
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

void SoraSdkPlugin::ClientWrapper::sendEvent(flutter::EncodableMap event) {
  if (!event_sink_active.load()) {
    return;
  }
  auto& codec = flutter::StandardMethodCodec::GetInstance();
  flutter::EncodableValue result(event);
  auto encoded = codec.EncodeSuccessEnvelope(&result);
  messenger->Send(event_channel_name, encoded->data(), encoded->size(),
                  nullptr);
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

std::string SoraSdkPlugin::GetStringValue(const flutter::EncodableValue& value,
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
    if (w > 0)
      width = w;
  }

  int height = 480;
  auto height_it = args->find(flutter::EncodableValue("videoHeight"));
  if (height_it != args->end()) {
    int h = static_cast<int>(GetIntValue(height_it->second, 0));
    if (h > 0)
      height = h;
  }

  int fps = 30;
  auto fps_it = args->find(flutter::EncodableValue("videoFrameRate"));
  if (fps_it != args->end()) {
    int f = static_cast<int>(GetIntValue(fps_it->second, 0));
    if (f > 0)
      fps = f;
  }

  auto capturer = std::make_unique<SoraCameraCapturer>(device_id, width, height,
                                                       fps, texture_registrar_);
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

void SoraSdkPlugin::HandleCreateRemoteVideoRenderer(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }

  auto client_id_it = args->find(flutter::EncodableValue("clientId"));
  if (client_id_it == args->end()) {
    result->Error("invalid_argument", "clientId is required.");
    return;
  }
  int64_t client_id = GetIntValue(client_id_it->second, -1);
  auto wrapper_it = clients_.find(client_id);
  if (wrapper_it == clients_.end()) {
    result->Error("client_not_found", "Client not found.");
    return;
  }

  // C ブリッジでレンダリングシンクを作成する
  WindowsRenderingSink* sink = CreateWindowsRenderingSink();
  if (sink == NULL) {
    result->Error("renderer_create_failed", "Failed to create rendering sink.");
    return;
  }

  auto ctx = std::make_unique<RemoteVideoRendererContext>();
  ctx->renderer_id = next_renderer_id_++;
  ctx->sink = sink;
  ctx->texture_registrar = texture_registrar_;

  // Flutter Texture を登録する
  // PixelBufferTexture は Flutter エンジンのレンダリングスレッドから呼ばれ、
  // その中で I420 → BGRA 変換を行う。
  ctx->pixel_buffer = {};
  auto texture = std::make_unique<flutter::PixelBufferTexture>(
      [ctx = ctx.get()](size_t width, size_t height) {
        (void)width;
        (void)height;
        if (ctx->sink == nullptr) {
          return &ctx->pixel_buffer;
        }
        if (!WindowsRenderingSinkCopyPixelBuffer(ctx->sink, ctx->buffer,
                                                 ctx->width, ctx->height)) {
          return &ctx->pixel_buffer;
        }
        std::lock_guard<std::mutex> lock(ctx->mutex);
        ctx->pixel_buffer.buffer = ctx->buffer.data();
        ctx->pixel_buffer.width = ctx->width;
        ctx->pixel_buffer.height = ctx->height;
        ctx->pixel_buffer.release_callback = nullptr;
        ctx->pixel_buffer.release_context = nullptr;
        return &ctx->pixel_buffer;
      });
  ctx->texture_variant =
      std::make_unique<flutter::TextureVariant>(std::move(*texture));
  ctx->texture_id =
      texture_registrar_->RegisterTexture(ctx->texture_variant.get());

  // フレーム通知コールバックを設定する
  // コールバックは webrtc スレッドから呼ばれる。
  // MarkTextureFrameAvailable はスレッドセーフ。
  WindowsRenderingSinkSetFrameCallback(
      sink,
      [](void* context) {
        auto* renderer_ctx = static_cast<RemoteVideoRendererContext*>(context);
        if (renderer_ctx->texture_id >= 0) {
          renderer_ctx->texture_registrar->MarkTextureFrameAvailable(
              renderer_ctx->texture_id);
        }
      },
      ctx.get());

  int64_t renderer_id = ctx->renderer_id;
  int64_t texture_id = ctx->texture_id;
  intptr_t rendering_sink_ptr = reinterpret_cast<intptr_t>(sink);
  intptr_t video_sink_ptr =
      reinterpret_cast<intptr_t>(WindowsRenderingSinkGetVideoSinkPtr(sink));

  remote_renderers_[renderer_id] = std::move(ctx);

  flutter::EncodableMap response;
  response[flutter::EncodableValue("rendererId")] =
      flutter::EncodableValue(renderer_id);
  response[flutter::EncodableValue("renderingSinkPtr")] =
      flutter::EncodableValue(rendering_sink_ptr);
  response[flutter::EncodableValue("videoSinkPtr")] =
      flutter::EncodableValue(video_sink_ptr);
  response[flutter::EncodableValue("textureId")] =
      flutter::EncodableValue(texture_id);
  result->Success(flutter::EncodableValue(response));
}

void SoraSdkPlugin::HandleDisposeRemoteVideoRenderer(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args =
      std::get_if<flutter::EncodableMap>(method_call.arguments());
  if (!args) {
    result->Error("invalid_argument", "Arguments are required.");
    return;
  }

  auto renderer_id_it = args->find(flutter::EncodableValue("rendererId"));
  if (renderer_id_it == args->end()) {
    result->Error("invalid_argument", "rendererId is required.");
    return;
  }
  int64_t renderer_id = GetIntValue(renderer_id_it->second, -1);

  auto it = remote_renderers_.find(renderer_id);
  if (it == remote_renderers_.end()) {
    result->Success();
    return;
  }

  // テクスチャを先に登録解除する。
  // PixelBufferTexture コールバックが発火しなくなるため、その後に
  // レンダリングシンクを安全に破棄できる。
  if (it->second->texture_id >= 0 && texture_registrar_) {
    texture_registrar_->UnregisterTexture(it->second->texture_id, nullptr);
    it->second->texture_id = -1;
  }

  // レンダリングシンクを破棄する。
  // DeleteWindowsRenderingSink は disposed を設定し、on_frame_available を
  // NULL にし、inflight の完了を待つ。
  if (it->second->sink) {
    DeleteWindowsRenderingSink(it->second->sink);
    it->second->sink = nullptr;
  }

  remote_renderers_.erase(it);
  result->Success();
}
