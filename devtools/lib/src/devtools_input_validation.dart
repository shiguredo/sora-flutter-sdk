/// DevTools の接続設定入力を検証する補助関数を提供する。
library;

/// シグナリング URL が WebSocket URL として利用可能か検証する。
String? validateSignalingUrl(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return 'Signaling URL を入力してください';
  }
  final uri = Uri.tryParse(text);
  if (uri == null ||
      (uri.scheme != 'ws' && uri.scheme != 'wss') ||
      uri.host.isEmpty) {
    return 'ws:// または wss:// で始まる URL を入力してください';
  }
  return null;
}

/// Channel ID が空でないか検証する。
String? validateChannelId(String? value) {
  if ((value?.trim() ?? '').isEmpty) {
    return 'Channel ID を入力してください';
  }
  return null;
}

/// カスタム DataChannel label の必須プレフィックスを検証する。
///
/// label が空の場合は DataChannel 自体を設定しないため正常とする。
String? validateDataChannelLabel(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  if (!text.startsWith('#')) {
    return 'カスタム label は # で始めてください';
  }
  return null;
}

/// WebRTC の `maxPacketLifeTime` に渡せるミリ秒値か検証する。
String? validateMaxPacketLifeTime(String? value) {
  final text = value?.trim() ?? '';
  final parsed = int.tryParse(text);
  if (parsed == null) {
    return '0 から 65535 の整数を入力してください';
  }
  // RTCDataChannelInit の maxPacketLifeTime は unsigned short である。
  if (parsed < 0 || parsed > 65535) {
    return '0 から 65535 の整数を入力してください';
  }
  return null;
}
