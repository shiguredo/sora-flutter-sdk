import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/media/sora_media_device_platform.dart'
    as media_device_platform;

void main() {
  group('videoInputFormatFromPlatformMap', () {
    test('非整数の maxFrameRate は四捨五入して int にする', () {
      // Windows 等が返す 29.97 fps を 30 に丸める。
      final format = media_device_platform.videoInputFormatFromPlatformMap(
        <String, Object?>{'width': 1280, 'height': 720, 'maxFrameRate': 29.97},
      );

      expect(format.maxFrameRate, 30);
      expect(format.maxFrameRate, isA<int>());
    });

    test('int の maxFrameRate はそのまま int として扱う', () {
      final format = media_device_platform.videoInputFormatFromPlatformMap(
        <String, Object?>{'width': 1280, 'height': 720, 'maxFrameRate': 30},
      );

      expect(format.maxFrameRate, 30);
      expect(format.maxFrameRate, isA<int>());
    });
  });

  group('isAudioInputDeviceNotFoundError の例外分類', () {
    test('iOS と Android のデバイス不存在は無視対象になる', () {
      // MethodChannel 経路のデバイス不存在コードを検証する。
      // message の内容は判定に使わない。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(
            code: 'audio_device_not_found',
            message: 'something else',
          ),
        ),
        isTrue,
      );
    });

    test('deviceId 未指定時の既定デバイス不存在は無視対象になる', () {
      // Linux の既定デバイス取得の不存在コードを検証する。
      // message の内容は判定に使わない。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(
            code: 'device_not_found',
            message: 'Default audio input device not found.',
          ),
        ),
        isTrue,
      );
      // 紛らわしい message があっても code 不一致は rethrow 対象になる。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(
            code: 'unexpected',
            message: 'Default audio input device not found.',
          ),
        ),
        isFalse,
      );
    });

    test('Dart 変換と FFI 経路の固定文言は無視対象になる', () {
      // 固定文言 2 件は完全一致で判定することを検証する。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('Default audio input device not found.'),
        ),
        isTrue,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('No audio input devices available.'),
        ),
        isTrue,
      );
    });

    test('デバイス ID 付きの不存在は前方一致で無視対象になる', () {
      // コロンと半角スペースまで含めた前方一致を検証する。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('Audio input device not found: builtin-mic'),
        ),
        isTrue,
      );
      // 接尾辞なしは前方一致しない。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('Audio input device not found'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('Audio input device not found:'),
        ),
        isFalse,
      );
    });

    test('タイムアウトとプラグイン未登録は rethrow 対象になる', () {
      // 切替未完了の通知は呼び出し側へ伝えることを検証する。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          TimeoutException(
            'setAudioInputDevice timed out after 10 seconds',
            const Duration(seconds: 10),
          ),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          MissingPluginException('No implementation found'),
        ),
        isFalse,
      );
    });

    test('想定外のコードとメッセージは rethrow 対象になる', () {
      // ホワイトリスト外の例外を検証する。
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(code: 'audio_routing_timeout'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(code: 'audio_routing_failed'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(code: 'set_preferred_input_failed'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          PlatformException(code: 'invalid_argument'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('AudioDeviceModule is not initialized.'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          StateError('SetRecordingDevice failed: deviceId=unknown'),
        ),
        isFalse,
      );
      expect(
        media_device_platform.isAudioInputDeviceNotFoundError(
          ArgumentError('unexpected'),
        ),
        isFalse,
      );
    });
  });
}
