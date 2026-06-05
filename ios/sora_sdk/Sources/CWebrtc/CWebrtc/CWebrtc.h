// libwebrtc-c C API ラッパーヘッダー
// Swift から import CWebrtc で利用可能にする
#pragma once

#include <webrtc_c.h>
// 以下は XCFramework の公開ヘッダ。iOS の AVAudioSession 操作に必要。
// macOS は CoreAudio を直接使用するため CWebrtc.h では include しない。
#include <webrtc_c/objc.h>
#include <webrtc_c/sdk/objc/components/audio/audio_session.h>

// sora_sdk 用の Apple 補助 API
extern const int sora_audio_session_error_none;
extern const int sora_audio_session_error_configuration;
extern const int sora_audio_session_error_input_initialization;

typedef void (*sora_audio_session_initialize_input_callback)(int result,
                                                             void* user_data);

int sora_audio_session_configure(int prefers_video_mode);
void sora_audio_session_initialize_input_async(
    sora_audio_session_initialize_input_callback callback,
    void* user_data);
int sora_audio_session_deactivate(void);

struct webrtc_VideoFrame_unique* sora_video_frame_create(
    struct webrtc_I420Buffer_refcounted* buffer,
    int rotation,
    int64_t timestamp_us,
    uint32_t timestamp_rtp);
struct webrtc_VideoFrame* sora_video_frame_unique_get(
    struct webrtc_VideoFrame_unique* frame);
void sora_video_frame_unique_delete(struct webrtc_VideoFrame_unique* frame);

// Apple レンダリングシンク (CVPixelBuffer ベース)
struct AppleRenderingSink;

struct AppleRenderingSink* apple_rendering_sink_create(void);

void apple_rendering_sink_set_frame_callback(struct AppleRenderingSink* sink,
                                             void (*callback)(void* context),
                                             void* context);

// 戻り値は CFRetain 済みの CVPixelBufferRef。呼び出し側で CFRelease すること。
// NULL の場合フレーム無し。
void* apple_rendering_sink_copy_pixel_buffer(struct AppleRenderingSink* sink);

void apple_rendering_sink_delete(struct AppleRenderingSink* sink);

// レンダリングシンクの VideoSinkInterface ポインタを取得する
void* apple_rendering_sink_get_sink_ptr(struct AppleRenderingSink* sink);
