import CoreGraphics
import CoreImage
import CoreMedia
import FlutterMacOS
import ScreenCaptureKit

@_implementationOnly import CWebrtc

/// ScreenCaptureKit のウィンドウキャプチャエラーです。
enum SoraWindowCaptureError: LocalizedError {
  /// 画面収録権限がない
  case permissionDenied

  /// 指定したウィンドウが見つからない
  case windowNotFound

  /// 既にキャプチャが動作中
  case alreadyRunning

  /// SCStream の開始がキャンセルされた
  case startCancelled

  /// SCStream の開始失敗
  case startFailed(Error)

  /// SCStream の実行中エラー
  case runtimeError(Error)

  var errorDescription: String? {
    switch self {
    case .permissionDenied:
      return "Screen recording permission is denied"
    case .windowNotFound:
      return "The specified window was not found"
    case .alreadyRunning:
      return "Window capture is already running"
    case .startCancelled:
      return "Window capture start was cancelled"
    case .startFailed(let error):
      return "Failed to start window capture: \(error.localizedDescription)"
    case .runtimeError(let error):
      return "Window capture runtime error: \(error.localizedDescription)"
    }
  }
}

/// ScreenCaptureKit によるウィンドウキャプチャと dart:ffi へのフレーム送出を担当するクラス。
///
/// `SCStream` で指定ウィンドウの映像を取得し、
/// `AdaptedVideoTrackSource` へ I420 フレームを投入する。
/// ローカルプレビュー用の `FlutterTextureRegistry` 管理も行う。
///
/// `SCStream` はメインスレッドで生成・開始・停止する必要があるため、
/// start / stop は `@MainActor` の Task 経由で行う。
/// 開始・停止の競合は iOS SDK の `ScreenCaptureController` と同様に
/// 状態機械と世代管理 (captureID) で排他する。
final class SoraWindowCapturer: NSObject, SCStreamOutput, SCStreamDelegate {
  // キャプチャ状況の列挙型
  private enum CaptureState {
    case stopped
    case starting
    case running
    case stopping
  }

  private enum StartCaptureResult {
    case success
    case failed(Error)
    case cancelled
  }

  private let windowId: CGWindowID
  private let requestedWidth: Int32
  private let requestedHeight: Int32
  private let requestedFrameRate: Int32
  private let showsCursor: Bool
  private let textureRegistry: FlutterTextureRegistry

  // 開始・停止の状態遷移を保護するロック
  private let lock = NSLock()
  private var captureState: CaptureState = .stopped
  // startCapture の非同期完了を世代管理するための ID です。
  // start / stop が前後したときに、古い start 完了コールバックを無効化します。
  private var captureID: UInt64 = 0
  private var activeCaptureID: UInt64?
  private var stream: SCStream?

  // dart:ffi 側の AdaptedVideoTrackSource ポインタ。
  // frameQueue (delegate) / stop (main) / 呼出スレッド (setter) の
  // 3 方向からアクセスされるため cross-queue データレースを防ぐ必要がある。
  private var _videoSourcePtr: OpaquePointer?
  // os_unfair_lock を利用する。
  // - 毎フレーム read と stop 時 write があり、頻度が高い
  // - delegate から main キューを待つと stopCapture と循環待ちしうる
  private var _videoSourceLock = os_unfair_lock()

  private var videoSourcePtr: OpaquePointer? {
    get {
      os_unfair_lock_lock(&_videoSourceLock)
      defer { os_unfair_lock_unlock(&_videoSourceLock) }
      return _videoSourcePtr
    }
    set {
      os_unfair_lock_lock(&_videoSourceLock)
      _videoSourcePtr = newValue
      os_unfair_lock_unlock(&_videoSourceLock)
    }
  }

  // ローカルプレビュー用
  private var previewTexture: SoraWindowPreviewTexture!
  private(set) var previewTextureId: Int64 = -1
  private var previewPixelBuffer: CVPixelBuffer?
  private var previewLock = NSLock()
  private let previewCiContext = CIContext()

  // フレーム処理用キュー
  private let frameQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.window.frame")

  // 非同期の stopCapture が完了するまで自身を保持するための参照。
  // SCStream は stopCapture 完了後にメインスレッドで解放する必要があり、
  // 停止完了前に dealloc されるとキャプチャ実行中の SCStream が不正な
  // タイミングで解放されて use-after-free を引き起こすため、ここで自己保持する。
  private var selfRetain: SoraWindowCapturer?

  // Dart 側へのエラー通知コールバック
  var onError: ((Error) -> Void)?

