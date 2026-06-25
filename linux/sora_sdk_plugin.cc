#include "include/sora_sdk/sora_sdk_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <inttypes.h>
#include <map>
#include <memory>
#include <set>

#include "sora_camera_capturer.h"

// ---------------------------------------------------------------------------
// SoraClient: EventChannel を保持するクライアント単位のコンテキスト
// ---------------------------------------------------------------------------

struct SoraClient {
  int64_t client_id;
  FlEventChannel* event_channel;
  FlEventChannelHandler listen_handler;
  FlEventChannelHandler cancel_handler;
  bool is_streaming;
};

// ---------------------------------------------------------------------------
// SoraSdkPluginContext: C++ のデータを保持するコンテキスト
// ---------------------------------------------------------------------------

struct SoraSdkPluginContext {
  // videoSourcePtr -> SoraCameraCapturer
  std::map<int64_t, std::unique_ptr<SoraCameraCapturer>> capturers;
  // client_id -> videoSourcePtr の set
  std::map<int64_t, std::set<int64_t>> client_capturers;
};

// ---------------------------------------------------------------------------
// SoraSdkPlugin: GObject プラグインインスタンス
// ---------------------------------------------------------------------------

struct _SoraSdkPlugin {
  GObject parent_instance;
  FlBinaryMessenger* messenger;
  FlTextureRegistrar* texture_registrar;
  GHashTable* clients;
  int64_t next_client_id;
  SoraSdkPluginContext* context;
};

G_DEFINE_TYPE(SoraSdkPlugin, sora_sdk_plugin, g_object_get_type())

static void sora_client_free(gpointer data) {
  auto* client = static_cast<SoraClient*>(data);
  if (client->event_channel != nullptr) {
    fl_event_channel_set_stream_handlers(client->event_channel, nullptr,
                                         nullptr, nullptr, nullptr);
    g_object_unref(client->event_channel);
  }
  g_free(client);
}

// ---------------------------------------------------------------------------
// EventChannel StreamHandlers
// ---------------------------------------------------------------------------

static FlMethodErrorResponse* sora_event_listen_cb(FlEventChannel* channel,
                                                    FlValue* args,
                                                    gpointer user_data) {
  auto* client = static_cast<SoraClient*>(user_data);
  client->is_streaming = true;
  return nullptr;
}

static FlMethodErrorResponse* sora_event_cancel_cb(FlEventChannel* channel,
                                                    FlValue* args,
                                                    gpointer user_data) {
  auto* client = static_cast<SoraClient*>(user_data);
  client->is_streaming = false;
  return nullptr;
}

// ---------------------------------------------------------------------------
// int64_t ヘルパー
// ---------------------------------------------------------------------------

static int64_t get_int64_from_map(FlValue* map, const char* key,
                                  int64_t default_value) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return default_value;
  }
  FlValue* v = fl_value_lookup_string(map, key);
  if (v == nullptr) {
    return default_value;
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) {
    return fl_value_get_int(v);
  }
  return default_value;
}

static std::string get_string_from_map(FlValue* map, const char* key,
                                       const std::string& default_value) {
  if (map == nullptr || fl_value_get_type(map) != FL_VALUE_TYPE_MAP) {
    return default_value;
  }
  FlValue* v = fl_value_lookup_string(map, key);
  if (v == nullptr) {
    return default_value;
  }
  if (fl_value_get_type(v) == FL_VALUE_TYPE_STRING) {
    return fl_value_get_string(v);
  }
  return default_value;
}

// ---------------------------------------------------------------------------
// クライアントの capturer を停止する
// ---------------------------------------------------------------------------

static void stop_client_capturers(SoraSdkPlugin* self, int64_t client_id) {
  if (!self->context) {
    return;
  }
  auto it = self->context->client_capturers.find(client_id);
  if (it == self->context->client_capturers.end()) {
    return;
  }
  for (auto source : it->second) {
    auto cap_it = self->context->capturers.find(source);
    if (cap_it != self->context->capturers.end()) {
      cap_it->second->Stop();
      self->context->capturers.erase(cap_it);
    }
  }
  self->context->client_capturers.erase(it);
}

// ---------------------------------------------------------------------------
// MethodChannel ハンドラ
// ---------------------------------------------------------------------------

