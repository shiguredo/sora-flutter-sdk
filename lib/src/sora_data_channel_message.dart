import 'dart:typed_data';

/// DataChannel メッセージング用のメッセージ
class SoraDataChannelMessage {
  /// @nodoc
  const SoraDataChannelMessage({required this.label, required this.data});

  /// DataChannel ラベル
  final String label;

  /// メッセージデータ
  final Uint8List data;
}
