/*
 * Apple (iOS/macOS) 用 C ブリッジ
 *
 * 1. PeerConnectionObserver コールバックブリッジ (sora_observer_bridge_*)
 *    - Android の jni_onload.c と同一ロジック (JNI 部分を除く)
 *    - NativeCallable.listener はポインタの値だけコピーするため、
 *      C 側で同期的にデータを抽出し Dart に渡す
 *
 * 2. リモートビデオレンダリング (apple_rendering_sink_*)
 *    - CVPixelBuffer ベースのレンダリングシンク
 *    - I420 -> BGRA 変換して FlutterTexture で表示する
 */

#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <dispatch/dispatch.h>
#include <CoreVideo/CoreVideo.h>
#include "CWebrtc/CWebrtc.h"

/* ===========================================================================
 * リモートビデオレンダリング用構造体
 * =========================================================================== */

typedef void (*frame_available_fn)(void* context);

typedef struct AppleRenderingSink {
    struct webrtc_VideoSinkInterface* sink;
    pthread_mutex_t lock;
    pthread_cond_t inflight_cond;
    int disposed;
    int inflight_dispatch_count;
    /* I420 バッファ (最新フレーム) */
    struct webrtc_I420Buffer* i420_buffer;
    int32_t width;
    int32_t height;
    /* BGRA ピクセルバッファ */
    CVPixelBufferRef pixel_buffer;
    /* フレーム通知コールバック (メインスレッドで呼ばれる) */
    frame_available_fn on_frame_available;
    void* frame_callback_context;
} AppleRenderingSink;

__attribute__((visibility("default")))
struct webrtc_VideoFrame_unique* sora_video_frame_create(
    struct webrtc_I420Buffer_refcounted* buffer,
    int rotation,
    int64_t timestamp_us,
    uint32_t timestamp_rtp) {
    struct webrtc_VideoFrameBuilder_unique* builder_unique =
        webrtc_VideoFrameBuilder_new(
            (struct webrtc_VideoFrameBuffer_refcounted*)buffer);
    if (builder_unique == NULL) {
        return NULL;
    }

    struct webrtc_VideoFrameBuilder* builder =
        webrtc_VideoFrameBuilder_unique_get(builder_unique);
    webrtc_VideoFrameBuilder_set_rotation(builder, rotation);
    webrtc_VideoFrameBuilder_set_timestamp_us(builder, timestamp_us);
    webrtc_VideoFrameBuilder_set_timestamp_rtp(builder, timestamp_rtp);

    struct webrtc_VideoFrame_unique* frame =
        webrtc_VideoFrameBuilder_build(builder);
    webrtc_VideoFrameBuilder_unique_delete(builder_unique);
    return frame;
}

__attribute__((visibility("default")))
struct webrtc_VideoFrame* sora_video_frame_unique_get(
    struct webrtc_VideoFrame_unique* frame) {
    return webrtc_VideoFrame_unique_get(frame);
}

__attribute__((visibility("default")))
void sora_video_frame_unique_delete(struct webrtc_VideoFrame_unique* frame) {
    webrtc_VideoFrame_unique_delete(frame);
}

/// I420 バッファを指定角度だけ回転させた新規バッファを返す。
/// rotation が 90/180/270 以外の場合は NULL を返す。
/// 成功時の戻り値は refcount=1 の新規バッファであり、呼び出し側で Release すること。
static struct webrtc_I420Buffer* create_rotated_i420_buffer(
    struct webrtc_I420Buffer* source,
    int rotation) {
    if (source == NULL) return NULL;
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
        // rotated_ref は借用ハンドル (WEBRTC_DECLARE_REFCOUNTED) であり
        // 専用の Release API が存在しないため解放不要。
        return NULL;
    }

    if (libyuv_I420Rotate(
            webrtc_I420Buffer_MutableDataY(source),
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
            webrtc_I420Buffer_StrideV(rotated),
            src_width,
            src_height,
            rotation) != 0) {
        webrtc_I420Buffer_Release(rotated);
        return NULL;
    }

    return rotated;
}

