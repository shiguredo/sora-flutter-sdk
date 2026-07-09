import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
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
        expect(wc.hasPendingStatsRequestForTest, false);
      } finally {
        wc.dispose();
      }
    });

    test('closePeerConnection は native stats リソースを孤立 request へ移す', () {
      if (!ffiAvailable) return;
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      final cbsPtr = calloc<RTCStatsCollectorCallbackCbs>();
      try {
        // native callback 未到達の getStats 実行中を模擬する。
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer, cbsPtr: cbsPtr);

        wc.closePeerConnection();

        // Dart 側の待ち合わせは閉じるが、native リソースはアクティブな
        // request としては残さず、遅延 callback 待ちの孤立 request に移す。
        expect(timer.isActive, false);
        expect(completer.isCompleted, true);
        expect(wc.hasPendingStatsRequestForTest, false);
        expect(wc.orphanedStatsRequestCountForTest, 1);
      } finally {
        calloc.free(cbsPtr);
        wc.dispose();
      }
    });
  });

  group('getStats reentrancy', () {
    late bool ffiAvailable;

    setUpAll(() {
      ffiAvailable = _ffiAvailable();
    });

    test('returns pending future when completer is already set', () {
      if (!ffiAvailable) return;
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      try {
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer);

        // StateError ではなく、進行中の future が返ることを確認
        final result = wc.getStats();
        expect(result, same(completer.future));
      } finally {
        wc.dispose();
      }
    });

    test('孤立 native リソースをアクティブな request として保持しない', () {
      if (!ffiAvailable) return;
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      // cbsPtr を割り当てて native callback 未到達状態を模擬
      final cbsPtr = calloc<RTCStatsCollectorCallbackCbs>();
      try {
        wc.setupPendingStatsForTest(null, null, cbsPtr: cbsPtr);

        // native リソースだけが残った状態は孤立 request として保持し、
        // アクティブな request として後続の getStats を塞がない。
        expect(wc.hasPendingStatsRequestForTest, false);
        expect(wc.orphanedStatsRequestCountForTest, 1);

        // この test では PeerConnection 未生成のため null が返る。
        final result = wc.getStats();
        expect(result, completion(isNull));
      } finally {
        calloc.free(cbsPtr);
        wc.dispose();
      }
    });
  });
}
