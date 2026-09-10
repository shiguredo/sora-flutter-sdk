// ignore_for_file: public_member_api_docs
/// connect メッセージの音声・映像値を構築する内部モジュール。
library;

import 'package:meta/meta.dart';

import 'sora_codec_type.dart';
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
      if (_buildAudioOpusParams(config) case final opusParams?) {
        // opus_params は codec_type: OPUS と併記しないと Sora が
        // invalid_audio_format で接続を拒否する。
        audio['codec_type'] = AudioCodecType.opus.value;
        audio['opus_params'] = opusParams;
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
  if (_buildAudioOpusParams(config) case final opusParams?) {
    // opus_params は codec_type: OPUS と併記しないと Sora が
    // invalid_audio_format で接続を拒否する。
    audio['codec_type'] = AudioCodecType.opus.value;
    audio['opus_params'] = opusParams;
  }

  if (audio.isEmpty) {
    return true;
  }
  return audio;
}

/// connect メッセージ用の `audio.opus_params` を構築する。
///
/// 指定された項目だけを含む Map を返す。全項目が未指定の場合は `null` を返し、
/// connect メッセージへ `opus_params` を含めない。
Map<String, Object?>? _buildAudioOpusParams(SoraConnectionConfig config) {
  final opusParams = <String, Object?>{};
  if (config.audioOpusParamsChannels case final value?) {
    opusParams['channels'] = value;
  }
  if (config.audioOpusParamsMaxplaybackrate case final value?) {
    opusParams['maxplaybackrate'] = value;
  }
  if (config.audioOpusParamsMinptime case final value?) {
    opusParams['minptime'] = value;
  }
  if (config.audioOpusParamsPtime case final value?) {
    opusParams['ptime'] = value;
  }
  if (config.audioOpusParamsStereo case final value?) {
    opusParams['stereo'] = value;
  }
  if (config.audioOpusParamsSpropStereo case final value?) {
    opusParams['sprop_stereo'] = value;
  }
  if (config.audioOpusParamsUseinbandfec case final value?) {
    opusParams['useinbandfec'] = value;
  }
  if (config.audioOpusParamsUsedtx case final value?) {
    opusParams['usedtx'] = value;
  }

  if (opusParams.isEmpty) {
    return null;
  }
  return opusParams;
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
