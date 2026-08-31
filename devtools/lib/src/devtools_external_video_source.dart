/// external video track サンプル用のカメラ入力と I420 変換ユーティリティ。
///
/// Flutter 公式 `camera` パッケージの出力を `ExternalVideoFrame` (I420) に
/// 変換し、`LocalVideoTrack.writeFrame()` へ投入する責務を持つ。
///
/// パフォーマンスが出ない場合は libyuv の導入を検討してください。
/// ここではサンプルとして純粋 Dart で最小限の変換のみ行う。
library;

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:sora_sdk/sora_sdk.dart';

/// [CameraImage] を I420 形式の [ExternalVideoFrame] へ変換する。
///
/// [sensorOrientation] はカメラセンサーの向き（度）。Android rear camera では通常 90。
///
/// 形式ごとの変換経路:
/// - Android: YUV_420_888 / NV21 → プレーン抽出のみ（tri-planar、純粋 Dart で実用的）
/// - iOS bgra8888: BGRA → I420 色空間変換 + 4:2:0 化（純粋 Dart では高負荷）
/// - iOS yuv420: 未対応（bi-planar のため別実装が必要。devtools では代わりに bgra8888 を要求）
///
/// パフォーマンスが出ない場合は libyuv の導入を検討してください。
ExternalVideoFrame cameraImageToExternalVideoFrame(
  CameraImage image, {
  int sensorOrientation = 0,
}) {
  switch (image.format.group) {
    case ImageFormatGroup.yuv420:
    case ImageFormatGroup.nv21:
      return _yuv420ToExternalVideoFrame(image, sensorOrientation);
    case ImageFormatGroup.bgra8888:
      return _bgra8888ToExternalVideoFrame(image, sensorOrientation);
    default:
      throw UnsupportedError(
        'Camera image format ${image.format.group} is not supported. '
        'Use libyuv FFI bindings for production apps.',
      );
  }
}

/// Android の tri-planar YUV_420_888 / NV21 を I420 に変換する。
///
/// Camera API の Plane から Y / U / V プレーンを抽出する。
/// UV プレーンが interleaved な場合（pixelStride > 1）は非インタリーブ化する。
///
/// iOS の bi-planar yuv420（Y + UV interleaved の 2 プレーン）は
/// プレーン構造が異なるためこの関数では処理できない。
/// iOS では devtools 側で明示的に bgra8888 を要求している。
ExternalVideoFrame _yuv420ToExternalVideoFrame(
  CameraImage image,
  int sensorOrientation,
) {
  final width = image.width;
  final height = image.height;
  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yData = _copyPlane(yPlane, width, height, pixelStride: 1);
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;

  final uvPixelStride = uPlane.bytesPerPixel ?? 1;
  final uData = _copyPlane(
    uPlane,
    chromaWidth,
    chromaHeight,
    pixelStride: uvPixelStride,
  );
  final vData = _copyPlane(
    vPlane,
    chromaWidth,
    chromaHeight,
    pixelStride: uvPixelStride,
  );

  return ExternalVideoFrame(
    width: width,
    height: height,
    yPlane: yData,
    uPlane: uData,
    vPlane: vData,
    yStride: width,
    uStride: chromaWidth,
    vStride: chromaWidth,
    rotation: sensorOrientation,
    timestampUs: DateTime.now().microsecondsSinceEpoch,
  );
}

/// Plane から指定サイズ・ピクセルストライドでデータをコピーする。
Uint8List _copyPlane(
  Plane plane,
  int width,
  int height, {
  required int pixelStride,
}) {
  final src = plane.bytes;
  final srcRowStride = plane.bytesPerRow;
  final dst = Uint8List(width * height);
  for (var row = 0; row < height; row++) {
    final srcRowStart = row * srcRowStride;
    final dstRowStart = row * width;
    for (var col = 0; col < width; col++) {
      dst[dstRowStart + col] = src[srcRowStart + col * pixelStride];
    }
  }
  return dst;
}

