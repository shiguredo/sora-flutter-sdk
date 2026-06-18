// dart:ffi から参照される C API シンボルを提供する Windows 版 C ブリッジ。

#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <windows.h>

#include <webrtc_c/api/peer_connection_interface.h>
#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>

// VEH: STATUS_BREAKPOINT をスキップ
static LONG CALLBACK VectoredHandler(struct _EXCEPTION_POINTERS* ei) {
  if (ei->ExceptionRecord->ExceptionCode == STATUS_BREAKPOINT) {
#ifdef _WIN64
    ei->ContextRecord->Rip++;
#else
    ei->ContextRecord->Eip++;
#endif
    return EXCEPTION_CONTINUE_EXECUTION;
  }
  return EXCEPTION_CONTINUE_SEARCH;
}

// setjmp/longjmp で abort を捕捉
static __declspec(thread) jmp_buf g_abort_jmp;

static void abort_handler(int sig) {
  (void)sig;
  longjmp(g_abort_jmp, 1);
}

BOOL WINAPI DllMain(HINSTANCE dll, DWORD reason, LPVOID rsv) {
  (void)dll;
  (void)rsv;
  if (reason == DLL_PROCESS_ATTACH) {
    AddVectoredExceptionHandler(1, VectoredHandler);
    signal(SIGABRT, abort_handler);
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);
    DisableThreadLibraryCalls(dll);
  }
  return TRUE;
}

// --- AudioDeviceModule ---
// webrtc_c/api/audio/audio_device.h は Windows ではインクルードしないので
// 必要な型と関数のみ前方宣言する。
struct webrtc_AudioDeviceModule_refcounted;
struct webrtc_Environment;

extern struct webrtc_AudioDeviceModule_refcounted*
webrtc_CreateAudioDeviceModule(struct webrtc_Environment* env, int type);

__declspec(dllexport) struct webrtc_AudioDeviceModule_refcounted*
sora_create_audio_device_module(struct webrtc_Environment* env, int type) {
  (void)type;
  // abort を setjmp/longjmp で捕捉して NULL を返す
  if (setjmp(g_abort_jmp) == 0) {
    return webrtc_CreateAudioDeviceModule(env, type);
  }
  return NULL;
}

// --- observer bridge ---

typedef void (*dart_on_state_fn)(int32_t state, void* user_data);
typedef void (*dart_on_ice_candidate_fn)(char* sdp,
                                         char* mid,
                                         int32_t mline_index,
                                         void* user_data);
typedef void (*dart_on_track_fn)(void* track_ref,
                                 char* kind,
                                 char* track_id,
                                 void* user_data);
typedef void (*dart_on_remove_track_fn)(void* track_ref,
                                        char* kind,
                                        char* track_id,
                                        void* user_data);
typedef void (*dart_on_datachannel_fn)(void* dc_ref,
                                       char* label,
                                       void* user_data);
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

  struct webrtc_PeerConnectionObserver* observer;

  CRITICAL_SECTION lock;
  CONDITION_VARIABLE inflight_cond;
  int disposed;
  int inflight_count;
} SoraObserverBridge;

/* bridge のコールバックインフライトを開始する。
   破棄済みの場合は false を返し、呼び出し元は即座に return する。 */
static int observer_bridge_begin_use(SoraObserverBridge* bridge) {
  EnterCriticalSection(&bridge->lock);
  if (bridge->disposed) {
    LeaveCriticalSection(&bridge->lock);
    return 0;
  }
  bridge->inflight_count++;
  LeaveCriticalSection(&bridge->lock);
  return 1;
}

/* bridge のコールバックインフライトを終了し、
   破棄待ちがあれば WakeConditionVariable を発火する。 */
static void observer_bridge_end_use(SoraObserverBridge* bridge) {
  EnterCriticalSection(&bridge->lock);
  bridge->inflight_count--;
  if (bridge->disposed && bridge->inflight_count == 0) {
    WakeConditionVariable(&bridge->inflight_cond);
  }
  LeaveCriticalSection(&bridge->lock);
}