  // MARK: - ウィンドウ列挙

  /// 共有可能なウィンドウ一覧を返します。
  ///
  /// 画面収録権限がない場合は throw します。
  static func enumerateWindows() async throws -> [[String: Any]] {
    let content = try await SCShareableContent.current
    return content.windows.map { window in
      [
        "id": String(window.windowID),
        "title": window.title ?? "",
        "applicationName": window.owningApplication?.applicationName ?? "",
      ]
    }
  }

  // MARK: - 初期化

  init(
    windowId: CGWindowID,
    width: Int32,
    height: Int32,
    frameRate: Int32,
    showsCursor: Bool,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.windowId = windowId
    self.requestedWidth = width
    self.requestedHeight = height
    self.requestedFrameRate = frameRate
    self.showsCursor = showsCursor
    self.textureRegistry = textureRegistry

    super.init()

    // ローカルプレビュー用テクスチャを登録する
    let tex = SoraWindowPreviewTexture(capturer: self)
    self.previewTexture = tex
    self.previewTextureId = textureRegistry.register(tex)
  }

  deinit {
    // stop() は stopCapture 完了まで selfRetain で自身を保持するため、
    // キャプチャ実行中の SCStream が不正なタイミングで解放されることはない。
    stop()
    if previewTextureId >= 0 {
      textureRegistry.unregisterTexture(previewTextureId)
      previewTextureId = -1
    }
    previewLock.lock()
    previewPixelBuffer = nil
    previewLock.unlock()
  }

  // MARK: - 公開プロパティ

  var localPreviewTextureId: Int64 {
    return previewTextureId
  }

  /// キャプチャが有効かどうかを返します。
  ///
  /// ウィンドウ消失などのエラーで SCStream が停止した場合は false になる。
  /// `ensureLocalVideoTrackTexture` の早期 return 判定で使用する。
  var isCapturing: Bool {
    withLock {
      switch captureState {
      case .starting, .running:
        return true
      case .stopped, .stopping:
        return false
      }
    }
  }

  // MARK: - ビデオソースポインタ

  /// dart:ffi 側の AdaptedVideoTrackSource ポインタを設定する。
  /// start() 直後に delegate が動くと初回フレームで videoSourcePtr が nil に
  /// なる場合があるが、その場合は OnFrame 呼び出しをスキップするため安全である。
  func setVideoSourcePtr(_ ptr: Int64) {
    videoSourcePtr = OpaquePointer(bitPattern: Int(ptr))
  }

  // MARK: - キャプチャ制御

  /// ウィンドウキャプチャを開始します。
  ///
  /// SCStream の構築・開始はメインスレッドで行います。
  /// 完了は completion で通知されます。
  func start(completion: @escaping (Error?) -> Void) {
    let captureID = beginStartCapture()
    guard let captureID = captureID else {
      completion(SoraWindowCaptureError.alreadyRunning)
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        completion(SoraWindowCaptureError.startCancelled)
        return
      }

      // start 完了前に stop が実行された場合は SCStream を生成しない
      guard self.withLock({ self.activeCaptureID == captureID }) else {
        completion(SoraWindowCaptureError.startCancelled)
        return
      }

      let content: SCShareableContent
      do {
        content = try await SCShareableContent.current
      } catch {
        self.completeStartCapture(
          captureID: captureID, error: SoraWindowCaptureError.permissionDenied)
        completion(SoraWindowCaptureError.permissionDenied)
        return
      }

      guard
        let window = content.windows.first(where: { $0.windowID == self.windowId })
      else {
        self.completeStartCapture(
          captureID: captureID, error: SoraWindowCaptureError.windowNotFound)
        completion(SoraWindowCaptureError.windowNotFound)
        return
      }

      let config = SCStreamConfiguration()
      config.capturesAudio = false
      config.showsCursor = self.showsCursor
      // 未指定 (0) のフィールドはウィンドウの現在のサイズを使う
      config.width = self.requestedWidth > 0 ? Int(self.requestedWidth) : Int(window.frame.width)
      config.height =
        self.requestedHeight > 0 ? Int(self.requestedHeight) : Int(window.frame.height)
      // フレームレートはフレーム更新間隔の最小値として指定する。
      // SCStream はこの間隔を下回る頻度ではフレームを送出しないため、
      // 指定レートは上限値として働く。
      config.minimumFrameInterval = CMTime(
        value: 1, timescale: CMTimeScale(self.requestedFrameRate))
      config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

      let filter = SCContentFilter(desktopIndependentWindow: window)
      let stream = SCStream(filter: filter, configuration: config, delegate: self)
      do {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.frameQueue)
      } catch {
        self.completeStartCapture(captureID: captureID, error: error)
        completion(SoraWindowCaptureError.startFailed(error))
        return
      }
      self.stream = stream

