import AVFoundation
@_implementationOnly import CWebrtc
import Flutter
import UIKit

/// カメラ映像のキャプチャと dart:ffi へのフレーム送出を担当するクラス。
///
/// `AVCaptureSession` で指定デバイスから映像を取得し、
/// `AdaptedVideoTrackSource` へ I420 フレームを投入する。
/// ローカルプレビュー用の `FlutterTextureRegistry` 管理も行う。
class SoraCameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private static let sessionQueueKey =
    DispatchSpecificKey<Void>()
  private var selectedDeviceId: String?
  private var requestedWidth: Int32
  private var requestedHeight: Int32
  private var requestedFps: Int32
  private let textureRegistry: FlutterTextureRegistry

  private var captureSession: AVCaptureSession?
  private var captureInput: AVCaptureDeviceInput?
  private var captureOutput: AVCaptureVideoDataOutput?
  private var captureQueue: DispatchQueue?
  private let sessionQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.camera.session")

  // dart:ffi 側の AdaptedVideoTrackSource ポインタ。
  // captureQueue (delegate) / sessionQueue (stop) / 呼出スレッド (setter) の
  // 3 方向からアクセスされるため cross-queue データレースを防ぐ必要がある。
  // 実体は _videoSourcePtr に格納し、computed property の get/set で lock する。
  private var _videoSourcePtr: OpaquePointer?
  // os_unfair_lock 利用する。
  // - 毎フレーム read と stop 時 write があり、頻度が高い
  // - ユーザー空間ロックでカーネル遷移がなく、数十 ns と軽量
  // - DispatchQueue.sync は delegate が captureQueue 上で走るため
  //   毎フレーム別キューを待つ競合が生じる
  // - NSLock より軽量、DispatchSemaphore は排他制御に過剰設計
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
  private var previewTexture: SoraLocalPreviewTexture!
  // Flutter の TextureRegistry.register() の初回返り値が 0 のため、-1 からスタート
  private(set) var previewTextureId: Int64 = -1
  private var previewPixelBuffer: CVPixelBuffer?
  private var previewLock = NSLock()

  private var running = false
  private var currentDeviceOrientation: UIDeviceOrientation = .portrait
  private var orientationObserver: NSObjectProtocol?

  // MARK: - クラスメソッド

  /// 利用可能なカメラデバイスを列挙する
  static func enumerateDevices() -> [[String: Any]] {
    var result: [[String: Any]] = []
    for device in availableDevices() {
      result.append([
        "deviceId": device.uniqueID,
        "label": device.localizedName,
      ])
    }
    return result
  }

  /// 指定したカメラデバイスの利用可能なフォーマット一覧を取得する
  static func formatsForDeviceId(_ deviceId: String) -> [[String: Any]] {
    guard let device = AVCaptureDevice(uniqueID: deviceId) else { return [] }

    var seen = Set<String>()
    var result: [[String: Any]] = []

    for format in device.formats {
      let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      var maxFrameRate: Float64 = 0
      for range in format.videoSupportedFrameRateRanges {
        if range.maxFrameRate > maxFrameRate {
          maxFrameRate = range.maxFrameRate
        }
      }
      let key = "\(dimensions.width)x\(dimensions.height)@\(Int(maxFrameRate))"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      result.append([
        "width": dimensions.width,
        "height": dimensions.height,
        "maxFrameRate": maxFrameRate,
      ])
    }

    result.sort { a, b in
      let aw = (a["width"] as? NSNumber)?.int32Value ?? 0
      let bw = (b["width"] as? NSNumber)?.int32Value ?? 0
      if aw != bw { return aw < bw }
      let ah = (a["height"] as? NSNumber)?.int32Value ?? 0
      let bh = (b["height"] as? NSNumber)?.int32Value ?? 0
      return ah < bh
    }
    return result
  }

  // MARK: - 初期化

  init(
    deviceId: String?, width: Int32, height: Int32, fps: Int32,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.selectedDeviceId = deviceId
    self.requestedWidth = width
    self.requestedHeight = height
    self.requestedFps = fps
    self.textureRegistry = textureRegistry

    super.init()

    sessionQueue.setSpecific(key: Self.sessionQueueKey, value: ())

    // ローカルプレビュー用テクスチャを登録する
    let tex = SoraLocalPreviewTexture(capturer: self)
    self.previewTexture = tex
    self.previewTextureId = textureRegistry.register(tex)
  }

  deinit {
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

  /// ローカルプレビューの Texture Id を取得する
  var localPreviewTextureId: Int64 {
    return previewTextureId
  }

  // MARK: - ビデオソースポインタ

  /// dart:ffi 側の AdaptedVideoTrackSource ポインタを設定する
  func setVideoSourcePtr(_ ptr: Int64) {
    videoSourcePtr = OpaquePointer(bitPattern: Int(ptr))
  }

  // MARK: - キャプチャ制御

  // カメラキャプチャを開始する
  func start() {
    guard !running else { return }
    running = true
    startDeviceOrientationMonitoring()
    sessionQueue.async { [weak self] in
      self?.startCaptureSessionOnQueue()
    }
  }

  // 現在のキャプチャ設定を更新し、必要ならセッションを開き直す
  func restart(deviceId: String?, width: Int32, height: Int32, fps: Int32) {
    selectedDeviceId = deviceId
    requestedWidth = width
    requestedHeight = height
    requestedFps = fps
    if !running {
      start()
      return
    }

    // 現在のセッションを停止し、新しい設定でセッションを再構築する。
    // デバイス・解像度・FPS の変更反映にはセッションの再作成が必要。
    // start/stop/restart の競合を防ぐため直列で実行する。
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.captureSession?.stopRunning()
      self.captureSession = nil
      self.captureInput = nil
      self.captureOutput = nil
      self.startCaptureSessionOnQueue()
    }
  }

  /// `sessionQueue` 上でキャプチャセッションを構築・開始する。
  ///
  /// 指定デバイスの解決、最適フォーマット選択、`AVCaptureSession` の生成と
  /// 入力・出力の追加、フレーム送出キューへの delegate 設定までを行う。
  /// このメソッドは必ず `sessionQueue` から呼ばれることを前提とする。
  private func startCaptureSessionOnQueue() {
    guard running else { return }
    let device = Self.resolveDevice(deviceId: self.selectedDeviceId)
    guard let device = device else {
      NSLog("No camera device available")
      self.running = false
      return
    }
    self.selectedDeviceId = device.uniqueID

    do {
      self.captureInput = try AVCaptureDeviceInput(device: device)
    } catch {
      NSLog("Failed to create capture input: %@", error.localizedDescription)
      self.running = false
      return
    }

    self.selectBestFormat(device)

    self.captureSession = AVCaptureSession()
    self.captureSession!.beginConfiguration()
    if self.captureSession!.canSetSessionPreset(.inputPriority) {
      // 解像度指定を優先するため、session preset ではなく input format を採用する
      self.captureSession!.sessionPreset = .inputPriority
    }
    if self.captureSession!.canAddInput(self.captureInput!) {
      self.captureSession!.addInput(self.captureInput!)
    }

    self.captureOutput = AVCaptureVideoDataOutput()
    self.captureOutput!.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    self.captureOutput!.alwaysDiscardsLateVideoFrames = true
    self.captureQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.camera")
    self.captureOutput!.setSampleBufferDelegate(self, queue: self.captureQueue)

    if self.captureSession!.canAddOutput(self.captureOutput!) {
      self.captureSession!.addOutput(self.captureOutput!)
    }

    self.captureSession!.commitConfiguration()
    self.captureSession!.startRunning()
  }

  // フロント/バックカメラを切り替える
  // iPhone 実機を想定しているため iOS のみ
  func switchCamera(completion: @escaping (Result<[String: Any], Error>) -> Void) {
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      guard self.running else {
        self.completeSwitchCamera(
          completion,
          with: .failure(self.makeCameraError("Camera is not running."))
        )
        return
      }
      guard
        let currentDevice = self.captureInput?.device
          ?? Self.resolveDevice(deviceId: self.selectedDeviceId)
      else {
        self.completeSwitchCamera(
          completion,
          with: .failure(self.makeCameraError("Current camera device is not available."))
        )
        return
      }
      guard let nextDevice = Self.findOppositeDevice(from: currentDevice) else {
        self.completeSwitchCamera(
          completion,
          with: .failure(self.makeCameraError("Alternative camera device is not available."))
        )
        return
      }
      guard let session = self.captureSession else {
        self.completeSwitchCamera(
          completion,
          with: .failure(self.makeCameraError("Capture session is not available."))
        )
        return
      }

      do {
        let nextInput = try AVCaptureDeviceInput(device: nextDevice)
        let previousInput = self.captureInput

        session.beginConfiguration()
        if session.canSetSessionPreset(.inputPriority) {
          // カメラ切り替え後も input format を優先する
          session.sessionPreset = .inputPriority
        }
        if let previousInput = previousInput {
          session.removeInput(previousInput)
        }
        guard session.canAddInput(nextInput) else {
          if let previousInput = previousInput, session.canAddInput(previousInput) {
            session.addInput(previousInput)
          }
          session.commitConfiguration()
          self.completeSwitchCamera(
            completion,
            with: .failure(self.makeCameraError("Failed to add the switched camera input."))
          )
          return
        }

        self.selectBestFormat(nextDevice)
        session.addInput(nextInput)
        self.captureInput = nextInput
        self.selectedDeviceId = nextDevice.uniqueID
        session.commitConfiguration()

        self.completeSwitchCamera(
          completion,
          with: .success([
            "deviceId": nextDevice.uniqueID,
            "label": nextDevice.localizedName,
          ])
        )
      } catch {
        self.completeSwitchCamera(completion, with: .failure(error))
      }
    }
  }

  /// カメラキャプチャを停止する。
  /// session 停止と delegate 解除を同期的に完了させてから return することで、
  /// in-flight フレームコールバックが解放済み video source を叩く UAF を防ぐ。
  /// sessionQueue 上から呼ばれた場合 (deinit 経由) は直接実行する。
  func stop() {
    guard running else { return }
    running = false
    stopDeviceOrientationMonitoring()
    let cleanup = { [weak self] in
      guard let self = self else { return }
      self.captureOutput?.setSampleBufferDelegate(nil, queue: nil)
      self.captureSession?.stopRunning()
      self.captureSession = nil
      self.captureInput = nil
      self.captureOutput = nil
      self.videoSourcePtr = nil
    }
    if DispatchQueue.getSpecific(key: Self.sessionQueueKey) != nil {
      cleanup()
    } else {
      sessionQueue.sync(execute: cleanup)
    }
  }

  /// デバイスの向き監視を開始し、現在の向きを初期値として設定する。
  ///
  /// `UIDevice.orientationDidChangeNotification` を購読し、
  /// 対応する向きの変化を `currentDeviceOrientation` に反映する。
  private func startDeviceOrientationMonitoring() {
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    let orientation = UIDevice.current.orientation
    if isSupportedDeviceOrientation(orientation) {
      currentDeviceOrientation = orientation
    }
    orientationObserver = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      guard let self = self else { return }
      let orientation = UIDevice.current.orientation
      if self.isSupportedDeviceOrientation(orientation) {
        self.currentDeviceOrientation = orientation
      }
    }
  }

  private func stopDeviceOrientationMonitoring() {
    if let observer = orientationObserver {
      NotificationCenter.default.removeObserver(observer)
      orientationObserver = nil
    }
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  private func isSupportedDeviceOrientation(_ orientation: UIDeviceOrientation) -> Bool {
    switch orientation {
    case .portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight:
      return true
    default:
      return false
    }
  }

  private func selectBestFormat(_ device: AVCaptureDevice) {
    var bestFormat: AVCaptureDevice.Format?
    var bestDiff = Int32.max
    var bestFps: Float64 = 0

    for format in device.formats {
      let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      let diff = abs(dims.width - requestedWidth) + abs(dims.height - requestedHeight)

      var maxFps: Float64 = 0
      for range in format.videoSupportedFrameRateRanges {
        if range.maxFrameRate > maxFps {
          maxFps = range.maxFrameRate
        }
      }

      if diff < bestDiff || (diff == bestDiff && maxFps > bestFps) {
        bestFormat = format
        bestDiff = diff
        bestFps = maxFps
      }
    }

    guard let bestFormat = bestFormat else { return }
    do {
      try device.lockForConfiguration()
      device.activeFormat = bestFormat
      let targetRange = resolveSupportedFrameRateRange(
        requestedFps: Float64(requestedFps),
        ranges: bestFormat.videoSupportedFrameRateRanges
      )
      if let targetRange = targetRange {
        let frameDuration = resolveFrameDuration(
          requestedFps: Float64(requestedFps),
          range: targetRange
        )
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
      } else if bestFps > 0 {
        let frameDuration = CMTime(value: 1, timescale: Int32(bestFps.rounded()))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
      }
      device.unlockForConfiguration()
    } catch {
      // フォーマット設定に失敗した場合はデフォルトを使用する
    }
  }

  // 選択した format が受け付ける fps range を返す
  private func resolveSupportedFrameRateRange(
    requestedFps: Float64,
    ranges: [AVFrameRateRange]
  ) -> AVFrameRateRange? {
    guard !ranges.isEmpty else { return nil }

    for range in ranges {
      if requestedFps >= range.minFrameRate && requestedFps <= range.maxFrameRate {
        return range
      }
    }

    return ranges.min {
      let lhs = max($0.minFrameRate, min(requestedFps, $0.maxFrameRate))
      let rhs = max($1.minFrameRate, min(requestedFps, $1.maxFrameRate))
      return abs(lhs - requestedFps) < abs(rhs - requestedFps)
    }
  }

  // 固定 fps の range では、AVFoundation が返す厳密な duration を使う
  private func resolveFrameDuration(
    requestedFps: Float64,
    range: AVFrameRateRange
  ) -> CMTime {
    if range.minFrameRate == range.maxFrameRate {
      return range.minFrameDuration
    }

    let targetFps = max(range.minFrameRate, min(requestedFps, range.maxFrameRate))
    return CMTime(value: 1, timescale: Int32(targetFps.rounded()))
  }

  private func currentFrameRotation() -> Int32 {
    let position = captureInput?.device.position ?? .unspecified
    switch currentDeviceOrientation {
    case .portrait:
      return webrtc_VideoRotation_90
    case .portraitUpsideDown:
      return webrtc_VideoRotation_270
    case .landscapeLeft:
      return position == .front ? webrtc_VideoRotation_180 : webrtc_VideoRotation_0
    case .landscapeRight:
      return position == .front ? webrtc_VideoRotation_0 : webrtc_VideoRotation_180
    default:
      return webrtc_VideoRotation_90
    }
  }

  private func createPreviewBuffer(
    sourceBuffer: OpaquePointer,
    width: Int32,
    height: Int32,
    rotation: Int32
  ) -> (buffer: OpaquePointer, width: Int32, height: Int32)? {
    if rotation != webrtc_VideoRotation_90
      && rotation != webrtc_VideoRotation_180
      && rotation != webrtc_VideoRotation_270
    {
      return nil
    }

    let rotatedWidth =
      (rotation == webrtc_VideoRotation_90 || rotation == webrtc_VideoRotation_270)
      ? height : width
    let rotatedHeight =
      (rotation == webrtc_VideoRotation_90 || rotation == webrtc_VideoRotation_270)
      ? width : height
    guard let rotatedRef = webrtc_I420Buffer_Create(rotatedWidth, rotatedHeight),
      let rotatedBuffer = webrtc_I420Buffer_refcounted_get(rotatedRef)
    else {
      return nil
    }

    let result = libyuv_I420Rotate(
      webrtc_I420Buffer_MutableDataY(sourceBuffer), webrtc_I420Buffer_StrideY(sourceBuffer),
      webrtc_I420Buffer_MutableDataU(sourceBuffer), webrtc_I420Buffer_StrideU(sourceBuffer),
      webrtc_I420Buffer_MutableDataV(sourceBuffer), webrtc_I420Buffer_StrideV(sourceBuffer),
      webrtc_I420Buffer_MutableDataY(rotatedBuffer), webrtc_I420Buffer_StrideY(rotatedBuffer),
      webrtc_I420Buffer_MutableDataU(rotatedBuffer), webrtc_I420Buffer_StrideU(rotatedBuffer),
      webrtc_I420Buffer_MutableDataV(rotatedBuffer), webrtc_I420Buffer_StrideV(rotatedBuffer),
      width, height, rotation
    )
    if result != 0 {
      webrtc_I420Buffer_Release(rotatedBuffer)
      return nil
    }

    return (rotatedBuffer, rotatedWidth, rotatedHeight)
  }

  // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard running else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
    let height = Int32(CVPixelBufferGetHeight(pixelBuffer))

    // I420 バッファを作成する
    guard let i420Ref = webrtc_I420Buffer_Create(width, height),
      let i420 = webrtc_I420Buffer_refcounted_get(i420Ref)
    else {
      return
    }
    let frameRotation = currentFrameRotation()

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

    // ローカルプレビュー用に BGRA 変換した CVPixelBuffer を作成する
    let rotatedPreview = createPreviewBuffer(
      sourceBuffer: i420,
      width: width,
      height: height,
      rotation: frameRotation
    )
    let previewSourceBuffer = rotatedPreview?.buffer ?? i420
    let previewWidth = rotatedPreview?.width ?? width
    let previewHeight = rotatedPreview?.height ?? height
    previewLock.lock()
    previewPixelBuffer = nil
    let options: [String: Any] = [
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    var previewBuffer: CVPixelBuffer?
    CVPixelBufferCreate(
      nil, Int(previewWidth), Int(previewHeight),
      kCVPixelFormatType_32BGRA,
      options as CFDictionary,
      &previewBuffer
    )
    if let previewBuffer = previewBuffer {
      CVPixelBufferLockBaseAddress(previewBuffer, [])
      if let dstPixels = CVPixelBufferGetBaseAddress(previewBuffer) {
        let dstPitch = Int32(CVPixelBufferGetBytesPerRow(previewBuffer))
        libyuv_ConvertFromI420(
          webrtc_I420Buffer_MutableDataY(previewSourceBuffer),
          webrtc_I420Buffer_StrideY(previewSourceBuffer),
          webrtc_I420Buffer_MutableDataU(previewSourceBuffer),
          webrtc_I420Buffer_StrideU(previewSourceBuffer),
          webrtc_I420Buffer_MutableDataV(previewSourceBuffer),
          webrtc_I420Buffer_StrideV(previewSourceBuffer),
          dstPixels.assumingMemoryBound(to: UInt8.self), dstPitch,
          previewWidth, previewHeight,
          libyuv_FOURCC_ARGB
        )
      }
      CVPixelBufferUnlockBaseAddress(previewBuffer, [])
    }
    previewPixelBuffer = previewBuffer
    previewLock.unlock()
    if let rotatedPreview = rotatedPreview {
      webrtc_I420Buffer_Release(rotatedPreview.buffer)
    }

    // VideoFrame を作成して AdaptedVideoTrackSource に投入する
    sourceBlock: if let sourcePtr = videoSourcePtr {
      let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
      let timestampUs = Int64(CMTimeGetSeconds(pts) * 1_000_000.0)

      guard
        let frame = sora_video_frame_create(
          i420Ref, frameRotation, timestampUs, 0)
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

  private static func availableDevices() -> [AVCaptureDevice] {
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera
    ]

    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    return session.devices
  }

  private static func resolveDevice(deviceId: String?) -> AVCaptureDevice? {
    if let deviceId = deviceId, let device = AVCaptureDevice(uniqueID: deviceId) {
      return device
    }
    return AVCaptureDevice.default(for: .video) ?? availableDevices().first
  }

  private static func findOppositeDevice(from device: AVCaptureDevice) -> AVCaptureDevice? {
    let nextPosition: AVCaptureDevice.Position
    switch device.position {
    case .front:
      nextPosition = .back
    case .back:
      nextPosition = .front
    default:
      return nil
    }
    return availableDevices().first { candidate in
      candidate.position == nextPosition
    }
  }

  private func completeSwitchCamera(
    _ completion: @escaping (Result<[String: Any], Error>) -> Void,
    with result: Result<[String: Any], Error>
  ) {
    DispatchQueue.main.async {
      completion(result)
    }
  }

  // カメラ処理におけるエラー
  // swift では NSError で返し、MethodChanel 側で FlutterError にする
  private func makeCameraError(_ message: String) -> NSError {
    NSError(
      domain: "jp.shiguredo.sora_sdk.camera",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

// ローカルプレビュー用テクスチャ
class SoraLocalPreviewTexture: NSObject, FlutterTexture {
  private weak var capturer: SoraCameraCapturer?

  init(capturer: SoraCameraCapturer) {
    self.capturer = capturer
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return capturer?.copyPreviewPixelBuffer()
  }
}
