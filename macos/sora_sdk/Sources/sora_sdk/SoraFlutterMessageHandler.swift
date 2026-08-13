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

/// ローカルビデオレンダラーの生成エラーです。
private enum LocalVideoRendererError: LocalizedError {
  case invalidWindowId(String)

  var errorDescription: String? {
    switch self {
    case .invalidWindowId(let value):
      return "Invalid window id: \(value)"
    }
  }
}

/// dart:ffi 側の VideoSource とローカルキャプチャを紐付ける内部クラス。
///
/// `captureType` に応じて `SoraCameraCapturer` または `SoraWindowCapturer` を
/// 生成・起動し、video source ポインタを渡して映像を dart:ffi へ流し込む。
/// プレビュー用 texture ID も提供する。
private class LocalVideoRenderer {
  let videoSourcePtr: Int64
  let cameraCapturer: SoraCameraCapturer?
  let windowCapturer: SoraWindowCapturer?

  // エラー通知の宛先となるクライアント ID。
  // 接続前 preview では 0 のままとなり、Sora 接続時に後付けで設定される。
  // `ensureLocalVideoTrackTexture` の再呼び出しでも更新される。
  var clientId: Int64 = 0

  init(
    videoSourcePtr: Int64,
    captureType: String,
    deviceId: String?,
    width: Int32,
    height: Int32,
    fps: Int32,
    showsCursor: Bool,
    textureRegistry: FlutterTextureRegistry,
    onError: ((Error) -> Void)?
  ) throws {
    self.videoSourcePtr = videoSourcePtr
    switch captureType {
    case "window":
      guard let deviceId, let windowId = CGWindowID(deviceId) else {
        throw LocalVideoRendererError.invalidWindowId(deviceId ?? "")
      }
      let capturer = SoraWindowCapturer(
        windowId: windowId,
        width: width,
        height: height,
        frameRate: fps,
        showsCursor: showsCursor,
        textureRegistry: textureRegistry
      )
      capturer.setVideoSourcePtr(videoSourcePtr)
      capturer.onError = onError
      self.windowCapturer = capturer
      self.cameraCapturer = nil
    default:
      let capturer = SoraCameraCapturer(
        deviceId: deviceId,
        width: width,
        height: height,
        fps: fps,
        textureRegistry: textureRegistry
      )
      capturer.setVideoSourcePtr(videoSourcePtr)
      capturer.start()
      self.cameraCapturer = capturer
      self.windowCapturer = nil
    }
  }

  var textureId: Int64 {
    if let windowCapturer {
      return windowCapturer.localPreviewTextureId
    }
    return cameraCapturer?.localPreviewTextureId ?? -1
  }

  /// キャプチャが有効な状態かどうかを返します。
  ///
  /// ウィンドウキャプチャは SCStream がエラーで停止した場合に false になる。
  /// カメラキャプチャはエラーによる停止経路がないため常に true。
  var isActive: Bool {
    if let windowCapturer {
      return windowCapturer.isCapturing
    }
    return true
  }

  // ウィンドウキャプチャの開始完了を待つ。
  // カメラキャプチャは init 内で開始済みのため、完了を即座に通知する。
  func start(completion: @escaping (Error?) -> Void) {
    if let windowCapturer {
      windowCapturer.start(completion: completion)
    } else {
      completion(nil)
    }
  }

