// dart:ffi から参照される C API シンボルを提供する Linux 版 C ブリッジ。

#include <pthread.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <webrtc_c.h>
#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>
#include <webrtc_c/libyuv.h>
#include "sora_sdk/sora_video_constants.h"

// --- audio_device_module ---

__attribute__((visibility("default"))) struct webrtc_AudioDeviceModule_refcounted*
sora_create_audio_device_module(struct webrtc_Environment* env, int type) {
  (void)env;
  (void)type;
  // 未実装: 後続 issue で実装する
  return NULL;
}

// --- video_frame ---

__attribute__((visibility("default"))) struct webrtc_VideoFrame_unique*
sora_video_frame_create(struct webrtc_I420Buffer_refcounted* buffer,
                        int rotation,
                        int64_t timestamp_us,
                        uint32_t timestamp_rtp) {
  struct webrtc_VideoFrameBuilder_unique* builder_unique =
      webrtc_VideoFrameBuilder_new(
          (struct webrtc_VideoFrameBuffer_refcounted*)buffer);
  if (builder_unique == NULL) {
    return NULL;
  }

  struct webrtc_VideoFrameBuilder* builder =
      webrtc_VideoFrameBuilder_unique_get(builder_unique);
  webrtc_VideoFrameBuilder_set_rotation(builder, rotation);
  webrtc_VideoFrameBuilder_set_timestamp_us(builder, timestamp_us);
  webrtc_VideoFrameBuilder_set_timestamp_rtp(builder, timestamp_rtp);

  struct webrtc_VideoFrame_unique* frame =
      webrtc_VideoFrameBuilder_build(builder);
  webrtc_VideoFrameBuilder_unique_delete(builder_unique);
  return frame;
}

__attribute__((visibility("default"))) struct webrtc_VideoFrame*
sora_video_frame_unique_get(struct webrtc_VideoFrame_unique* frame) {
  return webrtc_VideoFrame_unique_get(frame);
}

__attribute__((visibility("default"))) void sora_video_frame_unique_delete(
    struct webrtc_VideoFrame_unique* frame) {
  webrtc_VideoFrame_unique_delete(frame);
}

// ===========================================================================
// リモートビデオレンダリング用構造体
// ===========================================================================

typedef void (*frame_available_fn)(void* context);

typedef struct LinuxRenderingSink {
  struct webrtc_VideoSinkInterface* sink;
  pthread_mutex_t lock;
  pthread_cond_t inflight_cond;
  int disposed;
  int inflight_count;
  /* I420 バッファ (最新フレーム) */
  struct webrtc_I420Buffer* i420_buffer;
  int32_t width;
  int32_t height;
  /* RGBA ピクセルバッファ */
  uint8_t* rgba_buffer;
  size_t rgba_buffer_size;
  /* フレーム通知コールバック */
  frame_available_fn on_frame_available;
  void* frame_callback_context;
} LinuxRenderingSink;

// ===========================================================================
// I420 回転ヘルパー
// ===========================================================================

