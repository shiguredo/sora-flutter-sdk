import FlutterMacOS

/// Flutter プラグインのエントリポイント。
///
/// `register()` で `FlutterMethodChannel` を登録し、
/// 受信したメソッド呼び出しを `SoraFlutterMessageHandler` へ委譲する。
public class SoraSdkPlugin: NSObject, FlutterPlugin {
  private var messageHandler: SoraFlutterMessageHandler?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let textures = registrar.textures
    let channel = FlutterMethodChannel(
      name: "sora_sdk/method",
      binaryMessenger: messenger
    )
    let instance = SoraSdkPlugin()
    instance.messageHandler = SoraFlutterMessageHandler(
      messenger: messenger,
      textureRegistry: textures
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    messageHandler?.handle(call, result: result)
  }
}
