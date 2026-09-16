package jp.shiguredo.sora_sdk

import android.content.Context
import org.webrtc.ContextUtils

// libwebrtc-c C API の JNI バインディング。
// `sora_sdk` ネイティブライブラリを読み込み、JNI 経由で C の関数を呼び出す。
object WebrtcC {
    @Volatile
    private var androidInitialized = false

    // WebRTC の Android ランタイムを初期化する。
    //
    // [ContextUtils.initialize] でアプリケーションコンテキストを設定し、
    // [nativeInitializeAndroid] で JNI グローバル変数とクラスローダーを初期化する。
    // スレッドセーフかつ多重初期化を防止する。
    fun ensureAndroidInitialized(context: Context) {
        if (androidInitialized) return
        synchronized(this) {
            if (androidInitialized) return
            ContextUtils.initialize(context.applicationContext)
            androidInitialized = nativeInitializeAndroid(context.applicationContext)
            check(androidInitialized) { "Failed to initialize Android WebRTC runtime." }
        }
    }

    // WebRTC の Android 固有ランタイム (JNI グローバル変数、クラスローダー) を初期化する。
    external fun nativeInitializeAndroid(context: Context): Boolean

    // 映像レンダリング用の [RenderingSink] を生成し、ネイティブポインタを返す。
    // 戻り値は `nativeDeleteRenderingSink` で解放すること。
    external fun nativeCreateRenderingSink(surface: android.view.Surface): Long

    // [renderingSinkPtr] から `VideoSinkInterface` のポインタを取得する。
    external fun nativeGetSinkPtr(renderingSinkPtr: Long): Long

    // [renderingSinkPtr] で指定された RenderingSink を破棄する。
    //
    // 内部でインフライトのフレーム処理完了を待ってからリソースを解放する。
    external fun nativeDeleteRenderingSink(renderingSinkPtr: Long)

    // カメラキャプチャした I420 フレームを指定した [videoSourcePtr] の
    // `AdaptedVideoTrackSource` へ投入する。
    external fun nativeFeedVideoFrame(
        videoSourcePtr: Long,
        yBuffer: java.nio.ByteBuffer,
        uBuffer: java.nio.ByteBuffer,
        vBuffer: java.nio.ByteBuffer,
        width: Int,
        height: Int,
        yStride: Int,
        uStride: Int,
        vStride: Int,
        yPixelStride: Int,
        uPixelStride: Int,
        vPixelStride: Int,
        rotation: Int,
        timestampUs: Long,
    )

    // I420 フレームを指定した [renderingSinkPtr] のレンダリングシンクへ描画する。
    external fun nativeRenderVideoFrame(
        renderingSinkPtr: Long,
        yBuffer: java.nio.ByteBuffer,
        uBuffer: java.nio.ByteBuffer,
        vBuffer: java.nio.ByteBuffer,
        width: Int,
        height: Int,
        yStride: Int,
        uStride: Int,
        vStride: Int,
        yPixelStride: Int,
        uPixelStride: Int,
        vPixelStride: Int,
        rotation: Int,
        timestampUs: Long,
    )

    init {
        System.loadLibrary("sora_sdk")
    }
}
