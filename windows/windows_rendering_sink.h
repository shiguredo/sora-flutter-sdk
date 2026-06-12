#ifndef WINDOWS_RENDERING_SINK_H_
#define WINDOWS_RENDERING_SINK_H_

#include <windows.h>

#include <cstdint>
#include <vector>

typedef void (*frame_available_fn)(void* context);

struct WindowsRenderingSink {
  struct webrtc_VideoSinkInterface* sink;
  SRWLOCK lock;
  CONDITION_VARIABLE inflight_cond;
  bool disposed;
  int inflight_dispatch_count;
  struct webrtc_I420Buffer* i420_buffer;
  int32_t width;
  int32_t height;
  std::vector<uint8_t> bgra_buffer;
  frame_available_fn on_frame_available;
  void* frame_callback_context;
};

WindowsRenderingSink* CreateWindowsRenderingSink();
void SetFrameCallback(WindowsRenderingSink* sink,
                      frame_available_fn callback,
                      void* context);
bool CopyPixelBuffer(WindowsRenderingSink* sink,
                     std::vector<uint8_t>& out_buffer,
                     int& out_width,
                     int& out_height);
void DeleteWindowsRenderingSink(WindowsRenderingSink* sink);
void* GetVideoSinkPtr(WindowsRenderingSink* sink);

#endif
