import AVFoundation

// AVAudioSession を使って iOS の音声入出力デバイスを列挙する。
class SoraAudioDevices {
  // マイク (入力) 一覧を返す
  static func enumerateInputs() -> [[String: Any]] {
    let session = AVAudioSession.sharedInstance()
    let inputs = session.availableInputs ?? []
    return inputs.map { port in
      [
        "deviceId": port.uid,
        "label": "\(port.portName) - \(port.portType.rawValue)",
      ]
    }
  }

  // スピーカー (出力) 一覧を返す。
  // iOS には能動的に出力候補を列挙する API がないため、
  // 現在の AVAudioSession ルートに含まれる出力ポートを返す。
  static func enumerateOutputs() -> [[String: Any]] {
    let session = AVAudioSession.sharedInstance()
    let outputs = session.currentRoute.outputs
    return outputs.map { port in
      [
        "deviceId": port.uid,
        "label": "\(port.portName) - \(port.portType.rawValue)",
      ]
    }
  }
}