/* malloc で文字列をコピーする。Dart 側で free すること。 */
static char* strdup_safe(const char* src) {
  if (src == NULL) {
    char* empty = (char*)malloc(1);
    if (empty)
      empty[0] = '\0';
    return empty;
  }
  return _strdup(src);
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
  if (!observer_bridge_begin_use(bridge))
    return;
  if (bridge->on_connection_change) {
    bridge->on_connection_change((int32_t)new_state, bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_connection_change(
    webrtc_PeerConnectionInterface_IceConnectionState new_state,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;
  if (bridge->on_ice_connection_change) {
    bridge->on_ice_connection_change((int32_t)new_state,
                                     bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

static void bridge_on_ice_candidate(const struct webrtc_IceCandidate* candidate,
                                    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;
  if (bridge->on_ice_candidate == NULL) {
    observer_bridge_end_use(bridge);
    return;
  }

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

static void bridge_on_ice_candidate_error(const char* address,
                                          size_t address_len,
                                          int port,
                                          const char* url,
                                          size_t url_len,
                                          int error_code,
                                          const char* error_text,
                                          size_t error_text_len,
                                          void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;
  char buf[512];
  snprintf(buf, sizeof(buf),
           "native: ice_candidate_error address=%.*s port=%d "
           "url=%.*s code=%d text=%.*s",
           (int)address_len, address ? address : "", port, (int)url_len,
           url ? url : "", error_code, (int)error_text_len,
           error_text ? error_text : "");
  bridge_emit_debug(bridge, buf);
  observer_bridge_end_use(bridge);
}
static void bridge_on_track(
    struct webrtc_RtpTransceiverInterface_refcounted* transceiver_ref,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;

  struct webrtc_RtpReceiverInterface_refcounted* receiver_ref =
      webrtc_RtpTransceiverInterface_receiver(
          webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
  if (receiver_ref == NULL) {
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
  char* kind_copy = strdup_safe(kind_cstr);
  char* track_id_copy = strdup_safe(track_id_cstr);

  if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
    bridge_emit_debug(bridge, "native: ontrack kind=video");

    struct webrtc_VideoTrackInterface_refcounted* video_ref =
        webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
            track_ref);

    struct webrtc_VideoTrackInterface* video_track =
        webrtc_VideoTrackInterface_refcounted_get(video_ref);
    webrtc_VideoTrackInterface_AddRef(video_track);

    if (bridge->on_track) {
      bridge->on_track((void*)video_track, kind_copy, track_id_copy,
                       bridge->dart_user_data);
      kind_copy = NULL;
      track_id_copy = NULL;
    } else {
      webrtc_VideoTrackInterface_Release(video_track);
    }
  } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
    bridge_emit_debug(bridge, "native: ontrack kind=audio");
    if (bridge->on_track) {
      bridge->on_track(NULL, kind_copy, track_id_copy, bridge->dart_user_data);
      kind_copy = NULL;
      track_id_copy = NULL;
    }
  } else {
    char buf[128];
    snprintf(buf, sizeof(buf), "native: ontrack invalid kind=%s",
             kind_cstr != NULL ? kind_cstr : "(null)");
    bridge_emit_debug(bridge, buf);
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
static void bridge_on_remove_track(
    struct webrtc_RtpReceiverInterface_refcounted* receiver_ref,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;

  if (receiver_ref == NULL) {
    bridge_emit_debug(bridge,
                      "native: onremovetrack skipped, receiver is null");
    observer_bridge_end_use(bridge);
    return;
  }

  struct webrtc_MediaStreamTrackInterface_refcounted* track_ref =
      webrtc_RtpReceiverInterface_track(
          webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
  if (track_ref == NULL) {
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
  char* kind_copy = strdup_safe(kind_cstr);
  char* track_id_copy = strdup_safe(track_id_cstr);

  void* track_ptr = NULL;
  if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
    bridge_emit_debug(bridge, "native: onremovetrack kind=video");
    struct webrtc_VideoTrackInterface_refcounted* video_ref =
        webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
            track_ref);
    struct webrtc_VideoTrackInterface* video_track =
        webrtc_VideoTrackInterface_refcounted_get(video_ref);
    webrtc_VideoTrackInterface_AddRef(video_track);
    track_ptr = (void*)video_track;
  } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
    bridge_emit_debug(bridge, "native: onremovetrack kind=audio");
  } else {
    char buf[128];
    snprintf(buf, sizeof(buf), "native: onremovetrack invalid kind=%s",
             kind_cstr != NULL ? kind_cstr : "(null)");
    bridge_emit_debug(bridge, buf);
    std_string_unique_delete(kind);
    std_string_unique_delete(track_id);
    webrtc_MediaStreamTrackInterface_Release(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    if (kind_copy != NULL) {
      free(kind_copy);
    }
    if (track_id_copy != NULL) {
      free(track_id_copy);
    }
    observer_bridge_end_use(bridge);
    return;
  }

  std_string_unique_delete(kind);
  webrtc_MediaStreamTrackInterface_Release(
      webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));

  if (bridge->on_remove_track) {
    bridge->on_remove_track(track_ptr, kind_copy, track_id_copy,
                            bridge->dart_user_data);
    kind_copy = NULL;
    track_id_copy = NULL;
  } else if (track_ptr != NULL) {
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

static void bridge_on_datachannel(
    struct webrtc_DataChannelInterface_refcounted* dc_ref,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;
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

  char* label_copy = strdup_safe(label_cstr);
  std_string_unique_delete(label);

  webrtc_DataChannelInterface_AddRef(dc);
  if (bridge->on_datachannel) {
    bridge->on_datachannel((void*)dc, label_copy, bridge->dart_user_data);
    observer_bridge_end_use(bridge);
    return;
  }

  free(label_copy);
  webrtc_DataChannelInterface_Release(dc);
  observer_bridge_end_use(bridge);
}

static void noop_destroy(void* user_data) {
  (void)user_data;
}

static void bridge_on_ice_gathering_change(
    webrtc_PeerConnectionInterface_IceGatheringState new_state,
    void* user_data) {
  SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
  if (!observer_bridge_begin_use(bridge))
    return;
  if (bridge->on_ice_gathering_change) {
    bridge->on_ice_gathering_change((int32_t)new_state, bridge->dart_user_data);
  }
  observer_bridge_end_use(bridge);
}

__declspec(dllexport) SoraObserverBridge* sora_observer_bridge_create(
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
  if (bridge == NULL)
    return NULL;

  InitializeCriticalSection(&bridge->lock);
  InitializeConditionVariable(&bridge->inflight_cond);

  bridge->on_connection_change = on_connection_change;
  bridge->on_ice_connection_change = on_ice_connection_change;
  bridge->on_ice_gathering_change = on_ice_gathering_change;
  bridge->on_ice_candidate = on_ice_candidate;
  bridge->on_track = on_track;
  bridge->on_remove_track = on_remove_track;
  bridge->on_datachannel = on_datachannel;
  bridge->on_debug = on_debug;
  bridge->dart_user_data = dart_user_data;

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

  return bridge;
}

__declspec(dllexport) struct webrtc_PeerConnectionObserver*
sora_observer_bridge_get_observer(SoraObserverBridge* b) {
  return b ? b->observer : NULL;
}

__declspec(dllexport) void sora_observer_bridge_destroy(
    SoraObserverBridge* bridge) {
  if (bridge == NULL)
    return;

  /* disposed を立てて新規コールバックを抑止してから、
       lock 外で PeerConnectionObserver_delete を呼ぶ。
       delete が同期的に callback を流す実装でも
       begin_use が disposed を検出して return するため安全。 */
  EnterCriticalSection(&bridge->lock);
  bridge->disposed = 1;
  LeaveCriticalSection(&bridge->lock);

  if (bridge->observer != NULL) {
    webrtc_PeerConnectionObserver_delete(bridge->observer);
    bridge->observer = NULL;
  }

  /* インフライトのコールバック完了を待つ */
  EnterCriticalSection(&bridge->lock);
  while (bridge->inflight_count > 0) {
    SleepConditionVariableCS(&bridge->inflight_cond, &bridge->lock, INFINITE);
  }
  LeaveCriticalSection(&bridge->lock);

  DeleteCriticalSection(&bridge->lock);
  free(bridge);
}

__declspec(dllexport) void* sora_observer_bridge_setup_dc(void* a,
                                                          void* b,
                                                          void* c,
                                                          void* d,
                                                          void* e) {
  (void)a;
  (void)b;
  (void)c;
  (void)d;
  (void)e;
  return NULL;
}

__declspec(dllexport) void sora_observer_bridge_destroy_dc(void* a, void* b) {
  (void)a;
  (void)b;
}

// --- video frame ---

__declspec(dllexport) struct webrtc_VideoFrame_unique* sora_video_frame_create(
    struct webrtc_I420Buffer_refcounted* buffer,
    int rotation,
    int64_t timestamp_us,
    uint32_t timestamp_rtp) {
  struct webrtc_VideoFrameBuffer_refcounted* f =
      webrtc_I420Buffer_refcounted_cast_to_webrtc_VideoFrameBuffer(buffer);
  struct webrtc_VideoFrameBuilder_unique* b = webrtc_VideoFrameBuilder_new(f);
  if (!b)
    return NULL;
  struct webrtc_VideoFrameBuilder* builder =
      webrtc_VideoFrameBuilder_unique_get(b);
  webrtc_VideoFrameBuilder_set_rotation(builder, rotation);
  webrtc_VideoFrameBuilder_set_timestamp_us(builder, timestamp_us);
  webrtc_VideoFrameBuilder_set_timestamp_rtp(builder, timestamp_rtp);
  struct webrtc_VideoFrame_unique* frame =
      webrtc_VideoFrameBuilder_build(builder);
  webrtc_VideoFrameBuilder_unique_delete(b);
  return frame;
}

__declspec(dllexport) struct webrtc_VideoFrame* sora_video_frame_unique_get(
    struct webrtc_VideoFrame_unique* frame) {
  return webrtc_VideoFrame_unique_get(frame);
}

__declspec(dllexport) void sora_video_frame_unique_delete(
    struct webrtc_VideoFrame_unique* frame) {
  webrtc_VideoFrame_unique_delete(frame);
}
