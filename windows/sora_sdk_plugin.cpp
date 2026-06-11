#include "sora_sdk_plugin.h"

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
    result->Success(flutter::EncodableValue(flutter::EncodableList()));
    return;
  }
  if (method == "enumerateAudioInputDevices") {
    result->Success(flutter::EncodableValue(flutter::EncodableList()));
    return;
  }
  if (method == "enumerateAudioOutputDevices") {
    result->Success(flutter::EncodableValue(flutter::EncodableList()));
    return;
  }
  if (method == "getVideoInputFormats") {
    result->Success(flutter::EncodableValue(flutter::EncodableList()));
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
          reply(response.data(), response.size());
        } else {
          auto response = codec.EncodeErrorEnvelope(
              "error", "Not implemented", nullptr);
          reply(response.data(), response.size());
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
  // Flutter StandardMethodCodec は値の大きさによって int32_t と int64_t を
  // 使い分ける。両方のエンコードに対応するため両方をチェックする。
  if (auto* v = std::get_if<int32_t>(&value)) {
    return static_cast<int64_t>(*v);
  }
  if (auto* v = std::get_if<int64_t>(&value)) {
    return *v;
  }
  return default_value;
}
