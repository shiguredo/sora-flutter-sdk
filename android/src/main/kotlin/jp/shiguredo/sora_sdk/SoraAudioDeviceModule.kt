package jp.shiguredo.sora_sdk

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.webrtc.Logging
import org.webrtc.audio.JavaAudioDeviceModule

// 音声入出力デバイスのルーティング切り替えに失敗したときに送出される例外。
//
// [code] はエラー種別（`audio_routing_timeout` 等）、
// [message] は詳細メッセージ。
class SoraAudioRoutingException(
    val code: String,
    message: String,
) : IllegalStateException(message)

// Android の JavaAudioDeviceModule を保持し、入出力デバイス選択を反映する。
object SoraAudioDeviceModule {
    // libwebrtc の [JavaAudioDeviceModule] インスタンス ([createNativeAudioDeviceModule] で生成)
    @Volatile
    private var audioDeviceModule: JavaAudioDeviceModule? = null

    // ユーザーが指定した希望入力デバイス ID (null の場合は既定入力)
    @Volatile
    private var preferredInputDeviceId: Int? = null

    // ユーザーが指定した希望出力デバイス ID (null の場合は既定出力)
    @Volatile
    private var preferredOutputDeviceId: Int? = null

    // 現在 Android の communication route で実際に適用中の出力デバイス ID
    @Volatile
    private var activeCommunicationDeviceId: Int? = null

    // routing 変更前に退避した AudioManager.mode の値
    @Volatile
    private var previousAudioMode: Int? = null

    // routing 変更前に退避した speakerphone フラグの値
    @Volatile
    private var previousSpeakerphoneOn: Boolean? = null

    // routing 変更前に退避した Bluetooth SCO フラグの値
    @Volatile
    private var previousBluetoothScoOn: Boolean? = null

    // 入出力ルーティング操作の排他制御用 Mutex
    private val routingMutex = Mutex()

    // JavaAudioDeviceModule を生成し、現在の希望入力デバイス設定を反映した native ADM を返す。
    @JvmStatic
    fun createNativeAudioDeviceModule(
        context: Context,
        nativeEnvironment: Long,
    ): Long {
        if (audioDeviceModule != null) {
            Logging.e(
                TAG,
                "createNativeAudioDeviceModule: existing ADM detected before creation. This is a contract violation (audioDeviceModule must be null).",
            )
        }
        val adm =
            JavaAudioDeviceModule.builder(context.applicationContext).createAudioDeviceModule()
        audioDeviceModule = adm
        applyPreferredInputDeviceToAdm(context.applicationContext, adm, preferredInputDeviceId)
        return adm.getNative(nativeEnvironment)
    }

    // 次回以降の録音に使う希望入力デバイスを保存し、生成済み ADM にも即時反映する。
    suspend fun setPreferredInputDevice(
        context: Context,
        deviceId: Int?,
    ) {
        routingMutex.withLock {
            val applicationContext = context.applicationContext
            val device = deviceId?.let { SoraAudioDevices.findInput(applicationContext, it) }
            if (deviceId != null && device == null) {
                throw SoraAudioRoutingException(
                    code = "audio_device_not_found",
                    message = "Audio input device not found: $deviceId",
                )
            }

            preferredInputDeviceId = deviceId
            applyPreferredInputDeviceToAdm(applicationContext, audioDeviceModule, deviceId)
        }
    }

    // 次回以降の再生に使う希望出力デバイスを保存し、現在の Android route に反映する。
    suspend fun setPreferredOutputDevice(
        context: Context,
        deviceId: Int?,
    ) {
        routingMutex.withLock {
            val applicationContext = context.applicationContext
            val outputDevice = deviceId?.let { SoraAudioDevices.findOutput(applicationContext, it) }
            if (deviceId != null && outputDevice == null) {
                throw SoraAudioRoutingException(
                    code = "audio_device_not_found",
                    message = "Audio output device not found: $deviceId",
                )
            }

            preferredOutputDeviceId = deviceId
            applyPreferredOutputRouting(applicationContext, outputDevice)
        }
    }

