// Windows 版 音声デバイス (WASAPI) の列挙と選択を検証する E2E テスト。
//
// 本テストは Sora 接続を必要とせず、ローカルの WASAPI デバイス列挙と
// 入力デバイス切り替えのみを検証する。
// Windows 実機のマイク/スピーカーが存在する環境で実行すること。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'windows_audio_device: 音声入出力デバイスが列挙され、'
    '各デバイスに ID とラベルが存在することを確認する',
    (WidgetTester tester) async {
      // Windows 以外ではテストをスキップする
      if (!Platform.isWindows) {
        return;
      }

      // 音声入力デバイスを列挙する
      final inputDevices = await MediaDevices.enumerateAudioInputDevices();
      expect(inputDevices, isNotEmpty,
          reason:
              '少なくとも 1 件以上の音声入力デバイス（マイク）が存在すること。'
              'Windows 実機にマイクが接続されていることを確認してください。');

      for (final device in inputDevices) {
        expect(device.deviceId, isNotEmpty,
            reason:
                '各音声入力デバイスは空でない deviceId を持つこと。'
                'device.label=${device.label}');
        expect(device.label, isNotEmpty,
            reason:
                '各音声入力デバイスは空でない label を持つこと。'
                'device.deviceId=${device.deviceId}');
      }

      // 音声出力デバイスを列挙する
      final outputDevices = await MediaDevices.enumerateAudioOutputDevices();
      expect(outputDevices, isNotEmpty,
          reason:
              '少なくとも 1 件以上の音声出力デバイス（スピーカー）が存在すること。'
              'Windows 実機にスピーカーが接続されていることを確認してください。');

      for (final device in outputDevices) {
        expect(device.deviceId, isNotEmpty,
            reason:
                '各音声出力デバイスは空でない deviceId を持つこと。'
                'device.label=${device.label}');
        expect(device.label, isNotEmpty,
            reason:
                '各音声出力デバイスは空でない label を持つこと。'
                'device.deviceId=${device.deviceId}');
      }
    },
  );

  testWidgets(
    'windows_audio_device: 入力デバイス切り替えが成功することを確認する',
    (WidgetTester tester) async {
      if (!Platform.isWindows) {
        return;
      }

      final inputDevices = await MediaDevices.enumerateAudioInputDevices();
      expect(inputDevices, isNotEmpty,
          reason: '音声入力デバイスが存在しないため切り替えテストを実行できません。');

      // 先頭のデバイスを指定して audio track を生成する
      // これにより setAudioInputDevice → ADM SetRecordingDevice のパスが通る
      await MediaDevices.createAudioTrack(
        audioDeviceId: inputDevices.first.deviceId,
      );

      // createAudioTrack が例外を投げなければ成功とする
    },
  );
}
