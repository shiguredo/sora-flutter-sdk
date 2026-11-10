// 2 つの sendrecv 接続が、同時に映像を送信・受信できることを検証する E2E。
// 単一接続の送信確認では通らない sendrecv の受信トランシーバーと、
// 双方向の remote track / RTP 統計をまとめて確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'sendrecv_bidirectional: 双方が映像を送受信できることを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-sendrecv-bidirectional',
      );

      SoraConnectionConfig createConfig() {
        return SoraConnectionConfig(
          signalingUrls: env.signalingUrls,
          channelId: channelId,
          role: SoraRole.sendrecv,
          audio: false,
          video: true,
          useAudioDevice: false,
          metadata: env.metadata,
        );
      }

      final firstConfig = createConfig();
      final secondConfig = createConfig();
      final firstTimeout = connectionStageTimeout(firstConfig);
      final secondTimeout = connectionStageTimeout(secondConfig);
      const remoteTrackTimeout = Duration(seconds: 30);

      ObservedConnection? first;
      ObservedConnection? second;
      LocalMediaStream? firstStream;
      LocalMediaStream? secondStream;
      LocalVideoTrack? firstVideoTrack;
      LocalVideoTrack? secondVideoTrack;
      ColorBarVideoSource? firstVideoSource;
      ColorBarVideoSource? secondVideoSource;
      Object? bodyError;

      try {
        first = await ObservedConnection.create(
          name: 'first-sendrecv',
          config: firstConfig,
        );
        second = await ObservedConnection.create(
          name: 'second-sendrecv',
          config: secondConfig,
        );

        firstStream = MediaDevices.createMediaStream();
        firstVideoTrack = MediaDevices.createExternalVideoTrack();
        firstStream.addTrack(firstVideoTrack);
        firstVideoSource = ColorBarVideoSource(
          width: 320,
          height: 180,
          frameRate: 30,
        );

        secondStream = MediaDevices.createMediaStream();
        secondVideoTrack = MediaDevices.createExternalVideoTrack();
        secondStream.addTrack(secondVideoTrack);
        secondVideoSource = ColorBarVideoSource(
          width: 640,
          height: 360,
          frameRate: 24,
        );

        await first.connect(firstStream);
        await first.waitUntilConnected(firstTimeout);
        first.throwIfHasErrors();
        firstVideoSource.start(firstVideoTrack);

        await second.connect(secondStream);
        await second.waitUntilConnected(secondTimeout);
        second.throwIfHasErrors();
        secondVideoSource.start(secondVideoTrack);
        await tester.pump(const Duration(seconds: 1));

        final firstConnectionId = first.connectionId;
        final secondConnectionId = second.connectionId;
        expect(
          firstConnectionId,
          isNotNull,
          reason: '1 接続目の connectionId が確定していること。',
        );
        expect(
          secondConnectionId,
          isNotNull,
          reason: '2 接続目の connectionId が確定していること。',
        );

        final trackFromSecond = await first.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: secondConnectionId!,
          timeout: remoteTrackTimeout,
        );
        final trackFromFirst = await second.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: firstConnectionId!,
          timeout: remoteTrackTimeout,
        );
        expect(trackFromSecond.kind, 'video');
        expect(trackFromFirst.kind, 'video');

        final firstOutboundBefore = await waitForVideoOutboundStats(
          tester,
          first.connection,
        );
        final firstInboundBefore = await waitForVideoInboundStats(
          tester,
          first.connection,
        );
        final secondOutboundBefore = await waitForVideoOutboundStats(
          tester,
          second.connection,
        );
        final secondInboundBefore = await waitForVideoInboundStats(
          tester,
          second.connection,
        );

        final firstOutboundAfter = await waitForVideoOutboundStats(
          tester,
          first.connection,
          previous: firstOutboundBefore,
        );
        final firstInboundAfter = await waitForVideoInboundStats(
          tester,
          first.connection,
          previous: firstInboundBefore,
        );
        final secondOutboundAfter = await waitForVideoOutboundStats(
          tester,
          second.connection,
          previous: secondOutboundBefore,
        );
        final secondInboundAfter = await waitForVideoInboundStats(
          tester,
          second.connection,
          previous: secondInboundBefore,
        );

        expect(
          firstOutboundAfter.bytesSent,
          greaterThan(firstOutboundBefore.bytesSent),
          reason: '1 接続目の映像送信量が増加すること。',
        );
        expect(
          firstInboundAfter.bytesReceived,
          greaterThan(firstInboundBefore.bytesReceived),
          reason: '1 接続目の映像受信量が増加すること。',
        );
        expect(
          secondOutboundAfter.bytesSent,
          greaterThan(secondOutboundBefore.bytesSent),
          reason: '2 接続目の映像送信量が増加すること。',
        );
        expect(
          secondInboundAfter.bytesReceived,
          greaterThan(secondInboundBefore.bytesReceived),
          reason: '2 接続目の映像受信量が増加すること。',
        );

        expect(
          first.connection.remoteMediaStreams[secondConnectionId]?.videoTrack,
          isNotNull,
          reason: '1 接続目が 2 接続目の remote video track を保持すること。',
        );
        expect(
          second.connection.remoteMediaStreams[firstConnectionId]?.videoTrack,
          isNotNull,
          reason: '2 接続目が 1 接続目の remote video track を保持すること。',
        );
        first.throwIfHasErrors();
        second.throwIfHasErrors();
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        firstVideoSource?.stop();
        secondVideoSource?.stop();

        await runCleanupStep(cleanupErrors, 'first.disconnect', () async {
          if (first != null) {
            await first.disconnect();
            await first!.waitUntilDisconnected(firstTimeout);
          }
        });
        await runCleanupStep(cleanupErrors, 'second.disconnect', () async {
          if (second != null) {
            await second.disconnect();
            await second!.waitUntilDisconnected(secondTimeout);
          }
        });
        await runCleanupStep(
          cleanupErrors,
          'first.dispose',
          () async => first?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'second.dispose',
          () async => second?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'firstStream.dispose',
          () async => firstStream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'secondStream.dispose',
          () async => secondStream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'firstVideoTrack.dispose',
          () async => firstVideoTrack?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'secondVideoTrack.dispose',
          () async => secondVideoTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty && bodyError == null) {
          throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
        }
      }
    },
  );
}
