import AVFoundation
import Flutter
import ReplayKit

/// MethodChannel 引数から Bool 値を安全に取得するヘルパー。
///
/// Flutter 側の `bool` は `Bool` / `NSNumber` の両方で届く可能性があるため、
/// 両方を試行し、どちらでもなければ `defaultValue` を返す。
func soraConfigBoolValue(_ value: Any?, defaultValue: Bool) -> Bool {
  if let boolValue = value as? Bool {
    return boolValue
  }
  if let numberValue = value as? NSNumber {
    return numberValue.boolValue
  }
  return defaultValue
}

/// Flutter EventChannel と `SoraClientWrapper` を仲介する StreamHandler。
///
/// `onListen` で Dart 側の購読開始を受け取り、`SoraClientWrapper.eventSink`
/// へ `FlutterEventSink` を保持させることで、wrapper から Dart への
/// イベント送出を可能にする。
/// `onCancel` では eventSink を破棄し、以降のイベント送出を停止する。
private class SoraClientStreamHandler: NSObject, FlutterStreamHandler {
  weak var wrapper: SoraClientWrapper?

  init(wrapper: SoraClientWrapper) {
    self.wrapper = wrapper
  }

  /// Dart 側の購読開始を受け取り、`SoraClientWrapper.eventSink` へ
  /// `FlutterEventSink` を保持させる。wrapper から Dart への
  /// イベント送出が可能になる。
  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    wrapper?.eventSink = events
    wrapper?.emitPendingAudioInitErrorIfNeeded()
    return nil
  }

  /// eventSink を破棄し、以降のイベント送出を停止する。
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    wrapper?.eventSink = nil
    return nil
  }
}

/// ローカル映像レンダラーの生成エラーです。
private enum LocalVideoRendererError: LocalizedError {
  case unsupportedCaptureType(String)

  var errorDescription: String? {
    switch self {
    case .unsupportedCaptureType(let captureType):
      return "Unsupported local video capture type: \(captureType)"
    }
  }

  var channelCode: String {
    "screen_capture_unsupported_capture_type"
  }
}

/// dart:ffi 側の VideoSource とローカルキャプチャを紐付ける内部クラス。
private class LocalVideoRenderer {
  let videoSourcePtr: Int64
  let captureType: String
  let cameraCapturer: SoraCameraCapturer?
  let screenCapturer: SoraScreenCapturer?
  private let messageHandlerIdentity: UUID
  private(set) var screenOwner: SoraScreenCaptureOwner?

  init(
    videoSourcePtr: Int64,
    captureType: String,
    deviceId: String?,
    width: Int32,
    height: Int32,
    fps: Int32,
    textureRegistry: FlutterTextureRegistry,
    messageHandlerIdentity: UUID,
    onScreenCaptureError:
      @escaping (
        SoraScreenCaptureError,
        SoraScreenCaptureOwner,
        UInt64
      ) -> Void
  ) throws {
    self.videoSourcePtr = videoSourcePtr
    self.captureType = captureType
    self.messageHandlerIdentity = messageHandlerIdentity
    switch captureType {
    case "camera":
      let capturer = SoraCameraCapturer(
        deviceId: deviceId,
        width: width > 0 ? width : 640,
        height: height > 0 ? height : 480,
        fps: fps > 0 ? fps : 30,
        textureRegistry: textureRegistry
      )
      capturer.setVideoSourcePtr(videoSourcePtr)
      cameraCapturer = capturer
      screenCapturer = nil
    case "screen":
      let capturer = SoraScreenCapturer(
        videoSourcePtr: videoSourcePtr,
        frameRate: fps > 0 ? Int(fps) : 15,
        textureRegistry: textureRegistry
      )
      capturer.onRuntimeError = onScreenCaptureError
      cameraCapturer = nil
      screenCapturer = capturer
    default:
      throw LocalVideoRendererError.unsupportedCaptureType(captureType)
    }
  }

  var textureId: Int64 {
    cameraCapturer?.localPreviewTextureId
      ?? screenCapturer?.localPreviewTextureId
      ?? -1
  }

