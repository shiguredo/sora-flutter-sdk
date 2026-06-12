#include "windows_rendering_sink.h"

#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>
#include <webrtc_c/api/video/video_frame_buffer.h>
#include <webrtc_c/api/video/video_rotation.h>
#include <webrtc_c/api/video/video_sink_interface.h>
#include <webrtc_c/libyuv.h>

// I420 バッファを指定角度だけ回転させた新規バッファを返す。
// rotation が 90/180/270 以外の場合は NULL を返す。
static struct webrtc_I420Buffer* CreateRotatedI420Buffer(
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

static void OnFrame(const struct webrtc_VideoFrame* frame, void* user_data) {
  WindowsRenderingSink* sink = static_cast<WindowsRenderingSink*>(user_data);
  if (sink == NULL)
    return;

  AcquireSRWLockExclusive(&sink->lock);
  if (sink->disposed) {
    ReleaseSRWLockExclusive(&sink->lock);
    return;
  }

  struct webrtc_VideoFrameBuffer_refcounted* buffer_ref =
      webrtc_VideoFrame_video_frame_buffer(frame);
  struct webrtc_VideoFrameBuffer* frame_buffer =
      webrtc_VideoFrameBuffer_refcounted_get(buffer_ref);
  if (frame_buffer == NULL) {
    ReleaseSRWLockExclusive(&sink->lock);
    return;
  }

  struct webrtc_I420Buffer_refcounted* i420_ref =
      webrtc_VideoFrameBuffer_ToI420(frame_buffer);
  webrtc_VideoFrameBuffer_Release(frame_buffer);

  struct webrtc_I420Buffer* source_buffer =
      i420_ref == NULL ? NULL : webrtc_I420Buffer_refcounted_get(i420_ref);
  if (source_buffer == NULL) {
    ReleaseSRWLockExclusive(&sink->lock);
    return;
  }

  struct webrtc_I420Buffer* rotated_buffer = CreateRotatedI420Buffer(
      source_buffer, webrtc_VideoFrame_rotation(frame));
  struct webrtc_I420Buffer* buffer = rotated_buffer;
  if (buffer == NULL) {
    buffer = source_buffer;
    webrtc_I420Buffer_AddRef(buffer);
  }

  int32_t w = webrtc_I420Buffer_width(buffer);
  int32_t h = webrtc_I420Buffer_height(buffer);

  if (sink->i420_buffer != NULL) {
    webrtc_I420Buffer_Release(sink->i420_buffer);
  }
  sink->i420_buffer = buffer;
  sink->width = w;
  sink->height = h;

  frame_available_fn cb = sink->on_frame_available;
  void* ctx = sink->frame_callback_context;
  if (cb != NULL) {
    sink->inflight_dispatch_count++;
  }
  ReleaseSRWLockExclusive(&sink->lock);

  if (source_buffer != NULL) {
    webrtc_I420Buffer_Release(source_buffer);
  }

  if (cb != NULL) {
    cb(ctx);

    AcquireSRWLockExclusive(&sink->lock);
    sink->inflight_dispatch_count--;
    WakeAllConditionVariable(&sink->inflight_cond);
    ReleaseSRWLockExclusive(&sink->lock);
  }
}

static void OnDiscardedFrame(void* user_data) {
  (void)user_data;
}

static void OnDestroy(void* user_data) {
  (void)user_data;
}

WindowsRenderingSink* CreateWindowsRenderingSink() {
  WindowsRenderingSink* sink =
      static_cast<WindowsRenderingSink*>(calloc(1, sizeof(WindowsRenderingSink)));
  if (sink == NULL)
    return NULL;

  InitializeSRWLock(&sink->lock);
  InitializeConditionVariable(&sink->inflight_cond);

  struct webrtc_VideoSinkInterface_cbs cbs;
  memset(&cbs, 0, sizeof(cbs));
  cbs.OnFrame = OnFrame;
  cbs.OnDiscardedFrame = OnDiscardedFrame;
  cbs.OnDestroy = OnDestroy;
  sink->sink = webrtc_VideoSinkInterface_new(&cbs, sink);

  return sink;
}

void SetFrameCallback(WindowsRenderingSink* sink,
                      frame_available_fn callback,
                      void* context) {
  if (sink == NULL)
    return;
  AcquireSRWLockExclusive(&sink->lock);
  sink->on_frame_available = callback;
  sink->frame_callback_context = context;
  ReleaseSRWLockExclusive(&sink->lock);
}

bool CopyPixelBuffer(WindowsRenderingSink* sink,
                     std::vector<uint8_t>& out_buffer,
                     int& out_width,
                     int& out_height) {
  if (sink == NULL)
    return false;

  AcquireSRWLockExclusive(&sink->lock);
  if (sink->disposed || sink->i420_buffer == NULL) {
    ReleaseSRWLockExclusive(&sink->lock);
    return false;
  }

  int32_t w = sink->width;
  int32_t h = sink->height;

  if (w <= 0 || h <= 0) {
    ReleaseSRWLockExclusive(&sink->lock);
    return false;
  }

  // BGRA バッファを確保する
  size_t buffer_size = static_cast<size_t>(w) * h * 4;
  if (out_buffer.size() != buffer_size) {
    out_buffer.resize(buffer_size);
  }

  // I420 → BGRA 変換
  libyuv_ConvertFromI420(
      webrtc_I420Buffer_MutableDataY(sink->i420_buffer),
      webrtc_I420Buffer_StrideY(sink->i420_buffer),
      webrtc_I420Buffer_MutableDataU(sink->i420_buffer),
      webrtc_I420Buffer_StrideU(sink->i420_buffer),
      webrtc_I420Buffer_MutableDataV(sink->i420_buffer),
      webrtc_I420Buffer_StrideV(sink->i420_buffer),
      out_buffer.data(), w * 4, w, h, libyuv_FOURCC_ARGB);

  out_width = w;
  out_height = h;

  ReleaseSRWLockExclusive(&sink->lock);
  return true;
}

void DeleteWindowsRenderingSink(WindowsRenderingSink* sink) {
  if (sink == NULL)
    return;

  AcquireSRWLockExclusive(&sink->lock);
  sink->disposed = true;
  sink->on_frame_available = NULL;
  sink->frame_callback_context = NULL;
  while (sink->inflight_dispatch_count > 0) {
    SleepConditionVariableSRW(&sink->inflight_cond, &sink->lock, INFINITE, 0);
  }

  if (sink->i420_buffer != NULL) {
    webrtc_I420Buffer_Release(sink->i420_buffer);
    sink->i420_buffer = NULL;
  }
  ReleaseSRWLockExclusive(&sink->lock);

  if (sink->sink != NULL) {
    webrtc_VideoSinkInterface_delete(sink->sink);
    sink->sink = NULL;
  }

  free(sink);
}

void* GetVideoSinkPtr(WindowsRenderingSink* sink) {
  if (sink == NULL || sink->sink == NULL)
    return NULL;
  return sink->sink;
}
