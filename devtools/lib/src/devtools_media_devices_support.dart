/// DevTools 画面の media device 列挙と選択補助を提供するモジュール。
///
/// 動画入力解像度の抽出、audio device の絞り込み、Android 固有の
/// input / output 対応付けなどの補助ロジックをここに集約する。
library;

import 'package:flutter/services.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_models.dart';

class InitialAudioDevices {
  // 列挙済み audio device 一式と選択結果をまとめる。
  const InitialAudioDevices({
    required this.inputDevices,
    required this.selectedInputDevice,
    required this.outputDevices,
    required this.selectedOutputDevice,
  });

  final List<AudioInputDevice> inputDevices;
  final AudioInputDevice? selectedInputDevice;
  final List<AudioOutputDevice> outputDevices;
  final AudioOutputDevice? selectedOutputDevice;
}

class InitialVideoDevices {
  // 列挙済み video device 一式と既定選択結果をまとめる。
  const InitialVideoDevices({
    required this.devices,
    required this.selectedDevice,
    required this.resolutions,
    required this.selectedResolution,
  });

  final List<VideoInputDevice> devices;
  final VideoInputDevice? selectedDevice;
  final List<DevToolsVideoInputResolutionOption> resolutions;
  final DevToolsVideoInputResolutionOption? selectedResolution;
}

class DevToolsMediaDevicesSupport {
  // MediaDevices API と platform 補助を束ねる static helper 群。
  //
  // DevTools 画面で使う device 列挙、表示用整形、Android 固有の
  // input / output 対応付け、解像度候補選択を担当する。
  // Android の `AudioDeviceInfo.TYPE_BLE_BROADCAST` に対応する値。
  static const int audioTypeBleBroadcast = 30;
  // Android の `AudioDeviceInfo.TYPE_BLE_HEADSET` に対応する値。
  static const int audioTypeBleHeadset = 26;
  // Android の `AudioDeviceInfo.TYPE_BLE_SPEAKER` に対応する値。
  static const int audioTypeBleSpeaker = 27;
  // Android の `AudioDeviceInfo.TYPE_BLUETOOTH_A2DP` に対応する値。
  static const int audioTypeBluetoothA2dp = 8;
  // Android の `AudioDeviceInfo.TYPE_BLUETOOTH_SCO` に対応する値。
  static const int audioTypeBluetoothSco = 7;
  // Android の `AudioDeviceInfo.TYPE_BUILTIN_EARPIECE` に対応する値。
  static const int audioTypeBuiltinEarpiece = 1;
  // Android の `AudioDeviceInfo.TYPE_BUILTIN_MIC` に対応する値。
  static const int audioTypeBuiltinMic = 15;
  // Android の `AudioDeviceInfo.TYPE_BUILTIN_SPEAKER` に対応する値。
  static const int audioTypeBuiltinSpeaker = 2;
  // Android の `AudioDeviceInfo.TYPE_BUILTIN_SPEAKER_SAFE` に対応する値。
  static const int audioTypeBuiltinSpeakerSafe = 24;
  // Android の `AudioDeviceInfo.TYPE_USB_ACCESSORY` に対応する値。
  static const int audioTypeUsbAccessory = 12;
  // Android の `AudioDeviceInfo.TYPE_USB_DEVICE` に対応する値。
  static const int audioTypeUsbDevice = 11;
  // Android の `AudioDeviceInfo.TYPE_USB_HEADSET` に対応する値。
  static const int audioTypeUsbHeadset = 22;
  // Android の `AudioDeviceInfo.TYPE_WIRED_HEADPHONES` に対応する値。
  static const int audioTypeWiredHeadphones = 4;
  // Android の `AudioDeviceInfo.TYPE_WIRED_HEADSET` に対応する値。
  static const int audioTypeWiredHeadset = 3;

  // DevTools で選択対象に含める Android audio input type 一覧。
  static const Set<String> androidAllowedAudioInputTypes = <String>{
    'BUILTIN_MIC',
    'WIRED_HEADSET',
    'USB_DEVICE',
    'USB_HEADSET',
    'BLUETOOTH_SCO',
    'BLE_HEADSET',
  };

  // DevTools で選択対象に含める Android audio output type 一覧。
  static const Set<String> androidAllowedAudioOutputTypes = <String>{
    'BUILTIN_SPEAKER',
    'BUILTIN_EARPIECE',
    'WIRED_HEADPHONES',
    'WIRED_HEADSET',
    'USB_DEVICE',
    'USB_HEADSET',
    'BLUETOOTH_A2DP',
    'BLUETOOTH_SCO',
    'BLE_SPEAKER',
  };

  // 利用可能な video input device 一覧を列挙する。
  static Future<List<VideoInputDevice>> loadVideoInputDevices() {
    return MediaDevices.enumerateVideoInputDevices();
  }

