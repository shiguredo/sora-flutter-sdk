#include "include/sora_sdk/sora_sdk_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <inttypes.h>

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
// SoraSdkPlugin: GObject プラグインインスタンス
// ---------------------------------------------------------------------------

struct _SoraSdkPlugin {
  GObject parent_instance;
  FlBinaryMessenger* messenger;
  GHashTable* clients;
  int64_t next_client_id;
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

    // EventChannel を作成する
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
    g_autoptr(FlValue) result = fl_value_new_list();
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
    g_autoptr(FlValue) result = fl_value_new_list();
    fl_method_call_respond_success(method_call, result, &error);
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
  self->clients = g_hash_table_new_full(g_direct_hash, g_direct_equal,
                                        nullptr, sora_client_free);
  self->next_client_id = 1;
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

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel =
      fl_method_channel_new(fl_plugin_registrar_get_messenger(registrar),
                            "sora_sdk/method", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, g_object_ref(plugin), g_object_unref);

  g_object_unref(plugin);
}
