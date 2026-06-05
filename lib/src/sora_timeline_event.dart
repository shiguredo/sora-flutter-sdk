/// timeline ログの種別
enum SoraTimelineEventLogType {
  /// WebSocket イベント
  websocket('websocket'),

  /// DataChannel イベント
  datachannel('datachannel'),

  /// PeerConnection イベント
  peerconnection('peerconnection'),

  /// Sora 固有イベント
  sora('sora');

  /// @nodoc
  const SoraTimelineEventLogType(this.value);

  /// ログ出力で使用する文字列値。
  final String value;
}

/// JavaScript SDK の `timeline` callback 相当の構造化イベント
class SoraTimelineEvent {
  /// @nodoc
  const SoraTimelineEvent({
    required this.type,
    required this.logType,
    this.data,
    this.dataChannelId,
    this.dataChannelLabel,
  });

  /// イベント種別
  final String type;

  /// ログの分類
  final SoraTimelineEventLogType logType;

  /// イベント詳細
  final Object? data;

  /// DataChannel ID
  final int? dataChannelId;

  /// DataChannel label
  final String? dataChannelLabel;
}
