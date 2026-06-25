#include "include/sora_sdk/sora_sdk_plugin.h"

#include <flutter_linux/flutter_linux.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <inttypes.h>
#include <map>
#include <memory>
#include <set>

#include "sora_audio_devices.h"
#include "sora_camera_capturer.h"

// ---------------------------------------------------------------------------
// C ブリッジのレンダリングシンク API 宣言
// ---------------------------------------------------------------------------

extern "C" {
struct LinuxRenderingSink;
struct LinuxRenderingSink* linux_rendering_sink_create(void);
void linux_rendering_sink_set_frame_callback(
    struct LinuxRenderingSink* sink,
    void (*callback)(void*),
    void* context);
void* linux_rendering_sink_get_sink_ptr(struct LinuxRenderingSink* sink);
const uint8_t* linux_rendering_sink_copy_pixels(
    struct LinuxRenderingSink* sink,
    uint32_t* out_width,
    uint32_t* out_height);
void linux_rendering_sink_delete(struct LinuxRenderingSink* sink);
}

// ---------------------------------------------------------------------------
// SoraRemoteVideoTexture: FlPixelBufferTexture の GObject サブクラス
// ---------------------------------------------------------------------------

typedef struct _SoraRemoteVideoTexture SoraRemoteVideoTexture;
struct _SoraRemoteVideoTexture {
  FlPixelBufferTexture parent_instance;
  struct LinuxRenderingSink* sink;
};

#define SORA_TYPE_REMOTE_VIDEO_TEXTURE sora_remote_video_texture_get_type()
G_DECLARE_FINAL_TYPE(SoraRemoteVideoTexture,
                     sora_remote_video_texture,
                     SORA,
                     REMOTE_VIDEO_TEXTURE,
                     FlPixelBufferTexture)

static gboolean sora_remote_video_texture_copy_pixels(
    FlPixelBufferTexture* texture,
    const uint8_t** out_buffer,
    uint32_t* width,
    uint32_t* height,
    GError** error) {
  (void)error;
  auto* self = SORA_REMOTE_VIDEO_TEXTURE(texture);
  if (!self->sink) {
    return FALSE;
  }
  const uint8_t* pixels =
      linux_rendering_sink_copy_pixels(self->sink, width, height);
  if (!pixels) {
    return FALSE;
  }
  *out_buffer = pixels;
  return TRUE;
}

G_DEFINE_TYPE(SoraRemoteVideoTexture,
              sora_remote_video_texture,
              fl_pixel_buffer_texture_get_type())

static void sora_remote_video_texture_init(SoraRemoteVideoTexture* self) {
  self->sink = nullptr;
}

static void sora_remote_video_texture_class_init(
    SoraRemoteVideoTextureClass* klass) {
  FlPixelBufferTextureClass* fb_klass =
      reinterpret_cast<FlPixelBufferTextureClass*>(klass);
  fb_klass->copy_pixels = sora_remote_video_texture_copy_pixels;
}

// ---------------------------------------------------------------------------
// RemoteVideoRendererEntry: リモートビデオレンダラーの管理構造体
// ---------------------------------------------------------------------------

struct RemoteVideoRendererEntry {
  SoraRemoteVideoTexture* texture;
  struct LinuxRenderingSink* sink;
  FlTextureRegistrar* registrar;
};

// ---------------------------------------------------------------------------
// SoraClient: EventChannel を保持するクライアント単位のコンテキスト
// ---------------------------------------------------------------------------

