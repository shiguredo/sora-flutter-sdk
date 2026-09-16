import 'package:meta/meta.dart';

/// 音声入力デバイス (マイク) の情報です。
@immutable
class AudioInputDevice {
  /// @nodoc
  const AudioInputDevice({
    required this.deviceId,
    required this.label,
    this.type,
  });

  /// 音声デバイスの識別子です。
  final String deviceId;

  /// 音声デバイスの表示名です。
  final String label;

  /// 音声デバイスの種別です。
  ///
  /// 現在は Android のみ対応しており、未対応の platform では `null` になります。
  ///
  /// Android では `AudioDeviceInfo.getType()` の値を格納します。
  /// 詳しくは https://developer.android.com/reference/android/media/AudioDeviceInfo#getType() をご確認ください。
  final int? type;
}

/// 音声出力デバイス (スピーカー) の情報です。
@immutable
class AudioOutputDevice {
  /// @nodoc
  const AudioOutputDevice({
    required this.deviceId,
    required this.label,
    this.type,
  });

  /// 音声デバイスの識別子です。
  final String deviceId;

  /// 音声デバイスの表示名です。
  final String label;

  /// 音声デバイスの種別です。
  ///
  /// 現在は Android のみ対応しており、未対応の platform では `null` になります。
  ///
  /// Android では `AudioDeviceInfo.getType()` の値を格納します。
  /// 詳しくは https://developer.android.com/reference/android/media/AudioDeviceInfo#getType() をご確認ください。
  final int? type;
}
