/// 利用できる音声コーデックを示します。
enum AudioCodecType {
  /// OPUS
  opus('OPUS');

  const AudioCodecType(this.value);

  /// connect メッセージで使用する文字列値。
  final String value;

  /// 文字列値から [AudioCodecType] を復元する。不明な値は null を返す。
  static AudioCodecType? fromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final codec in values) {
      if (codec.value == value) {
        return codec;
      }
    }
    return null;
  }
}

/// 利用できる映像コーデックを示します。
enum VideoCodecType {
  /// VP8
  vp8('VP8'),

  /// VP9
  vp9('VP9'),

  /// AV1
  av1('AV1'),

  /// H.264
  h264('H264'),

  /// H.265
  h265('H265');

  const VideoCodecType(this.value);

  /// connect メッセージで使用する文字列値。
  final String value;

  /// 文字列値から [VideoCodecType] を復元する。不明な値は null を返す。
  static VideoCodecType? fromValue(String? value) {
    if (value == null) {
      return null;
    }
    for (final codec in values) {
      if (codec.value == value) {
        return codec;
      }
    }
    return null;
  }
}