struct SoraClient {
  int64_t client_id;
  FlEventChannel* event_channel;
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
  // client_id -> renderer_id -> RemoteVideoRendererEntry
  std::map<int64_t, std::map<int64_t, RemoteVideoRendererEntry>>
      client_renderers;
  // リモートレンダラーの ID 採番用
  int64_t next_renderer_id = 1;
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

// ---------------------------------------------------------------------------
// リモートレンダラーエントリの解放ヘルパー
// ---------------------------------------------------------------------------

static void release_remote_video_renderer_entry(
    SoraSdkPlugin* self,
    RemoteVideoRendererEntry& entry) {
  if (entry.texture && self->texture_registrar) {
    fl_texture_registrar_unregister_texture(
        self->texture_registrar, FL_TEXTURE(entry.texture));
    entry.texture->sink = nullptr;
    g_object_unref(entry.texture);
  }
  if (entry.sink) {
    linux_rendering_sink_delete(entry.sink);
  }
}

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
// クライアントのリモートレンダラーを停止する
// ---------------------------------------------------------------------------

static void stop_client_renderers(SoraSdkPlugin* self, int64_t client_id) {
  if (!self->context) {
    return;
  }
  auto it = self->context->client_renderers.find(client_id);
  if (it == self->context->client_renderers.end()) {
    return;
  }
  for (auto& [renderer_id, entry] : it->second) {
    release_remote_video_renderer_entry(self, entry);
  }
  self->context->client_renderers.erase(it);
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
    // このクライアントに関連するリモートレンダラーを停止する
    stop_client_renderers(self, client_id);

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
    FlValue* result = SoraAudioDevices::EnumerateInputDevices();
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- enumerateAudioOutputDevices ---
  if (strcmp(method, "enumerateAudioOutputDevices") == 0) {
    FlValue* result = SoraAudioDevices::EnumerateOutputDevices();
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- getDefaultAudioInputDevice ---
  if (strcmp(method, "getDefaultAudioInputDevice") == 0) {
    std::string device_id = SoraAudioDevices::GetDefaultInputDeviceId();
    if (device_id.empty()) {
      fl_method_call_respond_error(method_call, "device_not_found",
                                   "Default audio input device not found.",
                                   nullptr, &error);
      return;
    }
    g_autoptr(FlValue) result = fl_value_new_string(device_id.c_str());
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

    // カメラキャプチャのエラーをクライアントに通知するコールバックを設定する
    if (client_id > 0) {
      gpointer key = GSIZE_TO_POINTER(static_cast<gsize>(client_id));
      auto* client = static_cast<SoraClient*>(
          g_hash_table_lookup(self->clients, key));
      if (client && client->event_channel) {
        capturer->SetOnCameraOpenErrorCallback(
            [channel = client->event_channel,
             streaming_ptr = &client->is_streaming]
            (CameraOpenError error_code) {
              if (!*streaming_ptr) {
                return;
              }
              FlValue* event = fl_value_new_map();
              fl_value_set_string_take(
                  event, "type",
                  fl_value_new_string("camera_open_error"));
              fl_value_set_string_take(
                  event, "errorCode",
                  fl_value_new_int(static_cast<int>(error_code)));
              g_autoptr(GError) send_error = nullptr;
              fl_event_channel_send(channel, event, nullptr, &send_error);
            });
      }
    }

    if (client_id > 0) {
      self->context->client_capturers[client_id].insert(video_source_ptr);
    }

    capturer->Start();
    int64_t texture_id = capturer->preview_texture_id();
    if (texture_id < 0) {
      // テクスチャ登録に失敗した場合は capturer を破棄してエラーを返す。
      // client_capturers に追加済みのエントリも削除する。
      capturer->Stop();
      if (client_id > 0) {
        self->context->client_capturers[client_id].erase(video_source_ptr);
      }
      fl_method_call_respond_error(method_call, "capture_start_failed",
                                   "Failed to start camera capture.", nullptr,
                                   &error);
      return;
    }
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

  // --- createRemoteVideoRenderer ---
  if (strcmp(method, "createRemoteVideoRenderer") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                    "Arguments are required.", nullptr, &error);
      return;
    }
    int64_t client_id = get_int64_from_map(args, "clientId", 0);
    if (client_id == 0) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                    "clientId is required.", nullptr, &error);
      return;
    }

    gpointer key = GSIZE_TO_POINTER(static_cast<gsize>(client_id));
    auto* client = static_cast<SoraClient*>(
        g_hash_table_lookup(self->clients, key));
    if (client == nullptr) {
      fl_method_call_respond_error(method_call, "client_not_found",
                                    "Client not found.", nullptr, &error);
      return;
    }

    if (!self->context || !self->texture_registrar) {
      fl_method_call_respond_error(method_call, "internal_error",
                                    "Plugin not initialized.", nullptr, &error);
      return;
    }

    // C ブリッジでレンダリングシンクを作成する
    LinuxRenderingSink* sink = linux_rendering_sink_create();
    if (sink == nullptr) {
      fl_method_call_respond_error(method_call, "renderer_create_failed",
                                    "Failed to create rendering sink.", nullptr,
                                    &error);
      return;
    }

    // FlPixelBufferTexture を作成してテクスチャ登録する
    SoraRemoteVideoTexture* tex = SORA_REMOTE_VIDEO_TEXTURE(
        g_object_new(SORA_TYPE_REMOTE_VIDEO_TEXTURE, nullptr));
    tex->sink = sink;

