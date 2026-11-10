/// Sora 接続ロール種類
enum SoraRole {
  /// 送信のみ
  sendonly('sendonly'),

  /// 受信のみ
  recvonly('recvonly'),

  /// 送受信
  sendrecv('sendrecv');

  const SoraRole(this.value);

  /// connect メッセージで使用する文字列値
  final String value;
}
