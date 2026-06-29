#include "sora_camera_capturer.h"

#include <dirent.h>
#include <fcntl.h>
#include <linux/videodev2.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <csetjmp>
#include <cstring>

#include <jpeglib.h>

#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>
#include <webrtc_c/api/video/video_rotation.h>
#include <webrtc_c/libyuv.h>
#include <webrtc_c/media/base/adapted_video_track_source.h>
#include "sora_sdk/sora_video_constants.h"

// ============================================================================
// GObject 型: SoraLocalPreviewTexture (FlPixelBufferTexture のサブクラス)
// ============================================================================

static gboolean sora_local_preview_texture_copy_pixels(
    FlPixelBufferTexture* texture,
    const uint8_t** out_buffer,
    uint32_t* width,
    uint32_t* height,
    GError** error) {
  (void)error;
  auto* self = SORA_LOCAL_PREVIEW_TEXTURE(texture);
  // capturer は Stop() で明示的に nullptr に設定される前に
  // copy_pixels が呼ばれる可能性があるため、必ずチェックする
  if (!self->capturer) {
    return FALSE;
  }
  const uint8_t* pixels = self->capturer->CopyPreviewPixelBuffer(width, height);
  // カメラがまだ 1 フレームもキャプチャしていない場合は失敗として扱う
  if (!pixels || *width == 0 || *height == 0) {
    return FALSE;
  }
  *out_buffer = pixels;
  return TRUE;
}

G_DEFINE_TYPE(SoraLocalPreviewTexture,
              sora_local_preview_texture,
              fl_pixel_buffer_texture_get_type())

static void sora_local_preview_texture_init(SoraLocalPreviewTexture* self) {
  self->capturer = nullptr;
}

static void sora_local_preview_texture_class_init(
    SoraLocalPreviewTextureClass* klass) {
  FlPixelBufferTextureClass* fb_klass =
      reinterpret_cast<FlPixelBufferTextureClass*>(klass);
  fb_klass->copy_pixels = sora_local_preview_texture_copy_pixels;
}

// ============================================================================
// RGB24 → I420 変換 (MJPEG フォールバック用、BT.601)
// ============================================================================

static void Rgb24ToI420(const uint8_t* rgb,
                        int width,
                        int height,
                        uint8_t* dst_y,
                        int stride_y,
                        uint8_t* dst_u,
                        int stride_u,
                        uint8_t* dst_v,
                        int stride_v) {
  for (int j = 0; j < height; j++) {
    for (int i = 0; i < width; i++) {
      int r = rgb[(j * width + i) * 3 + 0];
      int g = rgb[(j * width + i) * 3 + 1];
      int b = rgb[(j * width + i) * 3 + 2];
      dst_y[j * stride_y + i] =
          static_cast<uint8_t>(((66 * r + 129 * g + 25 * b + 128) >> 8) + 16);
      if ((j & 1) == 0 && (i & 1) == 0) {
        dst_u[(j / 2) * stride_u + (i / 2)] =
            static_cast<uint8_t>(((-38 * r + -74 * g + 112 * b + 128) >> 8) + 128);
        dst_v[(j / 2) * stride_v + (i / 2)] =
            static_cast<uint8_t>(((112 * r + -94 * g + -18 * b + 128) >> 8) + 128);
      }
    }
  }
}

// ============================================================================
// static: デバイス列挙
// ============================================================================

