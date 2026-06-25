#include "sora_audio_devices.h"

#include <pulse/pulseaudio.h>

#include <cstring>
#include <functional>

// PulseAudio の非同期処理を同期的に完了させるための汎用コンテキスト。
// pa_mainloop_iterate で全イベントを処理し、コールバックが完了フラグを立てるまで待つ。
template <typename T>
struct PulseSyncContext {
  T data;
  bool done = false;
};

namespace {

// コンテキストの状態が PA_CONTEXT_READY になるまでメインループを回す。
// 接続失敗または接続拒否された場合は false を返す。
bool WaitForContextReady(pa_mainloop* mainloop, pa_context* ctx) {
  while (true) {
    pa_context_state_t state = pa_context_get_state(ctx);
    if (state == PA_CONTEXT_READY) {
      return true;
    }
    if (state == PA_CONTEXT_FAILED || state == PA_CONTEXT_TERMINATED) {
      return false;
    }
    pa_mainloop_iterate(mainloop, 1, nullptr);
  }
}

// 入力デバイス (ソース) を列挙するコールバック。
// モニタソース (スピーカー出力をループバックするもの) は除外する。
void EnumerateSourcesCallback(pa_context* /*ctx*/,
                              const pa_source_info* info,
                              int eol,
                              void* userdata) {
  auto* ctx = static_cast<PulseSyncContext<FlValue*>*>(userdata);
  if (eol) {
    ctx->done = true;
    return;
  }
  // monitor_of_sink が PA_INVALID_INDEX 以外のソースは
  // スピーカー出力をループバックするモニタソースなので除外する。
  if (info->monitor_of_sink != PA_INVALID_INDEX) {
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "deviceId",
                           fl_value_new_string(info->name));
  fl_value_set_string_take(map, "label",
                           fl_value_new_string(info->description));
  fl_value_append(ctx->data, map);
}

// 出力デバイス (シンク) を列挙するコールバック。
void EnumerateSinksCallback(pa_context* /*ctx*/,
                            const pa_sink_info* info,
                            int eol,
                            void* userdata) {
  auto* ctx = static_cast<PulseSyncContext<FlValue*>*>(userdata);
  if (eol) {
    ctx->done = true;
    return;
  }
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "deviceId",
                           fl_value_new_string(info->name));
  fl_value_set_string_take(map, "label",
                           fl_value_new_string(info->description));
  fl_value_append(ctx->data, map);
}

// サーバー情報を取得するコールバック。
// 既定ソース名を文字列として取り出す。
void ServerInfoCallback(pa_context* /*ctx*/,
                        const pa_server_info* info,
                        void* userdata) {
  auto* ctx = static_cast<PulseSyncContext<std::string>*>(userdata);
  ctx->data = std::string(info->default_source_name ? info->default_source_name
                                                     : "");
  ctx->done = true;
}

// PulseAudio の mainloop と context の RAII ラッパー。
class PulseConnection {
 public:
  PulseConnection() {
    mainloop_ = pa_mainloop_new();
    if (!mainloop_) {
      return;
    }
    auto* api = pa_mainloop_get_api(mainloop_);
    ctx_ = pa_context_new(api, "sora_sdk");
    if (!ctx_) {
      pa_mainloop_free(mainloop_);
      mainloop_ = nullptr;
      return;
    }
    pa_context_set_state_callback(
        ctx_,
        [](pa_context*, void*) {
          // 状態変更を検知するための空コールバック。
          // pa_mainloop_iterate の戻り値でループを継続させるために必要。
        },
        nullptr);
    int ret = pa_context_connect(ctx_, nullptr, PA_CONTEXT_NOFLAGS, nullptr);
    if (ret < 0) {
      pa_context_unref(ctx_);
      pa_mainloop_free(mainloop_);
      ctx_ = nullptr;
      mainloop_ = nullptr;
      return;
    }
    ready_ = WaitForContextReady(mainloop_, ctx_);
  }

  ~PulseConnection() {
    if (ctx_) {
      pa_context_disconnect(ctx_);
      pa_context_unref(ctx_);
    }
    if (mainloop_) {
      pa_mainloop_free(mainloop_);
    }
  }

  PulseConnection(const PulseConnection&) = delete;
  PulseConnection& operator=(const PulseConnection&) = delete;

  bool IsReady() const { return ready_; }

  pa_context* context() const { return ctx_; }
  pa_mainloop* mainloop() const { return mainloop_; }

  // done になるまでメインループを回すヘルパー。
  template <typename T>
  void RunUntilDone(PulseSyncContext<T>* sync_ctx) {
    while (!sync_ctx->done) {
      pa_mainloop_iterate(mainloop_, 1, nullptr);
    }
  }

 private:
  pa_mainloop* mainloop_ = nullptr;
  pa_context* ctx_ = nullptr;
  bool ready_ = false;
};

}  // namespace

FlValue* SoraAudioDevices::EnumerateInputDevices() {
  PulseSyncContext<FlValue*> sync_ctx;
  sync_ctx.data = fl_value_new_list();

  PulseConnection conn;
  if (!conn.IsReady()) {
    return sync_ctx.data;
  }

  pa_operation* op = pa_context_get_source_info_list(
      conn.context(), EnumerateSourcesCallback, &sync_ctx);
  if (!op) {
    return sync_ctx.data;
  }
  pa_operation_unref(op);

  conn.RunUntilDone(&sync_ctx);
  return sync_ctx.data;
}

FlValue* SoraAudioDevices::EnumerateOutputDevices() {
  PulseSyncContext<FlValue*> sync_ctx;
  sync_ctx.data = fl_value_new_list();

  PulseConnection conn;
  if (!conn.IsReady()) {
    return sync_ctx.data;
  }

  pa_operation* op = pa_context_get_sink_info_list(
      conn.context(), EnumerateSinksCallback, &sync_ctx);
  if (!op) {
    return sync_ctx.data;
  }
  pa_operation_unref(op);

  conn.RunUntilDone(&sync_ctx);
  return sync_ctx.data;
}

std::string SoraAudioDevices::GetDefaultInputDeviceId() {
  PulseSyncContext<std::string> sync_ctx;

  PulseConnection conn;
  if (!conn.IsReady()) {
    return "";
  }

  pa_operation* op = pa_context_get_server_info(
      conn.context(), ServerInfoCallback, &sync_ctx);
  if (!op) {
    return "";
  }
  pa_operation_unref(op);

  conn.RunUntilDone(&sync_ctx);
  return sync_ctx.data;
}
