import 'package:meta/meta.dart';

/// macOS で共有可能なウィンドウの情報です。
@immutable
class WindowCaptureSource {
  /// @nodoc
  const WindowCaptureSource({
    required this.id,
    required this.title,
    required this.applicationName,
  });

  /// ウィンドウを一意に識別する ID。
  ///
  /// macOS の `SCWindow.windowID` を文字列化した値です。
  /// ウィンドウを閉じて開き直すと ID は変わるため、
  /// 同一セッション内での識別に利用してください。
  final String id;

  /// ウィンドウのタイトル。
  final String title;

  /// ウィンドウを所有するアプリケーションの名前。
  final String applicationName;
}

/// macOS のウィンドウキャプチャの設定です。
@immutable
class WindowCaptureOptions {
  /// @nodoc
  const WindowCaptureOptions({
    this.width,
    this.height,
    this.frameRate,
    this.showsCursor = true,
  });

  /// キャプチャ解像度の幅。
  ///
  /// 省略時はウィンドウの現在のサイズを使います。
  final int? width;

  /// キャプチャ解像度の高さ。
  ///
  /// 省略時はウィンドウの現在のサイズを使います。
  final int? height;

  /// キャプチャのフレームレート。
  ///
  /// `SCStreamConfiguration.frameRate` へ渡す上限値であり、
  /// 実際の送出レートはウィンドウの更新頻度やシステム負荷に依存します。
  /// 省略時は 30 を使います。0 以下の値は指定できず、30 として扱います。
  final int? frameRate;

  /// カーソルをキャプチャ映像に含めるかどうか。
  ///
  /// デフォルトは true です。
  final bool showsCursor;
}