FlValue* SoraCameraCapturer::EnumerateDevices() {
  FlValue* result = fl_value_new_list();

  DIR* dir = opendir("/dev");
  if (!dir) {
    return result;
  }

  // デバイス候補を一時的に保持する。
  // ファイルシステムの readdir 順に依存せず、必ず video0 から並べるために
  // インデックスでソートする。
  struct CandidateDevice {
    int index;
    std::string path;
    std::string label;
    bool has_capture_format = false;
  };
  std::vector<CandidateDevice> candidates;

  struct dirent* entry;
  while ((entry = readdir(dir)) != nullptr) {
    if (strncmp(entry->d_name, "video", 5) != 0) {
      continue;
    }
    std::string device_path = std::string("/dev/") + entry->d_name;

    // デバイスインデックスを抽出する
    int device_index = 0;
    if (sscanf(entry->d_name, "video%d", &device_index) != 1) {
      continue;
    }

    int fd = open(device_path.c_str(), O_RDWR);
    if (fd < 0) {
      continue;
    }
    struct v4l2_capability cap;
    memset(&cap, 0, sizeof(cap));
    if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
      close(fd);
      continue;
    }
    if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
      close(fd);
      continue;
    }

    // V4L2_CAP_VIDEO_CAPTURE フラグが立っていても実際のキャプチャ
    // フォーマットに対応していないデバイス (C922 の /dev/video1 など) を
    // 除外するため、VIDIOC_ENUM_FMT で実効的なフォーマット有無を確認する。
    bool has_format = false;
    struct v4l2_fmtdesc fmt_desc;
    memset(&fmt_desc, 0, sizeof(fmt_desc));
    fmt_desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    for (int i = 0; i < 16; i++) {
      fmt_desc.index = i;
      if (ioctl(fd, VIDIOC_ENUM_FMT, &fmt_desc) < 0) {
        break;
      }
      if (fmt_desc.pixelformat == V4L2_PIX_FMT_YUYV ||
          fmt_desc.pixelformat == V4L2_PIX_FMT_NV12 ||
          fmt_desc.pixelformat == V4L2_PIX_FMT_MJPEG ||
          fmt_desc.pixelformat == V4L2_PIX_FMT_YUV420) {
        has_format = true;
        break;
      }
    }
    close(fd);

    if (!has_format) {
      continue;
    }

    CandidateDevice candidate;
    candidate.index = device_index;
    candidate.path = device_path;
    candidate.label = std::string(
        reinterpret_cast<const char*>(cap.card),
        strnlen(reinterpret_cast<const char*>(cap.card), sizeof(cap.card)));
    candidates.push_back(candidate);
  }
  closedir(dir);

  // デバイスインデックスでソートする
  std::sort(candidates.begin(), candidates.end(),
            [](const CandidateDevice& a, const CandidateDevice& b) {
              return a.index < b.index;
            });

  for (const auto& candidate : candidates) {
    FlValue* device_map = fl_value_new_map();
    fl_value_set_string_take(device_map, "deviceId",
                             fl_value_new_string(candidate.path.c_str()));
    fl_value_set_string_take(device_map, "label",
                             fl_value_new_string(candidate.label.c_str()));
    fl_value_append_take(result, device_map);
  }

  return result;
}

// ============================================================================
// static: フォーマット取得
// ============================================================================

