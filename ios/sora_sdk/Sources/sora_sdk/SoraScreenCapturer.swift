import CoreMedia
import Flutter
import Foundation
import ReplayKit

@_implementationOnly import CWebrtc

/// ReplayKit によるアプリ内画面キャプチャのエラーです。
enum SoraScreenCaptureError: LocalizedError {
  case invalidConnection
  case alreadyCapturing
  case operationInProgress
  case startCancelled
  case startFailed(Error)
  case stopFailed(Error)
  case unsupportedPixelFormat(OSType)
  case frameConversionFailed(OSType)
  case runtimeError(Error)

  var errorDescription: String? {
    switch self {
    case .invalidConnection:
      return "A valid connection is required to start screen capture"
    case .alreadyCapturing:
      return "Another screen capture is already running"
    case .operationInProgress:
      return "A screen capture operation is already in progress"
    case .startCancelled:
      return "Screen capture start was cancelled"
    case .startFailed(let error):
      return "Failed to start screen capture: \(error.localizedDescription)"
    case .stopFailed(let error):
      return "Failed to stop screen capture: \(error.localizedDescription)"
    case .unsupportedPixelFormat(let pixelFormat):
      return "Unsupported screen capture pixel format: \(pixelFormat)"
    case .frameConversionFailed(let pixelFormat):
      return "Failed to convert screen capture pixel format: \(pixelFormat)"
    case .runtimeError(let error):
      return "Screen capture runtime error: \(error.localizedDescription)"
    }
  }

  /// Dart 側へ通知する安定した原因識別子です。
  var channelCode: String {
    switch self {
    case .invalidConnection:
      return "screen_capture_invalid_connection"
    case .alreadyCapturing:
      return "screen_capture_already_capturing"
    case .operationInProgress:
      return "screen_capture_operation_in_progress"
    case .startCancelled:
      return "screen_capture_start_cancelled"
    case .startFailed:
      return "screen_capture_start_failed"
    case .stopFailed:
      return "screen_capture_stop_failed"
    case .unsupportedPixelFormat:
      return "screen_capture_unsupported_pixel_format"
    case .frameConversionFailed:
      return "screen_capture_frame_conversion_failed"
    case .runtimeError:
      return "screen_capture_runtime_error"
    }
  }
}

/// プロセス全体で共有する画面キャプチャの所有者です。
struct SoraScreenCaptureOwner: Equatable {
  let messageHandlerIdentity: UUID
  let videoSourcePtr: Int64
  let connectionId: Int64
}

/// 複数の Flutter engine をまたいで ReplayKit の所有権を管理します。
@MainActor
final class SoraScreenCaptureCoordinator {
  static let shared = SoraScreenCaptureCoordinator()

  private weak var capturer: SoraScreenCapturer?
  private var owner: SoraScreenCaptureOwner?
  private var generation: UInt64 = 0
  private var activeGeneration: UInt64?
  private var cleanupScheduled = false

  private init() {}

  func reserve(owner: SoraScreenCaptureOwner, capturer: SoraScreenCapturer) -> UInt64? {
    // capturer が先に解放されても recorder が収録中なら所有 token を
    // 破棄しない。token を失うと新しい engine が予約できる一方、古い
    // ReplayKit を停止する主体がなくなるため、coordinator 自身で再試行する。
    if self.capturer == nil {
      if self.owner != nil && RPScreenRecorder.shared().isRecording {
        scheduleCleanupIfNeeded()
        return nil
      }
      self.owner = nil
      self.activeGeneration = nil
    }
    if self.owner == nil {
      generation &+= 1
      self.owner = owner
      self.capturer = capturer
      activeGeneration = generation
      return generation
    }
    guard self.owner == owner,
      self.capturer === capturer,
      let activeGeneration
    else {
      return nil
    }
    return activeGeneration
  }

