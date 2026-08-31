// ignore_for_file: public_member_api_docs
/// connect メッセージの音声・映像値を構築する内部モジュール。
library;

import 'package:meta/meta.dart';

import 'sora_connection_config.dart';

/// connect メッセージ用の `audio` 値を構築する。
///
/// `audio` が `false` の場合は `false` を返し、ビットレートを含めない。
@internal
Object? buildOptionalAudioConnectValue(SoraConnectionConfig config) {
  switch (config.audio) {
    case false:
      return false;
    case true:
      return _audioConnectValueWhenExplicitlyOn(config);
    case null:
      final audio = <String, Object?>{};
      if (config.audioCodecType case final value?) {
        audio['codec_type'] = value.value;
      }
      if (config.audioBitRate case final value?) {
        audio['bit_rate'] = value;
      }
      if (audio.isEmpty) {
        return null;
      }
      return audio;
  }
}

/// `audio: true` の connect メッセージ値を構築する。
Object _audioConnectValueWhenExplicitlyOn(SoraConnectionConfig config) {
  final audio = <String, Object?>{};
  if (config.audioCodecType case final value?) {
    audio['codec_type'] = value.value;
  }
  if (config.audioBitRate case final value?) {
    audio['bit_rate'] = value;
  }

  if (audio.isEmpty) {
    return true;
  }
  return audio;
}

/// connect メッセージ用の `video` 値を構築する。
///
/// `video` が `false` の場合は `false` を返し、ビットレートを含めない。
@internal
Object? buildOptionalVideoConnectValue(SoraConnectionConfig config) {
  switch (config.video) {
    case false:
      return false;
    case true:
      return _videoConnectValueWhenExplicitlyOn(config);
    case null:
      final video = <String, Object?>{};
      if (config.videoCodecType case final value?) {
        video['codec_type'] = value.value;
      }
      if (config.videoBitRate case final value?) {
        video['bit_rate'] = value;
      }
      if (config.videoVp9Params case final value?) {
        video['vp9_params'] = value;
      }
      if (config.videoH264Params case final value?) {
        video['h264_params'] = value;
      }
      if (config.videoH265Params case final value?) {
        video['h265_params'] = value;
      }
      if (config.videoAv1Params case final value?) {
        video['av1_params'] = value;
      }
      if (video.isEmpty) {
        return null;
      }
      return video;
  }
}

/// `video: true` の connect メッセージ値を構築する。
Object _videoConnectValueWhenExplicitlyOn(SoraConnectionConfig config) {
  final video = <String, Object?>{};
  if (config.videoCodecType case final value?) {
    video['codec_type'] = value.value;
  }
  if (config.videoBitRate case final value?) {
    video['bit_rate'] = value;
  }
  if (config.videoVp9Params case final value?) {
    video['vp9_params'] = value;
  }
  if (config.videoH264Params case final value?) {
    video['h264_params'] = value;
  }
  if (config.videoH265Params case final value?) {
    video['h265_params'] = value;
  }
  if (config.videoAv1Params case final value?) {
    video['av1_params'] = value;
  }

  if (video.isEmpty) {
    return true;
  }
  return video;
}
