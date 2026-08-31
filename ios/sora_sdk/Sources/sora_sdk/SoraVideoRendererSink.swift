import Flutter

@_implementationOnly import CWebrtc

// テクスチャ更新通知用ラッパー
// C ブリッジのフレームコールバックから textureFrameAvailable を呼ぶために使う
private class TextureNotifier {
  let registry: FlutterTextureRegistry
  var textureId: Int64

  init(registry: FlutterTextureRegistry, textureId: Int64) {
    self.registry = registry
    self.textureId = textureId
  }

  func notify() {
    if textureId >= 0 {
      registry.textureFrameAvailable(textureId)
    }
  }
}

// FlutterTexture プロトコル実装
// C ブリッジの AppleRenderingSink から CVPixelBuffer を取得する
class SoraRemoteRendererTexture: NSObject, FlutterTexture {
  private var sinkPtr: OpaquePointer?

  init(sinkPtr: OpaquePointer) {
    self.sinkPtr = sinkPtr
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    guard let sink = sinkPtr else { return nil }
    guard let rawPtr = apple_rendering_sink_copy_pixel_buffer(sink) else {
      return nil
    }
    return Unmanaged<CVPixelBuffer>.fromOpaque(rawPtr)
  }

  func detach() {
    sinkPtr = nil
  }
}

// リモートビデオレンダリングを管理する
class RemoteVideoRenderer {
  private let textureRegistry: FlutterTextureRegistry
  private var texture: SoraRemoteRendererTexture?
  private var notifier: TextureNotifier?
  private var notifierRef: Unmanaged<TextureNotifier>?
  private(set) var sinkPtr: OpaquePointer?
  // iOS では textureId が 0 から始まるため、未登録を -1 で表す
  private(set) var textureId: Int64 = -1

  init?(textureRegistry: FlutterTextureRegistry) {
    self.textureRegistry = textureRegistry

    // C ブリッジでレンダリングシンクを作成する
    sinkPtr = apple_rendering_sink_create()
    guard let sinkPtr = sinkPtr else { return nil }

    // FlutterTexture を登録する
    let tex = SoraRemoteRendererTexture(sinkPtr: sinkPtr)
    texture = tex
    textureId = textureRegistry.register(tex)

    // フレーム通知コールバックを設定する
    let n = TextureNotifier(registry: textureRegistry, textureId: textureId)
    notifier = n
    let ref = Unmanaged.passRetained(n)
    notifierRef = ref

    apple_rendering_sink_set_frame_callback(
      sinkPtr,
      { ctx in
        guard let ctx = ctx else { return }
        Unmanaged<TextureNotifier>.fromOpaque(ctx)
          .takeUnretainedValue().notify()
      },
      ref.toOpaque()
    )
  }

  /// レンダリングシンクのアドレスを返す (dart:ffi に渡す用)
  var sinkAddress: Int {
    guard let ptr = sinkPtr else { return 0 }
    return Int(bitPattern: ptr)
  }

  /// VideoSinkInterface のアドレスを返す (dart:ffi でシンクアタッチ用)
  var videoSinkAddress: Int {
    guard let ptr = sinkPtr else { return 0 }
    guard let sinkRawPtr = apple_rendering_sink_get_sink_ptr(ptr) else { return 0 }
    return Int(bitPattern: sinkRawPtr)
  }

  /// レンダラを停止しリソースを解放する。
  /// shutdown 本体を main queue 上で直列実行し、C 層で enqueue 完了待ちした
  /// callback より後に notifier 解放処理を積むことで UAF を防ぐ。
  func shutdown() {
    if Thread.isMainThread {
      _shutdownBody()
    } else {
      DispatchQueue.main.sync { _shutdownBody() }
    }
  }

  private func _shutdownBody() {
    // テクスチャ通知を停止する
    notifier?.textureId = -1

    // テクスチャを解除する
    texture?.detach()
    if textureId >= 0 {
      textureRegistry.unregisterTexture(textureId)
      textureId = -1
    }

    // レンダリングシンクを破棄する
    if let sink = sinkPtr {
      apple_rendering_sink_delete(sink)
      sinkPtr = nil
    }

    // TextureNotifier は即時解放しない。
    // C 層の delete は worker 側 callback の main queue への enqueue 完了までしか待たないため、
    // release 自体を main queue の次ターンへ遅らせて enqueue 済み cb(ctx) を先に流す。
    if let ref = notifierRef {
      notifierRef = nil
      DispatchQueue.main.async {
        ref.release()
      }
    }
    notifier = nil
    texture = nil
  }

  deinit {
    shutdown()
  }
}
