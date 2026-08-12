import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // ダミーウィンドウ E2E テスト用の MethodChannel 名
  private static let dummyWindowChannelName = "e2e_test_app/dummy_window"
  // ダミーウィンドウのタイトル。Dart 側テストのタイトルと一致させる。
  private static let dummyWindowTitle = "Sora E2E Dummy Window"

  private var dummyWindow: NSWindow?
  private var dummyWindowTimer: Timer?
  private var dummyHue: CGFloat = 0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    registerDummyWindowChannel(with: flutterViewController)

    super.awakeFromNib()
  }

  // MARK: - ダミーウィンドウ

  /// ダミーウィンドウ E2E テスト用の MethodChannel を登録する。
  private func registerDummyWindowChannel(with flutterViewController: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: Self.dummyWindowChannelName,
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(
            code: "unavailable",
            message: "MainFlutterWindow is unavailable",
            details: nil))
        return
      }
      switch call.method {
      case "show":
        self.showDummyWindow()
        result(nil)
      case "hide":
        self.hideDummyWindow()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 色相が回転するダミーウィンドウを表示する。
  ///
  /// 静止画だと ScreenCaptureKit がフレームを送出しないため、
  /// 30fps で色を変化させて映像が流れ続けるようにする。
  private func showDummyWindow() {
    guard dummyWindow == nil else { return }

    let window = NSWindow(
      contentRect: NSRect(x: 100, y: 100, width: 640, height: 360),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = Self.dummyWindowTitle

    let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    contentView.wantsLayer = true
    contentView.layer?.backgroundColor = NSColor.green.cgColor
    window.contentView = contentView

    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    dummyWindow = window

    dummyHue = 0
    dummyWindowTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
      [weak self] _ in
      guard let self, let view = self.dummyWindow?.contentView else { return }
      self.dummyHue += 0.01
      if self.dummyHue >= 1.0 {
        self.dummyHue -= 1.0
      }
      view.layer?.backgroundColor =
        NSColor(
          hue: self.dummyHue, saturation: 0.8, brightness: 0.9, alpha: 1.0
        ).cgColor
    }
  }

  /// ダミーウィンドウを閉じて破棄する。
  private func hideDummyWindow() {
    dummyWindowTimer?.invalidate()
    dummyWindowTimer = nil
    dummyWindow?.close()
    dummyWindow = nil
  }
}
