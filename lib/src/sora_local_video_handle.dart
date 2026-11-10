import 'package:meta/meta.dart';

/// ローカル映像表示用の Texture ID。
///
/// `SoraConnection.localVideo` Stream から届くハンドルの `textureId` は
/// 常に有効な非負値。external track を使う接続では [SoraConnection.localVideo]
/// 自体が emit されず、このハンドルは届かない。
@immutable
class SoraLocalVideoHandle {
  /// @nodoc
  const SoraLocalVideoHandle({required this.textureId});

  /// Flutter の Texture widget に渡すテクスチャ ID。
  final int textureId;
}
