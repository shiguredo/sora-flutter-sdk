// dart:ffi から参照される C API シンボルを提供する Windows 版 C ブリッジ。
//
// libwebrtc-c の `WEBRTC_EXPORT` (`__declspec(dllexport)`) が付与された
// シンボルは libwebrtc-c.lib からのリンクで自動的にエクスポートされる。
// 本ファイルは libwebrtc-c に含まれない追加のブリッジ関数を提供する。

// webrtc_c.h には iOS/macOS 専用の Objective-C ヘッダが含まれるため
// Windows ではインクルードしない。必要なヘッダのみを個別にインクルードする。
// libwebrtc-c のシンボルは /WHOLEARCHIVE によりリンク保持し、
// __declspec(dllexport) でエクスポートする。

#include <windows.h>

#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>

// --- observer bridge ---

__declspec(dllexport) void* sora_observer_bridge_create(
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
  return NULL;
}

__declspec(dllexport) void* sora_observer_bridge_get_observer(void* bridge) {
  (void)bridge;
  return NULL;
}

__declspec(dllexport) void sora_observer_bridge_destroy(void* bridge) {
  (void)bridge;
}

__declspec(dllexport) void* sora_observer_bridge_setup_dc(
    void* bridge,
    void* dc,
    void* on_state_change,
    void* on_message,
    void* dart_user_data) {
  (void)bridge;
  (void)dc;
  (void)on_state_change;
  (void)on_message;
  (void)dart_user_data;
  return NULL;
}

__declspec(dllexport) void sora_observer_bridge_destroy_dc(
    void* ctx,
    void* dc) {
  (void)ctx;
  (void)dc;
}

// --- video frame ---

__declspec(dllexport) struct webrtc_VideoFrame_unique* sora_video_frame_create(
    struct webrtc_I420Buffer_refcounted* buffer,
    int rotation,
    int64_t timestamp_us,
    uint32_t timestamp_rtp) {
  struct webrtc_VideoFrameBuffer_refcounted* frame_buffer =
      webrtc_I420Buffer_refcounted_cast_to_webrtc_VideoFrameBuffer(buffer);
  struct webrtc_VideoFrameBuilder_unique* builder =
      webrtc_VideoFrameBuilder_new(frame_buffer);
  if (builder == NULL) {
    return NULL;
  }
  webrtc_VideoFrameBuilder_set_rotation(builder, rotation);
  webrtc_VideoFrameBuilder_set_timestamp_us(builder, timestamp_us);
  webrtc_VideoFrameBuilder_set_timestamp_rtp(builder, timestamp_rtp);
  struct webrtc_VideoFrame_unique* frame =
      webrtc_VideoFrameBuilder_build(builder);
  webrtc_VideoFrameBuilder_unique_delete(builder);
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
