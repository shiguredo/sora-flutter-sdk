import 'sora_codec_type.dart';
import 'sora_role.dart';
import 'sora_signaling_option.dart';
import 'sora_timeout_options.dart';

/// Sora 接続設定のデータクラス
class SoraConnectionConfig {
  /// @nodoc
  const SoraConnectionConfig({
    required this.signalingUrls,
    required this.channelId,
    required this.role,
    this.video,
    this.audio,
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

  /// 音声ビットレート (bps)。
  final int? audioBitRate;

  /// 映像ビットレート (bps)。
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

  /// カスタム DataChannel 設定のリスト。connect メッセージの data_channels に対応する。
  /// 各要素には `label`、`direction`、`compress` のキーを持つ Map を指定する。
  final List<Map<String, Object?>>? dataChannels;

  /// 転送フィルタ設定のリスト。connect メッセージの forwarding_filters に対応する。
  /// Map の有効キーは Sora の connect メッセージ仕様に従う。
  final List<Map<String, Object?>>? forwardingFilters;

  /// WebRTC 接続のライフサイクル各段階のタイムアウト設定
  final SoraTimeoutOptions timeoutOptions;

  /// connect メッセージの payload へ変換する。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'signalingUrls': signalingUrls,
      'channelId': channelId,
      'role': role.value,
      'video': video,
      'audio': audio,
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
      'dataChannels': dataChannels,
      'forwardingFilters': forwardingFilters,
      'useAudioDevice': useAudioDevice,
    };
  }
}