  func start(clientId: Int64?, completion: @escaping (Error?) -> Void) {
    if let cameraCapturer {
      cameraCapturer.setVideoSourcePtr(videoSourcePtr)
      cameraCapturer.start()
      completion(nil)
      return
    }
    guard let screenCapturer, let clientId, clientId > 0 else {
      completion(SoraScreenCaptureError.invalidConnection)
      return
    }
    let owner = SoraScreenCaptureOwner(
      messageHandlerIdentity: messageHandlerIdentity,
      videoSourcePtr: videoSourcePtr,
      connectionId: clientId
    )
    let previousOwner = screenOwner
    if let previousOwner, previousOwner != owner {
      completion(SoraScreenCaptureError.alreadyCapturing)
      return
    }
    screenOwner = owner
    screenCapturer.start(owner: owner) { [weak self] error in
      if error != nil && self?.screenOwner == owner {
        self?.screenOwner = nil
      }
      completion(error)
    }
  }

  func stop(
    clientId: Int64?,
    force: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    if let cameraCapturer {
      cameraCapturer.stop()
      completion(nil)
      return
    }
    guard let screenCapturer else {
      completion(nil)
      return
    }
    let requestedOwner: SoraScreenCaptureOwner?
    if let clientId, clientId > 0 {
      requestedOwner = SoraScreenCaptureOwner(
        messageHandlerIdentity: messageHandlerIdentity,
        videoSourcePtr: videoSourcePtr,
        connectionId: clientId
      )
    } else {
      requestedOwner = nil
    }
    screenCapturer.stop(owner: requestedOwner, force: force) { [weak self] error in
      let recorderStopped = !RPScreenRecorder.shared().isRecording
      if (error == nil || recorderStopped) && (force || self?.screenOwner == requestedOwner) {
        self?.screenOwner = nil
      }
      completion(error)
    }
  }

  func dispose(completion: @escaping (Error?) -> Void) {
    if let cameraCapturer {
      cameraCapturer.stop()
      completion(nil)
      return
    }
    guard let screenCapturer else {
      completion(nil)
      return
    }
    screenCapturer.dispose { [weak self] error in
      if error == nil || !RPScreenRecorder.shared().isRecording {
        self?.screenOwner = nil
      }
      completion(error)
    }
  }

  func isCurrentScreenCapture(
    owner: SoraScreenCaptureOwner,
    captureID: UInt64
  ) -> Bool {
    guard screenOwner == owner, let screenCapturer else { return false }
    return screenCapturer.isCurrentCapture(owner: owner, captureID: captureID)
  }
}

/// クライアントラッパー (カメラ・レンダリングのみ管理)
class SoraClientWrapper {
  /// Dart 側の SoraConnection に対応するクライアント ID
  let clientId: Int64

  /// イベント通知用 EventChannel の名前
  let eventChannelName: String

  /// AVAudioSession の管理を SDK に委任するかどうか
  let usesManagedAudioSession: Bool

  /// Dart 側へイベントを送るための FlutterEventSink
  var eventSink: FlutterEventSink?

  /// EventChannel 購読開始前に届いた audio_init_failed を保留する。
  /// `onListen` で eventSink が設定された時点で再送する。
  private var pendingAudioInitError: [String: Any]?

  /// EventChannel の StreamHandler（イベント購読ライフサイクル管理）
  private var streamHandler: SoraClientStreamHandler?

  /// EventChannel 本体（dispose 時に StreamHandler を解除するため保持）
  private var eventChannel: FlutterEventChannel?

  /// rendererId をキーとするリモートビデオレンダラーマップ
  var renderers: [Int64: RemoteVideoRenderer] = [:]

  /// 次に発行する rendererId。
  /// Dart 側が renderer を識別するための単純増分カウンタ。
  /// 再利用しないことで、dispose 済みの rendererId を誤って参照することを防ぐ。
  private var nextRendererId: Int64 = 1

