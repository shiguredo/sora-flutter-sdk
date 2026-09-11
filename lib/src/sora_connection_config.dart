import 'sora_codec_type.dart';
import 'sora_role.dart';
import 'sora_signaling_option.dart';
import 'sora_timeout_options.dart';
import 'sora_validator.dart';

/// Sora 接続設定のデータクラス
///
/// フィールドの検証は [SoraConnectionConfig.toMap] の実行時に行う。
/// `const` コンストラクタを維持するため、コンストラクタでは検証しない。
/// `signalingUrls` / `channelId` の空検証と数値の範囲検証は `toMap()` で行い、
/// 各 URL 要素の形式検証は接続開始時に行う。`toMap()` が投げる例外は
/// [SoraConnectionConfig.toMap] を参照すること。
class SoraConnectionConfig {
  /// @nodoc
  const SoraConnectionConfig({
    required this.signalingUrls,
    required this.channelId,
    required this.role,
    this.video,
    this.audio,
    this.audioStreamingLanguageCode,
    this.useAudioDevice = true,
    this.clientId,
    this.bundleId,
    this.metadata,
    this.signalingNotifyMetadata,
    this.dataChannelSignaling,
    this.ignoreDisconnectWebSocket,
    this.spotlight,
    this.spotlightFocusRid,
    this.spotlightUnfocusRid,
    this.simulcast,
    this.simulcastRequestRid,
    this.audioCodecType,
    this.videoCodecType,
    this.audioBitRate,
    this.videoBitRate,
    this.videoVp9Params,
    this.videoH264Params,
    this.videoH265Params,
    this.videoAv1Params,
    this.audioOpusParamsChannels,
    this.audioOpusParamsMaxplaybackrate,
    this.audioOpusParamsMinptime,
    this.audioOpusParamsPtime,
    this.audioOpusParamsStereo,
    this.audioOpusParamsSpropStereo,
    this.audioOpusParamsUseinbandfec,
    this.audioOpusParamsUsedtx,
    this.dataChannels,
    this.forwardingFilters,
    this.timeoutOptions = const SoraTimeoutOptions(),
  });

  /// シグナリングサーバの WebSocket URL リスト。
  /// 複数指定でフェイルオーバーに利用する。
  final List<String> signalingUrls;

  /// 接続先のチャネル ID。
  final String channelId;

  /// 送受信のロール。
  final SoraRole role;

  /// 映像の有効 (null の場合は connect メッセージに video キーを含めない)。
  final bool? video;

  /// 音声の有効 (null の場合は connect メッセージに audio キーを含めない)。
  final bool? audio;

  /// 音声ストリーミングの言語コード。
  ///
  /// 指定すると connect メッセージの `audio_streaming_language_code` に設定する。
  /// 未指定の場合はキーを送信しない。
  /// `audio` が `false` の場合は音声が無効なため送信しない。
  ///
  /// Sora は指定された文字列をそのまま言語コードとして扱うため、
  /// SDK 側での形式検証や長さ制限は行わない。
  final String? audioStreamingLanguageCode;

  /// 音声デバイスを利用するかどうか。
  ///
  /// デフォルトは `true`。
  /// `false` にすると一切の音声デバイスを掴まず、`kDummyAudio` ADM を利用する。
  /// 実マイクを使わずにカスタム音声ソース (BeepAudioSource 等) を使いたい場合に指定する。
  ///
  /// メディア API を接続前に呼び出す場合は、先に
  /// `MediaDevices.setUseAudioDevice()` で指定すること。
  /// 共有 `PeerConnectionFactory` 生成後に設定を変更することはできない。
  ///
  /// Android では `createAndroidAudioDeviceModule` を使用するため、
  /// この設定は無視され、常に実デバイスが使用される。
  final bool useAudioDevice;

  /// クライアント ID。未指定時は Sora サーバが自動割り当てする。
  final String? clientId;

  /// バンドル ID。同一の bundle_id を指定した接続間では、互いの音声・映像・メッセージ・シグナリング通知を受信しなくなる
  final String? bundleId;

  /// 接続メタデータ。Sora サーバへ通知する任意の JSON シリアライズ可能な値。
  final Object? metadata;

  /// signaling notify で通知するメタデータ。
  /// notify メッセージの connection.created に含める任意の JSON シリアライズ可能な値。
  final Object? signalingNotifyMetadata;

  /// DataChannel シグナリングを利用するかのフラグ。
  final bool? dataChannelSignaling;

  /// WebSocket 切断通知を無視する (DataChannel シグナリング切替時など)。
  final bool? ignoreDisconnectWebSocket;

  /// スポットライト機能を利用するかのフラグ。
  final bool? spotlight;

  /// スポットライトでフォーカスする配信者の RID。
  final SpotlightRid? spotlightFocusRid;

  /// スポットライトでフォーカスされていない配信者の RID。
  final SpotlightRid? spotlightUnfocusRid;

  /// サイマルキャストを利用するかのフラグ。
  final bool? simulcast;

  /// サイマルキャスト要求 RID。
  final SimulcastRequestRid? simulcastRequestRid;

  /// 音声コーデック (null の場合はサーバのデフォルト設定に従う)。
  final AudioCodecType? audioCodecType;

  /// 映像コーデック (null の場合はサーバのデフォルト設定に従う)。
  final VideoCodecType? videoCodecType;

  /// 音声の最大ビットレート (6 〜 510 kbps)。
  final int? audioBitRate;

  /// 映像の最大ビットレート (1 〜 50000 kbps)。
  final int? videoBitRate;