static void sora_sdk_plugin_handle_method_call(SoraSdkPlugin* self,
                                                FlMethodCall* method_call) {
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(GError) error = nullptr;

  // --- createClient ---
  if (strcmp(method, "createClient") == 0) {
    int64_t client_id = self->next_client_id++;
    gchar event_channel_name[64];
    snprintf(event_channel_name, sizeof(event_channel_name),
             "sora_sdk/event/%" PRId64, client_id);

    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    FlEventChannel* event_channel = fl_event_channel_new(
        self->messenger, event_channel_name, FL_METHOD_CODEC(codec));

    auto* client = static_cast<SoraClient*>(g_malloc(sizeof(SoraClient)));
    client->client_id = client_id;
    client->event_channel = event_channel;
    client->listen_handler = sora_event_listen_cb;
    client->cancel_handler = sora_event_cancel_cb;
    client->is_streaming = false;

    g_hash_table_insert(self->clients,
                        GSIZE_TO_POINTER(static_cast<gsize>(client_id)), client);

    fl_event_channel_set_stream_handlers(
        event_channel, sora_event_listen_cb, sora_event_cancel_cb, client,
        nullptr);

    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "clientId",
                             fl_value_new_int(client_id));
    fl_value_set_string_take(result, "eventChannelName",
                             fl_value_new_string(event_channel_name));
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- disposeClient ---
  if (strcmp(method, "disposeClient") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    FlValue* client_id_val = nullptr;
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      client_id_val = fl_value_lookup_string(args, "clientId");
    }
    if (client_id_val == nullptr ||
        fl_value_get_type(client_id_val) != FL_VALUE_TYPE_INT) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                   "clientId is required.", nullptr, &error);
      return;
    }
    int64_t client_id = fl_value_get_int(client_id_val);
    gpointer key = GSIZE_TO_POINTER(static_cast<gsize>(client_id));

    // このクライアントに関連する capturer を停止する
    stop_client_capturers(self, client_id);

    if (g_hash_table_lookup(self->clients, key) == nullptr) {
      fl_method_call_respond_error(method_call, "client_not_found",
                                   "Client not found.", nullptr, &error);
      return;
    }
    g_hash_table_remove(self->clients, key);
    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }

  // --- enumerateVideoInputDevices ---
  if (strcmp(method, "enumerateVideoInputDevices") == 0) {
    FlValue* result = SoraCameraCapturer::EnumerateDevices();
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- enumerateAudioInputDevices ---
  if (strcmp(method, "enumerateAudioInputDevices") == 0) {
    g_autoptr(FlValue) result = fl_value_new_list();
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- enumerateAudioOutputDevices ---
  if (strcmp(method, "enumerateAudioOutputDevices") == 0) {
    g_autoptr(FlValue) result = fl_value_new_list();
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- getVideoInputFormats ---
  if (strcmp(method, "getVideoInputFormats") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    std::string device_id =
        get_string_from_map(args, "deviceId", "");
    if (device_id.empty()) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                   "deviceId is required.", nullptr, &error);
      return;
    }
    FlValue* result = SoraCameraCapturer::GetFormats(device_id);
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- ensureLocalVideoTrackTexture ---
  if (strcmp(method, "ensureLocalVideoTrackTexture") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                   "Arguments are required.", nullptr, &error);
      return;
    }

    int64_t video_source_ptr =
        get_int64_from_map(args, "videoSourcePtr", 0);
    if (video_source_ptr == 0) {
      fl_method_call_respond_error(
          method_call, "invalid_argument",
          "videoSourcePtr must be a non-zero integer.", nullptr, &error);
      return;
    }

    int64_t client_id = get_int64_from_map(args, "clientId", 0);
    std::string device_id =
        get_string_from_map(args, "videoDeviceId", "");
    int width = static_cast<int>(get_int64_from_map(args, "videoWidth", 640));
    int height = static_cast<int>(get_int64_from_map(args, "videoHeight", 480));
    int fps = static_cast<int>(get_int64_from_map(args, "videoFrameRate", 30));

    if (width <= 0) width = 640;
    if (height <= 0) height = 480;
    if (fps <= 0) fps = 30;

    if (!self->context) {
      fl_method_call_respond_error(method_call, "internal_error",
                                   "Plugin context not initialized.", nullptr,
                                   &error);
      return;
    }

    auto capturer = std::make_unique<SoraCameraCapturer>(
        device_id, width, height, fps, self->texture_registrar);
    capturer->SetVideoSourcePtr(
        reinterpret_cast<void*>(static_cast<intptr_t>(video_source_ptr)));

    if (client_id > 0) {
      gpointer key = GSIZE_TO_POINTER(static_cast<gsize>(client_id));
      auto* client = static_cast<SoraClient*>(
          g_hash_table_lookup(self->clients, key));
      if (client) {
        // エラーコールバックは EventChannel の sendEvent に相当する実装が必要だが、
        // Linux では未対応のため省略する。必要に応じて後続 issue で対応する。
        (void)client;
      }
    }

    if (client_id > 0) {
      self->context->client_capturers[client_id].insert(video_source_ptr);
    }

    capturer->Start();
    int64_t texture_id = capturer->preview_texture_id();
    self->context->capturers[video_source_ptr] = std::move(capturer);

    g_autoptr(FlValue) response = fl_value_new_map();
    fl_value_set_string_take(response, "textureId",
                             fl_value_new_int(texture_id));
    fl_method_call_respond_success(method_call, response, &error);
    return;
  }

  // --- disposeLocalVideoTrackTexture ---
  if (strcmp(method, "disposeLocalVideoTrackTexture") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_success(method_call, nullptr, &error);
      return;
    }
    int64_t video_source_ptr =
        get_int64_from_map(args, "videoSourcePtr", 0);

    if (self->context) {
      auto it = self->context->capturers.find(video_source_ptr);
      if (it != self->context->capturers.end()) {
        it->second->Stop();
        self->context->capturers.erase(it);
      }

      // client_capturers からも削除する
      for (auto& pair : self->context->client_capturers) {
        pair.second.erase(video_source_ptr);
      }
    }

    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }

  // --- stopCameraCapturer ---
  if (strcmp(method, "stopCameraCapturer") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_success(method_call, nullptr, &error);
      return;
    }
    int64_t video_source_ptr =
        get_int64_from_map(args, "videoSourcePtr", 0);

    if (self->context) {
      auto it = self->context->capturers.find(video_source_ptr);
      if (it != self->context->capturers.end()) {
        it->second->Stop();
      }
    }

    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }

  // --- 未実装メソッドは FlMethodNotImplemented を返す ---
  fl_method_call_respond_not_implemented(method_call, &error);
}