/// I420 バッファを指定角度だけ回転させた新規バッファを返す。
/// rotation が 90/180/270 以外の場合は NULL を返す。
/// 成功時の戻り値は refcount=1 の新規バッファであり、呼び出し側で Release すること。
static struct webrtc_I420Buffer* create_rotated_i420_buffer(
    struct webrtc_I420Buffer* source,
    int rotation) {
  if (source == NULL)
    return NULL;
  if (rotation != 90 && rotation != 180 && rotation != 270) {
    return NULL;
  }

  int32_t src_width = webrtc_I420Buffer_width(source);
  int32_t src_height = webrtc_I420Buffer_height(source);
  int32_t dst_width =
      rotation == 90 || rotation == 270 ? src_height : src_width;
  int32_t dst_height =
      rotation == 90 || rotation == 270 ? src_width : src_height;

  struct webrtc_I420Buffer_refcounted* rotated_ref =
      webrtc_I420Buffer_Create(dst_width, dst_height);
  if (rotated_ref == NULL) {
    return NULL;
  }

  struct webrtc_I420Buffer* rotated =
      webrtc_I420Buffer_refcounted_get(rotated_ref);
  if (rotated == NULL) {
    // rotated_ref は借用ハンドル (WEBRTC_DECLARE_REFCOUNTED) であり
    // 専用の Release API が存在しないため解放不要。
    return NULL;
  }

  if (libyuv_I420Rotate(webrtc_I420Buffer_MutableDataY(source),
                        webrtc_I420Buffer_StrideY(source),
                        webrtc_I420Buffer_MutableDataU(source),
                        webrtc_I420Buffer_StrideU(source),
                        webrtc_I420Buffer_MutableDataV(source),
                        webrtc_I420Buffer_StrideV(source),
                        webrtc_I420Buffer_MutableDataY(rotated),
                        webrtc_I420Buffer_StrideY(rotated),
                        webrtc_I420Buffer_MutableDataU(rotated),
                        webrtc_I420Buffer_StrideU(rotated),
                        webrtc_I420Buffer_MutableDataV(rotated),
                        webrtc_I420Buffer_StrideV(rotated), src_width,
                        src_height, rotation) != 0) {
    webrtc_I420Buffer_Release(rotated);
    return NULL;
  }

  return rotated;
}

// ===========================================================================
// VideoSinkInterface コールバック
// ===========================================================================

static void on_linux_frame(const struct webrtc_VideoFrame* frame,
                           void* user_data) {
  LinuxRenderingSink* sink = (LinuxRenderingSink*)user_data;
  if (sink == NULL)
    return;

  if (pthread_mutex_lock(&sink->lock) != 0)
    return;
  if (sink->disposed) {
    pthread_mutex_unlock(&sink->lock);
    return;
  }

  struct webrtc_VideoFrameBuffer_refcounted* buffer_ref =
      webrtc_VideoFrame_video_frame_buffer(frame);
  if (buffer_ref == NULL) {
    pthread_mutex_unlock(&sink->lock);
    return;
  }
  struct webrtc_VideoFrameBuffer* frame_buffer =
      webrtc_VideoFrameBuffer_refcounted_get(buffer_ref);
  if (frame_buffer == NULL) {
    pthread_mutex_unlock(&sink->lock);
    return;
  }

  struct webrtc_I420Buffer_refcounted* i420_ref =
      webrtc_VideoFrameBuffer_ToI420(frame_buffer);
  webrtc_VideoFrameBuffer_Release(frame_buffer);

  struct webrtc_I420Buffer* source_buffer =
      i420_ref == NULL ? NULL : webrtc_I420Buffer_refcounted_get(i420_ref);
  if (source_buffer == NULL) {
    pthread_mutex_unlock(&sink->lock);
    return;
  }

  struct webrtc_I420Buffer* rotated_buffer = create_rotated_i420_buffer(
      source_buffer, webrtc_VideoFrame_rotation(frame));
  struct webrtc_I420Buffer* buffer = rotated_buffer;
  if (buffer == NULL) {
    buffer = source_buffer;
    webrtc_I420Buffer_AddRef(buffer);
  }

  int32_t w = webrtc_I420Buffer_width(buffer);
  int32_t h = webrtc_I420Buffer_height(buffer);

  /* 前の I420 バッファを解放する */
  if (sink->i420_buffer != NULL) {
    webrtc_I420Buffer_Release(sink->i420_buffer);
  }
  sink->i420_buffer = buffer;
  sink->width = w;
  sink->height = h;

  frame_available_fn cb = sink->on_frame_available;
  void* ctx = sink->frame_callback_context;
  if (cb != NULL) {
    sink->inflight_count++;
  }
  pthread_mutex_unlock(&sink->lock);

  /* source_buffer の解放（回転バッファを使った場合は不要） */
  if (source_buffer != NULL) {
    webrtc_I420Buffer_Release(source_buffer);
  }

  /* フレーム到着を通知する */
  if (cb != NULL) {
    cb(ctx);

    if (pthread_mutex_lock(&sink->lock) == 0) {
      sink->inflight_count--;
      pthread_cond_broadcast(&sink->inflight_cond);
      pthread_mutex_unlock(&sink->lock);
    }
  }
}