  /// VP9 コーデックの追加パラメータ。connect メッセージの video.vp9_params に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final Map<String, Object?>? videoVp9Params;

  /// H.264 コーデックの追加パラメータ。connect メッセージの video.h264_params に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final Map<String, Object?>? videoH264Params;

  /// H.265 コーデックの追加パラメータ。connect メッセージの video.h265_params に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final Map<String, Object?>? videoH265Params;

  /// AV1 コーデックの追加パラメータ。connect メッセージの video.av1_params に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final Map<String, Object?>? videoAv1Params;

  /// Opus の `channels` (1 〜 8)。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final int? audioOpusParamsChannels;

  /// Opus の `maxplaybackrate` (8000 〜 48000 Hz)。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final int? audioOpusParamsMaxplaybackrate;

  /// Opus の `minptime` (3 〜 120 ms)。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final int? audioOpusParamsMinptime;

  /// Opus の `ptime` (ms)。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の仕様に範囲が定義されていないため、SDK 側では範囲検証しない。
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final int? audioOpusParamsPtime;

  /// Opus の `stereo`。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final bool? audioOpusParamsStereo;

  /// Opus の `sprop_stereo`。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final bool? audioOpusParamsSpropStereo;

  /// Opus の `useinbandfec`。connect メッセージの audio.opus_params に対応する。
  ///
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final bool? audioOpusParamsUseinbandfec;

  /// Opus の `usedtx`。connect メッセージの audio.opus_params に対応する。
  ///
  /// 有効にすると録画がおかしくなる。
  /// Sora の実験的機能のため、利用には事前に Sora のサポートへの連絡が必要。
  final bool? audioOpusParamsUsedtx;

  /// カスタム DataChannel 設定のリスト。connect メッセージの data_channels に対応する。
  /// 各要素には `label`、`direction`、`compress` のキーを持つ Map を指定する。
  final List<Map<String, Object?>>? dataChannels;

  /// 転送フィルタ設定のリスト。connect メッセージの forwarding_filters に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final List<Map<String, Object?>>? forwardingFilters;

  /// WebRTC 接続のライフサイクル各段階のタイムアウト設定
  final SoraTimeoutOptions timeoutOptions;

  /// connect メッセージの payload へ変換する。
  ///
  /// `const` コンストラクタを維持するため、フィールドの検証は本メソッドの
  /// 実行時、すなわち接続生成時に行う。
  ///
  /// 例外:
  ///
  /// - [signalingUrls] が空の場合は [ArgumentError]。
  /// - [channelId] が空の場合は [ArgumentError]。
  /// - [audioBitRate] が 6 〜 510 の範囲外の場合は [RangeError]。
  /// - [videoBitRate] が 1 〜 50000 の範囲外の場合は [RangeError]。
  /// - [audioOpusParamsChannels] が 1 〜 8 の範囲外の場合は [RangeError]。
  /// - [audioOpusParamsMaxplaybackrate] が 8000 〜 48000 の範囲外の場合は
  ///   [RangeError]。
  /// - [audioOpusParamsMinptime] が 3 〜 120 の範囲外の場合は [RangeError]。
  Map<String, Object?> toMap() {
    // const コンストラクターを維持するため、接続設定の利用時に検証する。
    validateSignalingUrls(signalingUrls);
    validateChannelId(channelId);
    validateAudioBitRate(audioBitRate);
    validateVideoBitRate(videoBitRate);
    validateAudioOpusParams(
      channels: audioOpusParamsChannels,
      maxplaybackrate: audioOpusParamsMaxplaybackrate,
      minptime: audioOpusParamsMinptime,
    );

    return <String, Object?>{
      'signalingUrls': signalingUrls,
      'channelId': channelId,
      'role': role.value,
      'video': video,
      'audio': audio,
      'audioStreamingLanguageCode': audioStreamingLanguageCode,
      'clientId': clientId,
      'bundleId': bundleId,
      'metadata': metadata,
      'signalingNotifyMetadata': signalingNotifyMetadata,
      'dataChannelSignaling': dataChannelSignaling,
      'ignoreDisconnectWebSocket': ignoreDisconnectWebSocket,
      'spotlight': spotlight,
      'spotlightFocusRid': spotlightFocusRid?.value,
      'spotlightUnfocusRid': spotlightUnfocusRid?.value,
      'simulcast': simulcast,
      'simulcastRequestRid': simulcastRequestRid?.value,
      'audioCodecType': audioCodecType?.value,
      'videoCodecType': videoCodecType?.value,
      'audioBitRate': audioBitRate,
      'videoBitRate': videoBitRate,
      'videoVp9Params': videoVp9Params,
      'videoH264Params': videoH264Params,
      'videoH265Params': videoH265Params,
      'videoAv1Params': videoAv1Params,
      'audioOpusParamsChannels': audioOpusParamsChannels,
      'audioOpusParamsMaxplaybackrate': audioOpusParamsMaxplaybackrate,
      'audioOpusParamsMinptime': audioOpusParamsMinptime,
      'audioOpusParamsPtime': audioOpusParamsPtime,
      'audioOpusParamsStereo': audioOpusParamsStereo,
      'audioOpusParamsSpropStereo': audioOpusParamsSpropStereo,
      'audioOpusParamsUseinbandfec': audioOpusParamsUseinbandfec,
      'audioOpusParamsUsedtx': audioOpusParamsUsedtx,
      'dataChannels': dataChannels,
      'forwardingFilters': forwardingFilters,
      'useAudioDevice': useAudioDevice,
    };
  }
}
