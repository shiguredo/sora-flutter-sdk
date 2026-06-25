// dart:ffi から参照される C API シンボルを提供する Linux 版 C ブリッジ。

#include <stdint.h>
#include <stdlib.h>

#include <webrtc_c.h>

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
  (void)buffer;
  (void)rotation;
  (void)timestamp_us;
  (void)timestamp_rtp;
  // 未実装: 後続 issue で実装する
  return NULL;
}

__attribute__((visibility("default"))) struct webrtc_VideoFrame*
sora_video_frame_unique_get(struct webrtc_VideoFrame_unique* frame) {
  (void)frame;
  // 未実装: 後続 issue で実装する
  return NULL;
}

__attribute__((visibility("default"))) void sora_video_frame_unique_delete(
    struct webrtc_VideoFrame_unique* frame) {
  (void)frame;
  // 未実装: 後続 issue で実装する
}

// --- observer_bridge ---

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
