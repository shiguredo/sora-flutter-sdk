#include "sora_camera_capturer.h"

#include <flutter/standard_method_codec.h>

#include <mferror.h>
#include <set>

// Media Foundation API の DWORD 引数に符号付き定数が使われる箇所で
// C4245 (signed/unsigned mismatch) が発生するため抑制する。
#pragma warning(disable : 4245)
#include <sstream>

// libwebrtc-c / libyuv
// webrtc_c.h は Objective-C ヘッダを含むため Windows ではインクルードしない。
#include <webrtc_c/api/video/i420_buffer.h>
#include <webrtc_c/api/video/video_frame.h>
#include <webrtc_c/api/video/video_rotation.h>
#include <webrtc_c/libyuv.h>
#include <webrtc_c/media/base/adapted_video_track_source.h>

// libyuv の FOURCC_ABGR 値。
// webrtc_c/libyuv.h は FOURCC_ARGB / FOURCC_BGRA しかエクスポートしていないため、
// FOURCC_ABGR を直接定義する。
// ConvertFromI420 の内部では FOURCC_ABGR がサポートされており、
// little-endian でメモリ上 [R][G][B][A] (RGBA) バイト順で出力される。
static constexpr uint32_t kLibyuvFourccAbgr =
    (uint32_t)('A') | ((uint32_t)('B') << 8) | ((uint32_t)('G') << 16) |
    ((uint32_t)('R') << 24);

// ============================================================================
// static: デバイス列挙
// ============================================================================

flutter::EncodableList SoraCameraCapturer::EnumerateDevices() {
  flutter::EncodableList result;

  HRESULT hr = MFStartup(MF_VERSION);
  if (FAILED(hr)) {
    return result;
  }

  IMFAttributes* attributes = nullptr;
  hr = MFCreateAttributes(&attributes, 1);
  if (SUCCEEDED(hr)) {
    hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                             MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  }

  IMFActivate** devices = nullptr;
  UINT32 count = 0;
  if (SUCCEEDED(hr)) {
    hr = MFEnumDeviceSources(attributes, &devices, &count);
  }

  if (SUCCEEDED(hr)) {
    for (UINT32 i = 0; i < count; ++i) {
      WCHAR symbolic_link[MAX_PATH] = {};
      bool valid = SUCCEEDED(devices[i]->GetString(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
          symbolic_link, MAX_PATH, nullptr));

      WCHAR friendly_name[MAX_PATH] = {};
      if (valid) {
        valid = SUCCEEDED(devices[i]->GetString(
            MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME,
            friendly_name, MAX_PATH, nullptr));
      }

      if (valid) {
        flutter::EncodableMap device_map;
        int buf_size = WideCharToMultiByte(CP_UTF8, 0, symbolic_link, -1, nullptr,
                                           0, nullptr, nullptr);
        std::string device_id(buf_size, '\0');
        WideCharToMultiByte(CP_UTF8, 0, symbolic_link, -1, &device_id[0],
                            buf_size, nullptr, nullptr);
        device_id.pop_back();

        buf_size = WideCharToMultiByte(CP_UTF8, 0, friendly_name, -1, nullptr, 0,
                                       nullptr, nullptr);
        std::string label(buf_size, '\0');
        WideCharToMultiByte(CP_UTF8, 0, friendly_name, -1, &label[0], buf_size,
                            nullptr, nullptr);
        label.pop_back();

        device_map[flutter::EncodableValue("deviceId")] =
            flutter::EncodableValue(device_id);
        device_map[flutter::EncodableValue("label")] =
            flutter::EncodableValue(label);
        result.push_back(flutter::EncodableValue(device_map));
      }

      devices[i]->Release();
    }
    CoTaskMemFree(devices);
  }

  if (attributes) {
    attributes->Release();
  }

  MFShutdown();
  return result;
}

// ============================================================================
// static: フォーマット取得
// ============================================================================