  init(
    clientId: Int64, eventChannel: String,
    messenger: FlutterBinaryMessenger,
    textureRegistry: FlutterTextureRegistry,
    config: [String: Any],
    usesManagedAudioSession: Bool = false
  ) {
    self.clientId = clientId
    self.eventChannelName = eventChannel
    self.usesManagedAudioSession = usesManagedAudioSession

    // EventChannel を設定する
    let channel = FlutterEventChannel(name: eventChannel, binaryMessenger: messenger)
    let handler = SoraClientStreamHandler(wrapper: self)
    self.streamHandler = handler
    channel.setStreamHandler(handler)
    self.eventChannel = channel

  }

  func dispose() {
    eventChannel?.setStreamHandler(nil)
    for (_, renderer) in renderers {
      renderer.shutdown()
    }
    renderers.removeAll()
    pendingAudioInitError = nil
    eventSink = nil
    streamHandler = nil
  }

  /// 音声入力初期化失敗イベントを通知する。
  ///
  /// `eventSink` が未設定 (Dart 側がまだ購読開始前) の場合は保留し、
  /// `onListen` 時に `emitPendingAudioInitErrorIfNeeded()` で再送する。
  func emitAudioInitError(_ event: [String: Any]) {
    guard let sink = eventSink else {
      pendingAudioInitError = event
      return
    }
    sink(event)
  }

  /// 保留中の audio_init_failed を再送する。
  func emitPendingAudioInitErrorIfNeeded() {
    guard let event = pendingAudioInitError else { return }
    pendingAudioInitError = nil
    eventSink?(event)
  }

  /// 画面キャプチャの実行中エラーを通知する。
  func emitScreenCaptureError(_ error: SoraScreenCaptureError) {
    eventSink?([
      "type": "screen_capture_error",
      "platformError": error.channelCode,
      "message": error.localizedDescription,
    ])
  }

  /// リモートビデオレンダラーを作成する
  func createRemoteVideoRenderer(textureRegistry: FlutterTextureRegistry) -> [String: Any]? {
    guard let renderer = RemoteVideoRenderer(textureRegistry: textureRegistry) else { return nil }
    let rendererId = nextRendererId
    nextRendererId += 1
    renderers[rendererId] = renderer
    return [
      "rendererId": rendererId,
      "renderingSinkPtr": renderer.sinkAddress,
      "videoSinkPtr": renderer.videoSinkAddress,
      "textureId": renderer.textureId,
    ]
  }

  /// リモートビデオレンダラーを破棄する
  func disposeRemoteVideoRenderer(rendererId: Int64) {
    if let renderer = renderers.removeValue(forKey: rendererId) {
      renderer.shutdown()
    }
  }
}

/// Dart 側からの MethodChannel 呼び出しを処理するネイティブ側のエントリポイント。
///
/// `SoraClientWrapper` の生成・管理、カメラキャプチャ (`SoraCameraCapturer`)、
/// ローカル映像レンダラー (`LocalVideoRenderer`) を統括する。
class SoraFlutterMessageHandler {
  private let messenger: FlutterBinaryMessenger
  private let textureRegistry: FlutterTextureRegistry
  private let identity = UUID()
  private var nextClientId: Int64 = 1
  private var clients: [Int64: SoraClientWrapper] = [:]
  private var localVideoRenderers: [Int64: LocalVideoRenderer] = [:]
  private var disposed = false

  init(messenger: FlutterBinaryMessenger, textureRegistry: FlutterTextureRegistry) {
    self.messenger = messenger
    self.textureRegistry = textureRegistry
  }

  /// ローカル映像キャプチャの MethodChannel エラーコードを返す。
  private func localVideoCaptureChannelCode(for error: Error) -> String {
    if let error = error as? SoraScreenCaptureError {
      return error.channelCode
    }
    if let error = error as? LocalVideoRendererError {
      return error.channelCode
    }
    return "screen_capture_error"
  }

