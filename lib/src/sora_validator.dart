// ignore_for_file: public_member_api_docs
/// Sora SDK 内で利用するバリデーション関数群
///
/// 接続設定やユーザー入力値の妥当性を検証し、不正な値を呼び出し元で fail fast できるようにする
library;

/// シグナリング URL の妥当性を検証して Uri に変換する
///
/// scheme が `ws` または `wss` で host が空でない場合のみ有効とする
Uri? parseSignalingUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return null;
  }
  if ((uri.scheme != 'ws' && uri.scheme != 'wss') || uri.host.isEmpty) {
    return null;
  }
  return uri;
}

/// 音声ビットレートを Sora の指定可能範囲内か検証する。
///
/// `null` は未指定として許可する。
void validateAudioBitRate(int? value) {
  _validateOptionalIntInRange(
    value,
    minimum: 6,
    maximum: 510,
    name: 'audioBitRate',
  );
}

/// 映像ビットレートを Sora の指定可能範囲内か検証する。
///
/// `null` は未指定として許可する。
void validateVideoBitRate(int? value) {
  _validateOptionalIntInRange(
    value,
    minimum: 1,
    maximum: 50000,
    name: 'videoBitRate',
  );
}

/// Opus 詳細パラメーターのうち範囲が定義されている数値を検証する。
///
/// `null` は未指定として許可する。
/// `ptime` は Sora の仕様に範囲が定義されていないため検証対象に含めない。
void validateAudioOpusParams({
  int? channels,
  int? maxplaybackrate,
  int? minptime,
}) {
  _validateOptionalIntInRange(
    channels,
    minimum: 1,
    maximum: 8,
    name: 'audioOpusParamsChannels',
  );
  _validateOptionalIntInRange(
    maxplaybackrate,
    minimum: 8000,
    maximum: 48000,
    name: 'audioOpusParamsMaxplaybackrate',
  );
  _validateOptionalIntInRange(
    minptime,
    minimum: 3,
    maximum: 120,
    name: 'audioOpusParamsMinptime',
  );
}

/// シグナリング URL のリストが空でないことを検証する。
void validateSignalingUrls(List<String> urls) {
  if (urls.isEmpty) {
    throw ArgumentError.value(urls, 'signalingUrls', 'must not be empty');
  }
}

/// チャネル ID が空でないことを検証する。
void validateChannelId(String channelId) {
  if (channelId.isEmpty) {
    throw ArgumentError.value(channelId, 'channelId', 'must not be empty');
  }
}

/// 任意指定の整数を指定された範囲内か検証する。
void _validateOptionalIntInRange(
  int? value, {
  required int minimum,
  required int maximum,
  required String name,
}) {
  if (value == null || (value >= minimum && value <= maximum)) {
    return;
  }
  throw RangeError.range(value, minimum, maximum, name);
}
