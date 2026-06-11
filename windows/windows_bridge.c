// dart:ffi から参照される C API シンボルを提供する Windows 版 C ブリッジ。
//
// libwebrtc-c の `WEBRTC_EXPORT` (`__declspec(dllexport)`) が付与された
// シンボルは libwebrtc-c.lib からのリンクで自動的にエクスポートされる。
// 本ファイルは libwebrtc-c に含まれない追加のブリッジ関数を提供する。
//
// sora_observer_bridge_* / sora_video_frame_* の実体は後続 issue (0035-0037)
// で埋める。本 issue ではスタブを返す。

// webrtc_c.h には iOS/macOS 専用の Objective-C ヘッダが含まれるため
// Windows ではインクルードしない。libwebrtc-c のシンボルは
// /WHOLEARCHIVE によりリンク保持し、__declspec(dllexport) でエクスポートする。

#include <windows.h>

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

__declspec(dllexport) void* sora_video_frame_create(
    void* buffer,
    int rotation,
    long long timestamp_us,
    unsigned int timestamp_rtp) {
  (void)buffer;
  (void)rotation;
  (void)timestamp_us;
  (void)timestamp_rtp;
  return NULL;
}

__declspec(dllexport) void* sora_video_frame_unique_get(void* frame) {
  (void)frame;
  return NULL;
}

__declspec(dllexport) void sora_video_frame_unique_delete(void* frame) {
  (void)frame;
}
