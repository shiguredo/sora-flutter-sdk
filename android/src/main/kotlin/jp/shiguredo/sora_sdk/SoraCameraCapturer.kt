package jp.shiguredo.sora_sdk

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Range
import android.view.Surface
import android.view.WindowManager
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// カメラキャプチャクラス (Camera2 API 使用)
// dart:ffi 側で作成された AdaptedVideoTrackSource にフレームを入力する
class SoraCameraCapturer(
    private val context: Context,
    // / 画面回転角 (度数 0/90/180/270) を返す provider。
    // / Activity を直接保持しないよう、呼び出し側から注入する。
    private val rotationProvider: () -> Int = { 0 },
) {
    // カメラ切り替え中の一時状態を保持するデータクラス
    private data class PendingSwitchRequest(
        // 変更前カメラID
        val previousCameraId: String,
        // 切り替え先カメラID
        val nextCameraId: String,
        // Dart へ返すコールバック
        val completion: (Map<String, Any>?, String?) -> Unit,
        // 切り替え失敗によるロールバック中か
        var restoring: Boolean = false,
    )

    // 現在開いている Camera2 デバイス
    private var cameraDevice: CameraDevice? = null

    // 現在のキャプチャセッション
    private var captureSession: CameraCaptureSession? = null

    // YUV フレーム取得用 ImageReader
    private var imageReader: ImageReader? = null

    // カメラ操作専用のバックグラウンドスレッド
    private var backgroundThread: HandlerThread? = null

    // バックグラウンドスレッドに紐付く Handler
    private var backgroundHandler: Handler? = null

    // メインスレッド用 Handler
    private val mainHandler = Handler(Looper.getMainLooper())

    // キャプチャが動作中かどうか
    @Volatile private var running = false

    // dart:ffi 側の AdaptedVideoTrackSource ポインタ
    @Volatile private var videoSourcePtr: Long = 0

    // ローカルプレビュー用 SoraVideoRendererSink の native ポインタ
    @Volatile private var previewRenderingSinkPtr: Long = 0

    // カメラセンサーの物理的な取り付け角度
    private var cameraSensorOrientation: Int = 0

    // 現在のカメラがフロントフェイシングかどうか
    private var isFrontFacing: Boolean = false

    // ユーザーが指定したカメラ ID
    private var selectedCameraId: String? = null

    // 現在実際に開いているカメラ ID
    private var currentCameraId: String? = null

    // 要求映像幅 (デフォルト 640)
    private var requestedWidth: Int = 640

    // 要求映像高さ (デフォルト 480)
    private var requestedHeight: Int = 480

    // 要求フレームレート (デフォルト 30)
    private var requestedFps: Int = 30

    // 異なるカメラを開こうとするような競合防止のための世代管理
    // 非同期で古いコールバックが返ってきて現在処理中の世代と異なった場合は処理を中断する
    private var cameraGeneration: Long = 0
    private var pendingSwitchRequest: PendingSwitchRequest? = null

    // カメラデバイス列挙
    companion object {
        // / attempt に対応する再試行待機時間を返す。
        // / 待機リストに対応 index があれば待機ミリ秒を、上限超過 (リスト範囲外) は null を返す。
        internal fun getOpenCameraRetryDelayMs(
            attempt: Int,
            retryDelaysMs: List<Long>,
        ): Long? = retryDelaysMs.getOrNull(attempt)

        private fun getCameraLabel(
            facing: Int,
            cameraId: String,
        ): String =
            when (facing) {
                CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
                CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
                else -> "Camera $cameraId"
            }

        fun enumerateDevices(context: Context): List<Map<String, Any>> {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            return manager.cameraIdList.mapNotNull { id ->
                val chars =
                    try {
                        manager.getCameraCharacteristics(id)
                    } catch (_: Exception) {
                        return@mapNotNull null
                    }
                val facing = chars.get(CameraCharacteristics.LENS_FACING) ?: return@mapNotNull null
                mapOf("deviceId" to id, "label" to getCameraLabel(facing, id))
            }
        }

        // 利用可能なフォーマット一覧取得
        fun getFormats(
            context: Context,
            deviceId: String,
        ): List<Map<String, Any>> {
            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val chars =
                try {
                    manager.getCameraCharacteristics(deviceId)
                } catch (e: Exception) {
                    return emptyList()
                }
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP) ?: return emptyList()
            val sizes = map.getOutputSizes(ImageFormat.YUV_420_888) ?: return emptyList()
            val maxFrameRate =
                chars
                    .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                    ?.maxOfOrNull { range: Range<Int> -> range.upper.toDouble() }
                    ?: 30.0
            return sizes
                .map { size ->
                    mapOf(
                        "width" to size.width,
                        "height" to size.height,
                        "maxFrameRate" to maxFrameRate,
                    )
                }.sortedWith(compareBy({ it["width"] as Int }, { it["height"] as Int }))
        }
    }

    // dart:ffi 側の AdaptedVideoTrackSource ポインタを設定する
    fun setVideoSourcePtr(ptr: Long) {
        videoSourcePtr = ptr
    }

    // dart:ffi 側から渡されるローカルプレビュー用 SoraVideoRendererSink の native ポインタを保持する
    fun setPreviewRenderingSinkPtr(ptr: Long) {
        previewRenderingSinkPtr = ptr
    }

    // カメラオープン失敗時の再試行設定
    // 初回失敗後、最大 2 回まで再試行する (総試行回数 = 3 回)
    private val openCameraRetryDelaysMs = listOf(200L, 500L)

    internal var onCameraOpenError: ((errorCode: Int, attempts: Int) -> Unit)? = null

    // カメラキャプチャ開始
    fun start(
        deviceId: String?,
        width: Int,
        height: Int,
        fps: Int,
    ) {
        if (running) return
        running = true
        selectedCameraId = deviceId
        requestedWidth = width
        requestedHeight = height
        requestedFps = fps

        ensureBackgroundThread()
        backgroundHandler?.post {
            openSelectedCamera()
        }
    }

    // 現在のキャプチャ設定を更新し、必要ならカメラを開き直す
    fun restart(
        deviceId: String?,
        width: Int,
        height: Int,
        fps: Int,
    ) {
        selectedCameraId = deviceId
        requestedWidth = width
        requestedHeight = height
        requestedFps = fps
        if (!running) {
            start(deviceId, width, height, fps)
            return
        }

        ensureBackgroundThread()
        backgroundHandler?.post {
            openSelectedCamera()
        }
    }

    // フロントカメラとバックカメラを交互に切り替える
    fun switchCamera(completion: (Map<String, Any>?, String?) -> Unit) {
        val handler = backgroundHandler
        if (handler == null) {
            completeSwitch(completion, null, "Camera thread is not running.")
            return
        }
        handler.post {
            if (!running) {
                completeSwitch(completion, null, "Camera is not running.")
                return@post
            }
            if (pendingSwitchRequest != null) {
                completeSwitch(completion, null, "Camera switch is already in progress.")
                return@post
            }

            val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val activeCameraId =
                currentCameraId
                    ?: selectedCameraId
                    ?: resolveDefaultCameraId(manager)
            if (activeCameraId == null) {
                completeSwitch(completion, null, "Current camera device is not available.")
                return@post
            }
            val nextCameraId = findOppositeCameraId(manager, activeCameraId)
            if (nextCameraId == null) {
                completeSwitch(completion, null, "Alternative camera device is not available.")
                return@post
            }

            pendingSwitchRequest =
                PendingSwitchRequest(
                    previousCameraId = activeCameraId,
                    nextCameraId = nextCameraId,
                    completion = completion,
                )
            selectedCameraId = nextCameraId
            openSelectedCamera()
        }
    }

    // Camera2 の `Image` から YUV プレーンと回転情報を抽出し、
    // video source ポインタが設定されていればエンコード用に、
    // プレビュー sink ポインタが設定されていればローカル表示用に
    // それぞれフレームを送出する。
    private fun processImage(image: Image) {
        if (!running) return
        val planes = image.planes
        if (planes.size < 3) return
        val yPlane = planes[0]
        val uPlane = planes[1]
        val vPlane = planes[2]
        val rotation = getFrameRotation()

        if (videoSourcePtr != 0L) {
            // image.timestamp は ns のため us に変換する
            WebrtcC.nativeFeedVideoFrame(
                videoSourcePtr,
                yPlane.buffer,
                uPlane.buffer,
                vPlane.buffer,
                image.width,
                image.height,
                yPlane.rowStride,
                uPlane.rowStride,
                vPlane.rowStride,
                yPlane.pixelStride,
                uPlane.pixelStride,
                vPlane.pixelStride,
                rotation,
                image.timestamp / 1000,
            )
        }
        if (previewRenderingSinkPtr != 0L) {
            WebrtcC.nativeRenderVideoFrame(
                previewRenderingSinkPtr,
                yPlane.buffer,
                uPlane.buffer,
                vPlane.buffer,
                image.width,
                image.height,
                yPlane.rowStride,
                uPlane.rowStride,
                vPlane.rowStride,
                yPlane.pixelStride,
                uPlane.pixelStride,
                vPlane.pixelStride,
                rotation,
                image.timestamp / 1000,
            )
        }
    }

    // 映像フレームの回転角度を計算する。
    // rotationProvider から画面回転を取得し、カメラセンサーの取り付け角度と合成する。
    private fun getFrameRotation(): Int {
        val deviceRotation = rotationProvider()
        return if (isFrontFacing) {
            (cameraSensorOrientation + deviceRotation) % 360
        } else {
            (cameraSensorOrientation - deviceRotation + 360) % 360
        }
    }

    // カメラキャプチャを停止する。
    // backgroundThread の drain 完了を待ってから return することで、
    // 後続の nativeDeleteRenderingSink / adaptedVideoTrackSourceRelease が
    // 解放済みメモリを叩く UAF を防ぐ。
    fun stop() {
        if (!running) return
        running = false
        val request = pendingSwitchRequest
        if (request != null) {
            pendingSwitchRequest = null
            completeSwitch(request.completion, null, "Camera stopped during switch.")
        }
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        imageReader?.close()
        imageReader = null
        currentCameraId = null
        previewRenderingSinkPtr = 0
        selectedCameraId = null
        requestedWidth = 640
        requestedHeight = 480
        requestedFps = 30

        val sentinelLatch = CountDownLatch(1)
        val handler = backgroundHandler
        if (handler != null) {
            handler.post { sentinelLatch.countDown() }
            try {
                sentinelLatch.await(2000, TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
        videoSourcePtr = 0

        backgroundThread?.quitSafely()
        backgroundThread = null
        backgroundHandler = null
    }

    // Camera2 操作用のバックグラウンドスレッドと Handler を遅延生成する。
    // 既に存在する場合は再生成せずそのまま使う。
    private fun ensureBackgroundThread() {
        if (backgroundThread != null && backgroundHandler != null) {
            return
        }
        backgroundThread = HandlerThread("SoraCameraThread").also { it.start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    // 選択されているカメラを開いてフレームを取得する
    private fun openSelectedCamera() {
        cameraGeneration += 1
        doOpenCamera(cameraGeneration)
    }

    // 再試行用のカメラオープン処理
    // cameraGeneration をインクリメントせず、引数の generation を使用する
    private fun openSelectedCameraForRetry(
        generation: Long,
        attempt: Int,
    ) {
        if (!running || generation != cameraGeneration) return
        doOpenCamera(generation, attempt = attempt)
    }

    // カメラオープン処理の共通実装。
    // [attempt] == 0 が初回試行、>= 1 が再試行。
    // 再試行判定は [getOpenCameraRetryDelayMs] と [openCameraRetryDelaysMs] で行い、
    // 上限超過時は [onCameraOpenError] 経由で Dart 側へ通知する。
    private fun doOpenCamera(
        generation: Long,
        attempt: Int = 0,
    ) {
        val isFirstAttempt = attempt == 0
        val handler = backgroundHandler ?: return
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val targetCameraId = resolveConfiguredCameraId(manager)
        if (targetCameraId == null) {
            if (isFirstAttempt) {
                handleCameraFailure("No camera device available.")
            } else {
                onCameraOpenError?.invoke(0, attempt)
                handleCameraFailure("Failed to open camera (error=0, attempts=$attempt).")
            }
            return
        }

        val chars =
            try {
                manager.getCameraCharacteristics(targetCameraId)
            } catch (_: Exception) {
                if (isFirstAttempt) {
                    handleCameraFailure("Failed to get camera characteristics.")
                } else {
                    onCameraOpenError?.invoke(0, attempt)
                    handleCameraFailure("Failed to open camera (error=0, attempts=$attempt).")
                }
                return
            }

        if (isFirstAttempt) {
            cameraSensorOrientation =
                chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            isFrontFacing =
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT
        }

        closeCaptureResources(clearCurrentCameraId = true)

        imageReader =
            ImageReader.newInstance(
                requestedWidth,
                requestedHeight,
                ImageFormat.YUV_420_888,
                2,
            )
        imageReader!!.setOnImageAvailableListener({ reader ->
            val image = reader.acquireLatestImage() ?: return@setOnImageAvailableListener
            processImage(image)
            image.close()
        }, handler)

        try {
            manager.openCamera(
                targetCameraId,
                object : CameraDevice.StateCallback() {
                    override fun onOpened(camera: CameraDevice) {
                        if (!running || generation != cameraGeneration) {
                            camera.close()
                            return
                        }
                        cameraDevice = camera
                        currentCameraId = targetCameraId
                        startCaptureSession(generation, targetCameraId)
                    }

                    override fun onDisconnected(camera: CameraDevice) {
                        camera.close()
                        if (generation != cameraGeneration) {
                            return
                        }
                        cameraDevice = null
                        handleCameraFailure("Camera disconnected.")
                    }

                    override fun onError(
                        camera: CameraDevice,
                        error: Int,
                    ) {
                        camera.close()
                        if (generation != cameraGeneration) {
                            return
                        }
                        cameraDevice = null
                        if (error == CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE) {
                            val delayMs = getOpenCameraRetryDelayMs(attempt, openCameraRetryDelaysMs)
                            if (delayMs != null) {
                                backgroundHandler?.postDelayed({
                                    openSelectedCameraForRetry(generation, attempt + 1)
                                }, delayMs)
                                return
                            }
                        }
                        // 再試行しない場合 (非 MAX エラー / 上限超過)
                        if (isFirstAttempt) {
                            handleCameraFailure("Failed to open camera (error=$error).")
                        } else {
                            onCameraOpenError?.invoke(error, attempt)
                            handleCameraFailure("Failed to open camera (error=$error, attempts=$attempt).")
                        }
                    }
                },
                handler,
            )
        } catch (_: SecurityException) {
            if (isFirstAttempt) {
                handleCameraFailure("Failed to open camera.")
            } else {
                onCameraOpenError?.invoke(-1, attempt)
                handleCameraFailure("Failed to open camera (error=-1, attempts=$attempt).")
            }
        } catch (_: Exception) {
            if (isFirstAttempt) {
                handleCameraFailure("Failed to open camera.")
            } else {
                onCameraOpenError?.invoke(-1, attempt)
                handleCameraFailure("Failed to open camera (error=-1, attempts=$attempt).")
            }
        }
    }

    // カメラキャプチャセッションを開始する
    private fun startCaptureSession(
        generation: Long,
        targetCameraId: String,
    ) {
        val camera = cameraDevice ?: return
        val reader = imageReader ?: return
        val surface = reader.surface
        val handler = backgroundHandler

        camera.createCaptureSession(
            listOf(surface),
            object : CameraCaptureSession.StateCallback() {
                override fun onConfigured(session: CameraCaptureSession) {
                    if (!running || generation != cameraGeneration) {
                        session.close()
                        return
                    }
                    captureSession = session
                    val request =
                        camera
                            .createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                            .apply {
                                addTarget(surface)
                            }.build()
                    session.setRepeatingRequest(request, null, handler)
                    completePendingSwitchSuccess(targetCameraId)
                }

                override fun onConfigureFailed(session: CameraCaptureSession) {
                    if (generation != cameraGeneration) {
                        session.close()
                        return
                    }
                    session.close()
                    handleCameraFailure("Failed to configure capture session.")
                }
            },
            handler,
        )
    }

    // カメラキャプチャのリソース片付け
    // clearCurrentCameraId=true はカメラ切り替え時を想定
    private fun closeCaptureResources(clearCurrentCameraId: Boolean) {
        captureSession?.close()
        captureSession = null
        cameraDevice?.close()
        cameraDevice = null
        imageReader?.close()
        imageReader = null
        if (clearCurrentCameraId) {
            currentCameraId = null
        }
    }

    private fun resolveConfiguredCameraId(manager: CameraManager): String? {
        val requestedCameraId = selectedCameraId
        if (requestedCameraId != null && manager.cameraIdList.contains(requestedCameraId)) {
            return requestedCameraId
        }
        return resolveDefaultCameraId(manager)
    }

    // 利用可能なカメラリストの先頭をデフォルトとする
    private fun resolveDefaultCameraId(manager: CameraManager): String? = manager.cameraIdList.firstOrNull()

    // 引数 cameraId の切り替え先のカメラIDを取得
    // 例: フロントカメラの ID を渡した場合はバックカメラの ID を取得
    private fun findOppositeCameraId(
        manager: CameraManager,
        cameraId: String,
    ): String? {
        val chars =
            try {
                manager.getCameraCharacteristics(cameraId)
            } catch (_: Exception) {
                return null
            }
        val currentFacing = chars.get(CameraCharacteristics.LENS_FACING) ?: return null
        val targetFacing =
            when (currentFacing) {
                CameraCharacteristics.LENS_FACING_FRONT -> CameraCharacteristics.LENS_FACING_BACK
                CameraCharacteristics.LENS_FACING_BACK -> CameraCharacteristics.LENS_FACING_FRONT
                else -> return null
            }
        return manager.cameraIdList.firstOrNull { candidateId ->
            val candidateChars =
                try {
                    manager.getCameraCharacteristics(candidateId)
                } catch (_: Exception) {
                    return@firstOrNull false
                }
            candidateChars.get(CameraCharacteristics.LENS_FACING) == targetFacing
        }
    }

    // ペンディング中のカメラ切り替え完了を処理する。
    // リストア中 (切り替え失敗で元に戻す) の場合はエラー完了、
    // 通常の切り替え成功時は新しいカメラ情報を返す。
    private fun completePendingSwitchSuccess(cameraId: String) {
        val request = pendingSwitchRequest ?: return
        if (request.restoring) {
            if (cameraId != request.previousCameraId) {
                return
            }
            pendingSwitchRequest = null
            completeSwitch(request.completion, null, "Failed to switch camera.")
            return
        }
        // cameraId が期待値と一致しない場合は無視する
        if (cameraId != request.nextCameraId) {
            return
        }
        pendingSwitchRequest = null
        completeSwitch(request.completion, buildDeviceInfo(cameraId), null)
    }

    // カメラオープン失敗を処理する。
    // 切り替え中であれば元のカメラへのリストアを試み、
    // リストアも失敗した場合はエラーで完了させる。
    // 切り替え中でなければキャプチャを停止してリソースを解放する。
    private fun handleCameraFailure(message: String) {
        val request = pendingSwitchRequest
        if (request != null && !request.restoring) {
            request.restoring = true
            selectedCameraId = request.previousCameraId
            openSelectedCamera()
            return
        }
        if (request != null && request.restoring) {
            pendingSwitchRequest = null
            completeSwitch(request.completion, null, message)
            return
        }
        running = false
        closeCaptureResources(clearCurrentCameraId = true)
    }

    // カメラ ID からデバイス情報 (deviceId / label / facing) の Map を構築する。
    // カメラ切り替え成功時の Dart への返却情報として使う。
    private fun buildDeviceInfo(cameraId: String): Map<String, Any> {
        val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val chars =
            try {
                manager.getCameraCharacteristics(cameraId)
            } catch (_: Exception) {
                return mapOf("deviceId" to cameraId)
            }
        val facing = chars.get(CameraCharacteristics.LENS_FACING)
        val label = getCameraLabel(facing ?: 0, cameraId)
        return mapOf(
            "deviceId" to cameraId,
            "label" to label,
        )
    }

    // カメラ切り替えを完了する
    private fun completeSwitch(
        completion: (Map<String, Any>?, String?) -> Unit,
        info: Map<String, Any>?,
        errorMessage: String?,
    ) {
        mainHandler.post {
            completion(info, errorMessage)
        }
    }
}