  // 初期表示用に video input device 一覧と既定選択をまとめて読み込む。
  static Future<InitialVideoDevices> loadInitialVideoDevices() async {
    final devices = await loadVideoInputDevices();
    final selectedDevice = devices.isNotEmpty ? devices.first : null;
    final resolutions = selectedDevice == null
        ? const <DevToolsVideoInputResolutionOption>[]
        : await loadVideoInputFormats(selectedDevice);
    return InitialVideoDevices(
      devices: devices,
      selectedDevice: selectedDevice,
      resolutions: resolutions,
      selectedResolution: findDefaultResolution(resolutions),
    );
  }

  // 指定した video input device の対応解像度一覧を取得する。
  static Future<List<DevToolsVideoInputResolutionOption>> loadVideoInputFormats(
    VideoInputDevice device,
  ) async {
    final formats = await device.supportedFormats();
    return extractVideoInputResolutions(formats);
  }

  // Audio device 列挙前に必要な platform 側の準備を実行する。
  static Future<void> prepareAudioDeviceEnumeration(
    MethodChannel permissionChannel,
  ) {
    return permissionChannel.invokeMethod<void>(
      'prepareAudioDeviceEnumeration',
    );
  }

  // 現在の選択状態を考慮して audio input / output device 一覧を読み込む。
  //
  // Android では output device に応じた input device の補完も行う。
  static Future<InitialAudioDevices> loadAudioDevices({
    required bool isAndroid,
    required String? selectedAudioInputDeviceId,
    required String? selectedAudioOutputDeviceId,
  }) async {
    final inputDevices = filterDevToolsAudioInputDevices(
      await MediaDevices.enumerateAudioInputDevices(),
      isAndroid: isAndroid,
    );
    final outputDevices = filterDevToolsAudioOutputDevices(
      await MediaDevices.enumerateAudioOutputDevices(),
      isAndroid: isAndroid,
    );

    AudioInputDevice? selectedAudioInputDevice;
    for (final device in inputDevices) {
      if (device.deviceId == selectedAudioInputDeviceId) {
        selectedAudioInputDevice = device;
        break;
      }
    }

    AudioOutputDevice? selectedAudioOutputDevice;
    for (final device in outputDevices) {
      if (device.deviceId == selectedAudioOutputDeviceId) {
        selectedAudioOutputDevice = device;
        break;
      }
    }

    if (isAndroid) {
      selectedAudioOutputDevice =
          selectedAudioOutputDevice ??
          (outputDevices.isNotEmpty ? outputDevices.first : null);
      selectedAudioInputDevice =
          deriveAndroidAudioInputDevice(
            outputDevice: selectedAudioOutputDevice,
            inputDevices: inputDevices,
          ) ??
          selectedAudioInputDevice ??
          (inputDevices.isNotEmpty ? inputDevices.first : null);
    }

    return InitialAudioDevices(
      inputDevices: inputDevices,
      selectedInputDevice:
          selectedAudioInputDevice ??
          (inputDevices.isNotEmpty ? inputDevices.first : null),
      outputDevices: outputDevices,
      selectedOutputDevice:
          selectedAudioOutputDevice ??
          (outputDevices.isNotEmpty ? outputDevices.first : null),
    );
  }

  // DevTools で表示対象にする audio input device を絞り込む。
  static List<AudioInputDevice> filterDevToolsAudioInputDevices(
    List<AudioInputDevice> devices, {
    required bool isAndroid,
  }) {
    if (!isAndroid) {
      return devices;
    }
    return devices.where((device) {
      final type = androidAudioDeviceTypeLabel(device.type);
      return type != null && androidAllowedAudioInputTypes.contains(type);
    }).toList();
  }

  // DevTools で表示対象にする audio output device を絞り込む。
  static List<AudioOutputDevice> filterDevToolsAudioOutputDevices(
    List<AudioOutputDevice> devices, {
    required bool isAndroid,
  }) {
    if (!isAndroid) {
      return devices;
    }
    return devices.where((device) {
      final type = androidAudioDeviceTypeLabel(device.type);
      return type != null && androidAllowedAudioOutputTypes.contains(type);
    }).toList();
  }

  // Audio input device の表示用ラベルを生成する。
  static String formatAudioInputDeviceLabel(AudioInputDevice device) {
    return formatAudioDeviceLabel(device.label, device.type);
  }

  // Audio output device の表示用ラベルを生成する。
  static String formatAudioOutputDeviceLabel(AudioOutputDevice device) {
    return formatAudioDeviceLabel(device.label, device.type);
  }