      stream.startCapture { [weak self] error in
        guard let self else {
          completion(SoraWindowCaptureError.startCancelled)
          return
        }
        switch self.completeStartCapture(captureID: captureID, error: error) {
        case .success:
          completion(nil)
        case .failed(let error):
          // startCapture 失敗後の SCStream は再使用できないため破棄する
          self.stream = nil
          completion(SoraWindowCaptureError.startFailed(error))
        case .cancelled:
          self.stream = nil
          completion(SoraWindowCaptureError.startCancelled)
        }
      }
    }
  }

  /// ウィンドウキャプチャを停止します。
  ///
  /// SCStream の停止はメインスレッドで行います。
  /// stopCapture が完了するまで自身を保持し、完了後に解放されます。
  /// これによりキャプチャ実行中の SCStream が dealloc されるのを防ぎます。
  ///
  /// 完了条件は stopCapture 完了に加えて frameQueue 上のフレーム処理が
  /// すべて完了することです。Dart 側は `disposeLocalVideoTrackTexture` の
  /// 応答後に video source を解放するため、応答前にフレーム処理を
  /// 完了させることで解放済み source へのアクセス (UAF) を防ぎます。
  func stop(completion: (() -> Void)? = nil) {
    guard beginStopCapture() else {
      // 停止不要 (stopped / stopping) の場合は即座に完了を通知する
      completion?()
      return
    }
    // stop 開始時点で videoSourcePtr を同期的に nil 化する。
    // SoraCameraCapturer.stop() と対称の構造にし、
    // 以後のフレーム処理が source を参照しないことを保証する。
    videoSourcePtr = nil
    // SCStream の stopCapture 完了まで自身を保持する。
    // deinit から呼ばれた場合も、dealloc は stopCapture 完了まで遅延される。
    selfRetain = self
    Task { @MainActor [weak self] in
      guard let self else {
        completion?()
        return
      }
      guard let stream = self.stream else {
        // stream 未生成 (starting 中のキャンセル等) は状態を戻す
        self.withLock { self.captureState = .stopped }
        self.selfRetain = nil
        completion?()
        return
      }
      self.stream = nil
      stream.stopCapture { [weak self] _ in
        guard let self else {
          completion?()
          return
        }
        // stopCapture の completion は任意のスレッドで呼ばれるため、
        // メインスレッドへ移してから frameQueue の完了を待つ。
        Task { @MainActor [weak self] in
          guard let self else {
            completion?()
            return
          }
          // frameQueue に残っている in-flight フレーム処理の完了を待つ。
          // stopCapture 完了後は新しいフレームが来ないため、
          // ここで待てば処理中のフレームもすべて完了している。
          // フレーム処理はメインキューを同期的に待たないため、
          // デッドロックしない。
          self.frameQueue.sync {}
          self.withLock {
            self.captureState = .stopped
          }
          self.selfRetain = nil
          completion?()
        }
      }
    }
  }

  // MARK: - Private

  private func withLock<T>(_ block: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try block()
  }

  // startCapture 前に state チェック、更新を行います
  private func beginStartCapture() -> UInt64? {
    withLock {
      switch captureState {
      case .running, .starting, .stopping:
        return nil
      case .stopped:
        captureID += 1
        activeCaptureID = captureID
        captureState = .starting
        return captureID
      }
    }
  }

  // startCapture のコールバックが返ってきた後に state 更新等を行います
  private func completeStartCapture(captureID: UInt64, error: Error?) -> StartCaptureResult {
    withLock {
      // startCapture 終了前に stopCapture が実行された場合はキャンセルします
      // この時 activeCaptureID は nil となっています
      guard activeCaptureID == captureID else {
        return .cancelled
      }

      if let error {
        captureState = .stopped
        activeCaptureID = nil
        return .failed(error)
      }

      captureState = .running
      return .success
    }
  }

  // stopCapture 実行前に state チェック等を行います
  private func beginStopCapture() -> Bool {
    withLock {
      switch captureState {
      case .stopped, .stopping:
        return false
      case .starting, .running:
        captureState = .stopping
        activeCaptureID = nil
        return true
      }
    }
  }

  // MARK: - SCStreamDelegate

  // ウィンドウ消失や実行中エラーを検出します。
  // エラーは通知専用とし、キャプチャ停止は行いません。
  func stream(_ stream: SCStream, didStopWithError error: Error) {
    withLock {
      captureState = .stopped
    }
    // エラー後は Dart 側が dispose を呼ぶまでに source を解放しうるため、
    // 以後のフレーム処理が source を参照しないよう nil 化しておく。
    videoSourcePtr = nil
    // この delegate は com.screenCaptureKit.streamQueue で呼ばれる。
    // SCStream はメインスレッドで生成・開始・停止する必要があるため、
    // streamQueue 上で self.stream を解放してはいけない。
    // バックグラウンドスレッドで SCStream が dealloc されると
    // ScreenCaptureKit 内部のセッション状態が壊れ、同じウィンドウ ID の
    // 再キャプチャが "window not found" で失敗する。
    // エラー通知もメインスレッドへ移してから行う。
    let captureError = SoraWindowCaptureError.runtimeError(error)
    Task { @MainActor in
      self.stream = nil
      self.onError?(captureError)
    }
  }

  // MARK: - SCStreamOutput

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .screen else { return }
    withLock {
      guard captureState == .running else { return }
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
    let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

    // I420 バッファを作成する
    guard let i420Ref = webrtc_I420Buffer_Create(width, height),
      let i420 = webrtc_I420Buffer_refcounted_get(i420Ref)
    else {
      return
    }

    // NV12 -> I420 変換
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    let srcY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)!
      .assumingMemoryBound(to: UInt8.self)
    let srcStrideY = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
    let srcUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)!
      .assumingMemoryBound(to: UInt8.self)
    let srcStrideUV = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))

    libyuv_NV12ToI420(
      srcY, srcStrideY,
      srcUV, srcStrideUV,
      webrtc_I420Buffer_MutableDataY(i420), webrtc_I420Buffer_StrideY(i420),
      webrtc_I420Buffer_MutableDataU(i420), webrtc_I420Buffer_StrideU(i420),
      webrtc_I420Buffer_MutableDataV(i420), webrtc_I420Buffer_StrideV(i420),
      width, height
    )
    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

    // ローカルプレビュー用に BGRA の CVPixelBuffer を作成する
    previewLock.lock()
    previewPixelBuffer = nil
    let options: [String: Any] = [
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    var previewBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      nil, Int(width), Int(height),
      kCVPixelFormatType_32BGRA,
      options as CFDictionary,
      &previewBuffer
    )
    if let previewBuffer = previewBuffer {
      let image = CIImage(cvPixelBuffer: pixelBuffer)
      previewCiContext.render(image, to: previewBuffer)
    }
    previewPixelBuffer = previewBuffer
    previewLock.unlock()

    // VideoFrame を作成して AdaptedVideoTrackSource に投入する。
    // videoSourcePtr は軽量ロックで保護し、delegate から main キューを待たない。
    let sourcePtr = videoSourcePtr
    sourceBlock: if let sourcePtr = sourcePtr {
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      let timestampUs = Int64(CMTimeGetSeconds(pts) * 1_000_000.0)

      guard
        let frame = sora_video_frame_create(
          i420Ref, webrtc_VideoRotation_0, timestampUs, 0)
      else {
        break sourceBlock
      }
      guard let source = webrtc_AdaptedVideoTrackSource_refcounted_get(sourcePtr)
      else {
        webrtc_VideoFrame_unique_delete(frame)
        break sourceBlock
      }
      webrtc_AdaptedVideoTrackSource_OnFrame(
        source,
        webrtc_VideoFrame_unique_get(frame))
      webrtc_VideoFrame_unique_delete(frame)
    }
    webrtc_I420Buffer_Release(i420)

    // メインスレッドでテクスチャ更新を通知する
    let textureId = previewTextureId
    let registry = textureRegistry
    DispatchQueue.main.async {
      if textureId >= 0 {
        registry.textureFrameAvailable(textureId)
      }
    }
  }

  // MARK: - プレビューテクスチャ用

  func copyPreviewPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    previewLock.lock()
    defer { previewLock.unlock() }
    guard let pb = previewPixelBuffer else { return nil }
    return Unmanaged.passRetained(pb)
  }
}

// ローカルプレビュー用テクスチャ
private class SoraWindowPreviewTexture: NSObject, FlutterTexture {
  private weak var capturer: SoraWindowCapturer?

  init(capturer: SoraWindowCapturer) {
    self.capturer = capturer
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return capturer?.copyPreviewPixelBuffer()
  }
}