static void on_apple_frame(const struct webrtc_VideoFrame* frame,
                            void* user_data) {
    AppleRenderingSink* sink = (AppleRenderingSink*)user_data;
    if (sink == NULL) return;

    pthread_mutex_lock(&sink->lock);
    if (sink->disposed) {
        pthread_mutex_unlock(&sink->lock);
        return;
    }

    struct webrtc_VideoFrameBuffer_refcounted* buffer_ref =
        webrtc_VideoFrame_video_frame_buffer(frame);
    struct webrtc_VideoFrameBuffer* frame_buffer =
        webrtc_VideoFrameBuffer_refcounted_get(buffer_ref);
    if (frame_buffer == NULL) {
        pthread_mutex_unlock(&sink->lock);
        return;
    }

    struct webrtc_I420Buffer_refcounted* i420_ref =
        webrtc_VideoFrameBuffer_ToI420(frame_buffer);
    webrtc_VideoFrameBuffer_Release(frame_buffer);

    struct webrtc_I420Buffer* source_buffer =
        i420_ref == NULL ? NULL : webrtc_I420Buffer_refcounted_get(i420_ref);
    if (source_buffer == NULL) {
        pthread_mutex_unlock(&sink->lock);
        return;
    }

    struct webrtc_I420Buffer* rotated_buffer =
        create_rotated_i420_buffer(source_buffer, webrtc_VideoFrame_rotation(frame));
    struct webrtc_I420Buffer* buffer = rotated_buffer;
    if (buffer == NULL) {
        buffer = source_buffer;
        webrtc_I420Buffer_AddRef(buffer);
    }

    int32_t w = webrtc_I420Buffer_width(buffer);
    int32_t h = webrtc_I420Buffer_height(buffer);

    /* 前のバッファを解放する */
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
    pthread_mutex_unlock(&sink->lock);

    /* source_buffer の解放（回転バッファを使った場合は不要） */
    if (source_buffer != NULL) {
        webrtc_I420Buffer_Release(source_buffer);
    }

    /* メインスレッドでテクスチャ更新を通知する */
    if (cb != NULL) {
        dispatch_async(dispatch_get_main_queue(), ^{
            cb(ctx);
        });

        pthread_mutex_lock(&sink->lock);
        sink->inflight_dispatch_count--;
        pthread_cond_broadcast(&sink->inflight_cond);
        pthread_mutex_unlock(&sink->lock);
    }
}

static void on_apple_discarded(void* user_data) { (void)user_data; }
static void on_apple_destroy(void* user_data) { (void)user_data; }
static void noop_destroy(void* user_data) { (void)user_data; }

/* --- レンダリングシンク公開 API --- */

__attribute__((visibility("default")))
AppleRenderingSink* apple_rendering_sink_create(void) {
    AppleRenderingSink* sink =
        (AppleRenderingSink*)calloc(1, sizeof(AppleRenderingSink));
    if (sink == NULL) return NULL;

    pthread_mutex_init(&sink->lock, NULL);
    if (pthread_cond_init(&sink->inflight_cond, NULL) != 0) {
        pthread_mutex_destroy(&sink->lock);
        free(sink);
        return NULL;
    }

    struct webrtc_VideoSinkInterface_cbs cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.OnFrame = on_apple_frame;
    cbs.OnDiscardedFrame = on_apple_discarded;
    cbs.OnDestroy = on_apple_destroy;
    sink->sink = webrtc_VideoSinkInterface_new(&cbs, sink);

    return sink;
}

__attribute__((visibility("default")))
void apple_rendering_sink_set_frame_callback(
    AppleRenderingSink* sink,
    frame_available_fn callback,
    void* context) {
    if (sink == NULL) return;
    pthread_mutex_lock(&sink->lock);
    sink->on_frame_available = callback;
    sink->frame_callback_context = context;
    pthread_mutex_unlock(&sink->lock);
}

