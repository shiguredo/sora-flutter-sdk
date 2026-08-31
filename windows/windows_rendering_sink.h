#ifndef WINDOWS_RENDERING_SINK_H_
#define WINDOWS_RENDERING_SINK_H_

#include <windows.h>

#include <cstdint>
#include <vector>

typedef void (*frame_available_fn)(void* context);

// I420 フレームを受信し、BGRA 変換して Flutter Texture に配信するための
// レンダリングシンク。
// macOS apple_bridge.c の AppleRenderingSink に相当する。
// SRWLOCK + CONDITION_VARIABLE でマルチスレッド安全に動作する。
struct WindowsRenderingSink {
  struct webrtc_VideoSinkInterface* sink;
  SRWLOCK lock;
  CONDITION_VARIABLE inflight_cond;
  bool disposed;
  int inflight_dispatch_count;
  // 最新の I420 フレームバッファ (回転済み、ロック下でアクセス)
  struct webrtc_I420Buffer* i420_buffer;
  int32_t width;
  int32_t height;
  // フレーム到着通知コールバック (webrtc スレッドから呼ばれる)
  frame_available_fn on_frame_available;
  void* frame_callback_context;
};

WindowsRenderingSink* CreateWindowsRenderingSink();
void WindowsRenderingSinkSetFrameCallback(WindowsRenderingSink* sink,
                                          frame_available_fn callback,
                                          void* context);
bool WindowsRenderingSinkCopyPixelBuffer(WindowsRenderingSink* sink,
                                         std::vector<uint8_t>& out_buffer,
                                         int& out_width,
                                         int& out_height);
void DeleteWindowsRenderingSink(WindowsRenderingSink* sink);
void* WindowsRenderingSinkGetVideoSinkPtr(WindowsRenderingSink* sink);

#endif