flutter::EncodableList SoraCameraCapturer::GetFormats(
    const std::string& device_id) {
  flutter::EncodableList result;

  HRESULT hr = MFStartup(MF_VERSION);
  if (FAILED(hr)) {
    return result;
  }

  // シンボリックリンクから IMFMediaSource を作成する
  IMFMediaSource* media_source = nullptr;
  {
    IMFAttributes* attributes = nullptr;
    hr = MFCreateAttributes(&attributes, 2);
    if (SUCCEEDED(hr)) {
      attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
      int buf_len = MultiByteToWideChar(CP_UTF8, 0, device_id.c_str(), -1,
                                        nullptr, 0);
      std::wstring wide_id(buf_len, L'\0');
      MultiByteToWideChar(CP_UTF8, 0, device_id.c_str(), -1, &wide_id[0],
                          buf_len);
      attributes->SetString(
          MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
          wide_id.c_str());
      hr = MFCreateDeviceSource(attributes, &media_source);
      attributes->Release();
    }
  }

  if (SUCCEEDED(hr) && media_source) {
    IMFSourceReader* reader = nullptr;
    hr = MFCreateSourceReaderFromMediaSource(media_source, nullptr, &reader);
    if (SUCCEEDED(hr)) {
      std::set<std::pair<UINT32, UINT32>> seen_resolutions;

      for (DWORD type_index = 0;; ++type_index) {
        IMFMediaType* media_type = nullptr;
        hr = reader->GetNativeMediaType(
            MF_SOURCE_READER_FIRST_VIDEO_STREAM, type_index, &media_type);
        if (hr == MF_E_NO_MORE_TYPES || FAILED(hr)) {
          break;
        }

        UINT32 width = 0, height = 0;
        hr = MFGetAttributeSize(media_type, MF_MT_FRAME_SIZE, &width,
                                &height);
        if (FAILED(hr) || width == 0 || height == 0) {
          media_type->Release();
          continue;
        }

        UINT32 fps_num = 0, fps_den = 0;
        hr = MFGetAttributeRatio(media_type, MF_MT_FRAME_RATE, &fps_num,
                                 &fps_den);
        if (FAILED(hr) || fps_num == 0 || fps_den == 0) {
          fps_num = 30;
          fps_den = 1;
        }

        auto inserted = seen_resolutions.emplace(width, height).second;
        if (!inserted) {
          media_type->Release();
          continue;
        }

        flutter::EncodableMap format_map;
        format_map[flutter::EncodableValue("width")] =
            flutter::EncodableValue(static_cast<int>(width));
        format_map[flutter::EncodableValue("height")] =
            flutter::EncodableValue(static_cast<int>(height));
        double max_fps =
            static_cast<double>(fps_num) / static_cast<double>(fps_den);
        format_map[flutter::EncodableValue("maxFrameRate")] =
            flutter::EncodableValue(max_fps);
        result.push_back(flutter::EncodableValue(format_map));

        media_type->Release();
      }

      reader->Release();
    }
    media_source->Release();
  }

  MFShutdown();
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
    flutter::TextureRegistrar* texture_registrar)
    : device_id_(device_id),
      requested_width_(width),
      requested_height_(height),
      requested_fps_(fps),
      texture_registrar_(texture_registrar) {}

SoraCameraCapturer::~SoraCameraCapturer() {
  Stop();
}

// ============================================================================
// ビデオソースポインタ設定
// ============================================================================

void SoraCameraCapturer::SetVideoSourcePtr(void* video_source_ptr) {
  AcquireSRWLockExclusive(&video_source_lock_);
  video_source_ptr_ = video_source_ptr;
  ReleaseSRWLockExclusive(&video_source_lock_);
}

// ============================================================================
// キャプチャ開始
// ============================================================================