FlValue* SoraCameraCapturer::GetFormats(const std::string& device_id) {
  FlValue* result = fl_value_new_list();

  int fd = open(device_id.c_str(), O_RDWR);
  if (fd < 0) {
    return result;
  }

  struct v4l2_capability cap;
  memset(&cap, 0, sizeof(cap));
  if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0) {
    close(fd);
    return result;
  }
  if (!(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
    close(fd);
    return result;
  }

  struct v4l2_fmtdesc fmt_desc;
  memset(&fmt_desc, 0, sizeof(fmt_desc));
  fmt_desc.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  for (int i = 0;; i++) {
    fmt_desc.index = i;
    if (ioctl(fd, VIDIOC_ENUM_FMT, &fmt_desc) < 0) {
      break;
    }

    struct v4l2_frmsizeenum fsize;
    memset(&fsize, 0, sizeof(fsize));
    fsize.pixel_format = fmt_desc.pixelformat;
    fsize.index = 0;
    if (ioctl(fd, VIDIOC_ENUM_FRAMESIZES, &fsize) < 0) {
      continue;
    }

    if (fsize.type == V4L2_FRMSIZE_TYPE_DISCRETE) {
      for (int j = 0;; j++) {
        fsize.index = j;
        if (ioctl(fd, VIDIOC_ENUM_FRAMESIZES, &fsize) < 0) {
          break;
        }
        int max_fps = 0;
        struct v4l2_frmivalenum fival;
        memset(&fival, 0, sizeof(fival));
        fival.pixel_format = fmt_desc.pixelformat;
        fival.width = fsize.discrete.width;
        fival.height = fsize.discrete.height;
        fival.index = 0;
        if (ioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &fival) == 0 &&
            fival.type == V4L2_FRMIVAL_TYPE_DISCRETE) {
          for (int k = 0;; k++) {
            fival.index = k;
            if (ioctl(fd, VIDIOC_ENUM_FRAMEINTERVALS, &fival) < 0) {
              break;
            }
            int fps = fival.discrete.denominator / fival.discrete.numerator;
            if (fps > max_fps) {
              max_fps = fps;
            }
          }
        }
        if (max_fps == 0) {
          max_fps = 30;
        }
        FlValue* format_map = fl_value_new_map();
        fl_value_set_string_take(
            format_map, "width",
            fl_value_new_int(static_cast<int>(fsize.discrete.width)));
        fl_value_set_string_take(
            format_map, "height",
            fl_value_new_int(static_cast<int>(fsize.discrete.height)));
        fl_value_set_string_take(
            format_map, "maxFrameRate",
            fl_value_new_float(static_cast<double>(max_fps)));
        fl_value_append_take(result, format_map);
      }
    } else if (fsize.type == V4L2_FRMSIZE_TYPE_STEPWISE) {
      // STEPWISE の場合は代表的な解像度のみを列挙する
      unsigned int w_step = fsize.stepwise.step_width;
      if (w_step == 0) {
        w_step = 16;
      }
      unsigned int h_step = fsize.stepwise.step_height;
      if (h_step == 0) {
        h_step = 16;
      }
      unsigned int count = 0;
      for (unsigned int w = fsize.stepwise.min_width;
           w <= fsize.stepwise.max_width && count < 32;
           w += w_step) {
        for (unsigned int h = fsize.stepwise.min_height;
             h <= fsize.stepwise.max_height && count < 32;
             h += h_step) {
          FlValue* format_map = fl_value_new_map();
          fl_value_set_string_take(format_map, "width",
                                   fl_value_new_int(static_cast<int>(w)));
          fl_value_set_string_take(format_map, "height",
                                   fl_value_new_int(static_cast<int>(h)));
          fl_value_set_string_take(format_map, "maxFrameRate",
                                   fl_value_new_float(30.0));
          fl_value_append_take(result, format_map);
          count++;
        }
      }
    }
  }

  close(fd);
  return result;
}

// ============================================================================
// コンストラクタ / デストラクタ
// ============================================================================

SoraCameraCapturer::SoraCameraCapturer(
    const std::string& device_id,
    int width,
    int height,
    int fps,
    FlTextureRegistrar* texture_registrar)
    : device_id_(device_id),
      requested_width_(width),
      requested_height_(height),
      requested_fps_(fps),
      texture_registrar_(texture_registrar) {}

SoraCameraCapturer::~SoraCameraCapturer() {
  Stop();
}

// ============================================================================
// ビデオソースポインタ設定 / エラーコールバック
// ============================================================================

void SoraCameraCapturer::SetVideoSourcePtr(void* video_source_ptr) {
  std::lock_guard<std::mutex> lock(video_source_mutex_);
  video_source_ptr_ = video_source_ptr;
}

void SoraCameraCapturer::SetOnCameraOpenErrorCallback(
    std::function<void(CameraOpenError error_code)> callback) {
  on_camera_open_error_ = std::move(callback);
}

// ============================================================================
// キャプチャ開始
// ============================================================================

void SoraCameraCapturer::Start() {
  if (running_) {
    return;
  }

  // 前回のキャプチャスレッドが joinable な場合は join してから再作成する。
  // CaptureLoop がエラーで早期リターンした場合、running_ は false だが
  // capture_thread_ は joinable なまま残っているため、
  // そのまま代入すると std::terminate が発生する。
  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  // FlPixelBufferTexture の GObject サブクラスを作成してテクスチャ登録する
  preview_texture_ = static_cast<SoraLocalPreviewTexture*>(
      g_object_new(SORA_TYPE_LOCAL_PREVIEW_TEXTURE, nullptr));
  preview_texture_->capturer = this;
  gboolean registered = fl_texture_registrar_register_texture(
      texture_registrar_, FL_TEXTURE(preview_texture_));
  if (!registered) {
    g_object_unref(preview_texture_);
    preview_texture_ = nullptr;
    return;
  }
  preview_texture_id_ = fl_texture_get_id(FL_TEXTURE(preview_texture_));

  running_ = true;
  capture_thread_ = std::thread(&SoraCameraCapturer::CaptureLoop, this);
}

// ============================================================================
// キャプチャスレッドのメインループ
// ============================================================================

