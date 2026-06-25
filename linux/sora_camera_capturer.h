#ifndef SORA_SDK_SORA_CAMERA_CAPTURER_H_
#define SORA_SDK_SORA_CAMERA_CAPTURER_H_

#include <flutter_linux/flutter_linux.h>

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

// CaptureLoop() 内でカメラキャプチャの初期化に失敗した際のエラーコード
enum class CameraOpenError {
  DeviceOpenFailed = 0,   // open(/dev/videoX) 失敗
  VidiocSFmtFailed = 1,   // VIDIOC_S_FMT 失敗
  VidiocReqbufsFailed = 2,// VIDIOC_REQBUFS 失敗
  MmapFailed = 3,        // mmap バッファ確保失敗
  VidiocStreamonFailed = 4,// VIDIOC_STREAMON 失敗
};

// ---------------------------------------------------------------------------
// SoraLocalPreviewTexture: FlPixelBufferTexture の GObject サブクラス
// G_DECLARE_FINAL_TYPE の前に struct 定義が必要
// ---------------------------------------------------------------------------

class SoraCameraCapturer;

typedef struct _SoraLocalPreviewTexture SoraLocalPreviewTexture;
struct _SoraLocalPreviewTexture {
  FlPixelBufferTexture parent_instance;
  SoraCameraCapturer* capturer;
};

#define SORA_TYPE_LOCAL_PREVIEW_TEXTURE sora_local_preview_texture_get_type()
G_DECLARE_FINAL_TYPE(SoraLocalPreviewTexture,
                     sora_local_preview_texture,
                     SORA,
                     LOCAL_PREVIEW_TEXTURE,
                     FlPixelBufferTexture)

// ---------------------------------------------------------------------------
// SoraCameraCapturer: V4L2 カメラキャプチャ
// ---------------------------------------------------------------------------

class SoraCameraCapturer {
 public:
  static FlValue* EnumerateDevices();
  static FlValue* GetFormats(const std::string& device_id);

  SoraCameraCapturer(const std::string& device_id,
                     int width,
                     int height,
                     int fps,
                     FlTextureRegistrar* texture_registrar);
  ~SoraCameraCapturer();

  SoraCameraCapturer(const SoraCameraCapturer&) = delete;
  SoraCameraCapturer& operator=(const SoraCameraCapturer&) = delete;

  void SetVideoSourcePtr(void* video_source_ptr);
  void Start();
  void Stop();

  void SetOnCameraOpenErrorCallback(
      std::function<void(CameraOpenError error_code)> callback);

  int64_t preview_texture_id() const { return preview_texture_id_; }

  // FlPixelBufferTexture の copy_pixels から呼ばれる。
  // RGBA データのポインタと実サイズを返す。
  const uint8_t* CopyPreviewPixelBuffer(uint32_t* out_width,
                                        uint32_t* out_height);

 private:
  void CaptureLoop();
  void ProcessFrame(const void* data, size_t size, uint32_t pixelformat,
                    int width, int height);
  void CleanupV4l2();

  std::string device_id_;
  int requested_width_;
  int requested_height_;
  int requested_fps_;
  FlTextureRegistrar* texture_registrar_;

  std::function<void(CameraOpenError error_code)> on_camera_open_error_;

  void* video_source_ptr_ = nullptr;
  std::mutex video_source_mutex_;

  // V4L2 リソース
  int v4l2_fd_ = -1;
  uint32_t v4l2_pixelformat_ = 0;
  struct Buffer {
    void* start;
    size_t length;
  };
  std::vector<Buffer> v4l2_buffers_;

  std::atomic<bool> running_{false};
  std::thread capture_thread_;

  // ローカルプレビュー用テクスチャ
  int64_t preview_texture_id_ = -1;
  SoraLocalPreviewTexture* preview_texture_ = nullptr;

  // プレビュー RGBA バッファ
  std::vector<uint8_t> preview_buffer_;
  int preview_width_ = 0;
  int preview_height_ = 0;
  std::mutex preview_mutex_;
};

#endif
