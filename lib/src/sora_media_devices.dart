/// `getUserMedia` API とメディアデバイス列挙を提供するモジュールです。
///
/// 音声・映像の入力デバイス列挙、フォーマット取得、local track の生成を担当します。
library;

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'ffi/bindings.dart';
import 'ffi/webrtc_client.dart';
import 'media/sora_media_device_platform.dart' as media_device_platform;
import 'sora_audio_device.dart';
import 'sora_media_stream.dart';
import 'sora_video_device.dart';

// 接続前に作る local stream の ID を単純増分で払い出す。
int _nextMediaStreamSequence = 1;

/// `MediaDevices.getUserMedia()` に渡す入力条件です。
@immutable
class GetUserMediaOptions {
  /// @nodoc
  const GetUserMediaOptions({
    this.audio = true,
    this.video = true,
    this.audioDeviceId,
    this.videoDeviceId,
    this.videoWidth,
    this.videoHeight,
    this.videoFrameRate,
  });

  /// 音声 track を含めるかどうか。
  final bool audio;

  /// 映像 track を含めるかどうか。
  final bool video;

  /// 音声入力に使うデバイス ID です。
  /// 未指定の場合は前回の明示選択を解除し、プラットフォーム標準の入力選択へ戻す。
  /// iOS は `AVAudioSession` の通常ルーティング、macOS は CoreAudio の既定入力を使う。
  final String? audioDeviceId;

  /// 映像入力に使うデバイス ID です。
  final String? videoDeviceId;

  /// 映像入力の希望幅です。省略時は 640 を使う。
  final int? videoWidth;

  /// 映像入力の希望高さです。省略時は 480 を使う。
  final int? videoHeight;

  /// 映像入力の希望フレームレートです。省略時は 30 を使う。
  final int? videoFrameRate;
}

// `getUserMedia()` は W3C Media Capture and Streams の API 名に合わせるため、
// `get` をあえて残している。
// 映像サイズ / フレームレートが省略されたときに使うデフォルト値。
// ブラウザの getUserMedia({ video: true }) と合わせている。
const int _defaultVideoWidth = 640;
const int _defaultVideoHeight = 480;
const int _defaultVideoFrameRate = 30;

/// local メディア入力を生成・列挙する static API です。
abstract final class MediaDevices {
  /// 共有 factory の音声デバイス使用設定を、メディア生成前に指定する。
  static void setUseAudioDevice(bool value) {
    WebrtcClient.useAudioDevice = value;
  }

  /// 空の local MediaStream を生成する。
  static LocalMediaStream createMediaStream() {
    final lib = WebrtcClient.sharedLib;
    final factory = WebrtcClient.sharedFactory;
    final streamId = 'stream${_nextMediaStreamSequence++}';
    final streamUtf8 = streamId.toNativeUtf8();
    final streamIdNative = streamUtf8.cast<Char>();
    final streamRefPtr =
        calloc<Pointer<WebrtcMediaStreamInterfaceRefcounted>>();

    try {
      lib.pcFactoryCreateLocalMediaStream(
        factory,
        streamIdNative,
        streamUtf8.length,
        streamRefPtr,
      );
      final streamRef = streamRefPtr.value;
      if (streamRef == nullptr) {
        throw StateError('Failed to create local MediaStream.');
      }
      return LocalMediaStream.fromNative(streamRef);
    } finally {
      calloc.free(streamUtf8);
      calloc.free(streamRefPtr);
    }
  }

  /// 映像入力デバイス一覧を取得する。
  static Future<List<VideoInputDevice>> enumerateVideoInputDevices() async {
    return media_device_platform.enumerateVideoInputDevices();
  }

  /// 音声入力デバイス (マイク) 一覧を取得する。
  static Future<List<AudioInputDevice>> enumerateAudioInputDevices() async {
    return media_device_platform.enumerateAudioInputDevices();
  }

  /// 音声出力デバイス (スピーカー) 一覧を取得する。
  static Future<List<AudioOutputDevice>> enumerateAudioOutputDevices() async {
    return media_device_platform.enumerateAudioOutputDevices();
  }

  /// ローカルの LocalMediaStream を生成する。
  ///
  // W3C Media Capture and Streams の `MediaDevices.getUserMedia()` と
  // 名前をそろえるため、`get` をあえて残している。
  static Future<LocalMediaStream> getUserMedia(
    GetUserMediaOptions options,
  ) async {
    if (!options.audio && !options.video) {
      throw StateError('At least one of audio or video must be enabled.');
    }

    LocalMediaStream? stream;
    LocalAudioTrack? audioTrack;
    LocalVideoTrack? videoTrack;

    try {
      stream = createMediaStream();

      if (options.audio) {
        audioTrack = await createAudioTrack(
          audioDeviceId: options.audioDeviceId,
        );
        stream.addTrack(audioTrack);
      }

      if (options.video) {
        videoTrack = createCameraVideoTrack(
          videoDeviceId: options.videoDeviceId,
          videoWidth: options.videoWidth ?? _defaultVideoWidth,
          videoHeight: options.videoHeight ?? _defaultVideoHeight,
          videoFrameRate: options.videoFrameRate ?? _defaultVideoFrameRate,
        );
        stream.addTrack(videoTrack);
      }

      return stream;
    } catch (_) {
      await audioTrack?.dispose();
      await videoTrack?.dispose();
      await stream?.dispose();
      rethrow;
    }
  }