  /// Flutter engine の破棄時に全 client と local renderer を解放します。
  ///
  /// ReplayKit の停止は非同期のため、完了するまで各 renderer をローカル配列で
  /// 強く保持し、engine detach 直後の解放で収録が孤立しないようにします。
  func dispose(completion: @escaping () -> Void = {}) {
    guard !disposed else {
      completion()
      return
    }
    disposed = true

    let managedAudioSessionCount = clients.values.reduce(into: 0) { count, client in
      if client.usesManagedAudioSession {
        count += 1
      }
      client.dispose()
    }
    clients.removeAll()
    for _ in 0..<managedAudioSessionCount {
      SoraAudioSessionController.shared.release()
    }

    let renderers = Array(localVideoRenderers.values)
    localVideoRenderers.removeAll()

    guard !renderers.isEmpty else {
      completion()
      return
    }
    let group = DispatchGroup()
    for renderer in renderers {
      group.enter()
      renderer.dispose { [renderer] error in
        // 完了するまで renderer を強く保持する。
        _ = renderer
        if let error {
          NSLog("Failed to dispose local video renderer: %@", error.localizedDescription)
        }
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard !disposed else {
      result(
        FlutterError(
          code: "plugin_disposed",
          message: "The Sora SDK plugin has been detached from its Flutter engine.",
          details: nil))
      return
    }
    #if DEBUG
      if call.method == "debugGetScreenCaptureRecording" {
        result(RPScreenRecorder.shared().isRecording)
        return
      }
    #endif
    // 映像入力デバイス操作
    if call.method == "enumerateVideoInputDevices" {
      result(SoraCameraCapturer.enumerateDevices())
      return
    }
    if call.method == "getVideoInputFormats" {
      guard let args = call.arguments as? [String: Any],
        let deviceId = args["deviceId"] as? String
      else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "deviceId is required.",
            details: nil))
        return
      }
      result(SoraCameraCapturer.formatsForDeviceId(deviceId))
      return
    }

    // 音声入出力デバイス操作
    if call.method == "enumerateAudioInputDevices" {
      result(SoraAudioDevices.enumerateInputs())
      return
    }
    if call.method == "enumerateAudioOutputDevices" {
      result(SoraAudioDevices.enumerateOutputs())
      return
    }
    if call.method == "setAudioInputDevice" {
      let session = AVAudioSession.sharedInstance()
      let args = call.arguments as? [String: Any]
      let deviceId = args?["deviceId"] as? String
      do {
        if let deviceId = deviceId {
          guard let port = session.availableInputs?.first(where: { $0.uid == deviceId }) else {
            result(
              FlutterError(
                code: "audio_device_not_found",
                message: "Audio input device not found: \(deviceId)",
                details: nil))
            return
          }
          try session.setPreferredInput(port)
        } else {
          try session.setPreferredInput(nil)
        }
        result(nil)
      } catch {
        result(
          FlutterError(
            code: "set_preferred_input_failed",
            message: error.localizedDescription,
            details: nil))
      }
      return
    }

    // クライアント作成
    if call.method == "createClient" {
      let args = call.arguments as? [String: Any] ?? [:]
      let config = args["config"] as? [String: Any] ?? [:]
      handleCreateClientOnIOS(config: config, result: result)
      return
    }

    // 音声入力初期化の完了を待つ (iOS)
    if call.method == "awaitAudioInputReady" {
      SoraAudioSessionController.shared.awaitInputInitialized { success in
        if success {
          result(nil)
        } else {
          result(
            FlutterError(
              code: "audio_input_initialization_failed",
              message: "iOS audio input initialization failed.",
              details: nil))
        }
      }
      return
    }

