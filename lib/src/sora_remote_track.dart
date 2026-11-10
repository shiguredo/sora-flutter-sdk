import 'sora_media_stream_track_base.dart';

/// リモートの MediaStreamTrack
///
/// 音声と映像の区別は `kind` で行う。
/// 映像トラック (`kind == 'video'`) のみ `textureId` を持つ。
class RemoteMediaStreamTrack implements MediaStreamTrack {
  /// @nodoc
  const RemoteMediaStreamTrack({
    required this.trackId,
    required this.kind,
    required this.connectionId,
    this.textureId,
  });

  @override
  final String trackId;

  @override
  final String kind;

  /// トラック ID から復元した接続 ID
  final String connectionId;

  /// 描画に利用する Flutter Texture ID（kind == 'video' のとき non-null）
  final int? textureId;
}
