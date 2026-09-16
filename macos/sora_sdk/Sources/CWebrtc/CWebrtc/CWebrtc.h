// libwebrtc-c C API ラッパーヘッダー
// Swift から import CWebrtc で利用可能にする
// iOS と異なり、macOS では AudioDeviceModule を CoreAudio で直接操作するため
// CWebrtc.h では webrtc_c/objc.h と audio_session.h を include しない。
#pragma once

#include <webrtc_c.h>

// sora_sdk 用の Apple 補助 API
void sora_apple_set_system_tls_cert_verifier(
    struct webrtc_PeerConnectionDependencies* dependencies);

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