  // Android の output device から対応する input device を推定する。
  static AudioInputDevice? deriveAndroidAudioInputDevice({
    required AudioOutputDevice? outputDevice,
    required List<AudioInputDevice> inputDevices,
  }) {
    if (outputDevice == null) {
      return null;
    }
    final outputType = outputDevice.type;
    if (outputType == null) {
      return null;
    }
    final productName = outputDevice.label.trim();

    bool matchesFamily(AudioInputDevice inputDevice) {
      switch (outputType) {
        case audioTypeBuiltinSpeaker:
        case audioTypeBuiltinSpeakerSafe:
        case audioTypeBuiltinEarpiece:
          return inputDevice.type == audioTypeBuiltinMic;
        case audioTypeWiredHeadphones:
        case audioTypeWiredHeadset:
          return inputDevice.type == audioTypeWiredHeadset;
        case audioTypeUsbDevice:
        case audioTypeUsbHeadset:
          return inputDevice.type == audioTypeUsbDevice ||
              inputDevice.type == audioTypeUsbHeadset;
        case audioTypeBluetoothA2dp:
        case audioTypeBluetoothSco:
          return inputDevice.type == audioTypeBluetoothSco;
        case audioTypeBleSpeaker:
        case audioTypeBleHeadset:
          return inputDevice.type == audioTypeBleHeadset;
        default:
          return false;
      }
    }

    AudioInputDevice? sameProductName;
    AudioInputDevice? firstFamilyMatch;
    for (final inputDevice in inputDevices) {
      if (!matchesFamily(inputDevice)) {
        continue;
      }
      firstFamilyMatch ??= inputDevice;
      if (inputDevice.label.trim() == productName) {
        sameProductName = inputDevice;
        break;
      }
    }
    return sameProductName ?? firstFamilyMatch;
  }

  // Audio device の種別名を付けた表示用ラベルを生成する。
  static String formatAudioDeviceLabel(String label, int? type) {
    final typeLabel = androidAudioDeviceTypeLabel(type);
    if (typeLabel == null) {
      return label;
    }
    return '$label ($typeLabel)';
  }

  // Android の audio device type を DevTools 表示用ラベルへ変換する。
  static String? androidAudioDeviceTypeLabel(int? type) {
    switch (type) {
      case audioTypeBleBroadcast:
        return 'BLE_BROADCAST';
      case audioTypeBleHeadset:
        return 'BLE_HEADSET';
      case audioTypeBleSpeaker:
        return 'BLE_SPEAKER';
      case audioTypeBluetoothA2dp:
        return 'BLUETOOTH_A2DP';
      case audioTypeBluetoothSco:
        return 'BLUETOOTH_SCO';
      case audioTypeBuiltinEarpiece:
        return 'BUILTIN_EARPIECE';
      case audioTypeBuiltinMic:
        return 'BUILTIN_MIC';
      case audioTypeBuiltinSpeaker:
        return 'BUILTIN_SPEAKER';
      case audioTypeBuiltinSpeakerSafe:
        return 'BUILTIN_SPEAKER_SAFE';
      case audioTypeUsbAccessory:
        return 'USB_ACCESSORY';
      case audioTypeUsbDevice:
        return 'USB_DEVICE';
      case audioTypeUsbHeadset:
        return 'USB_HEADSET';
      case audioTypeWiredHeadphones:
        return 'WIRED_HEADPHONES';
      case audioTypeWiredHeadset:
        return 'WIRED_HEADSET';
      default:
        return type == null ? null : 'TYPE_$type';
    }
  }

  // `VideoInputFormat` 一覧から重複を除いた解像度一覧を抽出する。
  static List<DevToolsVideoInputResolutionOption> extractVideoInputResolutions(
    List<VideoInputFormat> formats,
  ) {
    final resolutions = <DevToolsVideoInputResolutionOption>[];
    for (final format in formats) {
      final resolution = DevToolsVideoInputResolutionOption(
        width: format.width,
        height: format.height,
      );
      if (!resolutions.contains(resolution)) {
        resolutions.add(resolution);
      }
    }
    return resolutions;
  }

  // 利用可能解像度の中から既定値に最も近い解像度を返す。
  static DevToolsVideoInputResolutionOption? findDefaultResolution(
    List<DevToolsVideoInputResolutionOption> resolutions,
  ) {
    if (resolutions.isEmpty) {
      return null;
    }
    final target = DevToolsVideoResolutionOption
        .presets[DevToolsVideoResolutionOption.defaultLandscapeIndex];
    DevToolsVideoInputResolutionOption? best;
    var bestDiff = 0x7fffffff;
    for (final resolution in resolutions) {
      final diff =
          (resolution.width - target.width).abs() +
          (resolution.height - target.height).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = resolution;
      }
    }
    return best;
  }

  // 指定解像度に最も近い利用可能解像度を返す。
  static DevToolsVideoInputResolutionOption? findClosestResolution(
    List<DevToolsVideoInputResolutionOption> resolutions,
    DevToolsVideoInputResolutionOption? target,
  ) {
    if (target == null || resolutions.isEmpty) {
      return findDefaultResolution(resolutions);
    }
    DevToolsVideoInputResolutionOption? best;
    var bestScore = double.infinity;
    for (final resolution in resolutions) {
      final score =
          (resolution.width - target.width).abs().toDouble() +
          (resolution.height - target.height).abs().toDouble();
      if (score < bestScore) {
        bestScore = score;
        best = resolution;
      }
    }
    return best;
  }
}
