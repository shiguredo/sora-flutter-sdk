import 'package:meta/meta.dart';

import 'media/sora_media_device_platform.dart' as media_device_platform;

/// 映像入力デバイス (カメラ) の情報です。
@immutable
class VideoInputDevice {
  /// @nodoc
  const VideoInputDevice({required this.deviceId, required this.label});

  /// デバイスを一意に識別する ID。
  final String deviceId;

  /// デバイスの表示名。
  final String label;

  /// このデバイスが対応する映像フォーマットの一覧を返す。
  Future<List<VideoInputFormat>> supportedFormats() {
    return media_device_platform.getVideoInputFormats(deviceId);
  }
}

/// 映像入力デバイスが対応する解像度とフレームレートの組です。
@immutable
class VideoInputFormat {
  /// @nodoc
  const VideoInputFormat({
    required this.width,
    required this.height,
    required this.maxFrameRate,
  });

  /// 映像の幅 (ピクセル)。
  final int width;

  /// 映像の高さ (ピクセル)。
  final int height;

  /// 最大フレームレート (fps)。
  ///
  /// `GetUserMediaOptions.videoFrameRate` と同じ `int` 型である。
  /// プラットフォームが非整数 (29.97 等) を返した場合は四捨五入して整数化する。
  final int maxFrameRate;

  @override
  String toString() => '${width}x$height @${maxFrameRate}fps';
}
