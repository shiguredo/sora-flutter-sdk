#include "sora_audio_devices.h"

#include <pulse/pulseaudio.h>

namespace {

// PulseAudio の非同期処理を同期的に完了させるための汎用コンテキスト。
// pa_mainloop_iterate で全イベントを処理し、コールバックが完了フラグを立てるまで待つ。
template <typename T>
struct PulseSyncContext {
  T data{};
  bool done = false;
};

// NULL 安全な文字列取得ヘルパー。
// PulseAudio の info->description 等は NULL になりうるため、
// fl_value_new_string に渡す前に空文字列にフォールバックする。
const char* SafeStr(const char* s) {
  return s ? s : "";
}

// FlValue リストにデバイス情報のマップを追加するヘルパー。
void AppendDeviceToFlValueList(FlValue* list,
                               const char* device_id,
                               const char* label) {
  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "deviceId", fl_value_new_string(device_id));
  fl_value_set_string_take(map, "label", fl_value_new_string(label));
  fl_value_append(list, map);
}

// コンテキストの状態が PA_CONTEXT_READY になるまでメインループを回す。
// 接続失敗・接続拒否・タイムアウト (5 秒) の場合は false を返す。
bool WaitForContextReady(pa_mainloop* mainloop, pa_context* ctx) {
  constexpr gint64 kTimeoutUs = 5 * G_TIME_SPAN_SECOND;
  gint64 deadline = g_get_monotonic_time() + kTimeoutUs;
  while (true) {
    pa_context_state_t state = pa_context_get_state(ctx);
    if (state == PA_CONTEXT_READY) {
      return true;
    }
    if (state == PA_CONTEXT_FAILED || state == PA_CONTEXT_TERMINATED) {
      return false;
    }
    if (g_get_monotonic_time() >= deadline) {
      g_warning(
          "PulseAudio context did not become ready within %" G_GINT64_FORMAT
          " us",
          kTimeoutUs);
      return false;
    }
    pa_mainloop_iterate(mainloop, 1, nullptr);
  }
}

// PulseAudio の mainloop と context の RAII ラッパー。
class PulseConnection {
 public:
  PulseConnection() {
    mainloop_ = pa_mainloop_new();
    if (!mainloop_) {
      g_warning("PulseAudio pa_mainloop_new() failed");
      return;
    }
    auto* api = pa_mainloop_get_api(mainloop_);
    ctx_ = pa_context_new(api, "sora_sdk");
    if (!ctx_) {
      g_warning("PulseAudio pa_context_new() failed");
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
      g_warning("PulseAudio pa_context_connect() failed: ret=%d", ret);
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

  // done になるまでメインループを回す。最大 5 秒のタイムアウト付き。
  template <typename T>
  void RunUntilDone(PulseSyncContext<T>* sync_ctx) {
    constexpr gint64 kTimeoutUs = 5 * G_TIME_SPAN_SECOND;
    gint64 deadline = g_get_monotonic_time() + kTimeoutUs;
    while (!sync_ctx->done) {
      if (g_get_monotonic_time() >= deadline) {
        g_warning("PulseAudio operation timed out after %" G_GINT64_FORMAT
                  " us",
                  kTimeoutUs);
        break;
      }
      pa_mainloop_iterate(mainloop_, 1, nullptr);
    }
  }

 private:
  pa_mainloop* mainloop_ = nullptr;
  pa_context* ctx_ = nullptr;
  bool ready_ = false;
};

// 入力デバイス (ソース) を列挙するコールバック。
// モニタソース (スピーカー出力をループバックするもの) は除外する。
void EnumerateSourcesCallback(pa_context* /*ctx*/,
                              const pa_source_info* info,
                              int eol,
                              void* userdata) {
  auto* sync_ctx = static_cast<PulseSyncContext<FlValue*>*>(userdata);
  if (eol) {
    sync_ctx->done = true;
    return;
  }
  // monitor_of_sink が PA_INVALID_INDEX 以外のソースは
  // スピーカー出力をループバックするモニタソースなので除外する。
  if (info->monitor_of_sink != PA_INVALID_INDEX) {
    return;
  }
  AppendDeviceToFlValueList(sync_ctx->data, SafeStr(info->name),
                            SafeStr(info->description));
}

// 出力デバイス (シンク) を列挙するコールバック。
void EnumerateSinksCallback(pa_context* /*ctx*/,
                            const pa_sink_info* info,
                            int eol,
                            void* userdata) {
  auto* sync_ctx = static_cast<PulseSyncContext<FlValue*>*>(userdata);
  if (eol) {
    sync_ctx->done = true;
    return;
  }
  AppendDeviceToFlValueList(sync_ctx->data, SafeStr(info->name),
                            SafeStr(info->description));
}

// サーバー情報を取得するコールバック。
// 既定ソース名を文字列として取り出す。
void ServerInfoCallback(pa_context* /*ctx*/,
                        const pa_server_info* info,
                        void* userdata) {
  auto* sync_ctx = static_cast<PulseSyncContext<std::string>*>(userdata);
  sync_ctx->data =
      std::string(info->default_source_name ? info->default_source_name : "");
  sync_ctx->done = true;
}

// PulseAudio の列挙操作に共通する処理のテンプレート。
// start_fn で PulseAudio の列挙操作を開始し、完了を同期的に待つ。
// 接続失敗・操作発行失敗時は空リストを返し g_warning でログを残す。
template <typename PaCallback>
FlValue* EnumerateDevicesInternal(pa_operation* (*start_fn)(pa_context*,
                                                            PaCallback,
                                                            void*),
                                  PaCallback callback,
                                  const char* log_label) {
  PulseSyncContext<FlValue*> sync_ctx;
  sync_ctx.data = fl_value_new_list();

  PulseConnection conn;
  if (!conn.IsReady()) {
    g_warning("PulseAudio connection failed: unable to enumerate %s devices",
              log_label);
    return sync_ctx.data;
  }

  pa_operation* op = start_fn(conn.context(), callback, &sync_ctx);
  if (!op) {
    g_warning("PulseAudio operation failed: unable to enumerate %s devices",
              log_label);
    return sync_ctx.data;
  }
  pa_operation_unref(op);

  conn.RunUntilDone(&sync_ctx);
  return sync_ctx.data;
}

}  // namespace

FlValue* SoraAudioDevices::EnumerateInputDevices() {
  return EnumerateDevicesInternal(pa_context_get_source_info_list,
                                  EnumerateSourcesCallback, "input");
}

FlValue* SoraAudioDevices::EnumerateOutputDevices() {
  return EnumerateDevicesInternal(pa_context_get_sink_info_list,
                                  EnumerateSinksCallback, "output");
}

std::string SoraAudioDevices::GetDefaultInputDeviceId() {
  PulseSyncContext<std::string> sync_ctx;

  PulseConnection conn;
  if (!conn.IsReady()) {
    g_warning(
        "PulseAudio connection failed: unable to get default input device");
    return "";
  }

  pa_operation* op =
      pa_context_get_server_info(conn.context(), ServerInfoCallback, &sync_ctx);
  if (!op) {
    g_warning("PulseAudio pa_context_get_server_info() failed");
    return "";
  }
  pa_operation_unref(op);

  conn.RunUntilDone(&sync_ctx);
  return sync_ctx.data;
}
