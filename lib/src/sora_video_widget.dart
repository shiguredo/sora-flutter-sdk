/// 映像表示用 Widget 群
///
/// リモート映像用とローカルプレビュー用の公開 Widget と、
/// 共通の描画組み立て処理をまとめて定義する。
library;

import 'package:flutter/widgets.dart';

import 'sora_remote_track.dart';

/// `textureId` が null のときに表示する既定のプレースホルダー
const Widget _defaultPlaceholder = ColoredBox(color: Color(0xFF000000));

/// 共通の映像描画 Widget を組み立てる
Widget _buildVideoTextureWidget({
  required int textureId,
  required BoxFit fit,
  required bool mirror,
}) {
  Widget result = Texture(textureId: textureId, key: ValueKey(textureId));

  if (fit == BoxFit.fill) {
    result = ClipRect(child: result);
  }

  if (mirror) {
    result = Transform(
      transform: Matrix4.diagonal3Values(-1, 1, 1),
      alignment: Alignment.center,
      child: result,
    );
  }

  return result;
}

/// リモート映像を表示する Widget
///
/// [track] には映像トラック（ `kind == 'video'` ）を渡すこと。
/// 音声トラック（ `kind == 'audio'` ）を渡した場合は debug 時に assert で検出する。
///
/// ```dart
/// SoraRemoteVideoWidget(track: videoTrack)
/// ```
class SoraRemoteVideoWidget extends StatelessWidget {
  /// @nodoc
  SoraRemoteVideoWidget({
    super.key,
    required this.track,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.placeholder = _defaultPlaceholder,
  }) : assert(track.kind == 'video', 'track must be kind=video');

  /// 表示するリモート映像トラック
  final RemoteMediaStreamTrack track;

  /// 映像の親領域へのフィット方法
  final BoxFit fit;

  /// 映像の水平反転
  final bool mirror;

  /// [track.textureId] が null の間に表示する代替 Widget
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final textureId = track.textureId;
    if (textureId == null) {
      return placeholder;
    }

    return _buildVideoTextureWidget(
      textureId: textureId,
      fit: fit,
      mirror: mirror,
    );
  }
}

/// ローカルプレビューを表示する Widget
///
/// [textureId] は null 許容。null の間は [placeholder] を表示する。
///
/// ```dart
/// SoraLocalVideoWidget(textureId: localTextureId, mirror: true)
/// ```
class SoraLocalVideoWidget extends StatelessWidget {
  /// @nodoc
  const SoraLocalVideoWidget({
    super.key,
    required this.textureId,
    this.fit = BoxFit.contain,
    this.mirror = false,
    this.placeholder = _defaultPlaceholder,
  });

  /// Flutter Texture に渡すテクスチャ ID（ null 許容 ）
  final int? textureId;

  /// 映像の親領域へのフィット方法
  final BoxFit fit;

  /// 映像の水平反転
  final bool mirror;

  /// [textureId] が null の間に表示する代替 Widget
  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    final textureId = this.textureId;
    if (textureId == null) {
      return placeholder;
    }

    return _buildVideoTextureWidget(
      textureId: textureId,
      fit: fit,
      mirror: mirror,
    );
  }
}
