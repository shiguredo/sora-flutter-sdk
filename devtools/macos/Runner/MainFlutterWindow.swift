import AVFoundation
import Cocoa
import FlutterMacOS

private final class PermissionHandler: NSObject {
  private let channel: FlutterMethodChannel

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "devtools/permissions",
      binaryMessenger: binaryMessenger
    )
    super.init()
    channel.setMethodCallHandler(handle)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isMicrophonePermissionUndetermined":
      result(AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined)
    case "ensureMediaPermissions":
      let args = call.arguments as? [String: Any] ?? [:]
      let needsCamera = (args["camera"] as? Bool) ?? false
      let needsMicrophone = (args["microphone"] as? Bool) ?? false
      ensureMediaPermissions(
        needsCamera: needsCamera,
        needsMicrophone: needsMicrophone,
        result: result
      )
    default:
      result(FlutterMethodNotImplemented)
    }
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
}

class MainFlutterWindow: NSWindow {
  private var permissionHandler: PermissionHandler?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    permissionHandler = PermissionHandler(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }
}
