// 同じ SoraConnection を使った再接続と、並列 disconnect を検証する E2E。
// セッション世代の更新、状態リセット、native PeerConnection の再生成を通す。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connection_lifecycle: 同一オブジェクトで再接続し並列切断できることを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: buildChannelId(
          env.channelPrefix,
          suffix: '-connection-lifecycle',
        ),
        role: SoraRole.recvonly,
        useAudioDevice: false,
        metadata: env.metadata,
      );
      final timeout = connectionStageTimeout(config);

      SoraConnection? connection;
      StreamSubscription<SoraConnectionEvent>? subscription;
      final recorder = _ConnectionStateRecorder();
      var finalDisconnectCompleted = false;
      Object? bodyError;

      try {
        connection = await Sora.createConnection(config);
        subscription = connection.events.listen(recorder.handle);

        // 1 回目の接続と切断で、セッション固有状態が初期化されることを確認する。
        await connection.connect();
        await recorder.waitForConnectedCount(tester,
            expected: 1, timeout: timeout);
        final firstConnectionId = connection.connectionId;
        expect(firstConnectionId, isNotNull);

        final firstStats = await connection.getStats();
        expect(firstStats, isNotNull);
        expect(statsJsonSuggestsMediaPathUp(firstStats!), isTrue);

        await connection.disconnect();
        await recorder.waitForDisconnectedCount(
          tester,
          expected: 1,
          timeout: timeout,
        );
        expect(
          connection.connectionId,
          isNull,
          reason: '切断後に前セッションの connectionId が残らないこと。',
        );

        // 同じ Dart / native client を再利用して 2 回目の接続を確立する。
        await connection.connect();
        await recorder.waitForConnectedCount(tester,
            expected: 2, timeout: timeout);
        final secondConnectionId = connection.connectionId;
        expect(
          secondConnectionId,
          isNotNull,
          reason: '再接続後のセッションに connectionId が割り当てられること。',
        );

        final secondStats = await connection.getStats();
        expect(secondStats, isNotNull);
        expect(statsJsonSuggestsMediaPathUp(secondStats!), isTrue);

        // 2 つの disconnect が同じ進行中処理を共有し、双方とも完了することを確認する。
        await Future.wait<void>(<Future<void>>[
          connection.disconnect(),
          connection.disconnect(),
        ]);
        await recorder.waitForDisconnectedCount(
          tester,
          expected: 2,
          timeout: timeout,
        );
        finalDisconnectCompleted = true;

        await tester.pump(const Duration(seconds: 1));
        expect(
          recorder.connectedCount,
          2,
          reason: '各セッションで connected が 1 回ずつ発火すること。',
        );
        expect(
          recorder.disconnectedCount,
          2,
          reason: '並列 disconnect で disconnected が重複しないこと。',
        );
        expect(recorder.errors, isEmpty);
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        if (!finalDisconnectCompleted) {
          await runCleanupStep(
            cleanupErrors,
            'connection.disconnect',
            () async => connection?.disconnect(),
          );
        }
        await runCleanupStep(
          cleanupErrors,
          'subscription.cancel',
          () async => subscription?.cancel(),
        );
        await runCleanupStep(
          cleanupErrors,
          'connection.dispose',
          () async => connection?.dispose(),
        );

        if (cleanupErrors.isNotEmpty && bodyError == null) {
          throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
        }
      }
    },
  );
}

/// 複数セッションにまたがる接続状態イベントを記録し、指定回数まで待つ。
final class _ConnectionStateRecorder {
  final List<SoraConnectionErrorEvent> errors = <SoraConnectionErrorEvent>[];
  var connectedCount = 0;
  var disconnectedCount = 0;

  void handle(SoraConnectionEvent event) {
    if (event is SoraConnectionErrorEvent) {
      errors.add(event);
      return;
    }
    if (event is! SoraConnectionStateChangedEvent) {
      return;
    }
    if (event.state is SoraConnectedState) {
      connectedCount++;
    } else if (event.state is SoraDisconnectedState) {
      disconnectedCount++;
    }
  }

  Future<void> waitForConnectedCount(
    WidgetTester tester, {
    required int expected,
    required Duration timeout,
  }) {
    return _waitForCount(
      tester,
      expected: expected,
      timeout: timeout,
      current: () => connectedCount,
      label: 'connected',
    );
  }

  Future<void> waitForDisconnectedCount(
    WidgetTester tester, {
    required int expected,
    required Duration timeout,
  }) {
    return _waitForCount(
      tester,
      expected: expected,
      timeout: timeout,
      current: () => disconnectedCount,
      label: 'disconnected',
    );
  }

  Future<void> _waitForCount(
    WidgetTester tester, {
    required int expected,
    required Duration timeout,
    required int Function() current,
    required String label,
  }) async {
    const interval = Duration(milliseconds: 100);
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (errors.isNotEmpty) {
        throw StateError(
          '接続エラーを検出しました: '
          '${errors.map((e) => '${e.code}:${e.message}').join(', ')}',
        );
      }
      if (current() >= expected) {
        return;
      }
      await tester.pump(interval);
    }
    throw StateError(
      '$label の待機がタイムアウトしました: '
      'expected=$expected actual=${current()}',
    );
  }
}
