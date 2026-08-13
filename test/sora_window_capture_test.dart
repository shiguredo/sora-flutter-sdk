import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_error_code.dart';
import 'package:sora_sdk/src/sora_window_capture.dart';

void main() {
  group('SoraErrorCode.windowCaptureError', () {
    test('ウィンドウキャプチャ用のエラーコードが定義されている', () {
      expect(SoraErrorCode.windowCaptureError, 'window_capture_error');
      expect(
        SoraErrorCode.windowCaptureError,
        isNot(SoraErrorCode.cameraOpenError),
      );
    });

    test('原因種別ごとのエラーコードが定義されている', () {
      // ネイティブ側の FlutterError code と一致させる。
      expect(
        SoraErrorCode.windowCapturePermissionDenied,
        'screen_capture_permission_denied',
      );
      expect(
        SoraErrorCode.windowCaptureWindowNotFound,
        'window_capture_window_not_found',
      );
      expect(
        SoraErrorCode.windowCaptureStartFailed,
        'window_capture_start_failed',
      );
      expect(
        SoraErrorCode.windowCaptureStartCancelled,
        'window_capture_start_cancelled',
      );
    });
  });

  group('WindowCaptureSource', () {
    test('ウィンドウ識別子・タイトル・アプリケーション名を保持する', () {
      const source = WindowCaptureSource(
        id: '12345',
        title: 'Sora DevTools',
        applicationName: 'Sora DevTools',
      );
      expect(source.id, '12345');
      expect(source.title, 'Sora DevTools');
      expect(source.applicationName, 'Sora DevTools');
    });

    test('タイトルとアプリケーション名が空文字でも保持できる', () {
      const source = WindowCaptureSource(
        id: '67890',
        title: '',
        applicationName: '',
      );
      expect(source.id, '67890');
      expect(source.title, isEmpty);
      expect(source.applicationName, isEmpty);
    });
  });

  group('WindowCaptureOptions', () {
    test('デフォルト値は width / height / frameRate が null、showsCursor が true', () {
      const options = WindowCaptureOptions();
      expect(options.width, isNull);
      expect(options.height, isNull);
      expect(options.frameRate, isNull);
      expect(options.showsCursor, isTrue);
    });

    test('カスタム値を指定できる', () {
      const options = WindowCaptureOptions(
        width: 1280,
        height: 720,
        frameRate: 60,
        showsCursor: false,
      );
      expect(options.width, 1280);
      expect(options.height, 720);
      expect(options.frameRate, 60);
      expect(options.showsCursor, isFalse);
    });

    test('width だけを指定できる', () {
      const options = WindowCaptureOptions(width: 1920);
      expect(options.width, 1920);
      expect(options.height, isNull);
      expect(options.frameRate, isNull);
      expect(options.showsCursor, isTrue);
    });

    test('showsCursor だけを指定できる', () {
      const options = WindowCaptureOptions(showsCursor: false);
      expect(options.width, isNull);
      expect(options.height, isNull);
      expect(options.frameRate, isNull);
      expect(options.showsCursor, isFalse);
    });
  });
}
