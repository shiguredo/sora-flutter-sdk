import 'dart:async';
import 'dart:typed_data';

import 'package:sora_sdk/sora_sdk.dart';

/// external video track に投入するカラーバー風の I420 映像ソース。
final class ColorBarVideoSource {
  ColorBarVideoSource({
    required this.width,
    required this.height,
    required this.frameRate,
  }) {
    if (width <= 0 || height <= 0 || frameRate <= 0) {
      throw StateError('Video source settings must be positive.');
    }
    if (width.isOdd || height.isOdd) {
      throw StateError('Video source width and height must be even.');
    }
  }

  // BT.601 相当の YUV 値を使い、横方向に 7 色のバーを作る。
  static const List<YuvColor> _colors = <YuvColor>[
    YuvColor(y: 235, u: 128, v: 128),
    YuvColor(y: 210, u: 16, v: 146),
    YuvColor(y: 170, u: 166, v: 16),
    YuvColor(y: 145, u: 54, v: 34),
    YuvColor(y: 106, u: 202, v: 222),
    YuvColor(y: 81, u: 90, v: 240),
    YuvColor(y: 41, u: 240, v: 110),
  ];

  final int width;
  final int height;
  final int frameRate;

  Timer? _timer;
  LocalVideoTrack? _track;
  var _frameIndex = 0;

  Duration get _interval => Duration(microseconds: 1000000 ~/ frameRate);

  /// [track] へのフレーム投入を開始する。
  void start(LocalVideoTrack track) {
    if (_timer != null) {
      throw StateError('Color bar video source is already started.');
    }
    _track = track;
    _writeNextFrame();
    _timer = Timer.periodic(_interval, (_) => _writeNextFrame());
  }

  /// フレーム投入を停止する。
  void stop() {
    _timer?.cancel();
    _timer = null;
    _track = null;
  }

  void _writeNextFrame() {
    final track = _track;
    if (track == null) {
      return;
    }

    final frame = _createFrame(_frameIndex);
    _frameIndex++;
    track.writeFrame(frame);
  }

  ExternalVideoFrame _createFrame(int frameIndex) {
    final chromaWidth = width ~/ 2;
    final chromaHeight = height ~/ 2;
    final yPlane = Uint8List(width * height);
    final uPlane = Uint8List(chromaWidth * chromaHeight);
    final vPlane = Uint8List(chromaWidth * chromaHeight);
    final offset = frameIndex * 4;

    for (var y = 0; y < height; y++) {
      final rowStart = y * width;
      for (var x = 0; x < width; x++) {
        yPlane[rowStart + x] = _colorAt(x + offset).y;
      }
    }

    for (var y = 0; y < chromaHeight; y++) {
      final rowStart = y * chromaWidth;
      for (var x = 0; x < chromaWidth; x++) {
        final color = _colorAt(x * 2 + offset);
        uPlane[rowStart + x] = color.u;
        vPlane[rowStart + x] = color.v;
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
      timestampUs: DateTime.now().microsecondsSinceEpoch,
    );
  }

  YuvColor _colorAt(int x) {
    final index = ((x % width) * _colors.length) ~/ width;
    return _colors[index];
  }
}

/// I420 の Y / U / V 値をまとめた色。
final class YuvColor {
  const YuvColor({required this.y, required this.u, required this.v});

  final int y;
  final int u;
  final int v;
}
