/*
 * JNI ブリッジ + dart:ffi コールバックブリッジ
 *
 * 1. JNI_OnLoad / JNI_OnUnload (JNI 必須)
 * 2. カメラフレーム入力: DirectByteBuffer → AdaptedVideoTrackSource (JNI 必須)
 * 3. リモートビデオレンダリング: VideoSink → ANativeWindow (JNI 必須)
 * 4. PeerConnectionObserver コールバックブリッジ: C 側でデータを安全に抽出して Dart に渡す
 *    NativeCallable.listener はポインタの値だけコピーするため、
 *    WebRTC スレッドからのコールバックで渡される一時ポインタは
 *    Dart が処理する時点で解放済みになる。
 *    この問題を回避するため、C 側で同期的にデータを抽出・コピーし、
 *    malloc 確保したバッファや AddRef した refcounted ポインタを
 *    NativeCallable.listener 経由で Dart に渡す。
 */

#include <jni.h>
#include <android/log.h>
#include <android/native_window.h>
#include <android/native_window_jni.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <webrtc_c.h>
#include <webrtc_c/android.h>

#define LOG_TAG "sora_sdk"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

/* ---------------------------------------------------------------------------
 * リモートビデオレンダリング用構造体
 * --------------------------------------------------------------------------- */
typedef struct RenderingSink {
  ANativeWindow* window;
  struct webrtc_VideoSinkInterface* sink;
  pthread_mutex_t lock;
  pthread_cond_t inflight_cond;
  atomic_int ref_count;
  int disposed;
  int inflight_count;
} RenderingSink;

static jobject g_application_context = NULL;
// WebRTC の worker thread からも安全に呼べるよう、
// plugin 初期化時に helper class / method を global ref として保持する。
static jclass g_sora_audio_device_module_class = NULL;
static jmethodID g_sora_audio_device_module_create_method = NULL;

static struct webrtc_I420Buffer* create_rotated_i420_buffer(
    struct webrtc_I420Buffer* source,
    int rotation) {
  if (source == NULL) return NULL;
  if (rotation != 90 && rotation != 180 && rotation != 270) {
    return NULL;
  }

  int src_width = webrtc_I420Buffer_width(source);
  int src_height = webrtc_I420Buffer_height(source);
  int dst_width = rotation == 90 || rotation == 270 ? src_height : src_width;
  int dst_height = rotation == 90 || rotation == 270 ? src_width : src_height;

  struct webrtc_I420Buffer_refcounted* rotated_ref =
      webrtc_I420Buffer_Create(dst_width, dst_height);
  if (rotated_ref == NULL) {
    return NULL;
  }

  struct webrtc_I420Buffer* rotated =
      webrtc_I420Buffer_refcounted_get(rotated_ref);
  if (rotated == NULL) {
    return NULL;
  }

  if (libyuv_I420Rotate(
          webrtc_I420Buffer_MutableDataY(source),
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
          webrtc_I420Buffer_StrideV(rotated),
          src_width,
          src_height,
          rotation) != 0) {
    webrtc_I420Buffer_Release(rotated);
    return NULL;
  }

  return rotated;
}

static void release_render_buffer(struct webrtc_I420Buffer* source_buffer,
                                  struct webrtc_I420Buffer* rotated_buffer) {
  if (rotated_buffer != NULL) {
    webrtc_I420Buffer_Release(rotated_buffer);
  }
  if (source_buffer != NULL) {
    webrtc_I420Buffer_Release(source_buffer);
  }
}

/*
 * RenderingSink は WebRTC callback と JNI 呼び出しが並行して触るため、
 * destroy 開始後も lock 待ち中の呼び出しが安全に `disposed` を確認して
 * 抜けられるよう、オブジェクト寿命を明示的な ref_count で管理する。
 */
static void rendering_sink_add_ref(RenderingSink* rs) {
  atomic_fetch_add_explicit(&rs->ref_count, 1, memory_order_relaxed);
}

static void rendering_sink_release(RenderingSink* rs) {
  if (atomic_fetch_sub_explicit(&rs->ref_count, 1, memory_order_acq_rel) == 1) {
    pthread_cond_destroy(&rs->inflight_cond);
    pthread_mutex_destroy(&rs->lock);
    free(rs);
  }
}

/*
 * 描画処理の入口で lifetime ref と inflight を同時に確保する。
 * lock 待ち中のスレッドも ref_count には含まれるため、
 * delete 側が owner ref を手放してもオブジェクト本体は解放されない。
 */
static int rendering_sink_begin_use(RenderingSink* rs) {
  if (rs == NULL) return 0;

  rendering_sink_add_ref(rs);
  pthread_mutex_lock(&rs->lock);
  if (rs->disposed || rs->window == NULL) {
    pthread_mutex_unlock(&rs->lock);
    rendering_sink_release(rs);
    return 0;
  }
  rs->inflight_count++;
  pthread_mutex_unlock(&rs->lock);
  return 1;
}

static void rendering_sink_end_use(RenderingSink* rs) {
  if (rs == NULL) return;

  pthread_mutex_lock(&rs->lock);
  rs->inflight_count--;
  if (rs->disposed && rs->inflight_count == 0) {
    pthread_cond_signal(&rs->inflight_cond);
  }
  pthread_mutex_unlock(&rs->lock);
  rendering_sink_release(rs);
}