void SoraCameraCapturer::CaptureLoop() {
  int fd = open(device_id_.c_str(), O_RDWR);
  if (fd < 0) {
    if (on_camera_open_error_)
      on_camera_open_error_(CameraOpenError::DeviceOpenFailed);
    running_ = false;
    return;
  }
  v4l2_fd_ = fd;

  struct v4l2_capability cap;
  memset(&cap, 0, sizeof(cap));
  if (ioctl(fd, VIDIOC_QUERYCAP, &cap) < 0 ||
      !(cap.capabilities & V4L2_CAP_VIDEO_CAPTURE)) {
    if (on_camera_open_error_)
      on_camera_open_error_(CameraOpenError::DeviceOpenFailed);
    v4l2_fd_ = -1;
    close(fd);
    running_ = false;
    return;
  }

  struct v4l2_format fmt;
  memset(&fmt, 0, sizeof(fmt));
  fmt.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  fmt.fmt.pix.width = static_cast<uint32_t>(requested_width_);
  fmt.fmt.pix.height = static_cast<uint32_t>(requested_height_);

  // 優先フォーマット順: YUYV > NV12 > MJPEG
  uint32_t preferred_formats[] = {
      V4L2_PIX_FMT_YUYV, V4L2_PIX_FMT_NV12, V4L2_PIX_FMT_MJPEG};
  bool format_set = false;
  for (auto pf : preferred_formats) {
    fmt.fmt.pix.pixelformat = pf;
    fmt.fmt.pix.field = V4L2_FIELD_ANY;
    if (ioctl(fd, VIDIOC_S_FMT, &fmt) >= 0) {
      v4l2_pixelformat_ = fmt.fmt.pix.pixelformat;
      format_set = true;
      break;
    }
  }
  if (!format_set) {
    if (on_camera_open_error_)
      on_camera_open_error_(CameraOpenError::VidiocSFmtFailed);
    v4l2_fd_ = -1;
    close(fd);
    running_ = false;
    return;
  }

  // 実際に設定された解像度とバイトストライドを反映する
  requested_width_ = static_cast<int>(fmt.fmt.pix.width);
  requested_height_ = static_cast<int>(fmt.fmt.pix.height);
  v4l2_bytesperline_ = static_cast<int>(fmt.fmt.pix.bytesperline);

  // bytesperline が 0 の場合はピクセルフォーマットから計算する。
  // 一部のドライバはパックドフォーマットで bytesperline を 0 に設定する。
  if (v4l2_bytesperline_ <= 0) {
    if (v4l2_pixelformat_ == V4L2_PIX_FMT_YUYV) {
      v4l2_bytesperline_ = requested_width_ * 2;
    } else if (v4l2_pixelformat_ == V4L2_PIX_FMT_NV12) {
      v4l2_bytesperline_ = requested_width_;
    } else {
      v4l2_bytesperline_ = requested_width_ * 2;
    }
  }

  // FPS 設定
  struct v4l2_streamparm parm;
  memset(&parm, 0, sizeof(parm));
  parm.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  parm.parm.capture.timeperframe.numerator = 1;
  parm.parm.capture.timeperframe.denominator =
      static_cast<uint32_t>(requested_fps_);
  ioctl(fd, VIDIOC_S_PARM, &parm);

  // バッファ要求
  struct v4l2_requestbuffers req;
  memset(&req, 0, sizeof(req));
  req.count = 4;
  req.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  req.memory = V4L2_MEMORY_MMAP;
  if (ioctl(fd, VIDIOC_REQBUFS, &req) < 0) {
    if (on_camera_open_error_)
      on_camera_open_error_(CameraOpenError::VidiocReqbufsFailed);
    v4l2_fd_ = -1;
    close(fd);
    running_ = false;
    return;
  }

  // mmap
  for (unsigned int i = 0; i < req.count; i++) {
    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = i;
    if (ioctl(fd, VIDIOC_QUERYBUF, &buf) < 0) {
      if (on_camera_open_error_)
        on_camera_open_error_(CameraOpenError::MmapFailed);
      CleanupV4l2();
      running_ = false;
      return;
    }
    void* start = mmap(nullptr, buf.length, PROT_READ | PROT_WRITE,
                       MAP_SHARED, fd, buf.m.offset);
    if (start == MAP_FAILED) {
      if (on_camera_open_error_)
        on_camera_open_error_(CameraOpenError::MmapFailed);
      CleanupV4l2();
      running_ = false;
      return;
    }
    v4l2_buffers_.push_back({start, buf.length});
  }

  // 全バッファをキューに投入
  for (unsigned int i = 0; i < req.count; i++) {
    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    buf.index = i;
    if (ioctl(fd, VIDIOC_QBUF, &buf) < 0) {
      // QBUF 失敗時はストリーミング開始前に異常を検出して終了する
      CleanupV4l2();
      running_ = false;
      return;
    }
  }

  // ストリーミング開始
  int v4l2_type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
  if (ioctl(fd, VIDIOC_STREAMON, &v4l2_type) < 0) {
    if (on_camera_open_error_)
      on_camera_open_error_(CameraOpenError::VidiocStreamonFailed);
    CleanupV4l2();
    running_ = false;
    return;
  }

  // メインループ
  while (running_) {
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    struct timeval tv = {0, 100000};  // 100ms タイムアウト
    int r = select(fd + 1, &fds, nullptr, nullptr, &tv);
    if (r < 0) {
      break;
    }
    if (r == 0) {
      continue;  // タイムアウト、running_ を再確認
    }

    struct v4l2_buffer buf;
    memset(&buf, 0, sizeof(buf));
    buf.type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    buf.memory = V4L2_MEMORY_MMAP;
    if (ioctl(fd, VIDIOC_DQBUF, &buf) < 0) {
      break;
    }

    if (buf.index < v4l2_buffers_.size()) {
      ProcessFrame(v4l2_buffers_[buf.index].start, buf.bytesused,
                   v4l2_pixelformat_, requested_width_,
                   requested_height_, v4l2_bytesperline_);
    }

    if (ioctl(fd, VIDIOC_QBUF, &buf) < 0) {
      break;
    }
  }

  CleanupV4l2();
  running_ = false;
}

