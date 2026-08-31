import CWebrtc
import Foundation

/// `sora_audio_session_initialize_input_async` のコールバックへ渡すコンテキスト。
///
/// controller と初期化開始時の世代を保持し、コールバック到着時に
/// 古い世代の結果を破棄できるようにする。
private final class AudioInitUserData {
  let controller: SoraAudioSessionController
  let generation: Int

  init(controller: SoraAudioSessionController, generation: Int) {
    self.controller = controller
    self.generation = generation
  }
}

/// C 層からの音声入力初期化完了コールバック。
///
/// `Unmanaged` 経由で `AudioInitUserData` を復元し、
/// controller と世代を `handleInitializeInputResult` へ伝達する。
private func soraAudioSessionInitializeInputCallback(
  result: Int32,
  userData: UnsafeMutableRawPointer?
) {
  guard let userData = userData else {
    return
  }
  let context = Unmanaged<AudioInitUserData>
    .fromOpaque(userData)
    .takeRetainedValue()
  // takeRetainedValue() は passRetained() で作られた +1 を消費する。
  // このコールバックは initializeInput の完了ハンドラが
  // exactly-once で呼ばれる前提に依存している。
  // 0 回だと +1 が回収されずリークし、2 回以上だと過剰 release でクラッシュする。
  context.controller.handleInitializeInputResult(
    result: result, generation: context.generation)
}

/// 接続設定から必要なメディア要件（カメラ・マイク）を抽出する。
///
/// `fromConfig()` で `role` / `video` / `audio` を評価し、
/// 送信ロールでない場合は全て不要とする。
struct SoraMediaRequirements {
  let needsCamera: Bool
  let needsMicrophone: Bool

  static func fromConfig(_ config: [String: Any]) -> SoraMediaRequirements {
    let role = config["role"] as? String
    let isSendingRole = role == "sendonly" || role == "sendrecv"

    if !isSendingRole {
      return SoraMediaRequirements(needsCamera: false, needsMicrophone: false)
    }

    return SoraMediaRequirements(
      needsCamera: soraConfigBoolValue(config["video"], defaultValue: true),
      needsMicrophone: soraConfigBoolValue(config["audio"], defaultValue: true)
    )
  }
}

/// iOS の `AVAudioSession` ライフサイクルを管理するシングルトン。
///
/// 参照カウント (`activeClientCount`) でセッションの取得・解放を制御し、
/// 複数クライアントが同時に存在する場合も最後のクライアントが解放するまで
/// セッションを維持する。音声入力初期化は C 層経由で非同期実行する。
final class SoraAudioSessionController {
  static let shared = SoraAudioSessionController()

  private let queue = DispatchQueue(label: "jp.shiguredo.sora_sdk.audio_session")
  private var activeClientCount: Int = 0
  private var inputInitialized: Bool = false
  private var inputInitializing: Bool = false

  /// `acquire()` が新規初期化を開始するたびにインクリメントする世代カウンタ。
  /// `handleInitializeInputResult` で世代一致を確認し、
  /// 古い C コールバックの結果を破棄するために使う。
  private var acquireGeneration: Int = 0

  /// 音声入力初期化の完了を待つコールバック群。
  private var pendingInputResults: [(Bool) -> Void] = []

  /// 世代別のエラー通知コールバック。
  /// 初期化失敗時に該当世代の登録済みクライアントだけへ通知する。
  private var generationErrorCallbacks: [Int: [(Int32) -> Void]] = [:]

  /// 完了済み世代の集合。`addErrorCallback` が完了済み世代への
  /// 登録を拒否するために使う。
  private var completedGenerations: Set<Int> = []

  /// 各世代の初期化失敗結果。
  /// コールバック登録前に初期化が失敗した場合、遅延登録された
  /// コールバックへこの値を即時配送する。
  private var generationErrorResult: [Int: Int32] = [:]

  /// 現在進行中または最後に完了した初期化の世代番号。
  /// `acquire()` 完了後に呼び出し元が `addErrorCallback(generation:_:)`
  /// でエラーハンドラを登録するために公開する。
  var currentGeneration: Int {
    queue.sync { acquireGeneration }
  }

  private init() {}

  func acquire(
    prefersVideoMode: Bool,
    completion: @escaping (Error?) -> Void
  ) {
    queue.async {
      do {
        try self.configureSession(prefersVideoMode: prefersVideoMode)
        self.acquireAfterConfiguration(completion: completion)
      } catch {
        DispatchQueue.main.async {
          completion(error)
        }
      }
    }
  }