  /// キャプチャを停止する。
  ///
  /// ウィンドウキャプチャは stopCapture 完了 (frameQueue のフレーム処理完了
  /// を含む) を待ってから completion を呼ぶ。カメラキャプチャは同期で停止が
  /// 完了するため即座に completion を呼ぶ。
  func dispose(completion: @escaping () -> Void) {
    if let windowCapturer {
      windowCapturer.stop(completion: completion)
    } else {
      cameraCapturer?.stop()
      completion()
    }
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

    // ウィンドウキャプチャ操作
    if call.method == "enumerateWindowCaptureSources" {
      Task {
        do {
          result(try await SoraWindowCapturer.enumerateWindows())
        } catch {
          result(
            FlutterError(
              code: "screen_capture_permission_denied",
              message: error.localizedDescription,
              details: nil))
        }
      }
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
      let captureType = args["captureType"] as? String ?? "camera"
      let clientId = (args["clientId"] as? NSNumber)?.int64Value ?? 0
      let videoDeviceId = args["videoDeviceId"] as? String
      let videoWidth = (args["videoWidth"] as? NSNumber)?.int32Value ?? 640
      let videoHeight = (args["videoHeight"] as? NSNumber)?.int32Value ?? 480
      let videoFrameRate = (args["videoFrameRate"] as? NSNumber)?.int32Value ?? 30
      let showsCursor = (args["showsCursor"] as? NSNumber)?.boolValue ?? true
      guard videoSourcePtr != 0 else {
        result(
          FlutterError(
            code: "invalid_argument",
            message: "videoSourcePtr is required.",
            details: nil))
        return
      }
      if let renderer = localVideoRenderers[videoSourcePtr] {
        // 接続前 preview で生成済みの renderer にも、
        // エラー通知の宛先 clientId を後付けで設定する
        renderer.clientId = clientId
        if renderer.isActive {
          result(["textureId": renderer.textureId])
          return
        }
        // ウィンドウ消失などのエラーでキャプチャが停止済みの renderer は
        // 破棄して作り直す。そのまま textureId を返すと、再接続時に
        // SCStream が再起動されず映像ゼロのまま成功してしまう。
        localVideoRenderers.removeValue(forKey: videoSourcePtr)?.dispose {}
      }
      // キャプチャ中のウィンドウ消失やストリームエラーを Dart 側へ通知する。
      // 通知先の clientId は renderer に後付けで設定されるため、
      // ensure 時点の clientId (接続前 preview では 0) ではなく
      // renderer の現在の clientId を参照する。
      let onError: (Error) -> Void = { [weak self] error in
        guard let self else { return }
        let clientId = self.localVideoRenderers[videoSourcePtr]?.clientId ?? 0
        self.clients[clientId]?.eventSink?([
          "type": "window_capture_error",
          "message": error.localizedDescription,
        ])
      }
      do {
        let renderer = try LocalVideoRenderer(
          videoSourcePtr: videoSourcePtr,
          captureType: captureType,
          deviceId: videoDeviceId,
          width: videoWidth,
          height: videoHeight,
          fps: videoFrameRate,
          showsCursor: showsCursor,
          textureRegistry: textureRegistry,
          onError: onError
        )
        renderer.clientId = clientId
        localVideoRenderers[videoSourcePtr] = renderer
        // ウィンドウキャプチャは SCStream の開始完了を待ってから返す
        renderer.start { [weak self] error in
          guard let self else { return }
          if let error {
            // 開始失敗時もフレーム処理の完了を待ってから応答する
            self.localVideoRenderers.removeValue(forKey: videoSourcePtr)?.dispose {
              result(
                FlutterError(
                  code: "capture_failed",
                  message: error.localizedDescription,
                  details: nil))
            }
          } else {
            result(["textureId": renderer.textureId])
          }
        }
      } catch {
        result(
          FlutterError(
            code: "capture_failed",
            message: error.localizedDescription,
            details: nil))
      }

    // ローカル映像プレビュー用のテクスチャを破棄する
    case "disposeLocalVideoTrackTexture":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      guard let renderer = localVideoRenderers.removeValue(forKey: videoSourcePtr) else {
        result(nil)
        break
      }
      // キャプチャ停止の完了 (stopCapture 完了と frameQueue 上の
      // フレーム処理完了) を待ってから応答する。
      // Dart 側は応答後に video source を解放するため、
      // 応答前にフレーム処理を完了させることで解放済み source への
      // アクセス (UAF) を防ぐ。
      renderer.dispose {
        result(nil)
      }

    // 実行中のウィンドウキャプチャを停止する
    case "stopWindowCapturer":
      let videoSourcePtr = (args["videoSourcePtr"] as? NSNumber)?.int64Value ?? 0
      guard let renderer = localVideoRenderers.removeValue(forKey: videoSourcePtr) else {
        result(nil)
        break
      }
      // disposeLocalVideoTrackTexture と同様に停止完了を待ってから応答する。
      // 呼び出し側 (replaceVideoTrack の失敗時など) が video source を
      // 解放する前に、frameQueue 上のフレーム処理を完了させる。
      renderer.dispose {
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
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
