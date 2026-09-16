package jp.shiguredo.sora_sdk

import android.app.Activity
import android.content.Context
import android.view.Surface
import android.view.WindowManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking

// リモートレンダラーのエントリ
private class RemoteRendererEntry(
    val textureEntry: TextureRegistry.SurfaceTextureEntry,
    val surface: Surface,
    val renderingSinkPtr: Long,
    val videoSinkPtr: Long,
)

// ローカルレンダラーのエントリ
private class LocalVideoRendererEntry(
    val textureEntry: TextureRegistry.SurfaceTextureEntry,
    val surface: Surface,
    val renderingSinkPtr: Long,
    val textureId: Long,
    val cameraCapturer: SoraCameraCapturer,
) {
    fun dispose() {
        cameraCapturer.stop()
        if (renderingSinkPtr != 0L) {
            WebrtcC.nativeDeleteRenderingSink(renderingSinkPtr)
        }
        surface.release()
        textureEntry.release()
    }
}

// クライアントラッパー (カメラ・レンダリングのみ管理)
private class SoraClientWrapper(
    val clientId: Int,
    val eventChannelName: String,
    // dispose 時に StreamHandler を解除するために保持する EventChannel
    val eventChannel: EventChannel,
    // ローカルプレビュー
    var localTextureEntry: TextureRegistry.SurfaceTextureEntry? = null,
    var localSurface: Surface? = null,
    var localRenderingSinkPtr: Long = 0,
) {
    var eventSink: EventChannel.EventSink? = null

    // リモートトラックレンダラー管理
    val remoteRenderers: MutableMap<Long, RemoteRendererEntry> = mutableMapOf()
    private var nextRendererId: Long = 1

    // リモート映像レンダラーを作成する。
    // `SurfaceTexture` を生成し、dart:ffi 側の rendering sink と video sink の
    // native ポインタを取得、rendererId を払い出して管理下に置く。
    // 返却 Map には rendererId / renderingSinkPtr / videoSinkPtr / textureId を含む。
    fun createRemoteVideoRenderer(textureRegistry: TextureRegistry): Map<String, Any>? {
        val textureEntry = textureRegistry.createSurfaceTexture()
        val surface = Surface(textureEntry.surfaceTexture())
        val renderingSinkPtr = WebrtcC.nativeCreateRenderingSink(surface)
        val videoSinkPtr = WebrtcC.nativeGetSinkPtr(renderingSinkPtr)
        if (renderingSinkPtr == 0L || videoSinkPtr == 0L) {
            if (renderingSinkPtr != 0L) {
                WebrtcC.nativeDeleteRenderingSink(renderingSinkPtr)
            }
            surface.release()
            textureEntry.release()
            return null
        }

        val rendererId = nextRendererId++
        remoteRenderers[rendererId] =
            RemoteRendererEntry(
                textureEntry = textureEntry,
                surface = surface,
                renderingSinkPtr = renderingSinkPtr,
                videoSinkPtr = videoSinkPtr,
            )

        return mapOf(
            "rendererId" to rendererId,
            "renderingSinkPtr" to renderingSinkPtr,
            "videoSinkPtr" to videoSinkPtr,
            "textureId" to textureEntry.id(),
        )
    }

    // リモート映像レンダラーを破棄する
    fun disposeRemoteVideoRenderer(rendererId: Long) {
        val entry = remoteRenderers.remove(rendererId) ?: return
        if (entry.renderingSinkPtr != 0L) {
            WebrtcC.nativeDeleteRenderingSink(entry.renderingSinkPtr)
        }
        entry.surface.release()
        entry.textureEntry.release()
    }

    fun dispose() {
        // EventChannel の StreamHandler を解除し messenger への登録蓄積を防ぐ
        eventChannel.setStreamHandler(null)
        // 全リモートレンダラーを破棄する
        for ((_, entry) in remoteRenderers) {
            if (entry.renderingSinkPtr != 0L) {
                WebrtcC.nativeDeleteRenderingSink(entry.renderingSinkPtr)
            }
            entry.surface.release()
            entry.textureEntry.release()
        }
        remoteRenderers.clear()
        if (localRenderingSinkPtr != 0L) {
            WebrtcC.nativeDeleteRenderingSink(localRenderingSinkPtr)
            localRenderingSinkPtr = 0
        }
        localSurface?.release()
        localSurface = null
        localTextureEntry?.release()
        localTextureEntry = null
        eventSink = null
    }
}

