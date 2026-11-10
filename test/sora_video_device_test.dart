import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_video_device.dart';

void main() {
  group('VideoInputFormat', () {
    test('maxFrameRate は int 型で保持される', () {
      // GetUserMediaOptions.videoFrameRate と同じ int 型であることを確認する。
      const format = VideoInputFormat(
        width: 1280,
        height: 720,
        maxFrameRate: 30,
      );

      expect(format.maxFrameRate, 30);
      expect(format.maxFrameRate, isA<int>());
    });

    test('toString は解像度と fps を返す', () {
      const format = VideoInputFormat(
        width: 1280,
        height: 720,
        maxFrameRate: 30,
      );

      expect(format.toString(), '1280x720 @30fps');
    });
  });
}
