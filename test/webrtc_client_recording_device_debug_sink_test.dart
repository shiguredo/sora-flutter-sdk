import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';

void main() {
  // 録音デバイスの切り替え失敗は `MediaDevices.createAudioTrack` が
  // デバイス不存在として握り潰すため、利用側は診断ログの出力先を設定して
  // 失敗の内容を受け取る。FFI を呼ばないためネイティブライブラリ無しで
  // 実行できる。
  group('recordingDeviceDebugSink', () {
    tearDown(() {
      // テスト間で出力先が残らないようにする。
      WebrtcClient.recordingDeviceDebugSink = null;
    });

    test('初期状態では出力先が未設定である', () {
      expect(WebrtcClient.recordingDeviceDebugSink, isNull);
    });

    test('公開 API で設定した出力先が WebrtcClient へ反映される', () {
      final messages = <String>[];
      MediaDevices.setRecordingDeviceDebugSink(messages.add);

      expect(WebrtcClient.recordingDeviceDebugSink, isNotNull);
      WebrtcClient.recordingDeviceDebugSink!('native: test message');
      expect(messages, <String>['native: test message']);
    });

    test('公開 API に null を渡すと出力を停止する', () {
      MediaDevices.setRecordingDeviceDebugSink((_) {});
      MediaDevices.setRecordingDeviceDebugSink(null);

      expect(WebrtcClient.recordingDeviceDebugSink, isNull);
    });
  });
}