// Flutter プラグインのエントリポイント。
// MethodChannel の登録・受信、[SoraClientWrapper] の生成・管理、
// ローカル映像レンダラー、音声入出力ルーティングを統括する。
class SoraSdkPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware {
    // Flutter 側との通信用 MethodChannel
    private lateinit var channel: MethodChannel

    // プラグインのバインディング (context / messenger / texture 取得用)
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding

    // 権限要求で使う現在の Activity (ActivityAware で更新)
    // rotationProvider がカメラスレッドから参照するため @Volatile で可視性を保証する
    @Volatile
    private var activity: Activity? = null

    // クライアント ID の単純増分カウンタ。
    // Dart 側の `SoraConnection` とネイティブ側の `SoraClientWrapper` を
    // 1 対 1 で結びつける識別子を払い出す。
    private var nextClientId = 1

    // clientId をキーとする SoraClientWrapper マップ
    private val clients: MutableMap<Int, SoraClientWrapper> = mutableMapOf()

    // videoSourcePtr をキーとするローカル映像レンダラーマップ
    private val localVideoRenderers: MutableMap<Long, LocalVideoRendererEntry> = mutableMapOf()

    // 音声入力ルーティング操作用 CoroutineScope
    private val audioInputRoutingScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // 音声出力ルーティング操作用 CoroutineScope
    private val audioOutputRoutingScope =
        CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // detach 時の reset 操作用 CoroutineScope
    private var detachScope: CoroutineScope? = null
    private var resetJob: Job? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val pendingResetJob = resetJob
        if (pendingResetJob != null) {
            runBlocking {
                pendingResetJob.join()
            }
            resetJob = null
        }
        this.binding = binding
        SoraAudioDeviceModule.incrementGeneration()
        WebrtcC.ensureAndroidInitialized(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "sora_sdk/method")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // routing coroutine を先に cancel する。
        // cancel を先に通知する。古い routing coroutine / reset は generation チェックで無効化され、
        // withLock 解放後に Main dispatcher の直列性で現在世代の reset が実行される。
        audioInputRoutingScope.cancel()
        audioOutputRoutingScope.cancel()
        val generation = SoraAudioDeviceModule.incrementGeneration()
        // 旧 detachScope を cancel してから新 scope を作り直すことで、
        // 複数回の detach が重なっても最新の reset だけが生き残る。
        // 古い scope の job は cancel により routingMutex を取得できず破棄される。
        detachScope?.cancel()
        val appContext = binding.applicationContext
        detachScope =
            CoroutineScope(SupervisorJob() + Dispatchers.Default).also { scope ->
                resetJob =
                    scope.launch {
                        try {
                            SoraAudioDeviceModule.reset(appContext, generation)
                        } catch (e: Throwable) {
                            android.util.Log.w("SoraSdkPlugin", "Failed to reset audio device module on engine detach", e)
                        }
                    }
            }
        for ((_, wrapper) in clients) {
            try {
                wrapper.dispose()
            } catch (e: Throwable) {
                android.util.Log.w("SoraSdkPlugin", "Failed to dispose client on engine detach", e)
            }
        }
        clients.clear()
        for ((_, renderer) in localVideoRenderers) {
            renderer.dispose()
        }
        localVideoRenderers.clear()
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        when (call.method) {
            // 映像入力デバイス一覧を取得する
            "enumerateVideoInputDevices" -> {
                result.success(SoraCameraCapturer.enumerateDevices(binding.applicationContext))
            }

            // 指定デバイスの映像入力フォーマット一覧を取得する
            "getVideoInputFormats" -> {
                val deviceId = (call.arguments as? Map<*, *>)?.get("deviceId") as? String
                if (deviceId == null) {
                    result.error("invalid_argument", "deviceId is required.", null)
                    return
                }
                result.success(SoraCameraCapturer.getFormats(binding.applicationContext, deviceId))
            }

            // 音声入力デバイス一覧を取得する
            "enumerateAudioInputDevices" -> {
                result.success(SoraAudioDevices.enumerateInputs(binding.applicationContext))
            }

            // 音声出力デバイス一覧を取得する
            "enumerateAudioOutputDevices" -> {
                result.success(SoraAudioDevices.enumerateOutputs(binding.applicationContext))
            }

            // 使用する音声入力デバイスを設定する (非同期)
            "setAudioInputDevice" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                val rawDeviceId = args["deviceId"] as? String
                val deviceId = rawDeviceId?.toIntOrNull()
                if (rawDeviceId != null && deviceId == null) {
                    result.error("invalid_argument", "deviceId must be an integer string.", null)
                    return
                }
                if (deviceId != null &&
                    SoraAudioDevices.findInput(binding.applicationContext, deviceId) == null
                ) {
                    result.error(
                        "audio_device_not_found",
                        "Audio input device not found: $rawDeviceId",
                        null,
                    )
                    return
                }
                // Bluetooth SCO の routing 完了待ちが非同期になるため、
                // MethodChannel の result を保持したまま専用 scope で完了まで処理する。
                audioInputRoutingScope.launch {
                    try {
                        SoraAudioDeviceModule.setPreferredInputDevice(
                            binding.applicationContext,
                            deviceId,
                        )
                        if (!isActive) return@launch
                        result.success(null)
                    } catch (e: CancellationException) {
                        // CancellationException は Throwable のサブクラスであるため、
                        // ここで捕捉しなければ catch (e: Throwable) が result.error() を呼んでしまう。
                        // それを防ぐため先に捕捉し、coroutine の cancel 規約に従って再 throw する。
                        throw e
                    } catch (e: SoraAudioRoutingException) {
                        if (!isActive) return@launch
                        result.error(e.code, e.message, null)
                    } catch (e: Throwable) {
                        if (!isActive) return@launch
                        result.error(
                            "audio_routing_failed",
                            e.message ?: "Audio input routing failed.",
                            null,
                        )
                    }
                }
            }

