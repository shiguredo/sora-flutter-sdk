// messaging 専用接続 (audio: false / video: false) の E2E 。
// 単一接続で local stream なしの connect() / DataChannel open /
// remoteMediaStreams が空のままであることを確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // ネットワーク遅延や SDK 内部 buffer を考慮し、イベント不在確認前に
  // 3 秒の settle 時間を確保する。
  const settleDuration = Duration(seconds: 3);

  testWidgets(
    'messaging_only: メディアなし接続と DataChannel open を検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(env.channelPrefix, suffix: '-messaging');

      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: false,
        video: false,
        useAudioDevice: false,
        // DataChannel signaling を有効にしないと #messaging が成立しない。
        dataChannelSignaling: true,
        dataChannels: const [
          {'label': '#messaging', 'direction': 'sendrecv', 'compress': true},
        ],
        metadata: env.metadata,
      );

      final connectTimeout = connectionStageTimeout(config);
      final dataChannelTimeout = connectionStageTimeout(config);

      ObservedConnection? connection;
      Object? bodyError;

      try {
        connection = await ObservedConnection.create(
          name: 'messaging',
          config: config,
        );

        logE2eMessage(
          'stage=connect_start channelId=$channelId '
          'bundleId=${connection.connection.bundleId}',
        );
        // local stream なしで接続する。
        await connection.connect();
        await connection.waitUntilConnected(connectTimeout);
        connection.throwIfHasErrors();
        logE2eMessage(
          'stage=connected channelId=$channelId '
          'connectionId=${connection.connectionId}',
        );

        // DataChannel が open するまで待つ。
        final dcEvent = await connection.waitForDataChannelOpen(
          tester,
          label: '#messaging',
          timeout: dataChannelTimeout,
        );
        logE2eMessage(
          'stage=data_channel_open channelId=$channelId '
          'label=${dcEvent.label} '
          'direction=${dcEvent.direction} '
          'compress=${dcEvent.compress}',
        );

        expect(
          dcEvent.label,
          '#messaging',
          reason: 'open した DataChannel の label が #messaging であること。',
        );
        expect(
          dcEvent.direction,
          isNotNull,
          reason: 'open した DataChannel の direction が null でないこと。',
        );
        expect(
          dcEvent.direction,
          'sendrecv',
          reason: 'open した DataChannel の direction が sendrecv であること。',
        );

        // 接続完了後、remoteMediaStreams が空のままであることを確認する。
        expect(
          connection.connection.remoteMediaStreams,
          isEmpty,
          reason: 'messaging 専用接続では remoteMediaStreams が空であること。',
        );

        // settle 時間を確保し、track イベントが来ないことを確認する。
        await tester.pump(settleDuration);

        expect(
          connection.trackEvents,
          isEmpty,
          reason: 'messaging 専用接続では SoraTrackEvent が発火しないこと。',
        );
        expect(
          connection.removeTrackEvents,
          isEmpty,
          reason: 'messaging 専用接続では SoraRemoveTrackEvent が発火しないこと。',
        );

        logE2eMessage('stage=disconnect_start');
        await connection.disconnect();
        await connection.waitUntilDisconnected(connectTimeout);
        logE2eMessage('stage=disconnected');
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        if (connection != null) {
          logE2eMessage(
            'stage=cleanup_start ${connection.debugSummary()}',
          );
        }

        final cleanupErrors = <String>[];

        await runCleanupStep(cleanupErrors, 'connection.dispose', () async {
          await connection?.dispose();
        });

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed errors=${cleanupErrors.join(" | ")}',
          );
          if (bodyError == null) {
            throw StateError(
              'Cleanup failed: ${cleanupErrors.join(" | ")}',
            );
          }
        } else {
          logE2eMessage('stage=cleanup_finished status=ok');
        }
      }

      expect(
        connection.errors,
        isEmpty,
        reason: '接続エラーイベントが発生しないこと。',
      );
    },
  );
}
