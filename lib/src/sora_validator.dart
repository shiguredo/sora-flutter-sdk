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
