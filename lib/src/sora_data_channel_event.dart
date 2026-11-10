/// DataChannel の open 時に通知する情報です。
class SoraDataChannelEvent {
  /// @nodoc
  const SoraDataChannelEvent({
    required this.label,
    this.direction,
    this.compress,
    this.header,
  });

  /// DataChannel の label です。
  ///
  /// Sora 予約済みの `signaling`、`notify`、`push`、`stats`、`rpc` や、
  /// リアルタイムメッセージング用の `#` 付き label が入ります。
  final String label;

  /// メッセージの方向です。
  ///
  /// `sendrecv`, `sendonly`, `recvonly` のいずれかが入ります。
  final String? direction;

  /// この label のメッセージを圧縮するかどうか。
  final bool? compress;

  /// `offer` の `data_channels` に含まれる header 値です。
  final Object? header;
}