// ============================================================================
// フレーム処理: ピクセル変換 → AdaptedVideoTrackSource → プレビュー
// ============================================================================

// g_idle_add でメインスレッドに dispatch するためのデータ構造
struct FrameAvailableData {
  FlTextureRegistrar* registrar;
  FlTexture* texture;
};

static gboolean frame_available_idle_cb(gpointer user_data) {
  auto* fd = static_cast<FrameAvailableData*>(user_data);
  fl_texture_registrar_mark_texture_frame_available(fd->registrar, fd->texture);
  g_object_unref(fd->texture);
  g_free(fd);
  return G_SOURCE_REMOVE;
}

void SoraCameraCapturer::ProcessFrame(const void* data,
                                      size_t size,
                                      uint32_t pixelformat,
                                      int width,
                                      int height,
                                      int bytesperline) {
  if (!data || size == 0) {
    return;
  }

  struct webrtc_I420Buffer_refcounted* i420_buffer =
      webrtc_I420Buffer_Create(width, height);
  if (!i420_buffer) {
    return;
  }
  struct webrtc_I420Buffer* i420 = webrtc_I420Buffer_refcounted_get(i420_buffer);

  switch (pixelformat) {
    case V4L2_PIX_FMT_YUYV: {
      // YUYV の 1 行あたりのバイト数は bytesperline (≧ width * 2)
      libyuv_YUY2ToI420(
          static_cast<const uint8_t*>(data), bytesperline,
          webrtc_I420Buffer_MutableDataY(i420),
          webrtc_I420Buffer_StrideY(i420),
          webrtc_I420Buffer_MutableDataU(i420),
          webrtc_I420Buffer_StrideU(i420),
          webrtc_I420Buffer_MutableDataV(i420),
          webrtc_I420Buffer_StrideV(i420), width, height);
      break;
    }
    case V4L2_PIX_FMT_NV12: {
      // NV12 の Y プレーンは bytesperline × height の領域
      const uint8_t* y_plane = static_cast<const uint8_t*>(data);
      const uint8_t* uv_plane = y_plane + bytesperline * height;
      libyuv_NV12ToI420(
          y_plane, bytesperline, uv_plane, bytesperline,
          webrtc_I420Buffer_MutableDataY(i420),
          webrtc_I420Buffer_StrideY(i420),
          webrtc_I420Buffer_MutableDataU(i420),
          webrtc_I420Buffer_StrideU(i420),
          webrtc_I420Buffer_MutableDataV(i420),
          webrtc_I420Buffer_StrideV(i420), width, height);
      break;
    }
    case V4L2_PIX_FMT_MJPEG: {
      struct MjpegErrorMgr {
        struct jpeg_error_mgr pub;
        jmp_buf setjmp_buffer;
      };
      struct jpeg_decompress_struct cinfo;
      MjpegErrorMgr jerr;
      cinfo.err = jpeg_std_error(&jerr.pub);
      jerr.pub.error_exit = [](j_common_ptr cinfo) {
        auto* mgr = reinterpret_cast<MjpegErrorMgr*>(cinfo->err);
        longjmp(mgr->setjmp_buffer, 1);
      };
      bool decoded = false;
      jpeg_create_decompress(&cinfo);
      if (setjmp(jerr.setjmp_buffer)) {
        // libjpeg のエラー発生時はここに飛ぶ。exit() を回避する
        jpeg_destroy_decompress(&cinfo);
        webrtc_I420Buffer_Release(i420);
        return;
      }
      jpeg_mem_src(&cinfo, static_cast<const unsigned char*>(data), size);
      if (jpeg_read_header(&cinfo, TRUE) == JPEG_HEADER_OK) {
        if (jpeg_start_decompress(&cinfo)) {
          int row_stride = cinfo.output_width * cinfo.output_components;
          std::vector<uint8_t> rgb_buffer(row_stride * cinfo.output_height);
          uint8_t* rows[1];
          while (cinfo.output_scanline < cinfo.output_height) {
            rows[0] = rgb_buffer.data() +
                      row_stride * static_cast<size_t>(cinfo.output_scanline);
            jpeg_read_scanlines(&cinfo, rows, 1);
          }
          int decoded_w = static_cast<int>(cinfo.output_width);
          int decoded_h = static_cast<int>(cinfo.output_height);
          // 実際のデコードサイズと要求サイズが異なる場合は i420 を再作成する
          if (decoded_w != width || decoded_h != height) {
            webrtc_I420Buffer_Release(i420);
            i420_buffer = webrtc_I420Buffer_Create(decoded_w, decoded_h);
            if (!i420_buffer) {
              jpeg_finish_decompress(&cinfo);
              jpeg_destroy_decompress(&cinfo);
              return;
            }
            i420 = webrtc_I420Buffer_refcounted_get(i420_buffer);
            width = decoded_w;
            height = decoded_h;
          }
          Rgb24ToI420(
              rgb_buffer.data(), width, height,
              webrtc_I420Buffer_MutableDataY(i420),
              webrtc_I420Buffer_StrideY(i420),
              webrtc_I420Buffer_MutableDataU(i420),
              webrtc_I420Buffer_StrideU(i420),
              webrtc_I420Buffer_MutableDataV(i420),
              webrtc_I420Buffer_StrideV(i420));
          decoded = true;
          jpeg_finish_decompress(&cinfo);
        }
      }
      jpeg_destroy_decompress(&cinfo);
      if (!decoded) {
        // デコード失敗時は I420 を解放して終了する
        webrtc_I420Buffer_Release(i420);
        return;
      }
      break;
    }
    default:
      webrtc_I420Buffer_Release(i420);
      return;
  }

  // ローカルプレビュー用に I420 → RGBA 変換
  {
    std::lock_guard<std::mutex> lock(preview_mutex_);
    preview_width_ = width;
    preview_height_ = height;
    preview_buffer_.resize(static_cast<size_t>(width) * height * 4);
    libyuv_ConvertFromI420(
        webrtc_I420Buffer_MutableDataY(i420),
        webrtc_I420Buffer_StrideY(i420),
        webrtc_I420Buffer_MutableDataU(i420),
        webrtc_I420Buffer_StrideU(i420),
        webrtc_I420Buffer_MutableDataV(i420),
        webrtc_I420Buffer_StrideV(i420),
        preview_buffer_.data(), width * 4,
        width, height, SORA_LIBYUV_FOURCC_RGBA);
  }

  // AdaptedVideoTrackSource にフレームを投入する
  {
    std::lock_guard<std::mutex> lock(video_source_mutex_);
    if (video_source_ptr_) {
      struct webrtc_AdaptedVideoTrackSource* source =
          webrtc_AdaptedVideoTrackSource_refcounted_get(
              static_cast<struct webrtc_AdaptedVideoTrackSource_refcounted*>(
                  video_source_ptr_));
      if (source) {
        struct webrtc_VideoFrameBuffer_refcounted* frame_buffer =
            webrtc_I420Buffer_refcounted_cast_to_webrtc_VideoFrameBuffer(
                i420_buffer);
        struct webrtc_VideoFrameBuilder_unique* builder =
            webrtc_VideoFrameBuilder_new(frame_buffer);
        if (builder) {
          struct webrtc_VideoFrameBuilder* b =
              webrtc_VideoFrameBuilder_unique_get(builder);
          webrtc_VideoFrameBuilder_set_rotation(b, webrtc_VideoRotation_0);
          webrtc_VideoFrameBuilder_set_timestamp_us(b, 0);
          struct webrtc_VideoFrame_unique* frame =
              webrtc_VideoFrameBuilder_build(b);
          webrtc_VideoFrameBuilder_unique_delete(builder);
          if (frame) {
            webrtc_AdaptedVideoTrackSource_OnFrame(
                source, webrtc_VideoFrame_unique_get(frame));
            webrtc_VideoFrame_unique_delete(frame);
          }
        }
      }
    }
  }

  webrtc_I420Buffer_Release(i420);

  // テクスチャフレーム更新を Flutter エンジンに通知する
  // fl_texture_registrar_mark_texture_frame_available はメインスレッドから呼ぶ必要があるため
  // g_idle_add_full でメインスレッドにディスパッチする
  if (preview_texture_ && texture_registrar_) {
    auto* fd = g_new0(FrameAvailableData, 1);
    fd->registrar = texture_registrar_;
    fd->texture = FL_TEXTURE(preview_texture_);
    g_object_ref(fd->texture);
    g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, frame_available_idle_cb, fd,
                    nullptr);
  }
}

