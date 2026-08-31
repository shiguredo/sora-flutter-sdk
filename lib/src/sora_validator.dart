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
  _validateOptionalBitRate(
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
  _validateOptionalBitRate(
    value,
    minimum: 1,
    maximum: 50000,
    name: 'videoBitRate',
  );
}

/// 任意指定のビットレートを指定された範囲内か検証する。
void _validateOptionalBitRate(
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
