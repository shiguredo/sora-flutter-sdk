/// シグナリングイベント
class SoraSignalingEvent {
  /// @nodoc
  const SoraSignalingEvent({
    required this.transportType,
    required this.direction,
    this.data,
  });

  /// トランスポート種別 ("websocket" または "datachannel")
  final String transportType;

  /// 送受信方向 ("sent" または "received")
  final String direction;

  /// メッセージ内容
  final Map<String, Object?>? data;
}
