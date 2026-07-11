/// DataChannel メッセージ送信可否と案内文を決定する補助関数を提供する。
library;

/// 現在の接続設定で DataChannel メッセージを送信可能か判定する。
bool canSendDataChannelMessage({
  required bool isConnected,
  required bool hasConnection,
  required bool dataChannelSignalingEnabled,
  required bool dataChannelsEnabled,
  required bool hasDataChannelConfig,
}) {
  return isConnected &&
      hasConnection &&
      dataChannelSignalingEnabled &&
      dataChannelsEnabled &&
      hasDataChannelConfig;
}

/// DataChannel メッセージを送信できない理由を、次の操作として返す。
String? buildDataChannelMessageSendGuidance({
  required bool isConnected,
  required bool dataChannelSignalingEnabled,
  required bool dataChannelsEnabled,
  required bool hasDataChannelConfig,
}) {
  if (!isConnected) {
    return 'Connect タブで接続するとメッセージを送信できます。';
  }
  if (!dataChannelSignalingEnabled && !dataChannelsEnabled) {
    return 'Connect タブで DataChannel Signaling を有効にし、dataChannels に label を設定してから再接続してください。';
  }
  if (!dataChannelSignalingEnabled) {
    return 'Connect タブで DataChannel Signaling を有効にしてから再接続してください。';
  }
  if (!dataChannelsEnabled) {
    return 'Connect タブで dataChannels を有効にし、label を設定してから再接続してください。';
  }
  if (!hasDataChannelConfig) {
    return 'Connect タブの dataChannels で # から始まる label を設定し、再接続してください。';
  }
  return null;
}
