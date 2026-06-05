import AVFoundation
import Flutter

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

/// dart:ffi 側の VideoSource とカメラキャプチャを紐付ける内部クラス。
///
/// `SoraCameraCapturer` を生成・起動し、video source ポインタを渡して
/// カメラ映像を dart:ffi へ流し込む。プレビュー用 texture ID も提供する。
private class LocalVideoRenderer {
  let videoSourcePtr: Int64
  let cameraCapturer: SoraCameraCapturer

  init(
    videoSourcePtr: Int64,
    deviceId: String?,
    width: Int32,
    height: Int32,
    fps: Int32,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.videoSourcePtr = videoSourcePtr
    self.cameraCapturer = SoraCameraCapturer(
      deviceId: deviceId,
      width: width,
      height: height,
      fps: fps,
      textureRegistry: textureRegistry
    )
    self.cameraCapturer.setVideoSourcePtr(videoSourcePtr)
    self.cameraCapturer.start()
  }

  var textureId: Int64 {
    cameraCapturer.localPreviewTextureId
  }

  func dispose() {
    cameraCapturer.stop()
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
  private var nextClientId: Int64 = 1
  private var clients: [Int64: SoraClientWrapper] = [:]
  private var localVideoRenderers: [Int64: LocalVideoRenderer] = [:]

  init(messenger: FlutterBinaryMessenger, textureRegistry: FlutterTextureRegistry) {
    self.messenger = messenger
    self.textureRegistry = textureRegistry
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
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
      let videoDeviceId = args["videoDeviceId"] as? String
      let videoWidth = (args["videoWidth"] as? NSNumber)?.int32Value ?? 640
      let videoHeight = (args["videoHeight"] as? NSNumber)?.int32Value ?? 480
      let videoFrameRate = (args["videoFrameRate"] as? NSNumber)?.int32Value ?? 30
      guard videoSourcePtr != 0 else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "videoSourcePtr is required.",
            details: nil))
        return
      }
      if let renderer = localVideoRenderers[videoSourcePtr] {
        result(["textureId": renderer.textureId])
        return
      }
      let renderer = LocalVideoRenderer(
        videoSourcePtr: videoSourcePtr,
        deviceId: videoDeviceId,
        width: videoWidth,
        height: videoHeight,
        fps: videoFrameRate,
        textureRegistry: textureRegistry
      )
      localVideoRenderers[videoSourcePtr] = renderer
      result(["textureId": renderer.textureId])

    // ローカル映像プレビュー用のテクスチャを破棄する
    case "disposeLocalVideoTrackTexture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      localVideoRenderers.removeValue(forKey: videoSourcePtr)?.dispose()
      result(nil)

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