  /// local audio track を 1 本生成する。
  /// `audioDeviceId` を指定すると、その ID のマイクを使うようネイティブ側に指示する。
  /// 未指定時は前回の明示選択を解除する。
  static Future<LocalAudioTrack> createAudioTrack({
    String? audioDeviceId,
  }) async {
    if (Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isWindows ||
        Platform.isLinux ||
        audioDeviceId != null) {
      // オーディオ入力デバイスが存在しない環境（CI 等）では
      // setAudioInputDevice が失敗する可能性があるが、ネイティブの
      // audio track 作成自体はデバイスがなくても成功するため、
      // エラーは無視して続行する。
      try {
        await media_device_platform.setAudioInputDevice(audioDeviceId);
      } catch (_) {}
    }
    final lib = WebrtcClient.sharedLib;
    final factory = WebrtcClient.sharedFactory;
    final audioSourceRefPtr =
        calloc<Pointer<WebrtcAudioSourceInterfaceRefcounted>>();
    final audioTrackRefPtr =
        calloc<Pointer<WebrtcAudioTrackInterfaceRefcounted>>();
    final trackId = 'audio${DateTime.now().microsecondsSinceEpoch}';
    final trackUtf8 = trackId.toNativeUtf8();
    final trackIdNative = trackUtf8.cast<Char>();

    try {
      lib.pcFactoryCreateAudioSource(factory, audioSourceRefPtr);
      final audioSourceRef = audioSourceRefPtr.value;
      if (audioSourceRef == nullptr) {
        throw StateError('Failed to create audio source.');
      }

      lib.pcFactoryCreateAudioTrack(
        factory,
        audioSourceRef,
        trackIdNative,
        trackUtf8.length,
        audioTrackRefPtr,
      );
      final audioTrackRef = audioTrackRefPtr.value;
      if (audioTrackRef == nullptr) {
        throw StateError('Failed to create audio track.');
      }

      final mediaTrackRef = lib.audioTrackCastToMediaStreamTrack(audioTrackRef);
      final track = LocalAudioTrack.fromNativeMediaTrack(mediaTrackRef);
      lib.audioTrackRelease(lib.audioTrackRefcountedGet(audioTrackRef));
      return track;
    } finally {
      final audioSourceRef = audioSourceRefPtr.value;
      if (audioSourceRef != nullptr) {
        lib.audioSourceRelease(lib.audioSourceRefcountedGet(audioSourceRef));
      }
      calloc.free(audioSourceRefPtr);
      calloc.free(audioTrackRefPtr);
      calloc.free(trackUtf8);
    }
  }

  /// SDK 管理カメラ入力の local video track を 1 本生成する。
  static LocalVideoTrack createCameraVideoTrack({
    String? videoDeviceId,
    int? videoWidth,
    int? videoHeight,
    int? videoFrameRate,
  }) {
    return _createVideoTrack(
      captureType: VideoTrackCaptureType.camera,
      captureSettings: VideoCaptureSettings(
        deviceId: videoDeviceId,
        width: videoWidth,
        height: videoHeight,
        frameRate: videoFrameRate,
      ),
    );
  }

  /// 外部映像入力の local video track を 1 本生成する。
  static LocalVideoTrack createExternalVideoTrack() {
    return _createVideoTrack(
      captureType: VideoTrackCaptureType.external,
      captureSettings: null,
    );
  }

  /// local video track を 1 本生成する。
  static LocalVideoTrack _createVideoTrack({
    required VideoTrackCaptureType captureType,
    required VideoCaptureSettings? captureSettings,
  }) {
    final lib = WebrtcClient.sharedLib;
    final factory = WebrtcClient.sharedFactory;
    final sourceRef = lib.adaptedVideoTrackSourceCreate();
    final videoTrackRefPtr =
        calloc<Pointer<WebrtcVideoTrackInterfaceRefcounted>>();
    final trackId = 'video${DateTime.now().microsecondsSinceEpoch}';
    final trackUtf8 = trackId.toNativeUtf8();
    final trackIdNative = trackUtf8.cast<Char>();

    var sourceTransferred = false;
    try {
      if (sourceRef == nullptr) {
        throw StateError('Failed to create video source.');
      }

      final videoSourceRef = lib.adaptedVideoTrackSourceCastToVideoTrackSource(
        sourceRef,
      );
      lib.pcFactoryCreateVideoTrack(
        factory,
        videoSourceRef,
        trackIdNative,
        trackUtf8.length,
        videoTrackRefPtr,
      );
      final videoTrackRef = videoTrackRefPtr.value;
      if (videoTrackRef == nullptr) {
        throw StateError('Failed to create video track.');
      }

      final mediaTrackRef = lib.videoTrackCastToMediaStreamTrack(videoTrackRef);
      final track = LocalVideoTrack.fromNativeMediaTrack(
        mediaTrackRef,
        captureType: captureType,
        captureSettings: captureSettings,
        videoSourceRef: sourceRef,
      );
      sourceTransferred = true;
      lib.videoTrackRelease(lib.videoTrackRefcountedGet(videoTrackRef));
      return track;
    } finally {
      if (!sourceTransferred && sourceRef != nullptr) {
        lib.adaptedVideoTrackSourceRelease(
          lib.adaptedVideoTrackSourceRefcountedGet(sourceRef),
        );
      }
      calloc.free(videoTrackRefPtr);
      calloc.free(trackUtf8);
    }
  }
}
