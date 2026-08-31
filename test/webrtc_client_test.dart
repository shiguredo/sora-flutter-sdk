import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/library_loader.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';

import 'support/ffi_test_environment.dart';

void main() {
  final ffiTestEnvironment = prepareFfiTestEnvironment();

  group('getStats cleanup on disconnect', () {
    test(
      'closePeerConnection completes pending getStats Future with StateError',
      () {
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
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      try {
        // getStats 実行中を模擬
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer);
        // closePeerConnection が発火する completeError(StateError) を吸収し、
        // unhandled error にしない。本 test は tracking のクリアだけを検証
        // するため future 自体は待たない。
        unawaited(
          completer.future.catchError(
            (_) => null,
            test: (e) => e is StateError,
          ),
        );

        wc.closePeerConnection();

        // 追跡状態がクリア済み
        expect(wc.cleanupPendingStatsRequest(), isNull);
        expect(wc.hasPendingStatsRequestForTest, false);
      } finally {
        wc.dispose();
      }
    });

    test('closePeerConnection は native stats リソースを孤立 request へ移す', () {
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      final cbsPtr = calloc<RTCStatsCollectorCallbackCbs>();
      try {
        // native callback 未到達の getStats 実行中を模擬する。
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer, cbsPtr: cbsPtr);
        // closePeerConnection が発火する completeError(StateError) を吸収し、
        // unhandled error にしない。本 test は孤立 request への移送と
        // completer / timer の完了だけを検証するため future 自体は待たない。
        unawaited(
          completer.future.catchError(
            (_) => null,
            test: (e) => e is StateError,
          ),
        );

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
  }, skip: ffiTestEnvironment.skipReason);

  group('getStats reentrancy', () {
    test('returns pending future when completer is already set', () {
      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      try {
        final completer = Completer<String?>();
        final timer = Timer(const Duration(seconds: 30), () {});
        wc.setupPendingStatsForTest(completer, timer);
        // finally 節の wc.dispose() が closePeerConnection 経由で
        // completeError(StateError) を発火するため、future を listen して
        // unhandled error 化を防ぐ。identity 比較の主張は影響を受けない。
        unawaited(
          completer.future.catchError(
            (_) => null,
            test: (e) => e is StateError,
          ),
        );

        // StateError ではなく、進行中の future が返ることを確認
        final result = wc.getStats();
        expect(result, same(completer.future));
      } finally {
        wc.dispose();
      }
    });

    test('孤立 native リソースをアクティブな request として保持しない', () {
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
  }, skip: ffiTestEnvironment.skipReason);

  group('PeerConnection state change のイベント変換', () {
    late WebrtcConstants consts;

    setUpAll(() {
      consts = WebrtcConstants(loadLibWebrtcC());
    });

    // 指定 state を注入し、受信した state_changed イベントを 1 件だけ返す。
    Map<String, Object?> stateChangedOn(int state) {
      final events = <(String, Map<String, Object?>)>[];
      final wc = WebrtcClient.create(
        config: {},
        onEvent: (type, data) {
          events.add((type, data));
        },
      );
      try {
        wc.handleConnectionChangeForTest(state);
      } finally {
        wc.dispose();
      }
      final stateChanged = events
          .where((e) => e.$1 == 'state_changed')
          .map((e) => e.$2)
          .toList();
      expect(stateChanged, hasLength(1));
      return stateChanged.single;
    }

    test('failed は disconnected + peer_connection_failed へ変換される', () {
      final event = stateChangedOn(consts.pcStateFailed);
      expect(event['state'], 'disconnected');
      expect(event['reason'], 'peer_connection_failed');
    });

    test('closed は disconnected + peer_connection_closed へ変換される', () {
      final event = stateChangedOn(consts.pcStateClosed);
      expect(event['state'], 'disconnected');
      expect(event['reason'], 'peer_connection_closed');
    });
  }, skip: ffiTestEnvironment.skipReason);

  group('DataChannel state change のイベント変換', () {
    late WebrtcConstants consts;

    setUpAll(() {
      consts = WebrtcConstants(loadLibWebrtcC());
    });

    // 指定 state を注入し、受信した指定 type のイベントを 1 件だけ返す。
    Map<String, Object?> dcEventOn(String type, int state) {
      final events = <(String, Map<String, Object?>)>[];
      final wc = WebrtcClient.create(
        config: {},
        onEvent: (eventType, data) {
          events.add((eventType, data));
        },
      );
      try {
        wc.notifyDataChannelStateForTest(state, 'signaling');
      } finally {
        wc.dispose();
      }
      final matched = events
          .where((e) => e.$1 == type)
          .map((e) => e.$2)
          .toList();
      expect(matched, hasLength(1));
      return matched.single;
    }

    test('closing は data_channel_closing へ変換される', () {
      final event = dcEventOn('data_channel_closing', consts.dcStateClosing);
      expect(event['label'], 'signaling');
    });

    test('closed は data_channel_closed へ変換される', () {
      final event = dcEventOn('data_channel_closed', consts.dcStateClosed);
      expect(event['label'], 'signaling');
    });

    test('open は data_channel_open へ変換される', () {
      final event = dcEventOn('data_channel_open', consts.dcStateOpen);
      expect(event['label'], 'signaling');
    });
  }, skip: ffiTestEnvironment.skipReason);
}