/// iOS の single-planar BGRA を I420 に変換する。
///
/// 2x2 ブロックごとに 4 つの Y 値と 1 組の U/V 値を BT.601 近似で計算する。
/// 純粋 Dart では毎フレームの色空間変換 + クロマサブサンプリングの負荷が大きく、
/// 高解像度・高フレームレートではパフォーマンスが出ない可能性があります。
/// パフォーマンスが出ない場合は libyuv の導入を検討してください。
ExternalVideoFrame _bgra8888ToExternalVideoFrame(
  CameraImage image,
  int sensorOrientation,
) {
  final width = image.width;
  final height = image.height;
  final src = image.planes[0].bytes;
  final srcStride = image.planes[0].bytesPerRow;

  final yPlane = Uint8List(width * height);
  final chromaWidth = (width + 1) ~/ 2;
  final chromaHeight = (height + 1) ~/ 2;
  final uPlane = Uint8List(chromaWidth * chromaHeight);
  final vPlane = Uint8List(chromaWidth * chromaHeight);

  for (var y = 0; y < height; y += 2) {
    for (var x = 0; x < width; x += 2) {
      final tl = _readBgraPixel(src, srcStride, x, y);
      final tr = (x + 1 < width)
          ? _readBgraPixel(src, srcStride, x + 1, y)
          : tl;
      final bl = (y + 1 < height)
          ? _readBgraPixel(src, srcStride, x, y + 1)
          : tl;
      final br = (x + 1 < width && y + 1 < height)
          ? _readBgraPixel(src, srcStride, x + 1, y + 1)
          : tl;

      yPlane[y * width + x] = _toY(tl);
      if (x + 1 < width) {
        yPlane[y * width + x + 1] = _toY(tr);
      }
      if (y + 1 < height) {
        yPlane[(y + 1) * width + x] = _toY(bl);
        if (x + 1 < width) {
          yPlane[(y + 1) * width + x + 1] = _toY(br);
        }
      }

      final cx = x ~/ 2;
      final cy = y ~/ 2;
      final avg = _averagePixel(tl, tr, bl, br);
      uPlane[cy * chromaWidth + cx] = _toU(avg);
      vPlane[cy * chromaWidth + cx] = _toV(avg);
    }
    if (width.isOdd) {
      for (var yy = y; yy < y + 2 && yy < height; yy++) {
        final pixel = _readBgraPixel(src, srcStride, width - 1, yy);
        yPlane[yy * width + width - 1] = _toY(pixel);
      }
    }
  }
  if (height.isOdd) {
    final lastY = height - 1;
    for (var x = 0; x < width; x++) {
      final pixel = _readBgraPixel(src, srcStride, x, lastY);
      yPlane[lastY * width + x] = _toY(pixel);
    }
  }

  return ExternalVideoFrame(
    width: width,
    height: height,
    yPlane: yPlane,
    uPlane: uPlane,
    vPlane: vPlane,
    yStride: width,
    uStride: chromaWidth,
    vStride: chromaWidth,
    rotation: sensorOrientation,
    timestampUs: DateTime.now().microsecondsSinceEpoch,
  );
}

(int, int, int) _readBgraPixel(Uint8List src, int rowStride, int x, int y) {
  final offset = y * rowStride + x * 4;
  return (src[offset], src[offset + 1], src[offset + 2]);
}

int _toY((int, int, int) bgr) {
  final (b, g, r) = bgr;
  return ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
}

int _toU((int, int, int) bgr) {
  final (b, g, r) = bgr;
  return ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
}

int _toV((int, int, int) bgr) {
  final (b, g, r) = bgr;
  return ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
}

(int, int, int) _averagePixel(
  (int, int, int) a,
  (int, int, int) b,
  (int, int, int) c,
  (int, int, int) d,
) {
  return (
    (a.$1 + b.$1 + c.$1 + d.$1) ~/ 4,
    (a.$2 + b.$2 + c.$2 + d.$2) ~/ 4,
    (a.$3 + b.$3 + c.$3 + d.$3) ~/ 4,
  );
}

/// `camera` パッケージの [CameraController] からフレームを取得し
/// I420 に変換して [LocalVideoTrack.writeFrame] へ投入するループ。
///
/// ライフサイクル: start() → (フレーム処理ループ) → stop()
/// フレーム変換に失敗した場合はエラーをログ出力し、後続フレームの処理を継続する。
///
/// [onFrame] はプレビュー用途等でフレーム情報を受け取る callback。
class ExternalVideoFrameSource {
  ExternalVideoFrameSource({
    required this.controller,
    required this.videoTrack,
    this.sensorOrientation = 0,
    this.onFrame,
  });

  final CameraController controller;
  final LocalVideoTrack videoTrack;
  final int sensorOrientation;
  final void Function(CameraImage image)? onFrame;

  bool _running = false;

  bool get isRunning => _running;

  /// フレーム取得を開始する。
  Future<void> start() async {
    if (_running) {
      return;
    }
    _running = true;
    await controller.startImageStream(_onImage);
  }

  /// フレーム取得を停止する。
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _running = false;
    try {
      await controller.stopImageStream();
    } catch (_) {
      // controller が既に dispose されている場合は無視する
    }
  }

  void _onImage(CameraImage image) {
    onFrame?.call(image);
    try {
      final frame = cameraImageToExternalVideoFrame(
        image,
        sensorOrientation: sensorOrientation,
      );
      videoTrack.writeFrame(frame);
    } catch (error, stackTrace) {
      // ignore: avoid_print
      print(
        'ExternalVideoFrameSource: convert/writeFrame error: $error\n$stackTrace',
      );
    }
  }
}