void SoraCameraCapturer::Start() {
  if (running_) {
    return;
  }

  // ローカルプレビュー用テクスチャを登録する
  auto texture = std::make_unique<flutter::PixelBufferTexture>(
      [this](size_t width, size_t height) {
        return this->CopyPreviewPixelBuffer(width, height);
      });
  texture_variant_ =
      std::make_unique<flutter::TextureVariant>(std::move(*texture));
  preview_texture_id_ =
      texture_registrar_->RegisterTexture(texture_variant_.get());

  running_ = true;
  capture_thread_ = std::thread(&SoraCameraCapturer::CaptureLoop, this);
}

// ============================================================================
// キャプチャスレッドのメインループ
// ============================================================================

void SoraCameraCapturer::CaptureLoop() {
  HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(hr)) {
    if (on_camera_open_error) on_camera_open_error(0);
    running_ = false;
    return;
  }

  hr = MFStartup(MF_VERSION);
  if (FAILED(hr)) {
    if (on_camera_open_error) on_camera_open_error(1);
    CoUninitialize();
    running_ = false;
    return;
  }

  if (!CreateMediaSource()) {
    if (on_camera_open_error) on_camera_open_error(2);
    MFShutdown();
    CoUninitialize();
    running_ = false;
    return;
  }

  if (!CreateSourceReader()) {
    if (on_camera_open_error) on_camera_open_error(3);
    Cleanup();
    running_ = false;
    return;
  }

  if (!SetCurrentMediaType()) {
    if (on_camera_open_error) on_camera_open_error(4);
    Cleanup();
    running_ = false;
    return;
  }

  while (running_) {
    DWORD stream_index = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    IMFSample* sample = nullptr;

    hr = source_reader_->ReadSample(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM,
        0,  // flags
        &stream_index, &flags, &timestamp, &sample);

    if (FAILED(hr)) {
      break;
    }

    if (flags & MF_SOURCE_READERF_STREAMTICK) {
      if (sample) {
        sample->Release();
      }
      continue;
    }

    if (flags & MF_SOURCE_READERF_ENDOFSTREAM) {
      if (sample) {
        sample->Release();
      }
      break;
    }

    if (sample) {
      ProcessSample(sample);
      sample->Release();
    }
  }

  Cleanup();
}

// ============================================================================
// Media Foundation リソース作成
// ============================================================================

bool SoraCameraCapturer::CreateMediaSource() {
  IMFAttributes* attributes = nullptr;
  HRESULT hr = MFCreateAttributes(&attributes, 2);
  if (FAILED(hr)) {
    return false;
  }

  hr = attributes->SetGUID(MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
                           MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);
  if (SUCCEEDED(hr)) {
    int buf_len = MultiByteToWideChar(CP_UTF8, 0, device_id_.c_str(), -1,
                                      nullptr, 0);
    std::wstring wide_id(buf_len, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, device_id_.c_str(), -1, &wide_id[0],
                        buf_len);
    hr = attributes->SetString(
        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_SYMBOLIC_LINK,
        wide_id.c_str());
  }

  if (SUCCEEDED(hr)) {
    hr = MFCreateDeviceSource(attributes, &media_source_);
  }

  attributes->Release();
  return SUCCEEDED(hr) && media_source_ != nullptr;
}

bool SoraCameraCapturer::CreateSourceReader() {
  IMFAttributes* attributes = nullptr;
  HRESULT hr = MFCreateAttributes(&attributes, 1);
  if (SUCCEEDED(hr)) {
    UINT32 value = 1;
    hr = attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, value);
  }
  if (SUCCEEDED(hr)) {
    hr = MFCreateSourceReaderFromMediaSource(media_source_, attributes,
                                             &source_reader_);
  }
  if (attributes) {
    attributes->Release();
  }
  return SUCCEEDED(hr) && source_reader_ != nullptr;
}