    // クライアント操作 (clientId 必須)
    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_argument",
          message: "Arguments are required.",
          details: nil))
      return
    }

    switch call.method {
    // ローカル映像プレビュー用のテクスチャを確保する
    case "ensureLocalVideoTrackTexture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      let captureType = args["captureType"] as? String ?? "camera"
      let videoDeviceId = args["videoDeviceId"] as? String
      let videoWidth = (args["videoWidth"] as? NSNumber)?.int32Value ?? 0
      let videoHeight = (args["videoHeight"] as? NSNumber)?.int32Value ?? 0
      let defaultFrameRate: Int32 = captureType == "screen" ? 15 : 30
      let videoFrameRate =
        (args["videoFrameRate"] as? NSNumber)?.int32Value ?? defaultFrameRate
      guard videoSourcePtr != 0 else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "videoSourcePtr is required.",
            details: nil))
        return
      }
      if let renderer = localVideoRenderers[videoSourcePtr] {
        guard renderer.captureType == captureType else {
          result(
            FlutterError(
              code: "invalid_argument",
              message: "captureType does not match the existing renderer.",
              details: nil))
          return
        }
        result(["textureId": renderer.textureId])
        return
      }
      do {
        let renderer = try LocalVideoRenderer(
          videoSourcePtr: videoSourcePtr,
          captureType: captureType,
          deviceId: videoDeviceId,
          width: videoWidth,
          height: videoHeight,
          fps: videoFrameRate,
          textureRegistry: textureRegistry,
          messageHandlerIdentity: identity,
          onScreenCaptureError: { [weak self] error, owner, captureID in
            Task { @MainActor in
              guard let self,
                let renderer = self.localVideoRenderers[videoSourcePtr],
                renderer.isCurrentScreenCapture(owner: owner, captureID: captureID)
              else {
                return
              }
              self.clients[owner.connectionId]?.emitScreenCaptureError(error)
            }
          }
        )
        localVideoRenderers[videoSourcePtr] = renderer
        result(["textureId": renderer.textureId])
      } catch {
        result(
          FlutterError(
            code: localVideoCaptureChannelCode(for: error),
            message: error.localizedDescription,
            details: nil))
      }

    // ローカル映像キャプチャを開始する
    case "startLocalVideoCapture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      let clientId = (args["clientId"] as? NSNumber)?.int64Value
      guard let renderer = localVideoRenderers[videoSourcePtr] else {
        result(
          FlutterError(
            code: "renderer_not_found",
            message: "Local video renderer was not found.",
            details: nil))
        return
      }
      if renderer.captureType == "screen" {
        guard let clientId, clients[clientId] != nil else {
          result(
            FlutterError(
              code: SoraScreenCaptureError.invalidConnection.channelCode,
              message: SoraScreenCaptureError.invalidConnection.localizedDescription,
              details: nil))
          return
        }
      }
      renderer.start(clientId: clientId) { [weak self] error in
        guard let self else { return }
        if let error {
          result(
            FlutterError(
              code: self.localVideoCaptureChannelCode(for: error),
              message: error.localizedDescription,
              details: nil))
        } else {
          result(nil)
        }
      }

    // ローカル映像キャプチャを停止する
    case "stopLocalVideoCapture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      let clientId = (args["clientId"] as? NSNumber)?.int64Value
      let force = soraConfigBoolValue(args["force"], defaultValue: false)
      guard let renderer = localVideoRenderers[videoSourcePtr] else {
        result(nil)
        return
      }
      renderer.stop(clientId: clientId, force: force) { [weak self] error in
        if let error {
          result(
            FlutterError(
              code: self?.localVideoCaptureChannelCode(for: error)
                ?? "screen_capture_stop_failed",
              message: error.localizedDescription,
              details: nil))
        } else {
          result(nil)
        }
      }

    // ローカル映像プレビュー用のテクスチャを破棄する
    case "disposeLocalVideoTrackTexture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      guard let renderer = localVideoRenderers[videoSourcePtr] else {
        result(nil)
        return
      }
      renderer.dispose { [weak self] error in
        if let error {
          result(
            FlutterError(
              code: self?.localVideoCaptureChannelCode(for: error)
                ?? "screen_capture_stop_failed",
              message: error.localizedDescription,
              details: nil))
          return
        }
        if self?.localVideoRenderers[videoSourcePtr] === renderer {
          self?.localVideoRenderers.removeValue(forKey: videoSourcePtr)
        }
        result(nil)
      }

    // リモートビデオレンダラーを作成する
    case "createRemoteVideoRenderer":
      let clientId = (args["clientId"] as? NSNumber)?.int64Value ?? 0
      let wrapper = clients[clientId]
      if let wrapper = wrapper,
        let info = wrapper.createRemoteVideoRenderer(textureRegistry: textureRegistry)
      {
        result(info)
      } else {
        result(
          FlutterError(
            code: "renderer_create_failed",
            message: "Failed to create remote video renderer.",
            details: nil))
      }

    // リモートビデオレンダラーを破棄する
    case "disposeRemoteVideoRenderer":
      let clientId = (args["clientId"] as? NSNumber)?.int64Value ?? 0
      let rendererId = (args["rendererId"] as? NSNumber)?.int64Value ?? 0
      let wrapper = clients[clientId]
      wrapper?.disposeRemoteVideoRenderer(rendererId: rendererId)
      result(nil)

    // クライアントを破棄し、関連リソースを解放する
    case "disposeClient":
      let clientId = (args["clientId"] as? NSNumber)?.int64Value ?? 0
      let wrapper = clients.removeValue(forKey: clientId)
      if wrapper == nil {
        result(
          FlutterError(
            code: "client_not_found",
            message: "Client not found.",
            details: nil))
        return
      }
      wrapper?.dispose()
      if wrapper?.usesManagedAudioSession == true {
        SoraAudioSessionController.shared.release()
      }
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// iOS の `AVAudioSession` 管理を含めてクライアントを作成する。
  ///
  /// マイク使用が必要な場合は `SoraAudioSessionController` でセッションを取得し、
  /// 完了後にクライアントを生成する。マイク不要の場合は直接作成する。
  private func handleCreateClientOnIOS(
    config: [String: Any],
    result: @escaping FlutterResult
  ) {
    let requirements = SoraMediaRequirements.fromConfig(config)
    let needsManagedAudioSession = requirements.needsMicrophone
    guard needsManagedAudioSession else {
      createClient(
        config: config,
        usesManagedAudioSession: false,
        result: result
      )
      return
    }

    SoraAudioSessionController.shared.acquire(
      prefersVideoMode: requirements.needsCamera
    ) { error in
      if let error = error {
        result(
          FlutterError(
            code: "audio_session_configuration_failed",
            message: "Failed to configure audio session.",
            details: error.localizedDescription))
        return
      }

      self.createClient(
        config: config,
        usesManagedAudioSession: true,
        audioInitGeneration: SoraAudioSessionController.shared.currentGeneration,
        result: result
      )
    }
  }

  /// `SoraClientWrapper` を生成し、clientId と EventChannel 名を Dart 側へ返す。
  ///
  /// clientId は単純増分で払い出し、対応する EventChannel を設定する。
  /// ローカル映像準備完了イベントが pending なら即時送出する。
  private func createClient(
    config: [String: Any],
    usesManagedAudioSession: Bool,
    audioInitGeneration: Int = 0,
    result: @escaping FlutterResult
  ) {
    let clientId = nextClientId
    let eventChannel = "sora_sdk/event/\(clientId)"

    let wrapper = SoraClientWrapper(
      clientId: clientId,
      eventChannel: eventChannel,
      messenger: messenger,
      textureRegistry: textureRegistry,
      config: config,
      usesManagedAudioSession: usesManagedAudioSession
    )
    clients[clientId] = wrapper
    nextClientId += 1

    if usesManagedAudioSession, audioInitGeneration > 0 {
      SoraAudioSessionController.shared.addErrorCallback(
        generation: audioInitGeneration
      ) { [weak wrapper] result in
        wrapper?.emitAudioInitError([
          "type": "audio_init_failed",
          "code": "audio_input_initialization_failed",
          "message": "iOS audio input initialization failed: result=\(result)",
        ])
      }
    }

    result(
      [
        "clientId": clientId,
        "eventChannelName": eventChannel,
      ] as [String: Any])
  }
}