// ============================================================================
// プレビューピクセルバッファ取得 (Flutter エンジンからのコールバック)
// ============================================================================

const uint8_t* SoraCameraCapturer::CopyPreviewPixelBuffer(
    uint32_t* out_width,
    uint32_t* out_height) {
  std::lock_guard<std::mutex> lock(preview_mutex_);
  *out_width = static_cast<uint32_t>(preview_width_);
  *out_height = static_cast<uint32_t>(preview_height_);
  if (preview_buffer_.empty()) {
    return nullptr;
  }
  // キャプチャスレッドが preview_buffer_ を再確保しても安全なように
  // 安定した出力バッファにコピーしてから返す
  output_buffer_ = preview_buffer_;
  return output_buffer_.data();
}

// ============================================================================
// キャプチャ停止
// ============================================================================

void SoraCameraCapturer::Stop() {
  running_ = false;

  // StreamOff を発行して DQBUF のブロックを解除する
  int fd = v4l2_fd_.load();
  if (fd >= 0) {
    int v4l2_type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    ioctl(fd, VIDIOC_STREAMOFF, &v4l2_type);
  }

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  // ローカルプレビューテクスチャを登録解除する。
  // GObject 解放の前に capturer ポインタをクリアし、
  // レンダースレッドからの copy_pixels コールバックを安全にする。
  if (preview_texture_ && texture_registrar_) {
    fl_texture_registrar_unregister_texture(
        texture_registrar_, FL_TEXTURE(preview_texture_));
    preview_texture_->capturer = nullptr;
    g_object_unref(preview_texture_);
    preview_texture_ = nullptr;
  }
  preview_texture_id_ = -1;

  // CleanupV4l2 は CaptureLoop() の終了時に呼ばれるため、
  // ここでは呼ばない。二重解放を防ぐ。

  {
    std::lock_guard<std::mutex> lock(video_source_mutex_);
    video_source_ptr_ = nullptr;
  }
}

// ============================================================================
// V4L2 リソース解放
// ============================================================================

void SoraCameraCapturer::CleanupV4l2() {
  for (auto& buf : v4l2_buffers_) {
    if (buf.start != nullptr) {
      munmap(buf.start, buf.length);
    }
  }
  v4l2_buffers_.clear();

  int fd = v4l2_fd_.exchange(-1);
  if (fd >= 0) {
    close(fd);
  }
}
