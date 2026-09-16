import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var permissionChannel: FlutterMethodChannel?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "devtools/permissions",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "ensureMediaPermissions":
        let args = call.arguments as? [String: Any] ?? [:]
        let needsCamera = (args["camera"] as? Bool) ?? false
        let needsMicrophone = (args["microphone"] as? Bool) ?? false
        self.ensureMediaPermissions(
          needsCamera: needsCamera,
          needsMicrophone: needsMicrophone,
          result: result
        )
      case "prepareAudioDeviceEnumeration":
        self.prepareAudioDeviceEnumeration(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    permissionChannel = channel
  }

  private func ensureMediaPermissions(
    needsCamera: Bool,
    needsMicrophone: Bool,
    result: @escaping FlutterResult
  ) {
    requestCameraIfNeeded(needsCamera) { cameraGranted in
      if !cameraGranted {
        result(false)
        return
      }
      self.requestMicrophoneIfNeeded(needsMicrophone) { microphoneGranted in
        result(microphoneGranted)
      }
    }
  }

  private func requestCameraIfNeeded(
    _ needsCamera: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    guard needsCamera else {
      completion(true)
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  private func requestMicrophoneIfNeeded(
    _ needsMicrophone: Bool,
    completion: @escaping (Bool) -> Void
  ) {
    guard needsMicrophone else {
      completion(true)
      return
    }

    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  // availableInputs は現在の AVAudioSession 設定に依存する。
  // Bluetooth / 有線ヘッドセット入力も候補に出せるよう、
  // 列挙前に PlayAndRecord + Bluetooth 許可で session を有効化する。
  private func prepareAudioDeviceEnumeration(result: @escaping FlutterResult) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .voiceChat,
        options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
      )
      try session.setActive(true)
      result(nil)
    } catch {
      result(
        FlutterError(
          code: "prepare_audio_device_enumeration_failed",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }
}
