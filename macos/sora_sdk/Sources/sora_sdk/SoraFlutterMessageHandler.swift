import FlutterMacOS

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

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    wrapper?.eventSink = events
    return nil
  }

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

  /// Dart 側へイベントを送るための FlutterEventSink
  var eventSink: FlutterEventSink?

  /// EventChannel の StreamHandler（イベント購読ライフサイクル管理）
  private var streamHandler: SoraClientStreamHandler?

  /// EventChannel 本体（dispose 時に StreamHandler を解除するため保持）
  private var eventChannel: FlutterEventChannel?

  /// rendererId をキーとするリモートビデオレンダラーマップ
  var renderers: [Int64: RemoteVideoRenderer] = [:]

  /// 次に発行する rendererId。
  ///
  /// Dart 側が renderer を識別するための単純増分カウンタ。
  /// 再利用しないことで、dispose 済みの rendererId を誤って参照することを防ぐ。
  private var nextRendererId: Int64 = 1

  init(
    clientId: Int64, eventChannel: String,
    messenger: FlutterBinaryMessenger,
    textureRegistry: FlutterTextureRegistry,
    config: [String: Any]
  ) {
    self.clientId = clientId
    self.eventChannelName = eventChannel

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
    eventSink = nil
    streamHandler = nil
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
    if call.method == "getDefaultAudioInputDevice" {
      result(SoraAudioDevices.defaultInputDeviceId())
      return
    }
    if call.method == "setAudioInputDevice" {
      // macOS の入力切り替えは Dart 側から libwebrtc の AudioDeviceModule を直接操作する。
      // MethodChannel では扱わない。
      result(
        FlutterError(
          code: "unsupported_platform",
          message: "setAudioInputDevice is not yet implemented on macOS.",
          details: nil))
      return
    }

    // クライアント作成
    if call.method == "createClient" {
      let args = call.arguments as? [String: Any] ?? [:]
      let config = args["config"] as? [String: Any] ?? [:]
      let clientId = nextClientId
      let eventChannel = "sora_sdk/event/\(clientId)"

      let wrapper = SoraClientWrapper(
        clientId: clientId,
        eventChannel: eventChannel,
        messenger: messenger,
        textureRegistry: textureRegistry,
        config: config
      )
      clients[clientId] = wrapper
      nextClientId += 1

      result(
        [
          "clientId": clientId,
          "eventChannelName": eventChannel,
        ] as [String: Any])
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
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