bool SoraCameraCapturer::SetCurrentMediaType() {
  IMFMediaType* media_type = nullptr;
  HRESULT hr = MFCreateMediaType(&media_type);
  if (FAILED(hr)) {
    return false;
  }

  hr = media_type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
  if (SUCCEEDED(hr)) {
    hr = media_type->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_NV12);
  }
  if (SUCCEEDED(hr)) {
    hr = MFSetAttributeSize(media_type, MF_MT_FRAME_SIZE,
                            requested_width_, requested_height_);
  }
  if (SUCCEEDED(hr) && requested_fps_ > 0) {
    hr = MFSetAttributeRatio(media_type, MF_MT_FRAME_RATE,
                             requested_fps_, 1);
  }

  if (SUCCEEDED(hr)) {
    hr = source_reader_->SetCurrentMediaType(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, media_type);
  }

  media_type->Release();

  if (SUCCEEDED(hr)) {
    IMFMediaType* actual_type = nullptr;
    hr = source_reader_->GetCurrentMediaType(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM, &actual_type);
    if (SUCCEEDED(hr)) {
      UINT32 w = 0, h = 0;
      MFGetAttributeSize(actual_type, MF_MT_FRAME_SIZE, &w, &h);
      if (w > 0 && h > 0) {
        requested_width_ = w;
        requested_height_ = h;
      }
      actual_type->Release();
    }
  }

  return SUCCEEDED(hr);
}

// ============================================================================
// フレーム処理: NV12 -> I420 -> AdaptedVideoTrackSource
// ============================================================================

