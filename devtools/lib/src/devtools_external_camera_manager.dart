/// external video track サンプル用のカメラライフサイクル管理。
///
/// [CameraController] の初期化・破棄と、
/// [ExternalVideoFrameSource] によるフレーム送信の開始・停止を一括管理する。
///
/// プレビュー用に [controller] を公開し、[isInitialized] で状態を問い合わせられる。
library;

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_external_video_source.dart';

class DevToolsExternalCameraManager {
  DevToolsExternalCameraManager({this.onLog});

  final void Function(String message)? onLog;

  CameraController? _controller;
  ExternalVideoFrameSource? _frameSource;

  /// [CameraPreview] 表示用のコントローラ。
  CameraController? get controller => _controller;

  /// カメラが初期化済みでプレビュー可能か。
  bool get isInitialized =>
      _controller != null && _controller!.value.isInitialized;

  /// カメラを初期化する。
  ///
  /// すでに初期化済みの場合は何もしない。
  /// Android では YUV420、iOS では BGRA のフォーマットを要求する。
  /// iOS の yuv420（bi-planar）は未対応のため、代わりに bgra8888 を利用する。
  Future<void> initialize() async {
    if (_controller != null) {
      return;
    }
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      throw StateError('No cameras available.');
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();
    } catch (_) {
      unawaited(controller.dispose());
      rethrow;
    }
    _controller = controller;
  }

  /// フレーム送信を開始する。
  ///
  /// [track] は [VideoTrackCaptureType.external] の video track。
  /// [CameraController.startImageStream] でフレームを取得し、
  /// [ExternalVideoFrameSource] が I420 変換 + [writeFrame] を行う。
  /// [CameraPreview] によるプレビューと [startImageStream] は共存可能。
  Future<void> start(LocalVideoTrack track) async {
    final controller = _controller;
    if (controller == null || _frameSource?.isRunning == true) {
      return;
    }
    _frameSource = ExternalVideoFrameSource(
      controller: controller,
      videoTrack: track,
      sensorOrientation: controller.description.sensorOrientation,
    );
    try {
      await _frameSource!.start();
      onLog?.call('external video track: frame source started');
    } catch (error) {
      onLog?.call('external video track: frame source start failed: $error');
      _frameSource = null;
    }
  }

  /// フレーム送信を停止する。
  ///
  /// track が dispose される前に呼ぶ必要がある。
  /// 停止後も [CameraPreview] によるプレビューは継続する。
  Future<void> stop() async {
    final source = _frameSource;
    if (source != null) {
      await source.stop();
      _frameSource = null;
      onLog?.call('external video track: frame source stopped');
    }
  }

  /// カメラを破棄する。
  ///
  /// フレーム送信停止 → [CameraController.dispose] の順でクリーンアップする。
  Future<void> dispose() async {
    await stop();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
      onLog?.call('external video track: camera disposed');
    }
  }
}
