/// DataChannel メッセージ送信可否と案内文を決定する補助関数を提供する。
library;

/// 現在の接続設定で DataChannel メッセージを送信可能か判定する。
bool canSendDataChannelMessage({
  required bool isConnected,
  required bool hasConnection,
  required bool dataChannelsEnabled,
  required bool hasDataChannelConfig,
  required String? label,
  required Set<String> openedDataChannelLabels,
}) {
  return isConnected &&
      hasConnection &&
      dataChannelsEnabled &&
      hasDataChannelConfig &&
      label != null &&
      openedDataChannelLabels.contains(label);
}

/// DataChannel メッセージを送信できない理由を、次の操作として返す。
String? buildDataChannelMessageSendGuidance({
  required bool isConnected,
  required bool dataChannelsEnabled,
  required bool hasDataChannelConfig,
  required String? label,
  required Set<String> openedDataChannelLabels,
}) {
  if (!isConnected) {
    return 'Connect タブで接続するとメッセージを送信できます。';
  }
  if (!dataChannelsEnabled) {
    return 'Connect タブで dataChannels を有効にし、label を設定してから再接続してください。';
  }
  if (!hasDataChannelConfig) {
    return 'Connect タブの dataChannels で # から始まる label を設定し、再接続してください。';
  }
  if (label == null || !openedDataChannelLabels.contains(label)) {
    return 'DataChannel が open するまでメッセージを送信できません。';
  }
  return null;
}
