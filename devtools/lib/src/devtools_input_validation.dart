/// DevTools の接続設定入力を検証する補助関数を提供する。
library;

import 'dart:convert';

/// 入力欄に改行区切りで指定されたシグナリング URL を取り出す。
///
/// 空行は、設定を貼り付けた際にも扱いやすいよう無視する。
List<String> parseSignalingUrls(String? value) {
  return (value ?? '')
      .split(RegExp(r'\r?\n'))
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList(growable: false);
}

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

/// 改行区切りで指定されたすべてのシグナリング URL を検証する。
String? validateSignalingUrls(String? value) {
  final urls = parseSignalingUrls(value);
  if (urls.isEmpty) {
    return 'Signaling URL を入力してください';
  }
  for (final url in urls) {
    final error = validateSignalingUrl(url);
    if (error != null) {
      return error;
    }
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

/// 空欄を許可する JSON 値を検証する。
///
/// metadata 系は JSON の型に制限を設けないため、object / array / scalar を
/// 受け付ける。
///
/// JSON の `null` は SDK では未指定と区別できず connect メッセージから省略
/// されるため、入力値としては受け付けない。
String? validateOptionalJsonValue(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  try {
    if (jsonDecode(text) == null) {
      return 'JSON null は指定できません';
    }
  } on FormatException {
    return '有効な JSON を入力してください';
  }
  return null;
}

/// 空欄を許可する JSON object を検証する。
String? validateOptionalJsonObject(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  try {
    if (jsonDecode(text) is! Map) {
      return 'JSON object を入力してください';
    }
  } on FormatException {
    return '有効な JSON を入力してください';
  }
  return null;
}

/// 空欄を許可する JSON object の配列を検証する。
String? validateOptionalJsonObjectArray(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is! List || decoded.any((item) => item is! Map)) {
      return 'JSON object の配列を入力してください';
    }
  } on FormatException {
    return '有効な JSON を入力してください';
  }
  return null;
}

/// 空欄を許可する 0 以上の整数を検証する。
String? validateOptionalNonNegativeInt(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 0) {
    return '0 以上の整数を入力してください';
  }
  return null;
}

/// 空欄を許可する音声ビットレート (6 〜 510 kbps) を検証する。
String? validateOptionalAudioBitRate(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) {
    return null;
  }
  final parsed = int.tryParse(text);
  if (parsed == null || parsed < 6 || parsed > 510) {
    return '6 から 510 kbps の整数を入力してください';
  }
  return null;
}

/// 空欄を null として JSON 値を復元する。
Object? parseOptionalJsonValue(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : jsonDecode(text);
}

/// 空欄を null として JSON object を SDK の設定型へ復元する。
Map<String, Object?>? parseOptionalJsonObject(String? value) {
  final decoded = parseOptionalJsonValue(value);
  if (decoded == null) {
    return null;
  }
  return Map<String, Object?>.from(decoded as Map);
}

/// 空欄を null として JSON object の配列を SDK の設定型へ復元する。
List<Map<String, Object?>>? parseOptionalJsonObjectArray(String? value) {
  final decoded = parseOptionalJsonValue(value);
  if (decoded == null) {
    return null;
  }
  return (decoded as List)
      .map((item) => Map<String, Object?>.from(item as Map))
      .toList(growable: false);
}
