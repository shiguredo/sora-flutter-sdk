/// デバッグ用 `log` callback 構造化ログ
class SoraLogEvent {
  /// @nodoc
  const SoraLogEvent({required this.title, this.message});

  /// ログタイトル
  final String title;

  /// ログ本文
  final Object? message;
}
