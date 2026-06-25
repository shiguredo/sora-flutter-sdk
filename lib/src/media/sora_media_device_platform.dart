/// デバイス列挙とプラットフォーム依存のメディア入出力制御を扱う内部モジュールです。
library;

import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

import '../ffi/webrtc_client.dart';
import '../sora_audio_device.dart';
import '../sora_method_channels.dart';
import '../sora_video_device.dart';

/// 映像入力デバイス一覧をプラットフォーム実装から取得します。
@internal
Future<List<VideoInputDevice>> enumerateVideoInputDevices() async {
  final List<Object?>? result = await soraMethodChannel
      .invokeMethod<List<Object?>>('enumerateVideoInputDevices');
  if (result == null) {
    return <VideoInputDevice>[];
  }
  return result.map(_videoInputDeviceFromPlatformMap).toList();
}

/// 指定した映像入力デバイスが対応するフォーマット一覧を取得します。
@internal
Future<List<VideoInputFormat>> getVideoInputFormats(String deviceId) async {
  final List<Object?>? result = await soraMethodChannel
      .invokeMethod<List<Object?>>('getVideoInputFormats', <String, Object?>{
        'deviceId': deviceId,
      });
  if (result == null) {
    return <VideoInputFormat>[];
  }
  return result.map((Object? item) {
    final map = Map<String, Object?>.from(item! as Map);
    return VideoInputFormat(
      width: map['width']! as int,
      height: map['height']! as int,
      maxFrameRate: (map['maxFrameRate']! as num).toDouble(),
    );
  }).toList();
}

/// 音声入力デバイス一覧をプラットフォーム実装から取得します。
@internal
Future<List<AudioInputDevice>> enumerateAudioInputDevices() async {
  final List<Object?>? result = await soraMethodChannel
      .invokeMethod<List<Object?>>('enumerateAudioInputDevices');
  if (result == null) {
    return <AudioInputDevice>[];
  }
  return result.map(_audioInputDeviceFromPlatformMap).toList();
}

/// 音声出力デバイス一覧をプラットフォーム実装から取得します。
@internal
Future<List<AudioOutputDevice>> enumerateAudioOutputDevices() async {
  final List<Object?>? result = await soraMethodChannel
      .invokeMethod<List<Object?>>('enumerateAudioOutputDevices');
  if (result == null) {
    return <AudioOutputDevice>[];
  }
  return result.map(_audioOutputDeviceFromPlatformMap).toList();
}

/// 次に生成する audio track で使う音声入力デバイスを設定します。
///
/// `deviceId == null` の場合は、前回の明示選択を解除してプラットフォーム既定の
/// 入力デバイスへ戻します。
@internal
Future<void> setAudioInputDevice(String? deviceId) async {
  // macOS / Windows / Linux では libwebrtc ADM が Dart 側から FFI で直接参照可能であり、
  // ネイティブ往復なしでデバイス切り替えが完了するため、
  // MethodChannel ではなく FFI 経由で libwebrtc の AudioDeviceModule (ADM) を直接操作する。
  // 既定デバイスへの復帰にはプラットフォーム既定の入力デバイス ID を取得する。
  // Android と異なり Bluetooth SCO のような長時間 suspend がなく、
  // 内部の getDefaultAudioInputDeviceId / enumerateAudioInputDevices も
  // 軽量な問い合わせであるため、タイムアウトは設定していない。
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    final effectiveDeviceId = deviceId ?? await getDefaultAudioInputDeviceId();
    final devices = await enumerateAudioInputDevices();
    AudioInputDevice? selectedDevice;
    for (final device in devices) {
      if (device.deviceId == effectiveDeviceId) {
        selectedDevice = device;
        break;
      }
    }
    WebrtcClient.setRecordingDeviceByGuid(
      effectiveDeviceId,
      labelHint: selectedDevice?.label,
      preferDefaultDevice: deviceId == null,
    );
    return;
  }
  await soraMethodChannel
      .invokeMethod<void>('setAudioInputDevice', <String, Object?>{
        'deviceId': deviceId,
      })
      .timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException(
          'setAudioInputDevice timed out after 10 seconds',
          const Duration(seconds: 10),
        ),
      );
}

/// 既定の音声入力デバイス ID を取得します。
@internal
Future<String> getDefaultAudioInputDeviceId() async {
  final deviceId = await soraMethodChannel.invokeMethod<String>(
    'getDefaultAudioInputDevice',
  );
  if (deviceId == null || deviceId.isEmpty) {
    throw StateError('Default audio input device not found.');
  }
  return deviceId;
}

/// ローカルのカメラ映像トラックが使うプレビューテクスチャを確保します。
@internal
Future<int> ensureLocalVideoTrackTexture({
  required int videoSourcePtr,
  required int clientId,
  String? videoDeviceId,
  int? videoWidth,
  int? videoHeight,
  int? videoFrameRate,
}) async {
  final response = await soraMethodChannel.invokeMethod<Map<Object?, Object?>>(
    'ensureLocalVideoTrackTexture',
    <String, Object?>{
      'videoSourcePtr': videoSourcePtr,
      'clientId': clientId,
      'videoDeviceId': videoDeviceId,
      'videoWidth': videoWidth,
      'videoHeight': videoHeight,
      'videoFrameRate': videoFrameRate,
    },
  );
  final textureId = response?['textureId'];
  if (textureId is! int) {
    throw StateError('Failed to resolve local video texture ID.');
  }
  return textureId;
}

/// ローカルのカメラ映像トラックが使うプレビューテクスチャを破棄します。
@internal
Future<void> disposeLocalVideoTrackTexture({
  required int videoSourcePtr,
}) async {
  await soraMethodChannel.invokeMethod<void>(
    'disposeLocalVideoTrackTexture',
    <String, Object?>{'videoSourcePtr': videoSourcePtr},
  );
}

/// 実行中のカメラキャプチャを停止します。
@internal
Future<void> stopCameraCapturer({required int videoSourcePtr}) async {
  await soraMethodChannel.invokeMethod<void>(
    'stopCameraCapturer',
    <String, Object?>{'videoSourcePtr': videoSourcePtr},
  );
}

/// MethodChannel から受け取った Map を映像入力デバイスへ変換する。
VideoInputDevice _videoInputDeviceFromPlatformMap(Object? item) {
  final map = Map<String, Object?>.from(item! as Map);
  return VideoInputDevice(
    deviceId: map['deviceId']! as String,
    label: map['label']! as String,
  );
}

/// MethodChannel から受け取った Map を音声入力デバイスへ変換する。
AudioInputDevice _audioInputDeviceFromPlatformMap(Object? item) {
  final map = Map<String, Object?>.from(item! as Map);
  return AudioInputDevice(
    deviceId: map['deviceId']! as String,
    label: map['label']! as String,
    type: (map['type'] as num?)?.toInt(),
  );
}

/// MethodChannel から受け取った Map を音声出力デバイスへ変換する。
AudioOutputDevice _audioOutputDeviceFromPlatformMap(Object? item) {
  final map = Map<String, Object?>.from(item! as Map);
  return AudioOutputDevice(
    deviceId: map['deviceId']! as String,
    label: map['label']! as String,
    type: (map['type'] as num?)?.toInt(),
  );
}
