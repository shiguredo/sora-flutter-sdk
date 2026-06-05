import 'package:meta/meta.dart';

/// ローカル映像表示用の Texture ID。
@immutable
class SoraLocalVideoHandle {
  /// @nodoc
  const SoraLocalVideoHandle({required this.textureId});

  /// Flutter の Texture widget に渡すテクスチャ ID。
  final int textureId;
}