void SoraCameraCapturer::ProcessSample(IMFSample* sample) {
  IMFMediaBuffer* media_buffer = nullptr;
  HRESULT hr = sample->GetBufferByIndex(0, &media_buffer);
  if (FAILED(hr)) {
    return;
  }

  IMF2DBuffer* buffer_2d = nullptr;
  hr = media_buffer->QueryInterface(IID_PPV_ARGS(&buffer_2d));

  BYTE* scanline0 = nullptr;
  LONG pitch0 = 0;
  BYTE* scanline1 = nullptr;
  LONG pitch1 = 0;

  if (SUCCEEDED(hr)) {
    // Windows SDK 10.0.26100 以降、IMF2DBuffer::Lock2D の引数が 2 つに
    // 変更された。NV12 の UV プレーンは Y プレーンの直後に配置される。
    hr = buffer_2d->Lock2D(&scanline0, &pitch0);
    if (SUCCEEDED(hr)) {
      // NV12: UV プレーンは Y プレーン (pitch0 * height) の直後
      scanline1 = scanline0 + pitch0 * requested_height_;
      pitch1 = pitch0;
    }
  }

  if (SUCCEEDED(hr) && scanline0) {
    int width = requested_width_;
    int height = requested_height_;

    // NV12 -> I420 変換
    struct webrtc_I420Buffer_refcounted* i420_buffer =
        webrtc_I420Buffer_Create(width, height);
    if (i420_buffer) {
      struct webrtc_I420Buffer* i420 =
          webrtc_I420Buffer_refcounted_get(i420_buffer);

      libyuv_NV12ToI420(
          scanline0, pitch0,
          scanline1, pitch1,
          webrtc_I420Buffer_MutableDataY(i420),
          webrtc_I420Buffer_StrideY(i420),
          webrtc_I420Buffer_MutableDataU(i420),
          webrtc_I420Buffer_StrideU(i420),
          webrtc_I420Buffer_MutableDataV(i420),
          webrtc_I420Buffer_StrideV(i420),
          width, height);

      // ローカルプレビュー用に I420 -> RGBA 変換
      // Flutter Windows の PixelBufferTexture は GL_RGBA を期待するため、
      // FOURCC_ABGR (little-endian でメモリ上 [R][G][B][A] バイト順) を使用する。
      {
        std::lock_guard<std::mutex> lock(preview_mutex_);
        preview_width_ = width;
        preview_height_ = height;
        preview_buffer_.resize(width * height * 4);
        libyuv_ConvertFromI420(
            webrtc_I420Buffer_MutableDataY(i420),
            webrtc_I420Buffer_StrideY(i420),
            webrtc_I420Buffer_MutableDataU(i420),
            webrtc_I420Buffer_StrideU(i420),
            webrtc_I420Buffer_MutableDataV(i420),
            webrtc_I420Buffer_StrideV(i420),
            preview_buffer_.data(), width * 4,
            width, height, kLibyuvFourccAbgr);
      }

      // AdaptedVideoTrackSource にフレームを投入する
      AcquireSRWLockShared(&video_source_lock_);
      void* source_ptr = video_source_ptr_;
      ReleaseSRWLockShared(&video_source_lock_);

      if (source_ptr) {
        LONGLONG timestamp_us = 0;
        sample->GetSampleTime(&timestamp_us);
        timestamp_us /= 10;

        struct webrtc_AdaptedVideoTrackSource* source =
            webrtc_AdaptedVideoTrackSource_refcounted_get(
                static_cast<struct webrtc_AdaptedVideoTrackSource_refcounted*>(
                    source_ptr));
        if (source) {
          struct webrtc_VideoFrameBuffer_refcounted* frame_buffer =
              webrtc_I420Buffer_refcounted_cast_to_webrtc_VideoFrameBuffer(
                  i420_buffer);
          struct webrtc_VideoFrameBuilder_unique* builder =
              webrtc_VideoFrameBuilder_new(frame_buffer);
          if (builder) {
            struct webrtc_VideoFrameBuilder* b =
                webrtc_VideoFrameBuilder_unique_get(builder);
            webrtc_VideoFrameBuilder_set_rotation(b,
                                                  webrtc_VideoRotation_0);
            webrtc_VideoFrameBuilder_set_timestamp_us(b, timestamp_us);
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

      webrtc_I420Buffer_Release(
          webrtc_I420Buffer_refcounted_get(i420_buffer));
    }

    buffer_2d->Unlock2D();
  }

  if (buffer_2d) {
    buffer_2d->Release();
  }
  media_buffer->Release();

  // テクスチャフレーム更新を Flutter エンジンに通知する
  if (preview_texture_id_ >= 0) {
    texture_registrar_->MarkTextureFrameAvailable(preview_texture_id_);
  }
}

// ============================================================================
// キャプチャ停止
// ============================================================================

void SoraCameraCapturer::Stop() {
  if (!running_) {
    return;
  }
  running_ = false;

  if (capture_thread_.joinable()) {
    capture_thread_.join();
  }

  // ローカルプレビューテクスチャを登録解除する
  if (preview_texture_id_ >= 0 && texture_registrar_) {
    texture_registrar_->UnregisterTexture(preview_texture_id_, nullptr);
    preview_texture_id_ = -1;
    texture_variant_.reset();
  }

  AcquireSRWLockExclusive(&video_source_lock_);
  video_source_ptr_ = nullptr;
  ReleaseSRWLockExclusive(&video_source_lock_);
}

// ============================================================================
// リソース解放
// ============================================================================

void SoraCameraCapturer::Cleanup() {
  if (source_reader_) {
    source_reader_->Release();
    source_reader_ = nullptr;
  }
  if (media_source_) {
    media_source_->Release();
    media_source_ = nullptr;
  }
  MFShutdown();
  CoUninitialize();
}

// ============================================================================
// プレビューピクセルバッファ取得 (Flutter エンジンからのコールバック)
// ============================================================================

const FlutterDesktopPixelBuffer* SoraCameraCapturer::CopyPreviewPixelBuffer(
    size_t width, size_t height) {
  (void)width;
  (void)height;
  std::lock_guard<std::mutex> lock(preview_mutex_);
  preview_pixel_buffer_.buffer = preview_buffer_.data();
  preview_pixel_buffer_.width = preview_width_;
  preview_pixel_buffer_.height = preview_height_;
  preview_pixel_buffer_.release_callback = nullptr;
  preview_pixel_buffer_.release_context = nullptr;
  return &preview_pixel_buffer_;
}