static struct webrtc_VideoFrame_unique* build_sora_video_frame(
    struct webrtc_I420Buffer_refcounted* buffer,
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

__attribute__((visibility("default")))
struct webrtc_VideoFrame_unique* sora_video_frame_create(
    struct webrtc_I420Buffer_refcounted* buffer,
    int rotation,
    int64_t timestamp_us,
    uint32_t timestamp_rtp) {
  return build_sora_video_frame(buffer, rotation, timestamp_us, timestamp_rtp);
}

__attribute__((visibility("default")))
struct webrtc_VideoFrame* sora_video_frame_unique_get(
    struct webrtc_VideoFrame_unique* frame) {
  return webrtc_VideoFrame_unique_get(frame);
}

__attribute__((visibility("default")))
void sora_video_frame_unique_delete(struct webrtc_VideoFrame_unique* frame) {
  webrtc_VideoFrame_unique_delete(frame);
}

__attribute__((visibility("default")))
struct webrtc_AudioDeviceModule_refcounted*
sora_android_create_audio_device_module(
    struct webrtc_Environment* webrtc_env) {
  if (webrtc_env == NULL) {
    LOGE("sora_android_create_audio_device_module: webrtc_env is null");
    return NULL;
  }
  if (g_application_context == NULL) {
    LOGE("sora_android_create_audio_device_module: application context is null");
    return NULL;
  }

  JNIEnv* env = webrtc_jni_AttachCurrentThreadIfNeeded();
  if (env == NULL) {
    LOGE("sora_android_create_audio_device_module: failed to attach thread");
    return NULL;
  }

  if (g_sora_audio_device_module_class == NULL ||
      g_sora_audio_device_module_create_method == NULL) {
    LOGE("sora_android_create_audio_device_module: helper class is not initialized");
    return NULL;
  }

  // worker thread 上では FindClass が app class loader を解決できないことがあるため、
  // 初期化時にキャッシュした helper を使って JavaAudioDeviceModule を生成する。
  jlong native_adm = (*env)->CallStaticLongMethod(
      env,
      g_sora_audio_device_module_class,
      g_sora_audio_device_module_create_method,
      g_application_context,
      (jlong)(intptr_t)webrtc_env);
  if ((*env)->ExceptionCheck(env)) {
    LOGE("sora_android_create_audio_device_module: helper method threw");
    (*env)->ExceptionClear(env);
    return NULL;
  }

  if (native_adm == 0) {
    LOGE("sora_android_create_audio_device_module: helper returned null");
    return NULL;
  }

  return (struct webrtc_AudioDeviceModule_refcounted*)(intptr_t)native_adm;
}

/**
* Java 側の `Image` から受け取った YUV 平面を、指定された `I420Buffer` に詰める
*
* Android の `YUV_420_888` は端末実装差があり、特に U/V 平面は
* `pixelStride != 1` になることがある。その場合、平面データは I420 のような
* 連続配置ではないため、`libyuv` にそのまま渡す前に SDK 側で 1 サンプルずつ
* 正規化する必要がある。
*/
static int copy_java_yuv_to_i420(
    JNIEnv* env,
    jobject yBuffer,
    jobject uBuffer,
    jobject vBuffer,
    jint width,
    jint height,
    jint yStride,
    jint uStride,
    jint vStride,
    jint yPixelStride,
    jint uPixelStride,
    jint vPixelStride,
    struct webrtc_I420Buffer* buffer) {
  uint8_t* src_y = (uint8_t*)(*env)->GetDirectBufferAddress(env, yBuffer);
  uint8_t* src_u = (uint8_t*)(*env)->GetDirectBufferAddress(env, uBuffer);
  uint8_t* src_v = (uint8_t*)(*env)->GetDirectBufferAddress(env, vBuffer);
  if (src_y == NULL || src_u == NULL || src_v == NULL) {
    return 0;
  }

  // 各平面のバッファ容量がコピーに必要な長さを満たすか検証する
  if (yStride <= 0 || uStride <= 0 || vStride <= 0 ||
      yPixelStride <= 0 || uPixelStride <= 0 || vPixelStride <= 0) {
    return 0;
  }
  jlong cap_y = (*env)->GetDirectBufferCapacity(env, yBuffer);
  jlong cap_u = (*env)->GetDirectBufferCapacity(env, uBuffer);
  jlong cap_v = (*env)->GetDirectBufferCapacity(env, vBuffer);
  if (cap_y < 0 || cap_u < 0 || cap_v < 0) return 0;

  jlong y_req = (jlong)(height - 1) * yStride + (jlong)(width - 1) * yPixelStride + 1;
  if (cap_y < y_req) return 0;

  int ch2 = ((int)height + 1) / 2;
  jlong u_req = (jlong)(ch2 - 1) * uStride + (jlong)((int)width / 2 - 1) * uPixelStride + 1;
  jlong v_req = (jlong)(ch2 - 1) * vStride + (jlong)((int)width / 2 - 1) * vPixelStride + 1;
  if (cap_u < u_req || cap_v < v_req) return 0;

  uint8_t* dst_y = webrtc_I420Buffer_MutableDataY(buffer);
  uint8_t* dst_u = webrtc_I420Buffer_MutableDataU(buffer);
  uint8_t* dst_v = webrtc_I420Buffer_MutableDataV(buffer);
  int dst_sy = webrtc_I420Buffer_StrideY(buffer);
  int dst_su = webrtc_I420Buffer_StrideU(buffer);
  int dst_sv = webrtc_I420Buffer_StrideV(buffer);

  int cy = (int)width < dst_sy ? (int)width : dst_sy;
  int cu = ((int)width / 2) < dst_su ? ((int)width / 2) : dst_su;
  int cv = ((int)width / 2) < dst_sv ? ((int)width / 2) : dst_sv;
  for (int r = 0; r < (int)height; r++) {
    uint8_t* src_row_y = src_y + r * (int)yStride;
    uint8_t* dst_row_y = dst_y + r * dst_sy;
    if ((int)yPixelStride == 1) {
      memcpy(dst_row_y, src_row_y, (size_t)cy);
    } else {
      for (int c = 0; c < cy; c++) {
        dst_row_y[c] = src_row_y[c * (int)yPixelStride];
      }
    }
  }

  int ch = ((int)height + 1) / 2;
  for (int r = 0; r < ch; r++) {
    uint8_t* src_row_u = src_u + r * (int)uStride;
    uint8_t* src_row_v = src_v + r * (int)vStride;
    uint8_t* dst_row_u = dst_u + r * dst_su;
    uint8_t* dst_row_v = dst_v + r * dst_sv;
    if ((int)uPixelStride == 1) {
      memcpy(dst_row_u, src_row_u, (size_t)cu);
    } else {
      for (int c = 0; c < cu; c++) {
        dst_row_u[c] = src_row_u[c * (int)uPixelStride];
      }
    }
    if ((int)vPixelStride == 1) {
      memcpy(dst_row_v, src_row_v, (size_t)cv);
    } else {
      for (int c = 0; c < cv; c++) {
        dst_row_v[c] = src_row_v[c * (int)vPixelStride];
      }
    }
  }

  return 1;
}

static void on_rendering_frame(const struct webrtc_VideoFrame* frame,
                                void* user_data) {
  RenderingSink* rs = (RenderingSink*)user_data;
  struct webrtc_VideoFrameBuffer_refcounted* buffer_ref = NULL;
  struct webrtc_VideoFrameBuffer* video_buffer = NULL;
  struct webrtc_I420Buffer_refcounted* i420_ref = NULL;
  struct webrtc_I420Buffer* source_buffer = NULL;
  struct webrtc_I420Buffer* rotated_buffer = NULL;
  struct webrtc_I420Buffer* buffer = NULL;
  int window_locked = 0;
  if (frame == NULL) {
    return;
  }

  if (!rendering_sink_begin_use(rs)) {
    return;
  }

  buffer_ref = webrtc_VideoFrame_video_frame_buffer(frame);
  if (buffer_ref == NULL) {
    rendering_sink_end_use(rs);
    return;
  }
  video_buffer = webrtc_VideoFrameBuffer_refcounted_get(buffer_ref);
  if (video_buffer != NULL) {
    i420_ref = webrtc_VideoFrameBuffer_ToI420(video_buffer);
    webrtc_VideoFrameBuffer_Release(video_buffer);
    video_buffer = NULL;
    if (i420_ref != NULL) {
      source_buffer = webrtc_I420Buffer_refcounted_get(i420_ref);
      if (source_buffer != NULL) {
        rotated_buffer =
            create_rotated_i420_buffer(source_buffer, webrtc_VideoFrame_rotation(frame));
        buffer = rotated_buffer != NULL ? rotated_buffer : source_buffer;
        int width = webrtc_I420Buffer_width(buffer);
        int height = webrtc_I420Buffer_height(buffer);

        if (width > 0 && height > 0) {
          ANativeWindow_setBuffersGeometry(rs->window, width, height,
                                            AHARDWAREBUFFER_FORMAT_R8G8B8A8_UNORM);
          ANativeWindow_Buffer window_buffer;
          if (ANativeWindow_lock(rs->window, &window_buffer, NULL) == 0) {
            window_locked = 1;

            static const uint32_t FOURCC_ABGR = 0x52474241;
            libyuv_ConvertFromI420(
                webrtc_I420Buffer_MutableDataY(buffer),
                webrtc_I420Buffer_StrideY(buffer),
                webrtc_I420Buffer_MutableDataU(buffer),
                webrtc_I420Buffer_StrideU(buffer),
                webrtc_I420Buffer_MutableDataV(buffer),
                webrtc_I420Buffer_StrideV(buffer),
                (uint8_t*)window_buffer.bits,
                window_buffer.stride * 4,
                width,
                height,
                FOURCC_ABGR);
          }
        }
      }
    }
  }

  if (window_locked) {
    ANativeWindow_unlockAndPost(rs->window);
  }
  if (i420_ref != NULL && source_buffer == NULL) {
    struct webrtc_I420Buffer* i420_buf = webrtc_I420Buffer_refcounted_get(i420_ref);
    if (i420_buf != NULL) {
      webrtc_I420Buffer_Release(i420_buf);
    }
  }
  release_render_buffer(source_buffer, rotated_buffer);
  rendering_sink_end_use(rs);
}

static void noop_destroy(void* user_data) { (void)user_data; }

/* ---------------------------------------------------------------------------
 * PeerConnectionObserver コールバックブリッジ
 *
 * Dart の NativeCallable.listener 関数ポインタを保持し、
 * WebRTC コールバックから同期的にデータを抽出して安全な形で Dart に渡す。
 *
 * Dart 側のコールバック型:
 * - on_connection_change: void(int32_t state, void*)
 * - on_ice_gathering_change: void(int32_t state, void*)
 * - on_ice_candidate_extracted: void(char* sdp, char* mid, int32_t mline_idx, void*)
 *   sdp と mid は malloc 確保。Dart 側で free すること。
 * - on_track_with_addref: void(refcounted_ptr transceiver, void*)
 *   transceiver は AddRef 済み。Dart 側で Release すること。
 * - on_remove_track_with_addref: void(refcounted_ptr receiver, void*)
 * - on_datachannel_with_addref: void(refcounted_ptr dc, void*)
 * - on_debug_message: void(char* message, void*)
 *   message は malloc 確保。Dart 側で free すること。
 * --------------------------------------------------------------------------- */

/* Dart 側のコールバック関数ポインタ型 */
typedef void (*dart_on_state_fn)(int32_t state, void* user_data);
typedef void (*dart_on_ice_candidate_fn)(
    char* sdp, char* mid, int32_t mline_index, void* user_data);
typedef void (*dart_on_track_fn)(void* track_ref, char* kind, char* track_id, void* user_data);
typedef void (*dart_on_remove_track_fn)(void* track_ref, char* kind, char* track_id, void* user_data);
typedef void (*dart_on_datachannel_fn)(void* dc_ref, char* label, void* user_data);
typedef void (*dart_on_debug_fn)(char* message, void* user_data);

typedef struct SoraObserverBridge {
  dart_on_state_fn on_connection_change;
  dart_on_state_fn on_ice_connection_change;
  dart_on_state_fn on_ice_gathering_change;
  dart_on_ice_candidate_fn on_ice_candidate;
  dart_on_track_fn on_track;
  dart_on_remove_track_fn on_remove_track;
  dart_on_datachannel_fn on_datachannel;
  dart_on_debug_fn on_debug;
  void* dart_user_data;

  /* C 側で管理するリソース */
  struct webrtc_PeerConnectionObserver* observer;

  /* インフライトコールバックの同期機構 */
  pthread_mutex_t lock;
  pthread_cond_t inflight_cond;
  int disposed;
  int inflight_count;
} SoraObserverBridge;

/* bridge のコールバックインフライトを開始する。
   破棄済みの場合は false を返し、呼び出し元は即座に return する。 */
static bool observer_bridge_begin_use(SoraObserverBridge* bridge) {
  pthread_mutex_lock(&bridge->lock);
  if (bridge->disposed) {
    pthread_mutex_unlock(&bridge->lock);
    return false;
  }
  bridge->inflight_count++;
  pthread_mutex_unlock(&bridge->lock);
  return true;
}

/* bridge のコールバックインフライトを終了し、
   破棄待ちがあれば cond_signal を発火する。 */
static void observer_bridge_end_use(SoraObserverBridge* bridge) {
  pthread_mutex_lock(&bridge->lock);
  bridge->inflight_count--;
  if (bridge->disposed && bridge->inflight_count == 0) {
    pthread_cond_signal(&bridge->inflight_cond);
  }
  pthread_mutex_unlock(&bridge->lock);
}

/* malloc で文字列をコピーする。Dart 側で free すること。 */
static char* strdup_safe(const char* src) {
  if (src == NULL) {
    char* empty = (char*)malloc(1);
    if (empty) empty[0] = '\0';
    return empty;
  }
  return strdup(src);
}

/* デバッグメッセージを Dart に送信する */
static void bridge_emit_debug(SoraObserverBridge* bridge, const char* msg) {
  if (bridge->on_debug) {
    bridge->on_debug(strdup_safe(msg), bridge->dart_user_data);
  }
}

/* --- PeerConnectionObserver コールバック実装 --- */

static void bridge_on_connection_change(
    webrtc_PeerConnectionInterface_PeerConnectionState new_state,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  if (bridge->on_connection_change) {
    bridge->on_connection_change((int32_t)new_state, bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_connection_change(
    webrtc_PeerConnectionInterface_IceConnectionState new_state,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  if (bridge->on_ice_connection_change) {
    bridge->on_ice_connection_change((int32_t)new_state, bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_gathering_change(
    webrtc_PeerConnectionInterface_IceGatheringState new_state,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  if (bridge->on_ice_gathering_change) {
    bridge->on_ice_gathering_change((int32_t)new_state, bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_candidate(const struct webrtc_IceCandidate* candidate,
                                     void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  if (bridge->on_ice_candidate == NULL) {
    observer_bridge_end_use(bridge);
    return;
  }

  /* SDP テキストを抽出する */
  struct std_string_unique* sdp = NULL;
  if (!webrtc_IceCandidate_ToString(candidate, &sdp)) {
    observer_bridge_end_use(bridge);
    return;
  }
  struct std_string_unique* sdp_mid = NULL;
  webrtc_IceCandidate_sdp_mid(candidate, &sdp_mid);
  int sdp_mline_index = webrtc_IceCandidate_sdp_mline_index(candidate);

  const char* sdp_cstr = std_string_c_str(std_string_unique_get(sdp));
  char* sdp_copy = strdup_safe(sdp_cstr);
  std_string_unique_delete(sdp);

  /* sdp_mid が NULL の場合は空文字列で代替する。
   * webrtc_IceCandidate_sdp_mid は void を返すため戻り値チェック不可 */
  char* mid_copy;
  if (sdp_mid == NULL) {
    mid_copy = strdup_safe("");
  } else {
    const char* mid_cstr = std_string_c_str(std_string_unique_get(sdp_mid));
    mid_copy = strdup_safe(mid_cstr);
    std_string_unique_delete(sdp_mid);
  }

  bridge->on_ice_candidate(sdp_copy, mid_copy, sdp_mline_index,
                            bridge->dart_user_data);
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_candidate_error(
    const char* address, size_t address_len,
    int port, const char* url, size_t url_len,
    int error_code, const char* error_text, size_t error_text_len,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  char buf[512];
  snprintf(buf, sizeof(buf),
           "native: ice_candidate_error address=%.*s port=%d url=%.*s code=%d text=%.*s",
           (int)address_len, address ? address : "",
           port,
           (int)url_len, url ? url : "",
           error_code,
           (int)error_text_len, error_text ? error_text : "");
  bridge_emit_debug(bridge, buf);
  observer_bridge_end_use(bridge);
}

/**
* track コールバック(追加時)用のブリッジ
*/
static void bridge_on_track(
    struct webrtc_RtpTransceiverInterface_refcounted* transceiver_ref,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;

  /* トラックの種別を確認する */
  struct webrtc_RtpReceiverInterface_refcounted* receiver_ref =
      webrtc_RtpTransceiverInterface_receiver(
          webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
  if (receiver_ref == NULL) {
    /* receiver_ref が NULL のため track / kind / track_id をまだ読めず、
     * 固定文字列でログを出す */
    bridge_emit_debug(bridge, "native: ontrack skipped, receiver is null");
    webrtc_RtpTransceiverInterface_Release(
        webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
    observer_bridge_end_use(bridge);
    return;
  }
  struct webrtc_MediaStreamTrackInterface_refcounted* track_ref =
      webrtc_RtpReceiverInterface_track(
          webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
  if (track_ref == NULL) {
    /* track_ref が NULL のため kind / track_id をまだ読めず、
     * 固定文字列でログを出す */
    bridge_emit_debug(bridge, "native: ontrack skipped, track is null");
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    webrtc_RtpTransceiverInterface_Release(
        webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
    observer_bridge_end_use(bridge);
    return;
  }
  struct std_string_unique* kind = webrtc_MediaStreamTrackInterface_kind(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
  struct std_string_unique* track_id = webrtc_MediaStreamTrackInterface_id(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
  const char* kind_cstr = std_string_c_str(std_string_unique_get(kind));
  const char* track_id_cstr = std_string_c_str(std_string_unique_get(track_id));
  /* kind の文字列は std_string_unique_delete 後に無効になるため、
   * Dart 側へ渡す場合に備えて malloc 済み文字列へコピーする。
   * Dart 側へ渡した場合は Dart 側で free し、渡さなかった場合は C 側で free する。 */
  char* kind_copy = strdup_safe(kind_cstr);
  char* track_id_copy = strdup_safe(track_id_cstr);

  // トラック種別は WebRTC 仕様上、 video / audio のみ
  if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
    /* 映像トラックの処理 */
    bridge_emit_debug(bridge, "native: ontrack kind=video");

    struct webrtc_VideoTrackInterface_refcounted* video_ref =
        webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
            track_ref);

    /* AddRef した参照の所有権は Dart 側へ移し、videoTrackRelease() で解放する */
    struct webrtc_VideoTrackInterface* video_track =
        webrtc_VideoTrackInterface_refcounted_get(video_ref);
    webrtc_VideoTrackInterface_AddRef(video_track);

    if (bridge->on_track) {
      bridge->on_track((void*)video_track, kind_copy, track_id_copy,
                       bridge->dart_user_data);
      /* 二重 free 防止のため NULL を入れる */
      kind_copy = NULL;
      track_id_copy = NULL;
    } else {
      /* callback 未登録時は AddRef した参照を C 側で戻す */
      webrtc_VideoTrackInterface_Release(video_track);
    }
  } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
    /* 音声トラックの処理 */
    bridge_emit_debug(bridge, "native: ontrack kind=audio");
    if (bridge->on_track) {
      /* 音声は Flutter で処理していないため　kind のみ通知 */
      bridge->on_track(NULL, kind_copy, track_id_copy, bridge->dart_user_data);
      /* 二重 free 防止のため NULL を入れる */
      kind_copy = NULL;
      track_id_copy = NULL;
    }
  }

  if (kind_copy != NULL) {
    free(kind_copy);
  }
  if (track_id_copy != NULL) {
    free(track_id_copy);
  }

  std_string_unique_delete(kind);
  std_string_unique_delete(track_id);
  webrtc_MediaStreamTrackInterface_Release(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
  webrtc_RtpReceiverInterface_Release(
      webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
  webrtc_RtpTransceiverInterface_Release(
      webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
  observer_bridge_end_use(bridge);
}

/**
* track コールバック(削除時)用のブリッジ
*/
static void bridge_on_remove_track(
    struct webrtc_RtpReceiverInterface_refcounted* receiver_ref,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;

  if (receiver_ref == NULL) {
    /* receiver_ref が NULL のため track / kind / track_id をまだ読めず、
     * 固定文字列でログを出す */
    bridge_emit_debug(bridge, "native: onremovetrack skipped, receiver is null");
    observer_bridge_end_use(bridge);
    return;
  }

  /* receiver からトラックを取得してビデオならポインタを Dart に渡す */
  struct webrtc_MediaStreamTrackInterface_refcounted* track_ref =
      webrtc_RtpReceiverInterface_track(
          webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
  if (track_ref == NULL) {
    /* track_ref が NULL のため kind / track_id をまだ読めず、
     * 固定文字列でログを出す */
    bridge_emit_debug(bridge, "native: onremovetrack skipped, track is null");
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    observer_bridge_end_use(bridge);
    return;
  }
  struct std_string_unique* kind = webrtc_MediaStreamTrackInterface_kind(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
  struct std_string_unique* track_id = webrtc_MediaStreamTrackInterface_id(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
  const char* kind_cstr = std_string_c_str(std_string_unique_get(kind));
  const char* track_id_cstr = std_string_c_str(std_string_unique_get(track_id));
  /* kind の文字列は std_string_unique_delete 後に無効になるため、
   * Dart 側へ渡す場合に備えて malloc 済み文字列へコピーする。
   * Dart 側へ渡した場合は Dart 側で free し、渡さなかった場合は C 側で free する。 */
  char* kind_copy = strdup_safe(kind_cstr);
  char* track_id_copy = strdup_safe(track_id_cstr);

  void* track_ptr = NULL;
  if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
    /* 映像トラックの処理 */
    bridge_emit_debug(bridge, "native: onremovetrack kind=video");
    struct webrtc_VideoTrackInterface_refcounted* video_ref =
        webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
            track_ref);
    struct webrtc_VideoTrackInterface* video_track =
        webrtc_VideoTrackInterface_refcounted_get(video_ref);
    /* AddRef した参照の所有権は Dart 側へ移し、videoTrackRelease() で解放する */
    webrtc_VideoTrackInterface_AddRef(video_track);
    track_ptr = (void*)video_track;
  } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
    /* 音声トラックの処理。音声は Flutter で処理していないのでここではログのみ */
    bridge_emit_debug(bridge, "native: onremovetrack kind=audio");
  } else {
    /* unknown kind は通知しない。
     * ただしここまでに track/kind/track_id と複製文字列を確保済みのため、
     * 通常経路と同等の cleanup を行ってから early return する。 */
    std_string_unique_delete(kind);
    webrtc_MediaStreamTrackInterface_Release(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    if (kind_copy != NULL) free(kind_copy);
    if (track_id_copy != NULL) free(track_id_copy);
    std_string_unique_delete(track_id);
    observer_bridge_end_use(bridge);
    return;
  }

  std_string_unique_delete(kind);
  webrtc_MediaStreamTrackInterface_Release(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));

  /* Flutter へ remove 通知する */
  if (bridge->on_remove_track) {
    bridge->on_remove_track(track_ptr, kind_copy, track_id_copy,
                            bridge->dart_user_data);
    /* 二重 free 防止のため NULL を入れる */
    kind_copy = NULL;
    track_id_copy = NULL;
  } else if (track_ptr != NULL) {
    /* callback 未登録時は AddRef した video track 参照を C 側で戻す */
    webrtc_VideoTrackInterface_Release(
        (struct webrtc_VideoTrackInterface*)track_ptr);
  }
  if (kind_copy != NULL) {
    free(kind_copy);
  }
  if (track_id_copy != NULL) {
    free(track_id_copy);
  }
  std_string_unique_delete(track_id);
  webrtc_RtpReceiverInterface_Release(
      webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
  observer_bridge_end_use(bridge);
}

static const char* datachannel_state_to_string(
    webrtc_DataChannelInterface_DataState state) {
  if (state == webrtc_DataChannelInterface_DataState_kConnecting) return "connecting";
  if (state == webrtc_DataChannelInterface_DataState_kOpen) return "open";
  if (state == webrtc_DataChannelInterface_DataState_kClosing) return "closing";
  if (state == webrtc_DataChannelInterface_DataState_kClosed) return "closed";
  return "unknown";
}

/*
 * DataChannel コールバック用コンテキスト。
 * Dart に malloc 確保したデータを渡すためのコールバックブリッジ。
 */
typedef void (*dart_on_dc_state_fn)(void* user_data);
typedef void (*dart_on_dc_message_fn)(
    uint8_t* data_copy, int32_t len, int32_t is_binary, void* user_data);

typedef struct DcBridgeContext {
  SoraObserverBridge* bridge;
  struct webrtc_DataChannelInterface* dc;
  char* label;
  struct webrtc_DataChannelObserver* observer;
  dart_on_dc_state_fn on_state_change;
  dart_on_dc_message_fn on_message;
  void* dart_user_data;

  /* インフライトコールバックの同期機構 */
  pthread_mutex_t lock;
  pthread_cond_t inflight_cond;
  int disposed;
  int inflight_count;
} DcBridgeContext;

/* DcBridgeContext のコールバックインフライトを開始する。
   破棄済みの場合は false を返す。 */
static bool dc_bridge_begin_use(DcBridgeContext* ctx) {
  pthread_mutex_lock(&ctx->lock);
  if (ctx->disposed) {
    pthread_mutex_unlock(&ctx->lock);
    return false;
  }
  ctx->inflight_count++;
  pthread_mutex_unlock(&ctx->lock);
  return true;
}

/* DcBridgeContext のコールバックインフライトを終了する。 */
static void dc_bridge_end_use(DcBridgeContext* ctx) {
  pthread_mutex_lock(&ctx->lock);
  ctx->inflight_count--;
  if (ctx->disposed && ctx->inflight_count == 0) {
    pthread_cond_signal(&ctx->inflight_cond);
  }
  pthread_mutex_unlock(&ctx->lock);
}

static void bridge_dc_on_state_change(void* user_data) {
  DcBridgeContext* ctx = (DcBridgeContext*)user_data;
  if (!dc_bridge_begin_use(ctx)) return;
  webrtc_DataChannelInterface_DataState state =
      webrtc_DataChannelInterface_state(ctx->dc);
  char buf[128];
  snprintf(
      buf, sizeof(buf), "native: datachannel(%s) state=%s",
      ctx->label != NULL ? ctx->label : "(unknown)",
      datachannel_state_to_string(state));
  bridge_emit_debug(ctx->bridge, buf);
  if (ctx->on_state_change) {
    ctx->on_state_change(ctx->dart_user_data);
  }
  dc_bridge_end_use(ctx);
}

static void bridge_dc_on_message(const uint8_t* data, size_t len,
                                  int is_binary, void* user_data) {
  DcBridgeContext* ctx = (DcBridgeContext*)user_data;
  if (!dc_bridge_begin_use(ctx)) return;
  if (ctx->on_message == NULL) {
    dc_bridge_end_use(ctx);
    return;
  }

  if (data == NULL || len == 0) {
    ctx->on_message(NULL, 0, is_binary ? 1 : 0, ctx->dart_user_data);
    dc_bridge_end_use(ctx);
    return;
  }

  /* データを malloc でコピーする。Dart 側で free すること。 */
  uint8_t* data_copy = (uint8_t*)malloc(len);
  if (data_copy == NULL) {
    LOGE("dc_on_message: malloc failed; dropped message len=%zu", len);
    dc_bridge_end_use(ctx);
    return;
  }
  memcpy(data_copy, data, len);
  ctx->on_message(data_copy, (int32_t)len, is_binary ? 1 : 0,
                   ctx->dart_user_data);
  dc_bridge_end_use(ctx);
}

static void bridge_on_datachannel(
    struct webrtc_DataChannelInterface_refcounted* dc_ref, void* user_data) {
  /* callback 登録時は AddRef した参照と label_copy を Dart 側へ移譲し、
   * callback 未登録時は C 側で解放する。 */
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge)) return;
  if (dc_ref == NULL) {
    observer_bridge_end_use(bridge);
    return;
  }

  struct webrtc_DataChannelInterface* dc =
      webrtc_DataChannelInterface_refcounted_get(dc_ref);
  struct std_string_unique* label = webrtc_DataChannelInterface_label(dc);
  const char* label_cstr = std_string_c_str(std_string_unique_get(label));

  char buf[256];
  snprintf(buf, sizeof(buf), "native: ondatachannel label=%s",
           label_cstr != NULL ? label_cstr : "");
  bridge_emit_debug(bridge, buf);

  /* label を malloc コピーして Dart に渡す */
  char* label_copy = strdup_safe(label_cstr);
  std_string_unique_delete(label);

  /* AddRef した参照と label_copy は callback 登録時に Dart 側へ所有権移譲する。 */
  webrtc_DataChannelInterface_AddRef(dc);
  if (bridge->on_datachannel) {
    bridge->on_datachannel((void*)dc, label_copy, bridge->dart_user_data);
    observer_bridge_end_use(bridge);
    return;
  }

  /* callback 未登録時は C 側で回収する。 */
  free(label_copy);
  webrtc_DataChannelInterface_Release(dc);
  observer_bridge_end_use(bridge);
}

/* ---------------------------------------------------------------------------
 * dart:ffi から呼ばれるブリッジ生成関数
 *
 * Dart 側で NativeCallable.listener の関数ポインタを確保し、
 * この関数に渡す。C 側でコールバックブリッジコールバック付きの
 * PeerConnectionObserver を生成する。
 * --------------------------------------------------------------------------- */

SoraObserverBridge* sora_observer_bridge_create(
    dart_on_state_fn on_connection_change,
    dart_on_state_fn on_ice_connection_change,
    dart_on_state_fn on_ice_gathering_change,
    dart_on_ice_candidate_fn on_ice_candidate,
    dart_on_track_fn on_track,
    dart_on_remove_track_fn on_remove_track,
    dart_on_datachannel_fn on_datachannel,
    dart_on_debug_fn on_debug,
    void* dart_user_data) {
  SoraObserverBridge* bridge =
      (SoraObserverBridge*)calloc(1, sizeof(SoraObserverBridge));
  if (bridge == NULL) return NULL;

  pthread_mutex_init(&bridge->lock, NULL);
  pthread_cond_init(&bridge->inflight_cond, NULL);

  bridge->on_connection_change = on_connection_change;
  bridge->on_ice_connection_change = on_ice_connection_change;
  bridge->on_ice_gathering_change = on_ice_gathering_change;
  bridge->on_ice_candidate = on_ice_candidate;
  bridge->on_track = on_track;
  bridge->on_remove_track = on_remove_track;
  bridge->on_datachannel = on_datachannel;
  bridge->on_debug = on_debug;
  bridge->dart_user_data = dart_user_data;

  /* PeerConnectionObserver を作成する */
  struct webrtc_PeerConnectionObserver_cbs obs_cbs;
  memset(&obs_cbs, 0, sizeof(obs_cbs));
  obs_cbs.OnStandardizedIceConnectionChange = bridge_on_ice_connection_change;
  obs_cbs.OnConnectionChange = bridge_on_connection_change;
  obs_cbs.OnIceGatheringChange = bridge_on_ice_gathering_change;
  obs_cbs.OnIceCandidate = bridge_on_ice_candidate;
  obs_cbs.OnIceCandidateError = bridge_on_ice_candidate_error;
  obs_cbs.OnTrack = bridge_on_track;
  obs_cbs.OnRemoveTrack = bridge_on_remove_track;
  obs_cbs.OnDataChannel = bridge_on_datachannel;
  obs_cbs.OnDestroy = noop_destroy;
  bridge->observer = webrtc_PeerConnectionObserver_new(&obs_cbs, bridge);

  LOGI("sora_observer_bridge_create bridge=%p observer=%p",
       (void*)bridge, (void*)bridge->observer);
  return bridge;
}

/* observer ポインタを取得する */
struct webrtc_PeerConnectionObserver* sora_observer_bridge_get_observer(
    SoraObserverBridge* bridge) {
  return bridge ? bridge->observer : NULL;
}

/* ブリッジの DataChannel コールバックを設定する */
DcBridgeContext* sora_observer_bridge_setup_dc(
    SoraObserverBridge* bridge,
    struct webrtc_DataChannelInterface* dc,
    dart_on_dc_state_fn on_state_change,
    dart_on_dc_message_fn on_message,
    void* dart_user_data) {
  DcBridgeContext* ctx = (DcBridgeContext*)calloc(1, sizeof(DcBridgeContext));
  if (ctx == NULL) return NULL;
  pthread_mutex_init(&ctx->lock, NULL);
  pthread_cond_init(&ctx->inflight_cond, NULL);
  ctx->bridge = bridge;
  ctx->dc = dc;
  ctx->on_state_change = on_state_change;
  ctx->on_message = on_message;
  ctx->dart_user_data = dart_user_data;
  struct std_string_unique* label = webrtc_DataChannelInterface_label(dc);
  const char* label_cstr = std_string_c_str(std_string_unique_get(label));
  ctx->label = strdup_safe(label_cstr);
  std_string_unique_delete(label);

  struct webrtc_DataChannelObserver_cbs cbs;
  memset(&cbs, 0, sizeof(cbs));
  cbs.OnStateChange = bridge_dc_on_state_change;
  cbs.OnMessage = bridge_dc_on_message;
  cbs.OnDestroy = noop_destroy;
  struct webrtc_DataChannelObserver* observer =
      webrtc_DataChannelObserver_new(&cbs, ctx);
  webrtc_DataChannelInterface_RegisterObserver(dc, observer);
  ctx->observer = observer;

  return ctx;
}

/* DcBridgeContext を破棄し、observer の解除と解放を行う。
   破棄前にインフライトのコールバック完了を待つ。 */
void sora_observer_bridge_destroy_dc(
    DcBridgeContext* ctx,
    struct webrtc_DataChannelInterface* dc) {
  if (ctx == NULL) return;

  /* disposed を立てて新規コールバックを抑止してから、
     lock 外で UnregisterObserver を呼ぶ。
     UnregisterObserver が同期的に callback を流す実装でも
     begin_use が disposed を検出して return するため安全。 */
  pthread_mutex_lock(&ctx->lock);
  ctx->disposed = 1;
  pthread_mutex_unlock(&ctx->lock);

  if (dc != NULL && ctx->observer != NULL) {
    webrtc_DataChannelInterface_UnregisterObserver(dc);
  }

  /* インフライトのコールバック完了を待つ */
  pthread_mutex_lock(&ctx->lock);
  while (ctx->inflight_count > 0) {
    pthread_cond_wait(&ctx->inflight_cond, &ctx->lock);
  }
  pthread_mutex_unlock(&ctx->lock);

  if (ctx->observer != NULL) {
    webrtc_DataChannelObserver_delete(ctx->observer);
  }

  pthread_mutex_destroy(&ctx->lock);
  pthread_cond_destroy(&ctx->inflight_cond);
  free(ctx->label);
  free(ctx);
}

/* ブリッジを破棄する。
   破棄前にインフライトのコールバック完了を待つ。 */
void sora_observer_bridge_destroy(SoraObserverBridge* bridge) {
  if (bridge == NULL) return;
  LOGI("sora_observer_bridge_destroy bridge=%p", (void*)bridge);

  /* disposed を立てて新規コールバックを抑止してから、
     lock 外で PeerConnectionObserver_delete を呼ぶ。
     delete が同期的に callback を流す実装でも
     begin_use が disposed を検出して return するため安全。 */
  pthread_mutex_lock(&bridge->lock);
  bridge->disposed = 1;
  pthread_mutex_unlock(&bridge->lock);

  if (bridge->observer != NULL) {
    webrtc_PeerConnectionObserver_delete(bridge->observer);
    bridge->observer = NULL;
  }

  /* インフライトのコールバック完了を待つ */
  pthread_mutex_lock(&bridge->lock);
  while (bridge->inflight_count > 0) {
    pthread_cond_wait(&bridge->inflight_cond, &bridge->lock);
  }
  pthread_mutex_unlock(&bridge->lock);

  pthread_mutex_destroy(&bridge->lock);
  pthread_cond_destroy(&bridge->inflight_cond);
  free(bridge);
}

JNIEXPORT jboolean JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeInitializeAndroid(
    JNIEnv* env, jclass clazz, jobject application_context) {
  (void)clazz;

  JavaVM* jvm = NULL;
  if ((*env)->GetJavaVM(env, &jvm) != JNI_OK || jvm == NULL) {
    LOGE("nativeInitializeAndroid: failed to get JavaVM");
    return JNI_FALSE;
  }

  if (webrtc_jni_InitGlobalJniVariables(jvm) < 0) {
    LOGE("nativeInitializeAndroid: failed to initialize JNI globals");
    return JNI_FALSE;
  }

  if (g_application_context != NULL) {
    (*env)->DeleteGlobalRef(env, g_application_context);
    g_application_context = NULL;
  }
  if (g_sora_audio_device_module_class != NULL) {
    (*env)->DeleteGlobalRef(env, g_sora_audio_device_module_class);
    g_sora_audio_device_module_class = NULL;
  }
  g_sora_audio_device_module_create_method = NULL;
  g_application_context = (*env)->NewGlobalRef(env, application_context);
  if (g_application_context == NULL) {
    LOGE("nativeInitializeAndroid: failed to create global application context");
    return JNI_FALSE;
  }

  // 以後は WebRTC 管理スレッドから helper を呼ぶため、
  // app class loader で解決できるこのタイミングで class / method を確保する。
  jclass helper_class =
      (*env)->FindClass(env, "jp/shiguredo/sora_sdk/SoraAudioDeviceModule");
  if (helper_class == NULL) {
    LOGE("nativeInitializeAndroid: failed to find SoraAudioDeviceModule");
    (*env)->ExceptionClear(env);
    return JNI_FALSE;
  }
  g_sora_audio_device_module_class =
      (jclass)(*env)->NewGlobalRef(env, helper_class);
  (*env)->DeleteLocalRef(env, helper_class);
  if (g_sora_audio_device_module_class == NULL) {
    LOGE("nativeInitializeAndroid: failed to create SoraAudioDeviceModule global ref");
    return JNI_FALSE;
  }

  g_sora_audio_device_module_create_method = (*env)->GetStaticMethodID(
      env,
      g_sora_audio_device_module_class,
      "createNativeAudioDeviceModule",
      "(Landroid/content/Context;J)J");
  if (g_sora_audio_device_module_create_method == NULL) {
    LOGE("nativeInitializeAndroid: failed to find createNativeAudioDeviceModule");
    (*env)->ExceptionClear(env);
    return JNI_FALSE;
  }

  webrtc_InitClassLoader(env);
  return JNI_TRUE;
}

/* ---------------------------------------------------------------------------
 * JNI 関数: レンダリングシンク
 * --------------------------------------------------------------------------- */

JNIEXPORT jlong JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeCreateRenderingSink(
    JNIEnv* env, jclass clazz, jobject surface) {
  (void)clazz;
  struct webrtc_VideoSinkInterface_cbs cbs;

  if (surface == NULL) return 0;

  RenderingSink* rs = (RenderingSink*)calloc(1, sizeof(RenderingSink));
  if (rs == NULL) return 0;

  if (pthread_mutex_init(&rs->lock, NULL) != 0) {
    free(rs);
    return 0;
  }

  if (pthread_cond_init(&rs->inflight_cond, NULL) != 0) {
    pthread_mutex_destroy(&rs->lock);
    free(rs);
    return 0;
  }
  atomic_init(&rs->ref_count, 1);

  rs->window = ANativeWindow_fromSurface(env, surface);
  if (rs->window == NULL) {
    pthread_cond_destroy(&rs->inflight_cond);
    pthread_mutex_destroy(&rs->lock);
    free(rs);
    return 0;
  }

  memset(&cbs, 0, sizeof(cbs));
  cbs.OnFrame = on_rendering_frame;
  cbs.OnDiscardedFrame = noop_destroy;
  cbs.OnDestroy = noop_destroy;
  rs->sink = webrtc_VideoSinkInterface_new(&cbs, rs);
  if (rs->sink == NULL) {
    ANativeWindow_release(rs->window);
    pthread_cond_destroy(&rs->inflight_cond);
    pthread_mutex_destroy(&rs->lock);
    free(rs);
    return 0;
  }

  LOGI("nativeCreateRenderingSink rs=%p sink=%p window=%p",
       (void*)rs, (void*)rs->sink, (void*)rs->window);
  return (jlong)(intptr_t)rs;
}

JNIEXPORT jlong JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeGetSinkPtr(
    JNIEnv* env, jclass clazz, jlong renderingSinkPtr) {
  (void)env; (void)clazz;
  RenderingSink* rs = (RenderingSink*)(intptr_t)renderingSinkPtr;
  jlong sink_ptr = 0;
  if (rs == NULL) return 0;

  /*
   * 呼び出し元は create 直後だけを想定しているが、
   * 誤用時も解放済み / dispose 済み sink を返さないよう lock で保護する。
   */
  pthread_mutex_lock(&rs->lock);
  if (!rs->disposed && rs->sink != NULL) {
    sink_ptr = (jlong)(intptr_t)rs->sink;
  }
  pthread_mutex_unlock(&rs->lock);
  return sink_ptr;
}

JNIEXPORT void JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeDeleteRenderingSink(
    JNIEnv* env, jclass clazz, jlong renderingSinkPtr) {
  (void)env; (void)clazz;
  RenderingSink* rs = (RenderingSink*)(intptr_t)renderingSinkPtr;
  if (rs == NULL) return;
  LOGI("nativeDeleteRenderingSink rs=%p", (void*)rs);

  /*
   * 先に disposed を立てて新規 entrant を止める。
   * 二重呼び出し時に disposed チェックで早期復帰し UAF を防ぐ。
   * その後 inflight 完了を待つことで、実行中 callback が rs->window を
   * 触り終えるまで owner ref を保持したまま寿命を延長する。
   */
  pthread_mutex_lock(&rs->lock);
  if (rs->disposed) {
    pthread_mutex_unlock(&rs->lock);
    return;
  }
  rs->disposed = 1;
  while (rs->inflight_count > 0) {
    pthread_cond_wait(&rs->inflight_cond, &rs->lock);
  }
  pthread_mutex_unlock(&rs->lock);

  /*
   * inflight が枯れた後に sink / window を解放する。
   * delete は lock 外で呼び、外部実装との相互待機を避ける。
   */
  if (rs->sink != NULL) {
    webrtc_VideoSinkInterface_delete(rs->sink);
    rs->sink = NULL;
  }
  if (rs->window != NULL) {
    ANativeWindow_release(rs->window);
    rs->window = NULL;
  }

  /* create 時に持っていた owner ref を手放し、最後の利用者が後始末する。 */
  rendering_sink_release(rs);
}

/* ---------------------------------------------------------------------------
 * JNI 関数: カメラフレーム入力
 * --------------------------------------------------------------------------- */

JNIEXPORT void JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeFeedVideoFrame(
    JNIEnv* env, jclass clazz, jlong videoSourcePtr,
    jobject yBuffer, jobject uBuffer, jobject vBuffer, jint width, jint height,
    jint yStride, jint uStride, jint vStride,
    jint yPixelStride, jint uPixelStride, jint vPixelStride,
    jint rotation,
    jlong timestampUs) {
  (void)clazz;
  if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return;
  struct webrtc_AdaptedVideoTrackSource_refcounted* source_ref =
      (struct webrtc_AdaptedVideoTrackSource_refcounted*)(intptr_t)videoSourcePtr;
  if (source_ref == NULL) return;

  struct webrtc_AdaptedVideoTrackSource* source =
      webrtc_AdaptedVideoTrackSource_refcounted_get(source_ref);

  int adapted_width = 0, adapted_height = 0;
  int crop_width = 0, crop_height = 0, crop_x = 0, crop_y = 0;
  if (!webrtc_AdaptedVideoTrackSource_AdaptFrame(
          source, (int)width, (int)height, (int64_t)timestampUs,
          &adapted_width, &adapted_height, &crop_width, &crop_height,
          &crop_x, &crop_y)) {
    return;
  }

  struct webrtc_I420Buffer_refcounted* buffer_ref =
      webrtc_I420Buffer_Create(adapted_width, adapted_height);
  if (buffer_ref == NULL) return;
  struct webrtc_I420Buffer* buffer = webrtc_I420Buffer_refcounted_get(buffer_ref);

  if (adapted_width == (int)width && adapted_height == (int)height) {
    if (!copy_java_yuv_to_i420(env, yBuffer, uBuffer, vBuffer, width, height,
                               yStride, uStride, vStride, yPixelStride,
                               uPixelStride, vPixelStride, buffer)) {
      webrtc_I420Buffer_Release(buffer);
      return;
    }
  } else {
    struct webrtc_I420Buffer_refcounted* src_ref =
        webrtc_I420Buffer_Create((int)width, (int)height);
    if (src_ref == NULL) {
      webrtc_I420Buffer_Release(buffer);
      return;
    }
    struct webrtc_I420Buffer* sb = webrtc_I420Buffer_refcounted_get(src_ref);
    if (!copy_java_yuv_to_i420(env, yBuffer, uBuffer, vBuffer, width, height,
                               yStride, uStride, vStride, yPixelStride,
                               uPixelStride, vPixelStride, sb)) {
      webrtc_I420Buffer_Release(sb);
      webrtc_I420Buffer_Release(buffer);
      return;
    }
    webrtc_I420Buffer_ScaleFrom(buffer, sb);
    webrtc_I420Buffer_Release(sb);
  }

  struct webrtc_VideoFrame_unique* vf =
      build_sora_video_frame(buffer_ref, rotation, (int64_t)timestampUs, 0);
  if (vf != NULL) {
    webrtc_AdaptedVideoTrackSource_OnFrame(
        source, webrtc_VideoFrame_unique_get(vf));
    webrtc_VideoFrame_unique_delete(vf);
  }
  webrtc_I420Buffer_Release(buffer);
}

JNIEXPORT void JNICALL
Java_jp_shiguredo_sora_1sdk_WebrtcC_nativeRenderVideoFrame(
    JNIEnv* env, jclass clazz, jlong renderingSinkPtr,
    jobject yBuffer, jobject uBuffer, jobject vBuffer, jint width, jint height,
    jint yStride, jint uStride, jint vStride,
    jint yPixelStride, jint uPixelStride, jint vPixelStride,
    jint rotation,
    jlong timestampUs) {
  (void)clazz;
  if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return;
  RenderingSink* rs = (RenderingSink*)(intptr_t)renderingSinkPtr;
  struct webrtc_I420Buffer_refcounted* buffer_ref = NULL;
  struct webrtc_I420Buffer* buffer = NULL;
  struct webrtc_VideoFrame_unique* vf = NULL;

  if (rs == NULL) return;

  if (!rendering_sink_begin_use(rs)) {
    return;
  }

  buffer_ref = webrtc_I420Buffer_Create((int)width, (int)height);
  if (buffer_ref != NULL) {
    buffer = webrtc_I420Buffer_refcounted_get(buffer_ref);
    if (buffer != NULL) {
      if (copy_java_yuv_to_i420(env, yBuffer, uBuffer, vBuffer, width, height,
                                yStride, uStride, vStride, yPixelStride,
                                uPixelStride, vPixelStride, buffer)) {
        vf = build_sora_video_frame(buffer_ref, rotation, (int64_t)timestampUs, 0);
        if (vf != NULL) {
          on_rendering_frame(webrtc_VideoFrame_unique_get(vf), rs);
          webrtc_VideoFrame_unique_delete(vf);
        }
      }
      webrtc_I420Buffer_Release(buffer);
    }
  }
  rendering_sink_end_use(rs);
}