  func release() {
    queue.async {
      guard self.activeClientCount > 0 else {
        return
      }
      self.activeClientCount -= 1
      guard self.activeClientCount == 0 else {
        return
      }

      let result = sora_audio_session_deactivate()
      if result != sora_audio_session_error_none {
        NSLog("Failed to deactivate audio session: result=%d", result)
      }
      self.inputInitialized = false
      self.inputInitializing = false
    }
  }

  /// 音声入力初期化の完了を待つ。
  ///
  /// `inputInitialized` が既に `true` なら即座に `completion(true)` を返す。
  /// 初期化が進行中なら保留し、完了時に `completion(_)` を呼ぶ。
  /// 初期化が未開始の場合は `completion(false)` を返す。
  func awaitInputInitialized(completion: @escaping (Bool) -> Void) {
    queue.async {
      if self.inputInitialized {
        DispatchQueue.main.async { completion(true) }
        return
      }
      guard self.inputInitializing else {
        DispatchQueue.main.async { completion(false) }
        return
      }
      self.pendingInputResults.append(completion)
    }
  }

  /// 指定された世代の初期化失敗時に呼ばれるエラーコールバックを登録する。
  ///
  /// 世代が進行中の初期化と一致しなければ即座に登録解除される。
  /// 主スレッドから呼ぶこと (世代が `queue` で更新されるため、
  /// 登録時点で既に初期化が完了している可能性がある)。
  func addErrorCallback(
    generation: Int,
    callback: @escaping (Int32) -> Void
  ) {
    queue.async {
      if let storedResult = self.generationErrorResult[generation] {
        DispatchQueue.main.async { callback(storedResult) }
        return
      }
      guard generation == self.acquireGeneration,
        !self.completedGenerations.contains(generation)
      else {
        return
      }
      self.generationErrorCallbacks[generation, default: []].append(callback)
    }
  }

  private func configureSession(prefersVideoMode: Bool) throws {
    let result = sora_audio_session_configure(prefersVideoMode ? 1 : 0)
    guard result == sora_audio_session_error_none else {
      throw SoraAudioSessionError(code: result)
    }
  }

  private func acquireAfterConfiguration(
    completion: @escaping (Error?) -> Void
  ) {
    if inputInitialized {
      activeClientCount += 1
      DispatchQueue.main.async {
        completion(nil)
      }
      return
    }

    activeClientCount += 1
    if inputInitializing {
      DispatchQueue.main.async {
        completion(nil)
      }
      return
    }

    DispatchQueue.main.async {
      completion(nil)
    }
    inputInitializing = true
    acquireGeneration += 1
    generationErrorCallbacks.removeAll()
    completedGenerations.removeAll()
    generationErrorResult.removeAll()
    generationErrorCallbacks[acquireGeneration] = []
    let userData = AudioInitUserData(
      controller: self, generation: acquireGeneration)

    sora_audio_session_initialize_input_async(
      soraAudioSessionInitializeInputCallback,
      Unmanaged.passRetained(userData).toOpaque()
    )
    // passRetained() は userData に +1 を付け、apple_bridge.c 側の
    // コールバックで takeRetainedValue() が消費することを前提としている。
    // コールバックが一度も呼ばれないと +1 が永久リークする。
    // 詳細は apple_bridge.c の sora_audio_session_on_initialize_input を参照。
  }

  fileprivate func handleInitializeInputResult(
    result: Int32, generation: Int
  ) {
    queue.async {
      // このコールバックが開始された後に別の acquire() で
      // 新しい初期化が開始されていたら、この古い結果で
      // inputInitialized や inputInitializing を一切書き換えない。
      guard generation == self.acquireGeneration else {
        return
      }

      self.inputInitializing = false

      let success = result == sora_audio_session_error_none
      if success {
        self.inputInitialized = self.activeClientCount > 0
      } else {
        self.inputInitialized = false
        NSLog("Failed to initialize iOS audio input: result=%d", result)
        self.generationErrorResult[generation] = result
        if let callbacks = self.generationErrorCallbacks[generation] {
          self.generationErrorCallbacks.removeValue(forKey: generation)
          for callback in callbacks {
            DispatchQueue.main.async { callback(result) }
          }
        }
      }
      self.completedGenerations.insert(generation)

      let pending = self.pendingInputResults
      self.pendingInputResults.removeAll()
      for completion in pending {
        DispatchQueue.main.async { completion(success) }
      }
    }
  }
}

/// iOS 音声セッション操作のエラー。
///
/// C 層の `sora_audio_session_error_*` コードに対応する `LocalizedError`。
private struct SoraAudioSessionError: LocalizedError {
  let code: Int32

  var errorDescription: String? {
    switch code {
    case sora_audio_session_error_configuration:
      return "Failed to configure iOS audio session."
    case sora_audio_session_error_input_initialization:
      return "Failed to initialize iOS audio input."
    default:
      return "Unknown iOS audio session error."
    }
  }
}