static void on_linux_discarded(void* user_data) {
  (void)user_data;
}

static void on_linux_destroy(void* user_data) {
  (void)user_data;
}

// ===========================================================================
// レンダリングシンク公開 API
// ===========================================================================

__attribute__((visibility("default"))) LinuxRenderingSink*
linux_rendering_sink_create(void) {
  LinuxRenderingSink* sink =
      (LinuxRenderingSink*)calloc(1, sizeof(LinuxRenderingSink));
  if (sink == NULL)
    return NULL;

  if (pthread_mutex_init(&sink->lock, NULL) != 0) {
    free(sink);
    return NULL;
  }
  if (pthread_cond_init(&sink->inflight_cond, NULL) != 0) {
    pthread_mutex_destroy(&sink->lock);
    free(sink);
    return NULL;
  }

  struct webrtc_VideoSinkInterface_cbs cbs;
  memset(&cbs, 0, sizeof(cbs));
  cbs.OnFrame = on_linux_frame;
  cbs.OnDiscardedFrame = on_linux_discarded;
  cbs.OnDestroy = on_linux_destroy;
  sink->sink = webrtc_VideoSinkInterface_new(&cbs, sink);
  if (sink->sink == NULL) {
    pthread_cond_destroy(&sink->inflight_cond);
    pthread_mutex_destroy(&sink->lock);
    free(sink);
    return NULL;
  }

  return sink;
}

__attribute__((visibility("default"))) void
linux_rendering_sink_set_frame_callback(LinuxRenderingSink* sink,
                                        frame_available_fn callback,
                                        void* context) {
  if (sink == NULL)
    return;
  if (pthread_mutex_lock(&sink->lock) != 0)
    return;
  sink->on_frame_available = callback;
  sink->frame_callback_context = context;
  pthread_mutex_unlock(&sink->lock);
}

__attribute__((visibility("default"))) void*
linux_rendering_sink_get_sink_ptr(LinuxRenderingSink* sink) {
  if (sink == NULL)
    return NULL;
  return (void*)sink->sink;
}

__attribute__((visibility("default"))) const uint8_t*
linux_rendering_sink_copy_pixels(LinuxRenderingSink* sink,
                                 uint32_t* out_width,
                                 uint32_t* out_height) {
  if (sink == NULL)
    return NULL;

  if (pthread_mutex_lock(&sink->lock) != 0)
    return NULL;
  if (sink->disposed || sink->i420_buffer == NULL) {
    pthread_mutex_unlock(&sink->lock);
    return NULL;
  }

  int32_t w = sink->width;
  int32_t h = sink->height;

  if (w <= 0 || h <= 0) {
    pthread_mutex_unlock(&sink->lock);
    return NULL;
  }

  /* 解像度が変わった場合は RGBA バッファを再確保する */
  size_t required_size = (size_t)w * h * 4;
  if (sink->rgba_buffer == NULL || sink->rgba_buffer_size < required_size) {
    uint8_t* new_buffer = (uint8_t*)realloc(sink->rgba_buffer, required_size);
    if (new_buffer == NULL) {
      pthread_mutex_unlock(&sink->lock);
      return NULL;
    }
    sink->rgba_buffer = new_buffer;
    sink->rgba_buffer_size = required_size;
  }

  /* I420 -> RGBA 変換 */
  libyuv_ConvertFromI420(
      webrtc_I420Buffer_MutableDataY(sink->i420_buffer),
      webrtc_I420Buffer_StrideY(sink->i420_buffer),
      webrtc_I420Buffer_MutableDataU(sink->i420_buffer),
      webrtc_I420Buffer_StrideU(sink->i420_buffer),
      webrtc_I420Buffer_MutableDataV(sink->i420_buffer),
      webrtc_I420Buffer_StrideV(sink->i420_buffer),
      sink->rgba_buffer, w * 4, w, h, SORA_LIBYUV_FOURCC_RGBA);

  *out_width = (uint32_t)w;
  *out_height = (uint32_t)h;
  const uint8_t* result = sink->rgba_buffer;
  pthread_mutex_unlock(&sink->lock);

  return result;
}

