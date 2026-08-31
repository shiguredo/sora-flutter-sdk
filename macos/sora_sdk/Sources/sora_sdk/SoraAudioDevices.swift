import AVFoundation
import CoreAudio

// CoreAudio を使って macOS の音声入出力デバイスを列挙する。
class SoraAudioDevices {
  // マイク (入力) 一覧を返す
  static func enumerateInputs() -> [[String: Any]] {
    return enumerate(scope: kAudioDevicePropertyScopeInput)
  }

  // 既定の音声入力デバイス ID を返す
  static func defaultInputDeviceId() -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var deviceId = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    if AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &address,
      0,
      nil,
      &size,
      &deviceId
    ) != noErr {
      return nil
    }
    return stringProperty(deviceId: deviceId, selector: kAudioDevicePropertyDeviceUID)
  }

  // スピーカー (出力) 一覧を返す
  static func enumerateOutputs() -> [[String: Any]] {
    return enumerate(scope: kAudioDevicePropertyScopeOutput)
  }

  // 指定スコープのストリームを持つデバイスを列挙する
  private static func enumerate(scope: AudioObjectPropertyScope) -> [[String: Any]] {
    var propertyAddress = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var dataSize: UInt32 = 0
    if AudioObjectGetPropertyDataSize(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0, nil, &dataSize
    ) != noErr {
      return []
    }
    let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
    if count == 0 {
      return []
    }
    var ids = [AudioDeviceID](repeating: 0, count: count)
    if AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject),
      &propertyAddress,
      0, nil, &dataSize, &ids
    ) != noErr {
      return []
    }

    var devices: [[String: Any]] = []
    for id in ids {
      if !hasStreamsOnScope(deviceId: id, scope: scope) {
        continue
      }
      guard
        let uid = stringProperty(deviceId: id, selector: kAudioDevicePropertyDeviceUID)
      else {
        continue
      }
      let label =
        stringProperty(deviceId: id, selector: kAudioObjectPropertyName) ?? uid
      devices.append([
        "deviceId": uid,
        "label": label,
      ])
    }
    return devices
  }

  // 指定スコープのストリームが存在するか調べる
  private static func hasStreamsOnScope(
    deviceId: AudioDeviceID,
    scope: AudioObjectPropertyScope
  ) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: scope,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    if AudioObjectGetPropertyDataSize(deviceId, &address, 0, nil, &size) != noErr {
      return false
    }
    return size > 0
  }

  // AudioObject の CFString プロパティを Swift の String として取り出す
  private static func stringProperty(
    deviceId: AudioDeviceID,
    selector: AudioObjectPropertySelector
  ) -> String? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    if AudioObjectGetPropertyData(deviceId, &address, 0, nil, &size, &value) != noErr {
      return nil
    }
    return value?.takeRetainedValue() as String?
  }
}