  /// capturer が解放された後も recorder が収録中なら停止を再試行します。
  private func scheduleCleanupIfNeeded() {
    guard !cleanupScheduled,
      let expectedOwner = owner,
      let expectedGeneration = activeGeneration
    else {
      return
    }
    cleanupScheduled = true
    let recorder = RPScreenRecorder.shared()
    Task { @MainActor [weak self] in
      defer { self?.cleanupScheduled = false }
      for attempt in 0..<10 {
        guard let self,
          self.owner == expectedOwner,
          self.activeGeneration == expectedGeneration
        else {
          return
        }
        if !recorder.isRecording {
          self.release(owner: expectedOwner, generation: expectedGeneration)
          return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          recorder.stopCapture { error in
            if let error {
              NSLog(
                "Failed to stop stale screen capture: %@ (attempt=%d)",
                error.localizedDescription,
                attempt + 1
              )
            }
            continuation.resume()
          }
        }
        if !recorder.isRecording {
          self.release(owner: expectedOwner, generation: expectedGeneration)
          return
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      NSLog("Stale screen capture is still recording after cleanup retries")
    }
  }

  func isOwner(
    _ owner: SoraScreenCaptureOwner,
    capturer: SoraScreenCapturer,
    generation: UInt64? = nil
  ) -> Bool {
    self.owner == owner
      && self.capturer === capturer
      && (generation == nil || activeGeneration == generation)
  }

  func isOwner(_ owner: SoraScreenCaptureOwner, generation: UInt64) -> Bool {
    self.owner == owner && activeGeneration == generation
  }

  func release(
    owner: SoraScreenCaptureOwner,
    capturer: SoraScreenCapturer,
    generation: UInt64? = nil
  ) {
    guard isOwner(owner, capturer: capturer, generation: generation) else { return }
    release(owner: owner, generation: activeGeneration)
  }

  func release(owner: SoraScreenCaptureOwner, generation: UInt64?) {
    guard self.owner == owner,
      generation == nil || activeGeneration == generation
    else {
      return
    }
    self.owner = nil
    self.capturer = nil
    self.activeGeneration = nil
  }
}

/// ReplayKit の画面映像を libwebrtc と Flutter Texture へ送出します。
final class SoraScreenCapturer: @unchecked Sendable {
  private enum CaptureState {
    case stopped
    case starting
    case running
    case stopping
  }

  private let recorder = RPScreenRecorder.shared()
  private let targetFPS: Int
  private let textureRegistry: FlutterTextureRegistry
  private let frameQueue = DispatchQueue(label: "jp.shiguredo.sora_sdk.screen.frame")
  private let frameSemaphore = DispatchSemaphore(value: 1)
  private let stateLock = NSLock()
  private let previewLock = NSLock()

  private var state: CaptureState = .stopped
  private var captureID: UInt64 = 0
  private var activeCaptureID: UInt64?
  private var owner: SoraScreenCaptureOwner?
  private var startCompletions: [(Error?) -> Void] = []
  private var stopCompletions: [(Error?) -> Void] = []
  private var stateBeforeStopping: CaptureState?
  private var hasPendingStartResult = false
  private var pendingStartResult: Error?
  private var coordinatorGeneration: UInt64?
  private var lastSentPresentationTimestamp: CMTime?
  private var lastSentUptime: TimeInterval?
  private var lastPixelFormatError: (pixelFormat: OSType, channelCode: String)?
  private var disposed = false

  private var _videoSourcePtr: OpaquePointer?
  private var videoSourceLock = os_unfair_lock()
  private var videoSourcePtr: OpaquePointer? {
    get {
      os_unfair_lock_lock(&videoSourceLock)
      defer { os_unfair_lock_unlock(&videoSourceLock) }
      return _videoSourcePtr
    }
    set {
      os_unfair_lock_lock(&videoSourceLock)
      _videoSourcePtr = newValue
      os_unfair_lock_unlock(&videoSourceLock)
    }
  }

  private var previewTexture: SoraScreenPreviewTexture!
  private(set) var previewTextureId: Int64 = -1
  private var previewPixelBuffer: CVPixelBuffer?

  var onRuntimeError: ((SoraScreenCaptureError, SoraScreenCaptureOwner, UInt64) -> Void)?

  init(
    videoSourcePtr: Int64,
    frameRate: Int,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.targetFPS = min(max(1, frameRate), 120)
    self.textureRegistry = textureRegistry
    self.videoSourcePtr = OpaquePointer(bitPattern: Int(videoSourcePtr))

    let texture = SoraScreenPreviewTexture(capturer: self)
    previewTexture = texture
    previewTextureId = textureRegistry.register(texture)
  }

  deinit {
    let captureContext = withStateLock {
      (owner: owner, generation: coordinatorGeneration)
    }
    let textureId = previewTextureId
    previewTextureId = -1
    if textureId >= 0 {
      textureRegistry.unregisterTexture(textureId)
    }
    videoSourcePtr = nil
    previewLock.lock()
    previewPixelBuffer = nil
    previewLock.unlock()

    // 通常は engine detach の明示的な dispose が先に呼ばれるが、
    // 想定外の破棄でも自分の lease に一致する収録だけを停止する。
    if let owner = captureContext.owner,
      let generation = captureContext.generation
    {
      let recorder = self.recorder
      Task { @MainActor in
        Self.stopCaptureAfterDeinit(
          recorder: recorder,
          owner: owner,
          generation: generation,
          attempt: 0
        )
      }
    }
  }

  /// 明示的な dispose が漏れた場合でも共有 recorder を停止します。
  ///
  /// ReplayKit の停止失敗は一時的に発生する可能性があるため、短い間隔で
  /// 再試行します。所有 token が変わった場合は新しい収録を停止しないよう、
  /// その時点で処理を打ち切ります。
  @MainActor
  private static func stopCaptureAfterDeinit(
    recorder: RPScreenRecorder,
    owner: SoraScreenCaptureOwner,
    generation: UInt64,
    attempt: Int
  ) {
    let coordinator = SoraScreenCaptureCoordinator.shared
    guard coordinator.isOwner(owner, generation: generation) else { return }
    recorder.stopCapture { error in
      Task { @MainActor in
        guard coordinator.isOwner(owner, generation: generation) else { return }
        if let error {
          NSLog(
            "Failed to stop screen capture during deinit: %@ (attempt=%d)",
            error.localizedDescription,
            attempt + 1
          )
          if !recorder.isRecording {
            coordinator.release(owner: owner, generation: generation)
            return
          }
          if attempt >= 9 {
            // 停止失敗が続いても owner token を破棄せず、一定時間後に
            // 再試行する。新しい engine の reserve も同じ coordinator が
            // cleanup を継続している間は拒否する。
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 1_000_000_000)
              Self.stopCaptureAfterDeinit(
                recorder: recorder,
                owner: owner,
                generation: generation,
                attempt: 0
              )
            }
            return
          }
          Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            Self.stopCaptureAfterDeinit(
              recorder: recorder,
              owner: owner,
              generation: generation,
              attempt: attempt + 1
            )
          }
          return
        }
        coordinator.release(owner: owner, generation: generation)
      }
    }
  }

  var localPreviewTextureId: Int64 {
    previewLock.lock()
    defer { previewLock.unlock() }
    return previewTextureId
  }

  /// 同じ接続からの重複 start は同じ完了結果へ合流させます。
  func start(
    owner requestedOwner: SoraScreenCaptureOwner,
    completion: @escaping (Error?) -> Void
  ) {
    performOnMainActor { [weak self] in
      guard let self else {
        completion(SoraScreenCaptureError.startCancelled)
        return
      }
      self.startOnMainActor(owner: requestedOwner, completion: completion)
    }
  }

  /// プロセス共有 coordinator の予約とローカル状態遷移を MainActor 上で直列化します。
  @MainActor
  private func startOnMainActor(
    owner requestedOwner: SoraScreenCaptureOwner,
    completion: @escaping (Error?) -> Void
  ) {
    let coordinator = SoraScreenCaptureCoordinator.shared
    guard
      let coordinatorGeneration = coordinator.reserve(
        owner: requestedOwner,
        capturer: self
      )
    else {
      completion(SoraScreenCaptureError.alreadyCapturing)
      return
    }

    var shouldStart = false
    var immediateError: Error?
    var completesImmediately = false

    withStateLock {
      guard !disposed else {
        immediateError = SoraScreenCaptureError.startCancelled
        completesImmediately = true
        return
      }
      switch state {
      case .running:
        completesImmediately = true
        if owner != requestedOwner {
          immediateError = SoraScreenCaptureError.alreadyCapturing
        }
      case .starting:
        if owner == requestedOwner {
          startCompletions.append(completion)
        } else {
          immediateError = SoraScreenCaptureError.alreadyCapturing
          completesImmediately = true
        }
      case .stopping:
        immediateError = SoraScreenCaptureError.operationInProgress
        completesImmediately = true
      case .stopped:
        captureID += 1
        activeCaptureID = captureID
        owner = requestedOwner
        self.coordinatorGeneration = coordinatorGeneration
        lastSentPresentationTimestamp = nil
        lastSentUptime = nil
        lastPixelFormatError = nil
        hasPendingStartResult = false
        pendingStartResult = nil
        startCompletions = [completion]
        state = .starting
        shouldStart = true
      }
    }

    if completesImmediately {
      if immediateError != nil && withStateLock({ state == .stopped }) {
        coordinator.release(
          owner: requestedOwner,
          capturer: self,
          generation: coordinatorGeneration
        )
      }
      completion(immediateError)
      return
    }
    guard shouldStart else { return }

    guard let currentCaptureID = withStateLock({ activeCaptureID }) else {
      coordinator.release(
        owner: requestedOwner,
        capturer: self,
        generation: coordinatorGeneration
      )
      completion(SoraScreenCaptureError.startCancelled)
      return
    }
    guard !recorder.isRecording else {
      coordinator.release(
        owner: requestedOwner,
        capturer: self,
        generation: coordinatorGeneration
      )
      completeStart(
        captureID: currentCaptureID,
        owner: requestedOwner,
        error: SoraScreenCaptureError.alreadyCapturing
      )
      return
    }

    recorder.isMicrophoneEnabled = false
    recorder.isCameraEnabled = false
    recorder.startCapture(
      handler: { [weak self] sampleBuffer, sampleBufferType, error in
        self?.handleSampleBuffer(
          sampleBuffer,
          sampleBufferType: sampleBufferType,
          error: error,
          owner: requestedOwner,
          captureID: currentCaptureID
        )
      },
      completionHandler: { [weak self] error in
        guard let self else { return }
        self.performOnMainActor {
          if let error {
            let isCurrentStart = self.withStateLock {
              self.state == .starting
                && self.activeCaptureID == currentCaptureID
                && self.owner == requestedOwner
            }
            if isCurrentStart {
              coordinator.release(
                owner: requestedOwner,
                capturer: self,
                generation: coordinatorGeneration
              )
            }
            self.completeStart(
              captureID: currentCaptureID,
              owner: requestedOwner,
              error: SoraScreenCaptureError.startFailed(error)
            )
            return
          }

          let accepted = self.completeStart(
            captureID: currentCaptureID,
            owner: requestedOwner,
            error: nil
          )
          let hasNewerCapture = self.withStateLock {
            self.activeCaptureID != nil && self.activeCaptureID != currentCaptureID
          }
          let isStopping = self.withStateLock { self.state == .stopping }
          let stillOwnsCoordinator = coordinator.isOwner(
            requestedOwner,
            capturer: self,
            generation: coordinatorGeneration
          )
          if !accepted && !hasNewerCapture && !isStopping && stillOwnsCoordinator {
            self.recorder.stopCapture { _ in
              self.performOnMainActor {
                coordinator.release(
                  owner: requestedOwner,
                  capturer: self,
                  generation: coordinatorGeneration
                )
              }
            }
          }
        }
      }
    )
  }

  /// 所有接続と一致する場合だけキャプチャを停止します。
  func stop(
    owner requestedOwner: SoraScreenCaptureOwner?,
    force: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    performOnMainActor { [weak self] in
      guard let self else {
        completion(
          SoraScreenCaptureError.stopFailed(
            SoraScreenCaptureError.startCancelled
          ))
        return
      }
      self.stopOnMainActor(
        owner: requestedOwner,
        force: force,
        completion: completion
      )
    }
  }

  @MainActor
  private func stopOnMainActor(
    owner requestedOwner: SoraScreenCaptureOwner?,
    force: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    var shouldStop = false
    var currentOwner: SoraScreenCaptureOwner?
    var currentCoordinatorGeneration: UInt64?
    var ignoredOwnerMismatch = false

    withStateLock {
      currentOwner = owner
      currentCoordinatorGeneration = coordinatorGeneration
      if !force, owner != requestedOwner {
        ignoredOwnerMismatch = true
        return
      }
      switch state {
      case .stopped:
        break
      case .stopping:
        stopCompletions.append(completion)
      case .starting, .running:
        stateBeforeStopping = state
        state = .stopping
        stopCompletions.append(completion)
        shouldStop = true
      }
    }

    if ignoredOwnerMismatch {
      completion(nil)
      return
    }
    guard shouldStop else {
      let isAlreadyStopping = withStateLock { state == .stopping }
      if !isAlreadyStopping {
        completion(nil)
      }
      return
    }

    recorder.stopCapture { [weak self] error in
      guard let self else {
        completion(
          SoraScreenCaptureError.stopFailed(
            SoraScreenCaptureError.startCancelled
          ))
        return
      }
      self.frameQueue.async { [weak self] in
        guard let self else { return }
        self.performOnMainActor {
          if let error {
            NSLog("Failed to stop screen capture: %@", error.localizedDescription)
            if !self.recorder.isRecording, let currentOwner {
              SoraScreenCaptureCoordinator.shared.release(
                owner: currentOwner,
                capturer: self,
                generation: currentCoordinatorGeneration
              )
            }
            self.completeStop(error: SoraScreenCaptureError.stopFailed(error))
            return
          }
          if let currentOwner {
            SoraScreenCaptureCoordinator.shared.release(
              owner: currentOwner,
              capturer: self,
              generation: currentCoordinatorGeneration
            )
          }
          self.completeStop(error: nil)
        }
      }
    }
  }

  /// キャプチャ停止後に Texture と映像ソースを破棄します。
  func dispose(completion: @escaping (Error?) -> Void) {
    let currentOwner = withStateLock { owner }
    stop(owner: currentOwner, force: true) { [self] error in
      if let error {
        completion(error)
        return
      }
      let shouldDispose = withStateLock { () -> Bool in
        if disposed { return false }
        disposed = true
        return true
      }
      guard shouldDispose else {
        completion(nil)
        return
      }
      videoSourcePtr = nil
      previewLock.lock()
      previewPixelBuffer = nil
      let textureId = previewTextureId
      previewTextureId = -1
      previewLock.unlock()
      if textureId >= 0 {
        textureRegistry.unregisterTexture(textureId)
      }
      completion(nil)
    }
  }

  private func completeStart(
    captureID: UInt64,
    owner expectedOwner: SoraScreenCaptureOwner,
    error: Error?
  ) -> Bool {
    var completions: [(Error?) -> Void] = []
    var accepted = false
    let completionError = error
    withStateLock {
      if state == .stopping,
        activeCaptureID == captureID,
        owner == expectedOwner
      {
        // stop が先行した場合は start callback を捨てず、stop の結果と
        // 一緒に確定する。これにより stop failure でも Dart Future が
        // 未完了のまま残らない。
        hasPendingStartResult = true
        pendingStartResult = completionError
        return
      }
      guard state == .starting,
        activeCaptureID == captureID,
        owner == expectedOwner
      else {
        return
      }
      completions = startCompletions
      startCompletions.removeAll()
      if error == nil {
        state = .running
        accepted = true
      } else {
        state = .stopped
        activeCaptureID = nil
        owner = nil
        coordinatorGeneration = nil
      }
    }
    for completion in completions {
      completion(completionError)
    }
    return accepted
  }

  private func completeStop(error: Error?) {
    var startCallbacks: [(Error?) -> Void] = []
    var stopCallbacks: [(Error?) -> Void] = []
    var startCallbackError: Error = SoraScreenCaptureError.startCancelled
    let recorderIsRecording = recorder.isRecording
    withStateLock {
      if let error {
        if hasPendingStartResult {
          startCallbackError = pendingStartResult ?? SoraScreenCaptureError.startCancelled
        }
        // stop が失敗しても recorder が停止済みなら terminal stopped として
        // lease を解放する。収録中なら running に戻して再停止できる状態を
        // 保持するが、start callback は必ず完了させる。
        state = recorderIsRecording ? (stateBeforeStopping ?? .running) : .stopped
        if state == .stopped {
          activeCaptureID = nil
          owner = nil
          coordinatorGeneration = nil
          lastSentPresentationTimestamp = nil
          lastSentUptime = nil
        }
        stateBeforeStopping = nil
        startCallbacks = startCompletions
        startCompletions.removeAll()
        hasPendingStartResult = false
        pendingStartResult = nil
        stopCallbacks = stopCompletions
        stopCompletions.removeAll()
      } else {
        if hasPendingStartResult {
          startCallbackError = pendingStartResult ?? SoraScreenCaptureError.startCancelled
        }
        state = .stopped
        activeCaptureID = nil
        owner = nil
        coordinatorGeneration = nil
        stateBeforeStopping = nil
        lastSentPresentationTimestamp = nil
        lastSentUptime = nil
        startCallbacks = startCompletions
        startCompletions.removeAll()
        hasPendingStartResult = false
        pendingStartResult = nil
        stopCallbacks = stopCompletions
        stopCompletions.removeAll()
      }
    }
    for callback in startCallbacks {
      callback(startCallbackError)
    }
    for callback in stopCallbacks {
      callback(error)
    }
  }

  private func handleSampleBuffer(
    _ sampleBuffer: CMSampleBuffer,
    sampleBufferType: RPSampleBufferType,
    error: Error?,
    owner expectedOwner: SoraScreenCaptureOwner,
    captureID expectedCaptureID: UInt64
  ) {
    if let error {
      guard isCurrentCapture(owner: expectedOwner, captureID: expectedCaptureID) else {
        return
      }
      onRuntimeError?(
        SoraScreenCaptureError.runtimeError(error),
        expectedOwner,
        expectedCaptureID
      )
      return
    }
    guard sampleBufferType == .video else { return }
    guard isCurrentCapture(owner: expectedOwner, captureID: expectedCaptureID) else {
      return
    }

    let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
    guard shouldSendFrame(presentationTimestamp) else { return }
    guard frameSemaphore.wait(timeout: .now()) == .success else { return }

    frameQueue.async { [weak self] in
      guard let self else { return }
      defer { self.frameSemaphore.signal() }
      guard
        self.isCurrentCapture(
          owner: expectedOwner,
          captureID: expectedCaptureID
        )
      else { return }
      self.markFrameSent(presentationTimestamp)
      self.processVideoFrame(
        sampleBuffer,
        presentationTimestamp: presentationTimestamp,
        owner: expectedOwner,
        captureID: expectedCaptureID
      )
    }
  }

  func isCurrentCapture(
    owner expectedOwner: SoraScreenCaptureOwner,
    captureID expectedCaptureID: UInt64
  ) -> Bool {
    withStateLock {
      state == .running
        && !disposed
        && owner == expectedOwner
        && activeCaptureID == expectedCaptureID
    }
  }

  private func shouldSendFrame(_ presentationTimestamp: CMTime) -> Bool {
    withStateLock {
      guard presentationTimestamp.isValid, !presentationTimestamp.isIndefinite,
        let last = lastSentPresentationTimestamp,
        last.isValid, !last.isIndefinite
      else {
        guard let lastSentUptime else { return true }
        return ProcessInfo.processInfo.systemUptime - lastSentUptime
          >= 1.0 / Double(targetFPS)
      }
      let elapsed = CMTimeSubtract(presentationTimestamp, last)
      guard elapsed.isValid, !elapsed.isIndefinite,
        CMTimeCompare(elapsed, .zero) >= 0
      else {
        guard let lastSentUptime else { return true }
        return ProcessInfo.processInfo.systemUptime - lastSentUptime
          >= 1.0 / Double(targetFPS)
      }
      let minimumInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
      return CMTimeCompare(elapsed, minimumInterval) >= 0
    }
  }

  private func markFrameSent(_ presentationTimestamp: CMTime) {
    withStateLock {
      lastSentUptime = ProcessInfo.processInfo.systemUptime
      if presentationTimestamp.isValid && !presentationTimestamp.isIndefinite {
        lastSentPresentationTimestamp = presentationTimestamp
      } else {
        lastSentPresentationTimestamp = nil
      }
    }
  }

  private func processVideoFrame(
    _ sampleBuffer: CMSampleBuffer,
    presentationTimestamp: CMTime,
    owner expectedOwner: SoraScreenCaptureOwner,
    captureID expectedCaptureID: UInt64
  ) {
    guard isCurrentCapture(owner: expectedOwner, captureID: expectedCaptureID) else {
      return
    }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    let width = Int32(CVPixelBufferGetWidth(pixelBuffer))
    let height = Int32(CVPixelBufferGetHeight(pixelBuffer))
    guard width > 0, height > 0,
      let i420Ref = webrtc_I420Buffer_Create(width, height),
      let i420 = webrtc_I420Buffer_refcounted_get(i420Ref)
    else {
      return
    }
    defer { webrtc_I420Buffer_Release(i420) }

    let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lockResult == kCVReturnSuccess else { return }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
    let converted: Bool
    switch pixelFormat {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
      converted = convertNV12(
        pixelBuffer,
        to: i420,
        width: width,
        height: height,
        fullRange: pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
      )
    case kCVPixelFormatType_32BGRA:
      converted = convertBGRA(pixelBuffer, to: i420, width: width, height: height)
    default:
      notifyPixelFormatError(
        .unsupportedPixelFormat(pixelFormat),
        pixelFormat: pixelFormat,
        owner: expectedOwner,
        captureID: expectedCaptureID
      )
      return
    }
    guard converted else {
      notifyPixelFormatError(
        .frameConversionFailed(pixelFormat),
        pixelFormat: pixelFormat,
        owner: expectedOwner,
        captureID: expectedCaptureID
      )
      return
    }

    guard isCurrentCapture(owner: expectedOwner, captureID: expectedCaptureID) else {
      return
    }
    updatePreview(from: i420, width: width, height: height)
    pushFrame(
      i420Ref,
      timestampUs: timestampUs(from: presentationTimestamp),
      owner: expectedOwner,
      captureID: expectedCaptureID
    )
  }

  private func convertNV12(
    _ pixelBuffer: CVPixelBuffer,
    to i420: OpaquePointer,
    width: Int32,
    height: Int32,
    fullRange: Bool
  ) -> Bool {
    guard CVPixelBufferGetPlaneCount(pixelBuffer) >= 2,
      let sourceY = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)?
        .assumingMemoryBound(to: UInt8.self),
      let sourceUV = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)?
        .assumingMemoryBound(to: UInt8.self)
    else {
      return false
    }
    let sourceStrideY = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0))
    let sourceStrideUV = Int32(CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1))
    if fullRange {
      return sora_full_range_nv12_to_i420(
        sourceY,
        sourceStrideY,
        sourceUV,
        sourceStrideUV,
        webrtc_I420Buffer_MutableDataY(i420),
        webrtc_I420Buffer_StrideY(i420),
        webrtc_I420Buffer_MutableDataU(i420),
        webrtc_I420Buffer_StrideU(i420),
        webrtc_I420Buffer_MutableDataV(i420),
        webrtc_I420Buffer_StrideV(i420),
        width,
        height
      ) == 0
    }
    return libyuv_NV12ToI420(
      sourceY,
      sourceStrideY,
      sourceUV,
      sourceStrideUV,
      webrtc_I420Buffer_MutableDataY(i420),
      webrtc_I420Buffer_StrideY(i420),
      webrtc_I420Buffer_MutableDataU(i420),
      webrtc_I420Buffer_StrideU(i420),
      webrtc_I420Buffer_MutableDataV(i420),
      webrtc_I420Buffer_StrideV(i420),
      width,
      height
    ) == 0
  }

  private func convertBGRA(
    _ pixelBuffer: CVPixelBuffer,
    to i420: OpaquePointer,
    width: Int32,
    height: Int32
  ) -> Bool {
    guard
      let source = CVPixelBufferGetBaseAddress(pixelBuffer)?
        .assumingMemoryBound(to: UInt8.self)
    else {
      return false
    }
    return sora_bgra_to_i420(
      source,
      Int32(CVPixelBufferGetBytesPerRow(pixelBuffer)),
      webrtc_I420Buffer_MutableDataY(i420),
      webrtc_I420Buffer_StrideY(i420),
      webrtc_I420Buffer_MutableDataU(i420),
      webrtc_I420Buffer_StrideU(i420),
      webrtc_I420Buffer_MutableDataV(i420),
      webrtc_I420Buffer_StrideV(i420),
      width,
      height
    ) == 0
  }

  private func updatePreview(from i420: OpaquePointer, width: Int32, height: Int32) {
    let options: [String: Any] = [
      kCVPixelBufferMetalCompatibilityKey as String: true,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
    ]
    var buffer: CVPixelBuffer?
    guard
      CVPixelBufferCreate(
        nil,
        Int(width),
        Int(height),
        kCVPixelFormatType_32BGRA,
        options as CFDictionary,
        &buffer
      ) == kCVReturnSuccess, let buffer
    else {
      return
    }

    guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
      return
    }
    var conversionResult: Int32 = -1
    if let destination = CVPixelBufferGetBaseAddress(buffer)?
      .assumingMemoryBound(to: UInt8.self)
    {
      conversionResult = libyuv_ConvertFromI420(
        webrtc_I420Buffer_MutableDataY(i420),
        webrtc_I420Buffer_StrideY(i420),
        webrtc_I420Buffer_MutableDataU(i420),
        webrtc_I420Buffer_StrideU(i420),
        webrtc_I420Buffer_MutableDataV(i420),
        webrtc_I420Buffer_StrideV(i420),
        destination,
        Int32(CVPixelBufferGetBytesPerRow(buffer)),
        width,
        height,
        libyuv_FOURCC_ARGB
      )
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard conversionResult == 0 else { return }

    previewLock.lock()
    previewPixelBuffer = buffer
    let textureId = previewTextureId
    previewLock.unlock()
    DispatchQueue.main.async { [weak self] in
      guard let self, textureId >= 0 else { return }
      self.previewLock.lock()
      let isRegistered = self.previewTextureId == textureId
      self.previewLock.unlock()
      if isRegistered {
        self.textureRegistry.textureFrameAvailable(textureId)
      }
    }
  }

  private func pushFrame(
    _ i420Ref: OpaquePointer,
    timestampUs: Int64,
    owner expectedOwner: SoraScreenCaptureOwner,
    captureID expectedCaptureID: UInt64
  ) {
    guard isCurrentCapture(owner: expectedOwner, captureID: expectedCaptureID) else {
      return
    }
    guard let sourcePtr = videoSourcePtr,
      let frame = sora_video_frame_create(
        i420Ref,
        webrtc_VideoRotation_0,
        timestampUs,
        0
      )
    else {
      return
    }
    defer { webrtc_VideoFrame_unique_delete(frame) }
    guard let source = webrtc_AdaptedVideoTrackSource_refcounted_get(sourcePtr) else {
      return
    }
    webrtc_AdaptedVideoTrackSource_OnFrame(
      source,
      webrtc_VideoFrame_unique_get(frame)
    )
  }

  private func timestampUs(from timestamp: CMTime) -> Int64 {
    if timestamp.isValid && !timestamp.isIndefinite {
      let seconds = CMTimeGetSeconds(timestamp)
      if seconds.isFinite {
        return Int64(seconds * 1_000_000.0)
      }
    }
    return Int64(ProcessInfo.processInfo.systemUptime * 1_000_000.0)
  }

  private func notifyPixelFormatError(
    _ error: SoraScreenCaptureError,
    pixelFormat: OSType,
    owner expectedOwner: SoraScreenCaptureOwner,
    captureID expectedCaptureID: UInt64
  ) {
    let shouldNotify = withStateLock { () -> Bool in
      guard state == .running,
        !disposed,
        owner == expectedOwner,
        activeCaptureID == expectedCaptureID
      else {
        return false
      }
      if lastPixelFormatError?.pixelFormat == pixelFormat,
        lastPixelFormatError?.channelCode == error.channelCode
      {
        return false
      }
      lastPixelFormatError = (pixelFormat, error.channelCode)
      return true
    }
    if shouldNotify {
      onRuntimeError?(error, expectedOwner, expectedCaptureID)
    }
  }

  func copyPreviewPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    previewLock.lock()
    defer { previewLock.unlock() }
    guard let previewPixelBuffer else { return nil }
    return Unmanaged.passRetained(previewPixelBuffer)
  }

  private func withStateLock<T>(_ body: () throws -> T) rethrows -> T {
    stateLock.lock()
    defer { stateLock.unlock() }
    return try body()
  }

  /// MethodChannel と ReplayKit のコールバックを同じ MainActor へ集約します。
  private func performOnMainActor(_ body: @MainActor @escaping () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(body)
      return
    }
    Task { @MainActor in
      body()
    }
  }
}

/// 画面キャプチャのローカルプレビュー用 Texture です。
private final class SoraScreenPreviewTexture: NSObject, FlutterTexture {
  private weak var capturer: SoraScreenCapturer?

  init(capturer: SoraScreenCapturer) {
    self.capturer = capturer
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    capturer?.copyPreviewPixelBuffer()
  }
}
