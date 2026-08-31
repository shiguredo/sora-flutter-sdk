package jp.shiguredo.sora_sdk

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager

// AudioManager を使って Android の音声入出力デバイスを列挙する。
object SoraAudioDevices {
    // マイク (入力) 一覧を返す
    fun enumerateInputs(context: Context): List<Map<String, Any?>> = enumerate(context, AudioManager.GET_DEVICES_INPUTS)

    // 指定したマイクを返す
    fun findInput(
        context: Context,
        deviceId: Int,
    ): AudioDeviceInfo? =
        audioManager(context).getDevices(AudioManager.GET_DEVICES_INPUTS).firstOrNull {
            it.id == deviceId
        }

    // スピーカー (出力) 一覧を返す
    fun enumerateOutputs(context: Context): List<Map<String, Any?>> = enumerate(context, AudioManager.GET_DEVICES_OUTPUTS)

    // 指定したスピーカーを返す
    fun findOutput(
        context: Context,
        deviceId: Int,
    ): AudioDeviceInfo? =
        audioManager(context).getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull {
            it.id == deviceId
        }

    private fun enumerate(
        context: Context,
        flag: Int,
    ): List<Map<String, Any?>> =
        audioManager(context).getDevices(flag).map { info ->
            val productName = info.productName?.toString()?.ifEmpty { "unknown" } ?: "unknown"
            mapOf(
                "deviceId" to info.id.toString(),
                "label" to productName,
                "type" to info.type,
            )
        }

    private fun audioManager(context: Context): AudioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
}
