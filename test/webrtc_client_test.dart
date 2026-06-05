import 'dart:async';
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/library_loader.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';

/// libwebrtc-c が利用可能か確認する。
bool _ffiAvailable() {
  try {
    final lib = LibWebrtcC(loadLibWebrtcC());
    final f = lib.createBuiltinVideoEncoderFactory();
    if (f != nullptr) {
      lib.videoEncoderFactoryUniqueDelete(f);
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

void main() {
  group('getStats cleanup on disconnect', () {
    late bool ffiAvailable;

    setUpAll(() {
      ffiAvailable = _ffiAvailable();
    });

    test(
      'closePeerConnection completes pending getStats Future with StateError',
      () {
        if (!ffiAvailable) return;
        final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
        try {
          // getStats 実行中を模擬
          final completer = Completer<String?>();
          final timer = Timer(const Duration(seconds: 30), () {});
          wc.setupPendingStatsForTest(completer, timer);

          // disconnect 相当の後始末
          wc.closePeerConnection();

          // completer が error 完了している
          expect(timer.isActive, false);
          expect(completer.isCompleted, true);
          expect(completer.future, throwsA(isA<StateError>()));
        } finally {
          wc.dispose();
        }
      },
    );

    test('closePeerConnection clears pending getStats tracking', () {
      if (!ffiAvailable) return;
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      try {
        // getStats 実行中を模擬
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer);

        wc.closePeerConnection();

        // 追跡状態がクリア済み
        expect(wc.cleanupPendingStatsRequest(), isNull);
      } finally {
        wc.dispose();
      }
    });
  });
}