__attribute__((visibility("default")))
void* apple_rendering_sink_copy_pixel_buffer(AppleRenderingSink* sink) {
    if (sink == NULL) return NULL;

    pthread_mutex_lock(&sink->lock);
    if (sink->disposed || sink->i420_buffer == NULL) {
        pthread_mutex_unlock(&sink->lock);
        return NULL;
    }

    int32_t w = sink->width;
    int32_t h = sink->height;

    if (w <= 0 || h <= 0) {
        pthread_mutex_unlock(&sink->lock);
        return NULL;
    }

    /* 解像度が変わった場合は CVPixelBuffer を再作成する */
    if (sink->pixel_buffer != NULL) {
        size_t pw = CVPixelBufferGetWidth(sink->pixel_buffer);
        size_t ph = CVPixelBufferGetHeight(sink->pixel_buffer);
        if ((int32_t)pw != w || (int32_t)ph != h) {
            CVPixelBufferRelease(sink->pixel_buffer);
            sink->pixel_buffer = NULL;
        }
    }

    if (sink->pixel_buffer == NULL) {
        /* Metal/IOSurface 互換の CVPixelBuffer を作成する */
        CFStringRef keys[2] = {
            kCVPixelBufferMetalCompatibilityKey,
            kCVPixelBufferIOSurfacePropertiesKey,
        };
        CFDictionaryRef empty_dict = CFDictionaryCreate(
            NULL, NULL, NULL, 0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        CFDictionaryRef attrs = NULL;
        if (empty_dict != NULL) {
            CFTypeRef values[2] = {
                kCFBooleanTrue,
                empty_dict,
            };
            attrs = CFDictionaryCreate(
                NULL,
                (const void**)keys,
                (const void**)values,
                2,
                &kCFTypeDictionaryKeyCallBacks,
                &kCFTypeDictionaryValueCallBacks);
        }
        /* empty_dict が NULL の場合 attrs は NULL のまま CVPixelBufferCreate へ渡る。
           作成されるピクセルバッファは Metal / IOSurface 属性を持たず sink に保持され、
           同解像度の間は再利用される。通常経路より機能が劣るが、empty_dict の確保失敗は
           メモリ枯渇相当の稀なケースであり、CFRetain(NULL) クラッシュ防止を優先する。 */

        CVReturn status = CVPixelBufferCreate(
            NULL, (size_t)w, (size_t)h,
            kCVPixelFormatType_32BGRA,
            attrs, &sink->pixel_buffer);

        if (empty_dict != NULL) {
            CFRelease(empty_dict);
        }
        if (attrs != NULL) {
            CFRelease(attrs);
        }

        if (status != kCVReturnSuccess) {
            sink->pixel_buffer = NULL;
            pthread_mutex_unlock(&sink->lock);
            return NULL;
        }
    }

    /* I420 -> BGRA 変換 */
    CVPixelBufferLockBaseAddress(sink->pixel_buffer, 0);
    void* pixels = CVPixelBufferGetBaseAddress(sink->pixel_buffer);
    if (pixels != NULL) {
        int32_t pitch = (int32_t)CVPixelBufferGetBytesPerRow(sink->pixel_buffer);
        libyuv_ConvertFromI420(
            webrtc_I420Buffer_MutableDataY(sink->i420_buffer),
            webrtc_I420Buffer_StrideY(sink->i420_buffer),
            webrtc_I420Buffer_MutableDataU(sink->i420_buffer),
            webrtc_I420Buffer_StrideU(sink->i420_buffer),
            webrtc_I420Buffer_MutableDataV(sink->i420_buffer),
            webrtc_I420Buffer_StrideV(sink->i420_buffer),
            (uint8_t*)pixels,
            pitch,
            w, h,
            libyuv_FOURCC_ARGB);
    }
    CVPixelBufferUnlockBaseAddress(sink->pixel_buffer, 0);

    CVPixelBufferRetain(sink->pixel_buffer);
    CVPixelBufferRef result = sink->pixel_buffer;
    pthread_mutex_unlock(&sink->lock);

    return (void*)result;
}

__attribute__((visibility("default")))
void apple_rendering_sink_delete(AppleRenderingSink* sink) {
    if (sink == NULL) return;

    pthread_mutex_lock(&sink->lock);
    sink->disposed = 1;
    sink->on_frame_available = NULL;
    sink->frame_callback_context = NULL;
    while (sink->inflight_dispatch_count > 0) {
        pthread_cond_wait(&sink->inflight_cond, &sink->lock);
    }

    if (sink->i420_buffer != NULL) {
        webrtc_I420Buffer_Release(sink->i420_buffer);
        sink->i420_buffer = NULL;
    }
    if (sink->pixel_buffer != NULL) {
        CVPixelBufferRelease(sink->pixel_buffer);
        sink->pixel_buffer = NULL;
    }
    pthread_mutex_unlock(&sink->lock);

    if (sink->sink != NULL) {
        webrtc_VideoSinkInterface_delete(sink->sink);
        sink->sink = NULL;
    }

    pthread_cond_destroy(&sink->inflight_cond);
    pthread_mutex_destroy(&sink->lock);
    free(sink);
}

/* ===========================================================================
 * PeerConnectionObserver コールバックブリッジ
 *
 * Dart の NativeCallable.listener 関数ポインタを保持し、
 * WebRTC コールバックから同期的にデータを抽出して安全な形で Dart に渡す。
 * =========================================================================== */

/* Dart 側のコールバック関数ポインタ型 */
typedef void (*dart_on_state_fn)(int32_t state, void* user_data);
typedef void (*dart_on_ice_candidate_fn)(
    char* sdp, char* mid, int32_t mline_index, void* user_data);
typedef void (*dart_on_track_fn)(void* track_ref, char* kind, char* track_id, void* user_data);
typedef void (*dart_on_remove_track_fn)(void* track_ref, char* kind, char* track_id, void* user_data);
typedef void (*dart_on_datachannel_fn)(void* dc_ref, char* label, void* user_data);
typedef void (*dart_on_debug_fn)(char* message, void* user_data);

typedef struct SoraObserverBridge {
    dart_on_state_fn on_connection_change;
    dart_on_state_fn on_ice_connection_change;
    dart_on_state_fn on_ice_gathering_change;
    dart_on_ice_candidate_fn on_ice_candidate;
    dart_on_track_fn on_track;
    dart_on_remove_track_fn on_remove_track;
    dart_on_datachannel_fn on_datachannel;
    dart_on_debug_fn on_debug;
    void* dart_user_data;

    /* C 側で管理するリソース */
    struct webrtc_PeerConnectionObserver* observer;

    /* インフライトコールバックの同期機構 */
    pthread_mutex_t lock;
    pthread_cond_t inflight_cond;
    int disposed;
    int inflight_count;
} SoraObserverBridge;

/* bridge のコールバックインフライトを開始する。
   破棄済みの場合は false を返し、呼び出し元は即座に return する。 */
static bool observer_bridge_begin_use(SoraObserverBridge* bridge) {
    pthread_mutex_lock(&bridge->lock);
    if (bridge->disposed) {
        pthread_mutex_unlock(&bridge->lock);
        return false;
    }
    bridge->inflight_count++;
    pthread_mutex_unlock(&bridge->lock);
    return true;
}

/* bridge のコールバックインフライトを終了し、
   破棄待ちがあれば cond_signal を発火する。 */
static void observer_bridge_end_use(SoraObserverBridge* bridge) {
    pthread_mutex_lock(&bridge->lock);
    bridge->inflight_count--;
    if (bridge->disposed && bridge->inflight_count == 0) {
        pthread_cond_signal(&bridge->inflight_cond);
    }
    pthread_mutex_unlock(&bridge->lock);
}

/* malloc で文字列をコピーする。Dart 側で free すること。 */
static char* strdup_safe(const char* src) {
    if (src == NULL) {
        char* empty = (char*)malloc(1);
        if (empty) empty[0] = '\0';
        return empty;
    }
    return strdup(src);
}

/* デバッグメッセージを Dart に送信する */
static void bridge_emit_debug(SoraObserverBridge* bridge, const char* msg) {
    if (bridge->on_debug) {
        bridge->on_debug(strdup_safe(msg), bridge->dart_user_data);
    }
}

/* --- PeerConnectionObserver コールバック実装 --- */

static void bridge_on_connection_change(
    webrtc_PeerConnectionInterface_PeerConnectionState new_state,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    if (bridge->on_connection_change) {
        bridge->on_connection_change((int32_t)new_state, bridge->dart_user_data);
    }
    observer_bridge_end_use(bridge);
}

static void bridge_on_ice_connection_change(
    webrtc_PeerConnectionInterface_IceConnectionState new_state,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    if (bridge->on_ice_connection_change) {
        bridge->on_ice_connection_change(
            (int32_t)new_state, bridge->dart_user_data);
    }
    observer_bridge_end_use(bridge);
}

static void bridge_on_ice_gathering_change(
    webrtc_PeerConnectionInterface_IceGatheringState new_state,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    if (bridge->on_ice_gathering_change) {
        bridge->on_ice_gathering_change(
            (int32_t)new_state, bridge->dart_user_data);
    }
    observer_bridge_end_use(bridge);
}

static void bridge_on_ice_candidate(
    const struct webrtc_IceCandidate* candidate,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    if (bridge->on_ice_candidate == NULL) {
        observer_bridge_end_use(bridge);
        return;
    }

    struct std_string_unique* sdp = NULL;
    if (!webrtc_IceCandidate_ToString(candidate, &sdp)) {
        observer_bridge_end_use(bridge);
        return;
    }
    struct std_string_unique* sdp_mid = NULL;
    webrtc_IceCandidate_sdp_mid(candidate, &sdp_mid);
    int sdp_mline_index = webrtc_IceCandidate_sdp_mline_index(candidate);

    const char* sdp_cstr = std_string_c_str(std_string_unique_get(sdp));
    char* sdp_copy = strdup_safe(sdp_cstr);
    std_string_unique_delete(sdp);

    /* sdp_mid が NULL の場合は空文字列で代替する */
    char* mid_copy;
    if (sdp_mid == NULL) {
        mid_copy = strdup_safe("");
    } else {
        const char* mid_cstr = std_string_c_str(std_string_unique_get(sdp_mid));
        mid_copy = strdup_safe(mid_cstr);
        std_string_unique_delete(sdp_mid);
    }

    bridge->on_ice_candidate(
        sdp_copy, mid_copy, sdp_mline_index, bridge->dart_user_data);
    observer_bridge_end_use(bridge);
}

static void bridge_on_ice_candidate_error(
    const char* address, size_t address_len,
    int port, const char* url, size_t url_len,
    int error_code, const char* error_text, size_t error_text_len,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    char buf[512];
    snprintf(buf, sizeof(buf),
             "native: ice_candidate_error address=%.*s port=%d "
             "url=%.*s code=%d text=%.*s",
             (int)address_len, address ? address : "",
             port,
             (int)url_len, url ? url : "",
             error_code,
             (int)error_text_len, error_text ? error_text : "");
    bridge_emit_debug(bridge, buf);
    observer_bridge_end_use(bridge);
}

/**
 * track コールバック(追加時)用のブリッジ
 */
static void bridge_on_track(
    struct webrtc_RtpTransceiverInterface_refcounted* transceiver_ref,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;

    /* トラックの種別を確認する */
    struct webrtc_RtpReceiverInterface_refcounted* receiver_ref =
        webrtc_RtpTransceiverInterface_receiver(
            webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
    if (receiver_ref == NULL) {
        /* receiver_ref が NULL のため track / kind / track_id をまだ読めず、
         * 固定文字列でログを出す */
        bridge_emit_debug(bridge, "native: ontrack skipped, receiver is null");
        webrtc_RtpTransceiverInterface_Release(
            webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
        observer_bridge_end_use(bridge);
        return;
    }
    struct webrtc_MediaStreamTrackInterface_refcounted* track_ref =
        webrtc_RtpReceiverInterface_track(
            webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    if (track_ref == NULL) {
        /* track_ref が NULL のため kind / track_id をまだ読めず、
         * 固定文字列でログを出す */
        bridge_emit_debug(bridge, "native: ontrack skipped, track is null");
        webrtc_RtpReceiverInterface_Release(
            webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
        webrtc_RtpTransceiverInterface_Release(
            webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
        observer_bridge_end_use(bridge);
        return;
    }
    struct std_string_unique* kind = webrtc_MediaStreamTrackInterface_kind(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    struct std_string_unique* track_id = webrtc_MediaStreamTrackInterface_id(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    const char* kind_cstr = std_string_c_str(std_string_unique_get(kind));
    const char* track_id_cstr = std_string_c_str(std_string_unique_get(track_id));
    /* kind の文字列は std_string_unique_delete 後に無効になるため、
     * Dart 側へ渡す場合に備えて malloc 済み文字列へコピーする。
     * Dart 側へ渡した場合は Dart 側で free し、渡さなかった場合は C 側で free する。 */
    char* kind_copy = strdup_safe(kind_cstr);
    char* track_id_copy = strdup_safe(track_id_cstr);

    if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
        /* 映像トラックの処理 */
        bridge_emit_debug(bridge, "native: ontrack kind=video");

        struct webrtc_VideoTrackInterface_refcounted* video_ref =
            webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
                track_ref);

        /* AddRef してビデオトラックポインタを Dart に渡す */
        struct webrtc_VideoTrackInterface* video_track =
            webrtc_VideoTrackInterface_refcounted_get(video_ref);
        webrtc_VideoTrackInterface_AddRef(video_track);

        if (bridge->on_track) {
            bridge->on_track((void*)video_track, kind_copy, track_id_copy,
                             bridge->dart_user_data);
            /* 二重 free 防止のため NULL を入れる */
            kind_copy = NULL;
            track_id_copy = NULL;
        } else {
            /* callback 未登録時は AddRef した参照を C 側で戻す */
            webrtc_VideoTrackInterface_Release(video_track);
        }
    } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
        /* 音声トラックの処理 */
        bridge_emit_debug(bridge, "native: ontrack kind=audio");
        if (bridge->on_track) {
            /* 音声は Flutter で処理していないため　kind のみ通知 */
            bridge->on_track(NULL, kind_copy, track_id_copy,
                             bridge->dart_user_data);
            /* 二重 free 防止のため NULL を入れる */
            kind_copy = NULL;
            track_id_copy = NULL;
        }
    } else {
        /* 想定外のトラック種類は通知しない */
        char buf[128];
        snprintf(buf, sizeof(buf), "native: ontrack invalid kind=%s",
                 kind_cstr != NULL ? kind_cstr : "(null)");
        bridge_emit_debug(bridge, buf);
    }

    if (kind_copy != NULL) {
        free(kind_copy);
    }
    if (track_id_copy != NULL) {
        free(track_id_copy);
    }

    std_string_unique_delete(kind);
    std_string_unique_delete(track_id);
    webrtc_MediaStreamTrackInterface_Release(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    webrtc_RtpTransceiverInterface_Release(
        webrtc_RtpTransceiverInterface_refcounted_get(transceiver_ref));
    observer_bridge_end_use(bridge);
}

/**
 * track コールバック(削除時)用のブリッジ
 */
static void bridge_on_remove_track(
    struct webrtc_RtpReceiverInterface_refcounted* receiver_ref,
    void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;

    if (receiver_ref == NULL) {
        /* receiver_ref が NULL のため track / kind / track_id をまだ読めず、
         * 固定文字列でログを出す */
        bridge_emit_debug(bridge, "native: onremovetrack skipped, receiver is null");
        observer_bridge_end_use(bridge);
        return;
    }

    /* receiver からトラックを取得してビデオならポインタを Dart に渡す */
    struct webrtc_MediaStreamTrackInterface_refcounted* track_ref =
        webrtc_RtpReceiverInterface_track(
            webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    if (track_ref == NULL) {
        /* track_ref が NULL のため kind / track_id をまだ読めず、
         * 固定文字列でログを出す */
        bridge_emit_debug(bridge, "native: onremovetrack skipped, track is null");
        webrtc_RtpReceiverInterface_Release(
            webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
        observer_bridge_end_use(bridge);
        return;
    }
    struct std_string_unique* kind = webrtc_MediaStreamTrackInterface_kind(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    struct std_string_unique* track_id = webrtc_MediaStreamTrackInterface_id(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
    const char* kind_cstr = std_string_c_str(std_string_unique_get(kind));
    const char* track_id_cstr = std_string_c_str(std_string_unique_get(track_id));
    /* kind の文字列は std_string_unique_delete 後に無効になるため、
     * Dart 側へ渡す場合に備えて malloc 済み文字列へコピーする。
     * Dart 側へ渡した場合は Dart 側で free し、渡さなかった場合は C 側で free する。 */
    char* kind_copy = strdup_safe(kind_cstr);
    char* track_id_copy = strdup_safe(track_id_cstr);

    void* track_ptr = NULL;
    if (kind_cstr != NULL && strcmp(kind_cstr, "video") == 0) {
        /* 映像トラックの削除処理 */
        bridge_emit_debug(bridge, "native: onremovetrack kind=video");
        struct webrtc_VideoTrackInterface_refcounted* video_ref =
            webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface(
                track_ref);
        struct webrtc_VideoTrackInterface* video_track =
            webrtc_VideoTrackInterface_refcounted_get(video_ref);
        webrtc_VideoTrackInterface_AddRef(video_track);
        track_ptr = (void*)video_track;
    } else if (kind_cstr != NULL && strcmp(kind_cstr, "audio") == 0) {
        /* 音声トラックの削除処理 */
        bridge_emit_debug(bridge, "native: onremovetrack kind=audio");
    } else {
        /* 想定外のトラック種類は通知しない */
        char buf[128];
        snprintf(buf, sizeof(buf), "native: onremovetrack invalid kind=%s",
                 kind_cstr != NULL ? kind_cstr : "(null)");
        bridge_emit_debug(bridge, buf);
        std_string_unique_delete(kind);
        std_string_unique_delete(track_id);
        webrtc_MediaStreamTrackInterface_Release(
            webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));
        webrtc_RtpReceiverInterface_Release(
            webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
        if (kind_copy != NULL) {
            free(kind_copy);
        }
        if (track_id_copy != NULL) {
            free(track_id_copy);
        }
        observer_bridge_end_use(bridge);
        return;
    }

    std_string_unique_delete(kind);
    webrtc_MediaStreamTrackInterface_Release(
        webrtc_MediaStreamTrackInterface_refcounted_get(track_ref));

    if (bridge->on_remove_track) {
        bridge->on_remove_track(track_ptr, kind_copy, track_id_copy,
                                bridge->dart_user_data);
        /* 二重 free 防止のため NULL を入れる */
        kind_copy = NULL;
        track_id_copy = NULL;
    } else if (track_ptr != NULL) {
        /* callback 未登録時は AddRef した video track 参照を C 側で戻す */
        webrtc_VideoTrackInterface_Release(
            (struct webrtc_VideoTrackInterface*)track_ptr);
    }
    if (kind_copy != NULL) {
        free(kind_copy);
    }
    if (track_id_copy != NULL) {
        free(track_id_copy);
    }
    std_string_unique_delete(track_id);
    webrtc_RtpReceiverInterface_Release(
        webrtc_RtpReceiverInterface_refcounted_get(receiver_ref));
    observer_bridge_end_use(bridge);
}

/* --- DataChannel コールバックブリッジ --- */

static const char* datachannel_state_to_string(
    webrtc_DataChannelInterface_DataState state) {
    if (state == webrtc_DataChannelInterface_DataState_kConnecting)
        return "connecting";
    if (state == webrtc_DataChannelInterface_DataState_kOpen) return "open";
    if (state == webrtc_DataChannelInterface_DataState_kClosing)
        return "closing";
    if (state == webrtc_DataChannelInterface_DataState_kClosed) return "closed";
    return "unknown";
}

typedef void (*dart_on_dc_state_fn)(void* user_data);
typedef void (*dart_on_dc_message_fn)(
    uint8_t* data_copy, int32_t len, int32_t is_binary, void* user_data);

typedef struct DcBridgeContext {
    SoraObserverBridge* bridge;
    struct webrtc_DataChannelInterface* dc;
    char* label;
    struct webrtc_DataChannelObserver* observer;
    dart_on_dc_state_fn on_state_change;
    dart_on_dc_message_fn on_message;
    void* dart_user_data;

    /* インフライトコールバックの同期機構 */
    pthread_mutex_t lock;
    pthread_cond_t inflight_cond;
    int disposed;
    int inflight_count;
} DcBridgeContext;

/* DcBridgeContext のコールバックインフライトを開始する。
   破棄済みの場合は false を返す。 */
static bool dc_bridge_begin_use(DcBridgeContext* ctx) {
    pthread_mutex_lock(&ctx->lock);
    if (ctx->disposed) {
        pthread_mutex_unlock(&ctx->lock);
        return false;
    }
    ctx->inflight_count++;
    pthread_mutex_unlock(&ctx->lock);
    return true;
}

/* DcBridgeContext のコールバックインフライトを終了する。 */
static void dc_bridge_end_use(DcBridgeContext* ctx) {
    pthread_mutex_lock(&ctx->lock);
    ctx->inflight_count--;
    if (ctx->disposed && ctx->inflight_count == 0) {
        pthread_cond_signal(&ctx->inflight_cond);
    }
    pthread_mutex_unlock(&ctx->lock);
}

static void bridge_dc_on_state_change(void* user_data) {
    DcBridgeContext* ctx = (DcBridgeContext*)user_data;
    if (!dc_bridge_begin_use(ctx)) return;
    webrtc_DataChannelInterface_DataState state =
        webrtc_DataChannelInterface_state(ctx->dc);
    char buf[128];
    snprintf(buf, sizeof(buf), "native: datachannel(%s) state=%s",
             ctx->label != NULL ? ctx->label : "(unknown)",
             datachannel_state_to_string(state));
    bridge_emit_debug(ctx->bridge, buf);
    if (ctx->on_state_change) {
        ctx->on_state_change(ctx->dart_user_data);
    }
    dc_bridge_end_use(ctx);
}

static void bridge_dc_on_message(const uint8_t* data, size_t len,
                                  int is_binary, void* user_data) {
    DcBridgeContext* ctx = (DcBridgeContext*)user_data;
    if (!dc_bridge_begin_use(ctx)) return;
    if (ctx->on_message == NULL) {
        dc_bridge_end_use(ctx);
        return;
    }

    if (data == NULL || len == 0) {
        ctx->on_message(NULL, 0, is_binary ? 1 : 0, ctx->dart_user_data);
        dc_bridge_end_use(ctx);
        return;
    }

    uint8_t* data_copy = (uint8_t*)malloc(len);
    if (data_copy == NULL) {
        char buf[192];
        snprintf(buf, sizeof(buf),
                 "dc_on_message: malloc failed; dropped message len=%zu", len);
        bridge_emit_debug(ctx->bridge, buf);
        dc_bridge_end_use(ctx);
        return;
    }
    memcpy(data_copy, data, len);
    ctx->on_message(
        data_copy, (int32_t)len, is_binary ? 1 : 0, ctx->dart_user_data);
    dc_bridge_end_use(ctx);
}

/*
 * DataChannel を Dart 側へ引き渡す。
 * callback 登録時は AddRef した参照と label_copy の所有権を Dart 側へ移譲し、
 * callback 未登録時は C 側で解放する。
 */
static void bridge_on_datachannel(
    struct webrtc_DataChannelInterface_refcounted* dc_ref, void* user_data) {
    SoraObserverBridge* bridge = (SoraObserverBridge*)user_data;
    if (!observer_bridge_begin_use(bridge)) return;
    if (dc_ref == NULL) {
        observer_bridge_end_use(bridge);
        return;
    }

    struct webrtc_DataChannelInterface* dc =
        webrtc_DataChannelInterface_refcounted_get(dc_ref);
    struct std_string_unique* label = webrtc_DataChannelInterface_label(dc);
    const char* label_cstr = std_string_c_str(std_string_unique_get(label));

    char buf[256];
    snprintf(buf, sizeof(buf), "native: ondatachannel label=%s",
             label_cstr != NULL ? label_cstr : "");
    bridge_emit_debug(bridge, buf);

    /* label を malloc コピーして Dart に渡す */
    char* label_copy = strdup_safe(label_cstr);
    std_string_unique_delete(label);

    /* AddRef した参照と label_copy は callback 登録時に Dart 側へ所有権移譲する。 */
    webrtc_DataChannelInterface_AddRef(dc);
    if (bridge->on_datachannel) {
        bridge->on_datachannel((void*)dc, label_copy, bridge->dart_user_data);
        observer_bridge_end_use(bridge);
        return;
    }

    /* callback 未登録時は C 側で回収する。 */
    free(label_copy);
    webrtc_DataChannelInterface_Release(dc);
    observer_bridge_end_use(bridge);
}

/* ===========================================================================
 * dart:ffi から呼ばれるブリッジ生成関数
 * =========================================================================== */

__attribute__((visibility("default")))
SoraObserverBridge* sora_observer_bridge_create(
    dart_on_state_fn on_connection_change,
    dart_on_state_fn on_ice_connection_change,
    dart_on_state_fn on_ice_gathering_change,
    dart_on_ice_candidate_fn on_ice_candidate,
    dart_on_track_fn on_track,
    dart_on_remove_track_fn on_remove_track,
    dart_on_datachannel_fn on_datachannel,
    dart_on_debug_fn on_debug,
    void* dart_user_data) {
    SoraObserverBridge* bridge =
        (SoraObserverBridge*)calloc(1, sizeof(SoraObserverBridge));
    if (bridge == NULL) return NULL;

    pthread_mutex_init(&bridge->lock, NULL);
    pthread_cond_init(&bridge->inflight_cond, NULL);

    bridge->on_connection_change = on_connection_change;
    bridge->on_ice_connection_change = on_ice_connection_change;
    bridge->on_ice_gathering_change = on_ice_gathering_change;
    bridge->on_ice_candidate = on_ice_candidate;
    bridge->on_track = on_track;
    bridge->on_remove_track = on_remove_track;
    bridge->on_datachannel = on_datachannel;
    bridge->on_debug = on_debug;
    bridge->dart_user_data = dart_user_data;

    struct webrtc_PeerConnectionObserver_cbs obs_cbs;
    memset(&obs_cbs, 0, sizeof(obs_cbs));
    obs_cbs.OnStandardizedIceConnectionChange = bridge_on_ice_connection_change;
    obs_cbs.OnConnectionChange = bridge_on_connection_change;
    obs_cbs.OnIceGatheringChange = bridge_on_ice_gathering_change;
    obs_cbs.OnIceCandidate = bridge_on_ice_candidate;
    obs_cbs.OnIceCandidateError = bridge_on_ice_candidate_error;
    obs_cbs.OnTrack = bridge_on_track;
    obs_cbs.OnRemoveTrack = bridge_on_remove_track;
    obs_cbs.OnDataChannel = bridge_on_datachannel;
    obs_cbs.OnDestroy = noop_destroy;
    bridge->observer = webrtc_PeerConnectionObserver_new(&obs_cbs, bridge);

    return bridge;
}

__attribute__((visibility("default")))
struct webrtc_PeerConnectionObserver* sora_observer_bridge_get_observer(
    SoraObserverBridge* bridge) {
    return bridge ? bridge->observer : NULL;
}

__attribute__((visibility("default")))
DcBridgeContext* sora_observer_bridge_setup_dc(
    SoraObserverBridge* bridge,
    struct webrtc_DataChannelInterface* dc,
    dart_on_dc_state_fn on_state_change,
    dart_on_dc_message_fn on_message,
    void* dart_user_data) {
    DcBridgeContext* ctx = (DcBridgeContext*)calloc(1, sizeof(DcBridgeContext));
    if (ctx == NULL) return NULL;
    pthread_mutex_init(&ctx->lock, NULL);
    pthread_cond_init(&ctx->inflight_cond, NULL);
    ctx->bridge = bridge;
    ctx->dc = dc;
    ctx->on_state_change = on_state_change;
    ctx->on_message = on_message;
    ctx->dart_user_data = dart_user_data;
    struct std_string_unique* label = webrtc_DataChannelInterface_label(dc);
    const char* label_cstr = std_string_c_str(std_string_unique_get(label));
    ctx->label = strdup_safe(label_cstr);
    std_string_unique_delete(label);

    struct webrtc_DataChannelObserver_cbs cbs;
    memset(&cbs, 0, sizeof(cbs));
    cbs.OnStateChange = bridge_dc_on_state_change;
    cbs.OnMessage = bridge_dc_on_message;
    cbs.OnDestroy = noop_destroy;
    struct webrtc_DataChannelObserver* observer =
        webrtc_DataChannelObserver_new(&cbs, ctx);
    webrtc_DataChannelInterface_RegisterObserver(dc, observer);
    ctx->observer = observer;

    return ctx;
}

/* DcBridgeContext を破棄し、observer の解除と解放を行う。
   破棄前にインフライトのコールバック完了を待つ。 */
__attribute__((visibility("default")))
void sora_observer_bridge_destroy_dc(
    DcBridgeContext* ctx,
    struct webrtc_DataChannelInterface* dc) {
    if (ctx == NULL) return;

    /* disposed を立てて新規コールバックを抑止してから、
       lock 外で UnregisterObserver を呼ぶ。
       UnregisterObserver が同期的に callback を流す実装でも
       begin_use が disposed を検出して return するため安全。 */
    pthread_mutex_lock(&ctx->lock);
    ctx->disposed = 1;
    pthread_mutex_unlock(&ctx->lock);

    if (dc != NULL && ctx->observer != NULL) {
        webrtc_DataChannelInterface_UnregisterObserver(dc);
    }

    /* インフライトのコールバック完了を待つ */
    pthread_mutex_lock(&ctx->lock);
    while (ctx->inflight_count > 0) {
        pthread_cond_wait(&ctx->inflight_cond, &ctx->lock);
    }
    pthread_mutex_unlock(&ctx->lock);

    if (ctx->observer != NULL) {
        webrtc_DataChannelObserver_delete(ctx->observer);
    }

    pthread_mutex_destroy(&ctx->lock);
    pthread_cond_destroy(&ctx->inflight_cond);
    free(ctx->label);
    free(ctx);
}

__attribute__((visibility("default")))
void sora_observer_bridge_destroy(SoraObserverBridge* bridge) {
    if (bridge == NULL) return;

    /* disposed を立てて新規コールバックを抑止してから、
       lock 外で PeerConnectionObserver_delete を呼ぶ。
       delete が同期的に callback を流す実装でも
       begin_use が disposed を検出して return するため安全。 */
    pthread_mutex_lock(&bridge->lock);
    bridge->disposed = 1;
    pthread_mutex_unlock(&bridge->lock);

    if (bridge->observer != NULL) {
        webrtc_PeerConnectionObserver_delete(bridge->observer);
        bridge->observer = NULL;
    }

    /* インフライトのコールバック完了を待つ */
    pthread_mutex_lock(&bridge->lock);
    while (bridge->inflight_count > 0) {
        pthread_cond_wait(&bridge->inflight_cond, &bridge->lock);
    }
    pthread_mutex_unlock(&bridge->lock);

    pthread_mutex_destroy(&bridge->lock);
    pthread_cond_destroy(&bridge->inflight_cond);
    free(bridge);
}

/* レンダリングシンクの VideoSinkInterface ポインタを取得する */
__attribute__((visibility("default")))
void* apple_rendering_sink_get_sink_ptr(AppleRenderingSink* sink) {
    if (sink == NULL) return NULL;
    return (void*)sink->sink;
}