    // プラグイン破棄時に保持中の希望状態と Android 側の route を初期状態へ戻す。
    // detachGeneration により、新しい engine が既に attach 済みの場合は何もしない。
    suspend fun reset(
        context: Context,
        detachGeneration: Int,
    ) {
        routingMutex.withLock {
            if (generation != detachGeneration) return
            val applicationContext = context.applicationContext
            preferredInputDeviceId = null
            preferredOutputDeviceId = null
            clearOutputRouting(applicationContext)
            audioDeviceModule?.let { clearPreferredInputDevice(it) }
            val adm = audioDeviceModule
            audioDeviceModule = null
            if (adm != null) {
                withContext(NonCancellable) {
                    withContext(Dispatchers.IO) {
                        adm.release()
                    }
                }
            }
        }
    }

    // 新しい engine の attach 時に世代を進める。
    // reset() が古い世代の detach 由来の場合に状態を上書きしないよう保護する。
    fun incrementGeneration(): Int = ++generation

    // engine attach/detach の世代カウンタ
    @Volatile
    private var generation = 0

    // JavaAudioDeviceModule に入力デバイス選択を適用し、未指定時は明示選択を解除する。
    private fun applyPreferredInputDeviceToAdm(
        context: Context,
        adm: JavaAudioDeviceModule?,
        deviceId: Int?,
    ) {
        if (adm == null) {
            return
        }

        val device = deviceId?.let { SoraAudioDevices.findInput(context, it) }
        if (deviceId != null && device == null) {
            Logging.e(TAG, "Preferred input device not found: id=$deviceId")
            return
        }

        if (device != null) {
            adm.setPreferredInputDevice(device)
            return
        }

        clearPreferredInputDevice(adm)
    }

    // output 側は Android の communication route を使って再生先を切り替える。
    private suspend fun applyPreferredOutputRouting(
        context: Context,
        outputDevice: AudioDeviceInfo?,
    ) {
        if (outputDevice == null) {
            clearOutputRouting(context)
            return
        }

        val audioManager = audioManager(context)
        rememberAudioState(audioManager)
        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION

        // Android 12 (API 31) 以降は `setCommunicationDevice()`、
        // それ以前は `isSpeakerphoneOn` フラグで出力先を切り替える。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val communicationDevice =
                findCommunicationDeviceForOutput(audioManager, outputDevice)
                    ?: throw SoraAudioRoutingException(
                        code = "audio_device_not_found",
                        message = "Audio output communication device not found.",
                    )
            if (!audioManager.setCommunicationDevice(communicationDevice)) {
                throw SoraAudioRoutingException(
                    code = "audio_routing_failed",
                    message = "Failed to set communication device.",
                )
            }
            activeCommunicationDeviceId = communicationDevice.id
            if (requiresBluetoothSco(outputDevice, communicationDevice)) {
                routeBluetoothSco(context, audioManager, communicationDevice)
                return
            }
            stopBluetoothSco(audioManager)
            return
        }

