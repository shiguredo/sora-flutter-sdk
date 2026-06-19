#ifndef SORA_SDK_SORA_CAMERA_CAPTURER_H_
#define SORA_SDK_SORA_CAMERA_CAPTURER_H_

#include <flutter/encodable_value.h>
#include <flutter/texture_registrar.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>

class SoraCameraCapturer {
 public:
  static flutter::EncodableList EnumerateDevices();
  static flutter::EncodableList GetFormats(const std::string& device_id);

  SoraCameraCapturer(const std::string& device_id,
                     int width,
                     int height,
                     int fps,
                     flutter::TextureRegistrar* texture_registrar);
  ~SoraCameraCapturer();

  SoraCameraCapturer(const SoraCameraCapturer&) = delete;
  SoraCameraCapturer& operator=(const SoraCameraCapturer&) = delete;

  void SetVideoSourcePtr(void* video_source_ptr);
  void Start();
  void Stop();

  std::function<void(int errorCode)> on_camera_open_error;
  void set_client_id(int64_t id) { client_id_ = id; }
  int64_t client_id() const { return client_id_; }

  int64_t preview_texture_id() const { return preview_texture_id_; }

  const FlutterDesktopPixelBuffer* CopyPreviewPixelBuffer(size_t width,
                                                          size_t height);

 private:
  bool CreateMediaSource();
  bool CreateSourceReader();
  bool SetCurrentMediaType();
  void CaptureLoop();
  void ProcessSample(IMFSample* sample);
  void Cleanup();

  std::string device_id_;
  int requested_width_;
  int requested_height_;
  int requested_fps_;
  flutter::TextureRegistrar* texture_registrar_;
  int64_t client_id_ = -1;

  void* video_source_ptr_ = nullptr;
  SRWLOCK video_source_lock_ = SRWLOCK_INIT;

  IMFMediaSource* media_source_ = nullptr;
  IMFSourceReader* source_reader_ = nullptr;

  std::atomic<bool> running_{false};
  std::thread capture_thread_;

  int64_t preview_texture_id_ = -1;
  std::unique_ptr<flutter::TextureVariant> texture_variant_;

  std::vector<uint8_t> preview_buffer_;
  int preview_width_ = 0;
  int preview_height_ = 0;
  std::mutex preview_mutex_;
  FlutterDesktopPixelBuffer preview_pixel_buffer_{};
};

#endif
