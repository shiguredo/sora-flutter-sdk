// dart:ffi から参照される C API シンボルを提供する Windows 版 C ブリッジ。

#include <setjmp.h>
#include <signal.h>
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

__declspec(dllexport) struct webrtc_AudioDeviceModule_refcounted*
sora_create_audio_device_module(struct webrtc_Environment* env, int type) {
  (void)type;
  // abort を setjmp/longjmp で捕捉して NULL を返す
  if (setjmp(g_abort_jmp) == 0) {
    // webrtc-c API: webrtc_CreateAudioDeviceModule(env, type)
    extern struct webrtc_AudioDeviceModule_refcounted*
    webrtc_CreateAudioDeviceModule(struct webrtc_Environment * env, int type);
    return webrtc_CreateAudioDeviceModule(env, type);
  }
  return NULL;
}

// --- observer bridge ---

typedef void (*dart_on_state_fn)(int32_t state, void* user_data);

typedef struct SoraObserverBridge {
  dart_on_state_fn on_connection_change;
  dart_on_state_fn on_ice_connection_change;
  dart_on_state_fn on_ice_gathering_change;
  void* on_ice_candidate;
  void* on_track;
  void* on_remove_track;
  void* on_datachannel;
  void* on_debug;
  void* dart_user_data;
  struct webrtc_PeerConnectionObserver* observer;
} SoraObserverBridge;

static void on_connection_change(
    webrtc_PeerConnectionInterface_PeerConnectionState s,
    void* u) {
  SoraObserverBridge* b = (SoraObserverBridge*)u;
  if (b->on_connection_change)
    b->on_connection_change((int32_t)s, b->dart_user_data);
}

__declspec(dllexport) SoraObserverBridge* sora_observer_bridge_create(
    dart_on_state_fn a1,
    dart_on_state_fn a2,
    dart_on_state_fn a3,
    void* a4,
    void* a5,
    void* a6,
    void* a7,
    void* a8,
    void* a9) {
  (void)a2;
  (void)a3;
  (void)a4;
  (void)a5;
  (void)a6;
  (void)a7;
  (void)a8;
  SoraObserverBridge* b =
      (SoraObserverBridge*)calloc(1, sizeof(SoraObserverBridge));
  if (!b)
    return NULL;
  b->on_connection_change = a1;
  b->dart_user_data = a9;
  struct webrtc_PeerConnectionObserver_cbs cbs;
  memset(&cbs, 0, sizeof(cbs));
  cbs.OnConnectionChange = on_connection_change;
  b->observer = webrtc_PeerConnectionObserver_new(&cbs, b);
  return b;
}

__declspec(dllexport) struct webrtc_PeerConnectionObserver*
sora_observer_bridge_get_observer(SoraObserverBridge* b) {
  return b ? b->observer : NULL;
}

__declspec(dllexport) void sora_observer_bridge_destroy(SoraObserverBridge* b) {
  if (!b)
    return;
  if (b->observer) {
    webrtc_PeerConnectionObserver_delete(b->observer);
    b->observer = NULL;
  }
  free(b);
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
  webrtc_VideoFrameBuilder_set_rotation(b, rotation);
  webrtc_VideoFrameBuilder_set_timestamp_us(b, timestamp_us);
  webrtc_VideoFrameBuilder_set_timestamp_rtp(b, timestamp_rtp);
  struct webrtc_VideoFrame_unique* frame = webrtc_VideoFrameBuilder_build(b);
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