        // `minSdk 29` のため、Android 12 未満は speakerphone フラグで出力先を切り替える。
        @Suppress("DEPRECATION")
        run {
            audioManager.isSpeakerphoneOn = shouldUseSpeakerphone(outputDevice)
        }
        activeCommunicationDeviceId = outputDevice.id
    }

    // Bluetooth 系の出力では SCO を開始し、実際に route が切り替わるまで待機する。
    private suspend fun routeBluetoothSco(
        context: Context,
        audioManager: AudioManager,
        communicationDevice: AudioDeviceInfo,
    ) {
        // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
        @Suppress("DEPRECATION")
        run {
            audioManager.isSpeakerphoneOn = false
            audioManager.isBluetoothScoOn = true
            audioManager.startBluetoothSco()
        }

        // 指定デバイスで既に接続済みなら終了
        if (isBluetoothScoConnected(audioManager, communicationDevice)) {
            return
        }

        val connected = awaitBluetoothScoConnection(context, audioManager, communicationDevice)
        if (!connected) {
            // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
            @Suppress("DEPRECATION")
            val bluetoothScoOn = audioManager.isBluetoothScoOn
            Logging.e(
                TAG,
                "routeBluetoothSco: SCO connection timed out communication=${describeAudioDevice(
                    communicationDevice,
                )} bluetoothScoOn=$bluetoothScoOn",
            )
            clearOutputRouting(context)
            throw SoraAudioRoutingException(
                code = "audio_routing_timeout",
                message = "Bluetooth SCO routing timed out.",
            )
        }
    }

    // 明示出力 routing を解除し、speakerphone / mode / SCO を元の状態へ戻す。
    private fun clearOutputRouting(context: Context) {
        if (activeCommunicationDeviceId == null && previousAudioMode == null) {
            return
        }

        val audioManager = audioManager(context)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            audioManager.clearCommunicationDevice()
        }
        stopBluetoothSco(audioManager)
        // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
        @Suppress("DEPRECATION")
        run {
            audioManager.isSpeakerphoneOn = previousSpeakerphoneOn ?: false
        }
        audioManager.mode = previousAudioMode ?: AudioManager.MODE_NORMAL

        activeCommunicationDeviceId = null
        previousAudioMode = null
        previousSpeakerphoneOn = null
        previousBluetoothScoOn = null
    }

    // Dart 側が持つ output device 一覧と Android の communication device 一覧は一致前提にできない。
    // そのため SDK 側で type と productName を使って communication device 候補を解決する。
    private fun findCommunicationDeviceForOutput(
        audioManager: AudioManager,
        outputDevice: AudioDeviceInfo,
    ): AudioDeviceInfo? {
        val desiredProductName =
            outputDevice.productName
                ?.toString()
                ?.trim()
                .orEmpty()
        val candidateTypes =
            when (outputDevice.type) {
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
                -> {
                    setOf(AudioDeviceInfo.TYPE_BUILTIN_SPEAKER)
                }

                AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> {
                    setOf(AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
                }

                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                -> {
                    setOf(AudioDeviceInfo.TYPE_WIRED_HEADSET)
                }

                AudioDeviceInfo.TYPE_USB_DEVICE,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                -> {
                    setOf(AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET)
                }

                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_BLE_HEADSET,
                AudioDeviceInfo.TYPE_BLE_SPEAKER,
                -> {
                    bluetoothOutputTypes
                }

                else -> {
                    setOf(outputDevice.type)
                }
            }
        val candidates =
            audioManager.availableCommunicationDevices.filter {
                it.type in candidateTypes
            }
        if (candidates.isEmpty()) {
            return null
        }
        if (desiredProductName.isNotEmpty()) {
            candidates
                .firstOrNull {
                    it.productName?.toString()?.trim() == desiredProductName
                }?.let { return it }
        }
        return candidates.first()
    }

    // Bluetooth SCO の接続完了または失敗を broadcast で待機する。
    private suspend fun awaitBluetoothScoConnection(
        context: Context,
        audioManager: AudioManager,
        communicationDevice: AudioDeviceInfo,
    ): Boolean {
        val applicationContext = context.applicationContext
        val deferred = CompletableDeferred<Boolean>()
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(
                    context: Context?,
                    intent: Intent?,
                ) {
                    val state =
                        intent?.getIntExtra(AudioManager.EXTRA_SCO_AUDIO_STATE, -1) ?: return
                    when (state) {
                        AudioManager.SCO_AUDIO_STATE_CONNECTED -> {
                            if (!deferred.isCompleted) {
                                deferred.complete(
                                    isBluetoothScoConnected(audioManager, communicationDevice),
                                )
                            }
                        }

                        AudioManager.SCO_AUDIO_STATE_DISCONNECTED,
                        AudioManager.SCO_AUDIO_STATE_ERROR,
                        -> {
                            if (!deferred.isCompleted) {
                                deferred.complete(false)
                            }
                        }
                    }
                }
            }

        registerScoReceiver(applicationContext, receiver)
        try {
            if (isBluetoothScoConnected(audioManager, communicationDevice)) {
                return true
            }
            return withTimeoutOrNull(BLUETOOTH_SCO_TIMEOUT_MS) {
                deferred.await()
            } ?: false
        } finally {
            applicationContext.unregisterReceiver(receiver)
        }
    }

    // SCO 状態通知を受け取る receiver を API level に応じた overload で登録する。
    private fun registerScoReceiver(
        context: Context,
        receiver: BroadcastReceiver,
    ) {
        val filter = IntentFilter(AudioManager.ACTION_SCO_AUDIO_STATE_UPDATED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            return
        }
        // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
        @Suppress("DEPRECATION")
        context.registerReceiver(receiver, filter)
    }

    // route 変更前の audio mode / speakerphone / SCO 状態を一度だけ退避する。
    private fun rememberAudioState(audioManager: AudioManager) {
        if (previousAudioMode == null) {
            previousAudioMode = audioManager.mode
            // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
            @Suppress("DEPRECATION")
            run {
                previousSpeakerphoneOn = audioManager.isSpeakerphoneOn
                previousBluetoothScoOn = audioManager.isBluetoothScoOn
            }
        }
    }

    // 現在の communication device と SCO 状態から Bluetooth route の成立を判定する。
    private fun isBluetoothScoConnected(
        audioManager: AudioManager,
        communicationDevice: AudioDeviceInfo,
    ): Boolean {
        val communicationDeviceMatches =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.communicationDevice?.id == communicationDevice.id
            } else {
                true
            }

        // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
        @Suppress("DEPRECATION")
        val bluetoothScoOn = audioManager.isBluetoothScoOn
        return communicationDeviceMatches && bluetoothScoOn
    }

    // 出力デバイスの種別から Bluetooth SCO 開始が必要かどうかを判定する。
    private fun requiresBluetoothSco(
        outputDevice: AudioDeviceInfo,
        communicationDevice: AudioDeviceInfo,
    ): Boolean =
        outputDevice.type in bluetoothOutputTypes ||
            communicationDevice.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO

    private fun shouldUseSpeakerphone(outputDevice: AudioDeviceInfo): Boolean =
        when (outputDevice.type) {
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER,
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE,
            -> true

            else -> false
        }

    // 旧 API の SCO 停止とフラグ復元をまとめて行う。
    private fun stopBluetoothSco(audioManager: AudioManager) {
        // `minSdk 29` を維持するため、Android 12 未満では deprecated な SCO API を継続利用する。
        @Suppress("DEPRECATION")
        run {
            audioManager.stopBluetoothSco()
            audioManager.isBluetoothScoOn = previousBluetoothScoOn ?: false
        }
    }

    // public API に解除メソッドが無いため、内部 AudioRecord に reflection で null を渡して解除する。
    private fun clearPreferredInputDevice(adm: JavaAudioDeviceModule) {
        try {
            val audioInputField = JavaAudioDeviceModule::class.java.getDeclaredField("audioInput")
            audioInputField.isAccessible = true
            val audioInput = audioInputField.get(adm) ?: return
            val setPreferredDevice =
                audioInput.javaClass.getDeclaredMethod(
                    "setPreferredDevice",
                    AudioDeviceInfo::class.java,
                )
            setPreferredDevice.isAccessible = true
            setPreferredDevice.invoke(audioInput, null)
        } catch (e: ReflectiveOperationException) {
            Logging.e(TAG, "Failed to clear preferred input device: ${e.message}")
        }
    }

    // AudioManager を application context から取得する。
    private fun audioManager(context: Context): AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    // debug log 用に AudioDeviceInfo の主要属性を短く整形する。
    private fun describeAudioDevice(device: AudioDeviceInfo): String {
        val productName = device.productName?.toString()?.ifEmpty { "unknown" } ?: "unknown"
        return "id=${device.id},type=${device.type},productName=$productName"
    }

    // ログタグ
    private const val TAG = "SoraAudioDeviceModule"

    // Bluetooth SCO 接続の待機タイムアウト (ミリ秒)
    private const val BLUETOOTH_SCO_TIMEOUT_MS = 5_000L

    // Bluetooth 出力デバイスと判定する [AudioDeviceInfo] タイプのセット
    private val bluetoothOutputTypes =
        setOf(
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
            AudioDeviceInfo.TYPE_BLE_HEADSET,
            AudioDeviceInfo.TYPE_BLE_SPEAKER,
        )
}