            // 使用する音声出力デバイスを設定する (非同期)
            "setAudioOutputDevice" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any?>()
                val rawDeviceId = args["deviceId"] as? String
                val deviceId = rawDeviceId?.toIntOrNull()
                if (rawDeviceId != null && deviceId == null) {
                    result.error("invalid_argument", "deviceId must be an integer string.", null)
                    return
                }
                if (deviceId != null &&
                    SoraAudioDevices.findOutput(binding.applicationContext, deviceId) == null
                ) {
                    result.error(
                        "audio_device_not_found",
                        "Audio output device not found: $rawDeviceId",
                        null,
                    )
                    return
                }
                // 共有 ADM への反映を直列化するため、専用 scope で処理する。
                audioOutputRoutingScope.launch {
                    try {
                        SoraAudioDeviceModule.setPreferredOutputDevice(
                            binding.applicationContext,
                            deviceId,
                        )
                        if (!isActive) return@launch
                        result.success(null)
                    } catch (e: CancellationException) {
                        // CancellationException は Throwable のサブクラスであるため、
                        // ここで捕捉しなければ catch (e: Throwable) が result.error() を呼んでしまう。
                        // それを防ぐため先に捕捉し、coroutine の cancel 規約に従って再 throw する。
                        throw e
                    } catch (e: SoraAudioRoutingException) {
                        if (!isActive) return@launch
                        result.error(e.code, e.message, null)
                    } catch (e: Throwable) {
                        if (!isActive) return@launch
                        result.error(
                            "audio_routing_failed",
                            e.message ?: "Audio output routing failed.",
                            null,
                        )
                    }
                }
            }

            // クライアントを作成する
            "createClient" -> {
                createClient(call, result)
            }

            // ローカル映像プレビュー用のテクスチャを確保する
            "ensureLocalVideoTrackTexture" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val videoSourcePtr = (args["videoSourcePtr"] as? Number)?.toLong() ?: 0L
                val videoDeviceId = args["videoDeviceId"] as? String
                val videoWidth = (args["videoWidth"] as? Number)?.toInt() ?: 640
                val videoHeight = (args["videoHeight"] as? Number)?.toInt() ?: 480
                val videoFrameRate = (args["videoFrameRate"] as? Number)?.toInt() ?: 30
                val clientId = (args["clientId"] as? Number)?.toInt() ?: 0
                if (videoSourcePtr == 0L) {
                    result.error("invalid_argument", "videoSourcePtr is required.", null)
                    return
                }
                val existing = localVideoRenderers[videoSourcePtr]
                if (existing != null) {
                    result.success(mapOf("textureId" to existing.textureId))
                    return
                }

                val textureEntry = binding.textureRegistry.createSurfaceTexture()
                val surface = Surface(textureEntry.surfaceTexture())
                val renderingSinkPtr = WebrtcC.nativeCreateRenderingSink(surface)
                if (renderingSinkPtr == 0L) {
                    surface.release()
                    textureEntry.release()
                    result.error(
                        "renderer_create_failed",
                        "Failed to create local video renderer.",
                        null,
                    )
                    return
                }
                // capturer に application context を渡し Activity への強参照を避ける。
                // 画面回転は rotationProvider 経由で plugin の activity を都度参照し、
                // detach 中は 0 度にフォールバックする。例外時も安全のため 0 度を返す。
                val capturer =
                    SoraCameraCapturer(
                        context = binding.applicationContext,
                        rotationProvider = {
                            val act = activity
                            if (act != null) {
                                try {
                                    val windowManager =
                                        act.getSystemService(Context.WINDOW_SERVICE) as? WindowManager
                                    val rotation =
                                        act.display?.rotation
                                            ?: windowManager?.defaultDisplay?.rotation
                                            ?: Surface.ROTATION_0
                                    when (rotation) {
                                        Surface.ROTATION_90 -> 90
                                        Surface.ROTATION_180 -> 180
                                        Surface.ROTATION_270 -> 270
                                        else -> 0
                                    }
                                } catch (_: Exception) {
                                    0
                                }
                            } else {
                                0
                            }
                        },
                    )
                capturer.setPreviewRenderingSinkPtr(renderingSinkPtr)
                capturer.setVideoSourcePtr(videoSourcePtr)
                if (clientId != 0) {
                    capturer.onCameraOpenError = { errorCode, attempts ->
                        clients[clientId]?.eventSink?.success(
                            mapOf(
                                "type" to "camera_open_error",
                                "errorCode" to errorCode,
                                "attempts" to attempts,
                            ),
                        )
                    }
                }
                capturer.start(videoDeviceId, videoWidth, videoHeight, videoFrameRate)
                val entry =
                    LocalVideoRendererEntry(
                        textureEntry = textureEntry,
                        surface = surface,
                        renderingSinkPtr = renderingSinkPtr,
                        textureId = textureEntry.id(),
                        cameraCapturer = capturer,
                    )
                localVideoRenderers[videoSourcePtr] = entry
                result.success(mapOf("textureId" to entry.textureId))
            }

            // ローカル映像プレビュー用のテクスチャを破棄する
            "disposeLocalVideoTrackTexture" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val videoSourcePtr = (args["videoSourcePtr"] as? Number)?.toLong() ?: 0L
                localVideoRenderers.remove(videoSourcePtr)?.dispose()
                result.success(null)
            }

            // 実行中のカメラキャプチャを停止する
            "stopCameraCapturer" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val videoSourcePtr = (args["videoSourcePtr"] as? Number)?.toLong() ?: 0L
                if (videoSourcePtr != 0L) {
                    localVideoRenderers[videoSourcePtr]?.cameraCapturer?.stop()
                }
                result.success(null)
            }

            // リモートビデオレンダラーを作成する
            "createRemoteVideoRenderer" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val clientId = (args["clientId"] as? Number)?.toInt()
                val wrapper = clients[clientId]
                if (wrapper != null) {
                    val info = wrapper.createRemoteVideoRenderer(binding.textureRegistry)
                    if (info == null) {
                        result.error(
                            "renderer_create_failed",
                            "Failed to create remote video renderer.",
                            null,
                        )
                    } else {
                        result.success(info)
                    }
                } else {
                    result.error("client_not_found", "Client not found.", null)
                }
            }

            // リモートビデオレンダラーを破棄する
            "disposeRemoteVideoRenderer" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val clientId = (args["clientId"] as? Number)?.toInt()
                val rendererId = (args["rendererId"] as? Number)?.toLong() ?: 0L
                val wrapper = clients[clientId]
                wrapper?.disposeRemoteVideoRenderer(rendererId)
                result.success(null)
            }

            // クライアントを破棄し、関連リソースを解放する
            "disposeClient" -> {
                val clientId = ((call.arguments as? Map<*, *>)?.get("clientId") as? Number)?.toInt()
                val wrapper = clients.remove(clientId)
                if (wrapper == null) {
                    result.error("client_not_found", "Client not found.", null)
                    return
                }
                wrapper.dispose()
                result.success(null)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    // `SoraClientWrapper` を生成し、clientId と EventChannel 名を Dart 側へ返す。
    // clientId は単純増分で払い出し、対応する EventChannel を設定する。
    // ローカル映像準備完了イベントが pending なら即時送出する。
    @Suppress("UNCHECKED_CAST")
    private fun createClient(
        call: MethodCall,
        result: Result,
    ) {
        val clientId = nextClientId++
        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
        val config = (args["config"] as? Map<String, Any?>) ?: emptyMap()
        val eventChannelName = "sora_sdk/event/$clientId"

        val eventChannel = EventChannel(binding.binaryMessenger, eventChannelName)

        val wrapper = SoraClientWrapper(clientId, eventChannelName, eventChannel)
        clients[clientId] = wrapper

        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    wrapper.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    wrapper.eventSink = null
                }
            },
        )

        result.success(
            mapOf(
                "clientId" to clientId,
                "eventChannelName" to eventChannelName,
            ),
        )
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }
}
