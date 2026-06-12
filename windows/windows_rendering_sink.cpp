#include "windows_rendering_sink.h"

#include <cstring>

#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>
#include <webrtc_c/api/video/video_frame_buffer.h>
#include <webrtc_c/api/video/video_rotation.h>
#include <webrtc_c/api/video/video_sink_interface.h>
#include <webrtc_c/libyuv.h>

// I420 バッファを指定角度だけ回転させた新規バッファを返す。
// rotation が 90/180/270 以外の場合は NULL を返す。
// macOS apple_bridge.c の create_rotated_i420_buffer と同一ロジック。
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

  // webrtc_I420Buffer_refcounted_get は借用ハンドルであり、別途解放は不要。
  // 返された raw buffer は rotated_ref と同じ参照カウントを共有する。
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

// VideoSinkInterface.OnFrame コールバック。
// webrtc の内部スレッドから呼ばれる。
// SRWLOCK で保護された i420_buffer にフレームを保存し、フレーム通知
// コールバックを呼び出して MarkTextureFrameAvailable をトリガーする。
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

  // ToI420 は新しい参照を返す。呼び出し側で Release が必要。
  struct webrtc_I420Buffer_refcounted* i420_ref =
      webrtc_VideoFrameBuffer_ToI420(frame_buffer);
  webrtc_VideoFrameBuffer_Release(frame_buffer);

  struct webrtc_I420Buffer* source_buffer =
      i420_ref == NULL ? NULL : webrtc_I420Buffer_refcounted_get(i420_ref);
  if (source_buffer == NULL) {
    ReleaseSRWLockExclusive(&sink->lock);
    return;
  }

  // フレームの回転情報に従って I420 バッファを回転させる。
  // 回転が不要 (rotation == 0) の場合は CreateRotatedI420Buffer が
  // NULL を返すため、元のバッファを AddRef して保持する。
  struct webrtc_I420Buffer* rotated_buffer =
      CreateRotatedI420Buffer(source_buffer, webrtc_VideoFrame_rotation(frame));
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

  // フレーム通知コールバックとコンテキストをロック下で読む。
  // コールバックはロックを解放した後に呼び出す（デッドロック防止）。
  frame_available_fn cb = sink->on_frame_available;
  void* ctx = sink->frame_callback_context;
  if (cb != NULL) {
    // コールバック発行前に inflight を増やし、DeleteWindowsRenderingSink
    // がコールバック完了まで待機できるようにする。
    sink->inflight_dispatch_count++;
  }
  ReleaseSRWLockExclusive(&sink->lock);

  // ToI420 が返した source_buffer の参照を解放する。
  // 回転バッファを使う場合は source_buffer は不要になる。
  if (source_buffer != NULL) {
    webrtc_I420Buffer_Release(source_buffer);
  }

  if (cb != NULL) {
    cb(ctx);

    // コールバック完了後に inflight を減らし、待機中の
    // DeleteWindowsRenderingSink を起こす。
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
  WindowsRenderingSink* sink = static_cast<WindowsRenderingSink*>(
      calloc(1, sizeof(WindowsRenderingSink)));
  if (sink == NULL)
    return NULL;

  InitializeSRWLock(&sink->lock);
  InitializeConditionVariable(&sink->inflight_cond);

  struct webrtc_VideoSinkInterface_cbs cbs;
  std::memset(&cbs, 0, sizeof(cbs));
  cbs.OnFrame = OnFrame;
  cbs.OnDiscardedFrame = OnDiscardedFrame;
  cbs.OnDestroy = OnDestroy;
  sink->sink = webrtc_VideoSinkInterface_new(&cbs, sink);
  if (sink->sink == NULL) {
    free(sink);
    return NULL;
  }

  return sink;
}

void WindowsRenderingSinkSetFrameCallback(WindowsRenderingSink* sink,
                                          frame_available_fn callback,
                                          void* context) {
  if (sink == NULL)
    return;
  // SRWLOCK で保護してコールバックポインタを設定する。
  // OnFrame はロック下でこの値を読み取るため、競合なく安全に更新できる。
  AcquireSRWLockExclusive(&sink->lock);
  sink->on_frame_available = callback;
  sink->frame_callback_context = context;
  ReleaseSRWLockExclusive(&sink->lock);
}

bool WindowsRenderingSinkCopyPixelBuffer(WindowsRenderingSink* sink,
                                         std::vector<uint8_t>& out_buffer,
                                         int& out_width,
                                         int& out_height) {
  if (sink == NULL)
    return false;

  // 最新の I420 フレームを SRWLOCK で保護して読み取り、BGRA に変換する。
  // この関数は Flutter エンジンのレンダリングスレッドから呼ばれるため、
  // webrtc スレッドの OnFrame との排他が必要。
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

  size_t buffer_size = static_cast<size_t>(w) * h * 4;
  if (out_buffer.size() != buffer_size) {
    out_buffer.resize(buffer_size);
  }

  // I420 → BGRA (ARGB fourcc) 変換。
  // libyuv_FOURCC_ARGB は little-endian 環境では BGRA バイト順
  // (B, G, R, A) で出力される。既存の sora_camera_capturer.cpp と
  // macOS apple_bridge.c も同じ FOURCC を使用している。
  if (libyuv_ConvertFromI420(webrtc_I420Buffer_MutableDataY(sink->i420_buffer),
                             webrtc_I420Buffer_StrideY(sink->i420_buffer),
                             webrtc_I420Buffer_MutableDataU(sink->i420_buffer),
                             webrtc_I420Buffer_StrideU(sink->i420_buffer),
                             webrtc_I420Buffer_MutableDataV(sink->i420_buffer),
                             webrtc_I420Buffer_StrideV(sink->i420_buffer),
                             out_buffer.data(), w * 4, w, h,
                             libyuv_FOURCC_ARGB) != 0) {
    ReleaseSRWLockExclusive(&sink->lock);
    return false;
  }

  out_width = w;
  out_height = h;

  ReleaseSRWLockExclusive(&sink->lock);
  return true;
}

void DeleteWindowsRenderingSink(WindowsRenderingSink* sink) {
  if (sink == NULL)
    return;

  // 三段階でクリーンアップする:
  // 1. disposed を設定し、新規 OnFrame を即座に棄却させる
  // 2. コールバックポインタを NULL 化し、以降のフレーム通知を止める
  // 3. inflight_dispatch_count が 0 になるまで待機し、実行中の
  //    コールバックが全て完了したことを確認する
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

void* WindowsRenderingSinkGetVideoSinkPtr(WindowsRenderingSink* sink) {
  if (sink == NULL || sink->sink == NULL)
    return NULL;
  return sink->sink;
}
