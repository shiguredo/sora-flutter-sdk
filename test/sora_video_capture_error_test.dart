import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_video_capture_error.dart';

void main() {
  // `screenCapturePlatformErrorCode` は純粋関数として抽出されており、
  // `PlatformException` の実インスタンスを直接渡して分類ロジックを検証する。
  // モックやスタブは使わない。
  group('screenCapturePlatformErrorCode', () {
    test('PlatformException なら code を返す', () {
      final error = PlatformException(
        code: 'ReplayKit_User_Declined',
        message: 'user declined the recording',
      );
      expect(screenCapturePlatformErrorCode(error), 'ReplayKit_User_Declined');
    });

    test(
      'PlatformException 以外は screen_capture_error にフォールバックする (StateError)',
      () {
        // `_applyVideoCaptureBackend` 内で throw する `StateError` (video track が
        // dispose 済みになった場合) が経由するフォールバック分岐を検証する。
        expect(
          screenCapturePlatformErrorCode(StateError('unexpected teardown')),
          'screen_capture_error',
        );
      },
    );

    test(
      'PlatformException 以外は screen_capture_error にフォールバックする (Exception)',
      () {
        expect(
          screenCapturePlatformErrorCode(Exception('generic')),
          'screen_capture_error',
        );
      },
    );

    test('PlatformException 以外は screen_capture_error にフォールバックする (String)', () {
      // Object 型で受け取るため、非例外オブジェクトも通過する。ここでは文字列を
      // 渡してフォールバックが `is PlatformException` の false 判定で動くこと
      // を確認する。
      expect(
        screenCapturePlatformErrorCode('string-error'),
        'screen_capture_error',
      );
    });

    test('PlatformException.code が空文字列でもそのまま返す', () {
      // 空文字列を既定値 (`screen_capture_error`) に置き換えてしまうと、
      // caller 側で「空 code のプラットフォーム例外」と「非 PlatformException」
      // を区別できなくなる。code の値そのものを返して呼び出し元の判断に
      // 委ねる。
      final error = PlatformException(code: '');
      expect(screenCapturePlatformErrorCode(error), '');
    });
  });
}
