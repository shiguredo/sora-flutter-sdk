import AVFoundation
import CoreImage
import FlutterMacOS

@_implementationOnly import CWebrtc

/// カメラ映像のキャプチャと dart:ffi へのフレーム送出を担当するクラス。
///
/// `AVCaptureSession` で指定デバイスから映像を取得し、
/// `AdaptedVideoTrackSource` へ I420 フレームを投入する。
/// ローカルプレビュー用の `FlutterTextureRegistry` 管理も行う。
class SoraCameraCapturer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  private static let sessionQueueKey =
    DispatchSpecificKey<Void>()
  // captureSession / videoSourcePtr への書き込みを直列化し、
  // delegate コールバック (captureQueue) とのデータレースを防ぐ。
  // deinit 経路では getSpecific でキュー判定し直接実行する。
  private let sessionQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.camera.session")
  private var selectedDeviceId: String?
  private var requestedWidth: Int32
  private var requestedHeight: Int32
  private var requestedFps: Int32
  private var selectedFormatWidth: Int32?
  private var selectedFormatHeight: Int32?
  private let textureRegistry: FlutterTextureRegistry

  private var captureSession: AVCaptureSession?
  private var captureInput: AVCaptureDeviceInput?
  private var captureOutput: AVCaptureVideoDataOutput?
  private var captureQueue: DispatchQueue?

  // dart:ffi 側の AdaptedVideoTrackSource ポインタ
  private var videoSourcePtr: OpaquePointer?

  // ローカルプレビュー用
  private var previewTexture: SoraLocalPreviewTexture!
  private(set) var previewTextureId: Int64 = -1
  private var previewPixelBuffer: CVPixelBuffer?
  private var previewLock = NSLock()
  private let previewCiContext = CIContext()

  private var running = false

  // MARK: - クラスメソッド

  static func enumerateDevices() -> [[String: Any]] {
    var result: [[String: Any]] = []

    let deviceTypes: [AVCaptureDevice.DeviceType] = [
      .builtInWideAngleCamera,
      .external,
    ]

    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    )
    for device in session.devices {
      result.append([
        "deviceId": device.uniqueID,
        "label": device.localizedName,
      ])
    }
    return result
  }

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

  var localPreviewTextureId: Int64 {
    return previewTextureId
  }

  // MARK: - ビデオソースポインタ

  /// dart:ffi 側の AdaptedVideoTrackSource ポインタを設定する。
  /// 書き込みは sessionQueue.async で直列化するため、setter から戻った時点で
  /// videoSourcePtr の更新完了は保証しない。
  /// start() 直後に delegate が動くと初回フレームで videoSourcePtr が nil に
  /// なる場合があるが、その場合は OnFrame 呼び出しをスキップするため安全である。
  func setVideoSourcePtr(_ ptr: Int64) {
    sessionQueue.async { [weak self] in
      self?.videoSourcePtr = OpaquePointer(bitPattern: Int(ptr))
    }
  }

  // MARK: - キャプチャ制御

  func start() {
    guard !running else { return }
    running = true
    sessionQueue.async { [weak self] in
      self?.startCaptureSessionOnQueue()
    }
  }

  /// sessionQueue 上で呼ばれることを前提としたセッション構築。
  /// restart() では cleanup と同一 sessionQueue ブロック内で呼ぶことで
  /// 旧 captureOutput callback との競合を防ぐ。
  private func startCaptureSessionOnQueue() {
    running = true

    var device: AVCaptureDevice?
    if let deviceId = selectedDeviceId {
      device = AVCaptureDevice(uniqueID: deviceId)
    }
    if device == nil {
      device = AVCaptureDevice.default(for: .video)
    }
    guard let device = device else {
      NSLog("No camera device available")
      running = false
      return
    }
    selectedDeviceId = device.uniqueID

    do {
      captureInput = try AVCaptureDeviceInput(device: device)
    } catch {
      NSLog("Failed to create capture input: %@", error.localizedDescription)
      running = false
      return
    }

    selectBestFormat(device)

    captureSession = AVCaptureSession()
    captureSession!.beginConfiguration()
    if captureSession!.canAddInput(captureInput!) {
      captureSession!.addInput(captureInput!)
    }

    captureOutput = AVCaptureVideoDataOutput()
    var videoSettings: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    if let selectedFormatWidth = selectedFormatWidth,
      let selectedFormatHeight = selectedFormatHeight
    {
      // macOS では inputPriority を使えないため、output 側のバッファサイズを明示する
      // ここで selectBestFormat() で選んだ format と同じ幅・高さを指定しておかないと、
      // session / output 側の都合で別の解像度に丸められることがある
      videoSettings[kCVPixelBufferWidthKey as String] = selectedFormatWidth
      videoSettings[kCVPixelBufferHeightKey as String] = selectedFormatHeight
    }
    captureOutput!.videoSettings = videoSettings
    captureOutput!.alwaysDiscardsLateVideoFrames = true
    captureQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.camera")
    captureOutput!.setSampleBufferDelegate(self, queue: captureQueue)

    if captureSession!.canAddOutput(captureOutput!) {
      captureSession!.addOutput(captureOutput!)
    }

    captureSession!.commitConfiguration()
    captureSession!.startRunning()
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
    sessionQueue.async { [weak self] in
      guard let self = self else { return }
      self.captureOutput?.setSampleBufferDelegate(nil, queue: nil)
      self.captureSession?.stopRunning()
      self.captureSession = nil
      self.captureInput = nil
      self.captureOutput = nil
      self.running = false
      self.startCaptureSessionOnQueue()
    }
  }

  /// カメラキャプチャを停止する。
  /// sessionQueue 経由で delegate コールバックと直列化し、
  /// delegate が captureSession / videoSourcePtr を読んでいる途中で
  /// stop が書き換えるデータレースを防ぐ。
  func stop() {
    guard running else { return }
    running = false
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

  // 要求された解像度と fps に一番近い AVCaptureDevice.Format を選んで適用する
  private func selectBestFormat(_ device: AVCaptureDevice) {
    // restart() のたびに選び直すため、前回の format 情報は必ず捨てる
    selectedFormatWidth = nil
    selectedFormatHeight = nil
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
    let bestDimensions = CMVideoFormatDescriptionGetDimensions(bestFormat.formatDescription)
    // start() で VideoDataOutput の出力サイズにも同じ値を使う
    selectedFormatWidth = bestDimensions.width
    selectedFormatHeight = bestDimensions.height
    do {
      try device.lockForConfiguration()
      // capture device 自体の activeFormat も要求解像度に最も近いものへ合わせる
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
      NSLog("Failed to configure camera format: %@", error.localizedDescription)
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
    // videoSourcePtr の読み出しは sessionQueue 経由で直列化し、
    // stop() / restart() の書き込みとのデータレースを防ぐ。
    let sourcePtr = sessionQueue.sync { [weak self] in
      self?.videoSourcePtr
    }
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
class SoraLocalPreviewTexture: NSObject, FlutterTexture {
  private weak var capturer: SoraCameraCapturer?

  init(capturer: SoraCameraCapturer) {
    self.capturer = capturer
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    return capturer?.copyPreviewPixelBuffer()
  }
}