    gboolean registered = fl_texture_registrar_register_texture(
        self->texture_registrar, FL_TEXTURE(tex));
    if (!registered) {
      tex->sink = nullptr;
      g_object_unref(tex);
      linux_rendering_sink_delete(sink);
      fl_method_call_respond_error(method_call, "texture_register_failed",
                                    "Failed to register texture.", nullptr,
                                    &error);
      return;
    }
    int64_t texture_id = fl_texture_get_id(FL_TEXTURE(tex));

    // 登録エントリを作成する
    int64_t renderer_id = self->context->next_renderer_id++;
    RemoteVideoRendererEntry entry;
    entry.texture = tex;
    entry.sink = sink;
    entry.registrar = self->texture_registrar;

    self->context->client_renderers[client_id][renderer_id] = entry;

    // フレーム到着時にテクスチャ更新を通知するコールバックを設定する
    linux_rendering_sink_set_frame_callback(
        sink,
        [](void* context) {
          auto* e =
              static_cast<RemoteVideoRendererEntry*>(context);
          if (e && e->registrar && e->texture) {
            fl_texture_registrar_mark_texture_frame_available(
                e->registrar, FL_TEXTURE(e->texture));
          }
        },
        &self->context->client_renderers[client_id][renderer_id]);

    // VideoSinkInterface のポインタを取得する
    void* video_sink_ptr = linux_rendering_sink_get_sink_ptr(sink);

    g_autoptr(FlValue) result = fl_value_new_map();
    fl_value_set_string_take(result, "rendererId",
                             fl_value_new_int(renderer_id));
    fl_value_set_string_take(result, "renderingSinkPtr",
                             fl_value_new_int(
                                 static_cast<int64_t>(
                                     reinterpret_cast<intptr_t>(sink))));
    fl_value_set_string_take(result, "videoSinkPtr",
                             fl_value_new_int(
                                 static_cast<int64_t>(
                                     reinterpret_cast<intptr_t>(
                                         video_sink_ptr))));
    fl_value_set_string_take(result, "textureId",
                             fl_value_new_int(texture_id));
    fl_method_call_respond_success(method_call, result, &error);
    return;
  }

  // --- disposeRemoteVideoRenderer ---
  if (strcmp(method, "disposeRemoteVideoRenderer") == 0) {
    FlValue* args = fl_method_call_get_args(method_call);
    if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      fl_method_call_respond_error(method_call, "invalid_argument",
                                    "Arguments are required.", nullptr, &error);
      return;
    }
    int64_t client_id = get_int64_from_map(args, "clientId", 0);
    int64_t renderer_id = get_int64_from_map(args, "rendererId", 0);
    if (client_id == 0 || renderer_id == 0) {
      fl_method_call_respond_error(
          method_call, "invalid_argument",
          "clientId and rendererId are required.", nullptr, &error);
      return;
    }

    if (!self->context) {
      fl_method_call_respond_error(method_call, "internal_error",
                                    "Plugin context not initialized.", nullptr,
                                    &error);
      return;
    }

    auto client_it =
        self->context->client_renderers.find(client_id);
    if (client_it == self->context->client_renderers.end()) {
      fl_method_call_respond_error(method_call, "renderer_not_found",
                                    "Renderer not found.", nullptr, &error);
      return;
    }

    auto renderer_it = client_it->second.find(renderer_id);
    if (renderer_it == client_it->second.end()) {
      fl_method_call_respond_error(method_call, "renderer_not_found",
                                    "Renderer not found.", nullptr, &error);
      return;
    }

    RemoteVideoRendererEntry& entry = renderer_it->second;
    release_remote_video_renderer_entry(self, entry);
    client_it->second.erase(renderer_it);

    fl_method_call_respond_success(method_call, nullptr, &error);
    return;
  }

  // --- 未実装メソッドは FlMethodNotImplemented を返す ---
  fl_method_call_respond_not_implemented(method_call, &error);
}

// ---------------------------------------------------------------------------
// GObject ライフサイクル
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

    // 全リモートレンダラーを停止する
    for (auto& [client_id, renderers] : self->context->client_renderers) {
      for (auto& [renderer_id, entry] : renderers) {
        release_remote_video_renderer_entry(self, entry);
      }
    }
    self->context->client_renderers.clear();

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
// MethodChannel コールバック
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