__attribute__((visibility("default"))) void linux_rendering_sink_delete(
    LinuxRenderingSink* sink) {
  if (sink == NULL)
    return;

  if (pthread_mutex_lock(&sink->lock) != 0)
    return;
  sink->disposed = 1;
  sink->on_frame_available = NULL;
  sink->frame_callback_context = NULL;
  while (sink->inflight_count > 0) {
    // pthread_cond_wait が失敗した場合でも mutex は保持されている。
    // inflight_count の変化がなければ再度待機することで安全性を保つ。
    if (pthread_cond_wait(&sink->inflight_cond, &sink->lock) != 0) {
      continue;
    }
  }

  if (sink->i420_buffer != NULL) {
    webrtc_I420Buffer_Release(sink->i420_buffer);
    sink->i420_buffer = NULL;
  }
  if (sink->rgba_buffer != NULL) {
    free(sink->rgba_buffer);
    sink->rgba_buffer = NULL;
    sink->rgba_buffer_size = 0;
  }
  pthread_mutex_unlock(&sink->lock);

  if (sink->sink != NULL) {
    webrtc_VideoSinkInterface_delete(sink->sink);
    sink->sink = NULL;
  }

  pthread_cond_destroy(&sink->inflight_cond);
  pthread_mutex_destroy(&sink->lock);
  free(sink);
}

// ===========================================================================
// Observer ブリッジ (未実装: 後続 issue で実装する)
// ===========================================================================

struct SoraObserverBridge;

__attribute__((visibility("default"))) struct SoraObserverBridge*
sora_observer_bridge_create(
    void* on_connection_change,
    void* on_ice_connection_change,
    void* on_ice_gathering_change,
    void* on_ice_candidate,
    void* on_track,
    void* on_remove_track,
    void* on_datachannel,
    void* on_debug,
    void* dart_user_data) {
  (void)on_connection_change;
  (void)on_ice_connection_change;
  (void)on_ice_gathering_change;
  (void)on_ice_candidate;
  (void)on_track;
  (void)on_remove_track;
  (void)on_datachannel;
  (void)on_debug;
  (void)dart_user_data;
  // 未実装: 後続 issue で実装する
  return NULL;
}

__attribute__((visibility("default"))) struct webrtc_PeerConnectionObserver*
sora_observer_bridge_get_observer(struct SoraObserverBridge* bridge) {
  (void)bridge;
  // 未実装: 後続 issue で実装する
  return NULL;
}

__attribute__((visibility("default"))) void sora_observer_bridge_destroy(
    struct SoraObserverBridge* bridge) {
  (void)bridge;
  // 未実装: 後続 issue で実装する
}

__attribute__((visibility("default"))) void* sora_observer_bridge_setup_dc(
    struct SoraObserverBridge* bridge,
    struct webrtc_DataChannelInterface* dc,
    void* on_state_change,
    void* on_message,
    void* dc_user_data) {
  (void)bridge;
  (void)dc;
  (void)on_state_change;
  (void)on_message;
  (void)dc_user_data;
  // 未実装: 後続 issue で実装する
  return NULL;
}

__attribute__((visibility("default"))) void sora_observer_bridge_destroy_dc(
    void* dc_context,
    struct webrtc_DataChannelInterface* dc) {
  (void)dc_context;
  (void)dc;
  // 未実装: 後続 issue で実装する
}