// ---------------------------------------------------------------------------
// GObject lifecycle
// ---------------------------------------------------------------------------

static void sora_sdk_plugin_dispose(GObject* object) {
  auto* self = SORA_SDK_PLUGIN(object);

  // 全 capturer を停止する
  if (self->context) {
    for (auto& pair : self->context->capturers) {
      pair.second->Stop();
    }
    self->context->capturers.clear();
    self->context->client_capturers.clear();
    delete self->context;
    self->context = nullptr;
  }

  if (self->texture_registrar != nullptr) {
    g_object_unref(self->texture_registrar);
    self->texture_registrar = nullptr;
  }

  if (self->clients != nullptr) {
    g_hash_table_unref(self->clients);
    self->clients = nullptr;
  }
  if (self->messenger != nullptr) {
    g_object_unref(self->messenger);
    self->messenger = nullptr;
  }
  G_OBJECT_CLASS(sora_sdk_plugin_parent_class)->dispose(object);
}

static void sora_sdk_plugin_class_init(SoraSdkPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = sora_sdk_plugin_dispose;
}

static void sora_sdk_plugin_init(SoraSdkPlugin* self) {
  self->messenger = nullptr;
  self->texture_registrar = nullptr;
  self->clients = g_hash_table_new_full(g_direct_hash, g_direct_equal,
                                        nullptr, sora_client_free);
  self->next_client_id = 1;
  self->context = new SoraSdkPluginContext();
}

// ---------------------------------------------------------------------------
// MethodChannel callback
// ---------------------------------------------------------------------------

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  auto* plugin = SORA_SDK_PLUGIN(user_data);
  sora_sdk_plugin_handle_method_call(plugin, method_call);
}

// ---------------------------------------------------------------------------
// プラグイン登録エントリポイント
// ---------------------------------------------------------------------------

__attribute__((visibility("default"))) void
sora_sdk_plugin_register_with_registrar(FlPluginRegistrar* registrar) {
  auto* plugin = SORA_SDK_PLUGIN(
      g_object_new(sora_sdk_plugin_get_type(), nullptr));
  plugin->messenger =
      FL_BINARY_MESSENGER(g_object_ref(fl_plugin_registrar_get_messenger(registrar)));
  plugin->texture_registrar = FL_TEXTURE_REGISTRAR(
      g_object_ref(fl_plugin_registrar_get_texture_registrar(registrar)));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "sora_sdk/method", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
