// sender / receiver の 2 接続を同時に立ち上げ、送信映像が相手に届くことを検証する E2E。
// track event の厳密な順序や remoteMediaStreams の grouping は未対応。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two-party: sender の映像が receiver に届くことを検証する', (
    WidgetTester tester,
  ) async {
    final env = loadE2eEnvironment();
    final channelId = buildChannelId(env.channelPrefix, suffix: '-twoparty');

    final receiverConfig = SoraConnectionConfig(
      signalingUrls: env.signalingUrls,
      channelId: channelId,
      role: SoraRole.recvonly,
      metadata: env.metadata,
    );
    final senderConfig = SoraConnectionConfig(
      signalingUrls: env.signalingUrls,
      channelId: channelId,
      role: SoraRole.sendonly,
      video: true,
      audio: false,
      metadata: env.metadata,
    );

    final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
    final senderConnectTimeout = connectionStageTimeout(senderConfig);
    final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
    final senderDisconnectTimeout = connectionStageTimeout(senderConfig);
    const receiverTrackTimeout = Duration(seconds: 30);

    ObservedConnection? sender;
    ObservedConnection? receiver;
    LocalMediaStream? stream;
    LocalVideoTrack? videoTrack;
    ColorBarVideoSource? videoSource;
    VideoOutboundStats? firstOutbound;
    VideoOutboundStats? secondOutbound;
    VideoInboundStats? firstInbound;
    VideoInboundStats? secondInbound;
    Object? bodyError;

    try {
      stream = MediaDevices.createMediaStream();
      videoTrack = MediaDevices.createExternalVideoTrack();
      stream.addTrack(videoTrack);
      videoSource = ColorBarVideoSource(width: 320, height: 180, frameRate: 30);

      receiver = await ObservedConnection.create(
        name: 'receiver',
        config: receiverConfig,
      );
      sender = await ObservedConnection.create(
        name: 'sender',
        config: senderConfig,
      );

      logE2eMessage(
        'stage=receiver_connect_start channelId=$channelId '
        'bundleId=${receiver.connection.bundleId}',
      );
      await receiver.connect();
      await receiver.waitUntilConnected(receiverConnectTimeout);
      receiver.throwIfHasErrors();
      logE2eMessage(
        'stage=receiver_connected channelId=$channelId '
        'receiverConnectionId=${receiver.connectionId}',
      );

      logE2eMessage(
        'stage=sender_connect_start channelId=$channelId '
        'bundleId=${sender.connection.bundleId}',
      );
      await sender.connect(stream);
      await sender.waitUntilConnected(senderConnectTimeout);
      sender.throwIfHasErrors();
      logE2eMessage(
        'stage=sender_connected channelId=$channelId '
        'senderConnectionId=${sender.connectionId}',
      );

      final senderConnectionId = sender.connectionId;
      expect(
        senderConnectionId,
        isNotNull,
        reason: 'sender connected 後に connectionId が確定していること。',
      );

      // sender の接続完了後にフレーム投入を開始し、受信待ちに入る。
      videoSource.start(videoTrack);
      await tester.pump(const Duration(seconds: 1));

      final remoteTrack = await receiver.waitForRemoteVideoTrackFrom(
        tester,
        remoteConnectionId: senderConnectionId!,
        timeout: receiverTrackTimeout,
      );
      logE2eMessage(
        'stage=receiver_track_ready channelId=$channelId '
        'trackId=${remoteTrack.trackId} remoteConnectionId=${remoteTrack.connectionId}',
      );

      firstOutbound =
          await waitForVideoOutboundStats(tester, sender.connection);
      secondOutbound = await waitForVideoOutboundStats(
        tester,
        sender.connection,
        previous: firstOutbound,
      );
      sender.throwIfHasErrors();
      logE2eMessage(
        'stage=sender_outbound_ready channelId=$channelId '
        'first=$firstOutbound second=$secondOutbound',
      );

      firstInbound =
          await waitForVideoInboundStats(tester, receiver.connection);
      secondInbound = await waitForVideoInboundStats(
        tester,
        receiver.connection,
        previous: firstInbound,
      );
      receiver.throwIfHasErrors();
      logE2eMessage(
        'stage=receiver_inbound_ready channelId=$channelId '
        'first=$firstInbound second=$secondInbound',
      );

      expect(
        firstOutbound.bytesSent,
        greaterThan(0),
        reason: 'sender 初回取得時に video outbound-rtp の bytesSent が増えていること。',
      );
      expect(
        firstOutbound.packetsSent,
        greaterThan(0),
        reason: 'sender 初回取得時に video outbound-rtp の packetsSent が増えていること。',
      );
      expect(
        secondOutbound.bytesSent,
        greaterThan(firstOutbound.bytesSent),
        reason: 'sender 2 回目取得時に video outbound-rtp の bytesSent が増えていること。',
      );
      expect(
        secondOutbound.packetsSent,
        greaterThan(firstOutbound.packetsSent),
        reason: 'sender 2 回目取得時に video outbound-rtp の packetsSent が増えていること。',
      );

      expect(
        firstInbound.bytesReceived,
        greaterThan(0),
        reason: 'receiver 初回取得時に video inbound-rtp の bytesReceived が増えていること。',
      );
      expect(
        firstInbound.packetsReceived,
        greaterThan(0),
        reason: 'receiver 初回取得時に video inbound-rtp の packetsReceived が増えていること。',
      );
      expect(
        secondInbound.bytesReceived,
        greaterThan(firstInbound.bytesReceived),
        reason: 'receiver 2 回目取得時に video inbound-rtp の bytesReceived が増えていること。',
      );
      expect(
        secondInbound.packetsReceived,
        greaterThan(firstInbound.packetsReceived),
        reason:
            'receiver 2 回目取得時に video inbound-rtp の packetsReceived が増えていること。',
      );

      final framesDecoded = secondInbound.framesDecoded;
      if (framesDecoded != null) {
        expect(
          framesDecoded,
          greaterThan(0),
          reason: 'framesDecoded が存在する場合は 0 より大きいこと。',
        );
      }

      final framesReceived = secondInbound.framesReceived;
      if (framesReceived != null) {
        expect(
          framesReceived,
          greaterThan(0),
          reason: 'framesReceived が存在する場合は 0 より大きいこと。',
        );
      }

      expect(
        remoteTrack.kind,
        'video',
        reason: 'receiver で sender 由来の video track が 1 回到達すること。',
      );
    } catch (e) {
      bodyError = e;
      rethrow;
    } finally {
      if (sender != null || receiver != null) {
        logE2eMessage(
          'stage=cleanup_start '
          'sender=${sender?.debugSummary()} '
          'receiver=${receiver?.debugSummary()} '
          'senderOutboundLast=$secondOutbound '
          'receiverInboundLast=$secondInbound',
        );
      }

      final cleanupErrors = <String>[];

      Future<void> runCleanupStep(
        String name,
        Future<void> Function() action,
      ) async {
        try {
          await action();
        } catch (e) {
          cleanupErrors.add('$name: $e');
          logE2eMessage('stage=cleanup_error step=$name error=$e');
        }
      }

      try {
        videoSource?.stop();
      } catch (e) {
        cleanupErrors.add('videoSource.stop: $e');
        logE2eMessage('stage=cleanup_error step=videoSource.stop error=$e');
      }
      await runCleanupStep('sender.disconnect', () async {
        if (sender != null) {
          await sender.disconnect();
          await sender.waitUntilDisconnected(senderDisconnectTimeout);
        }
      });
      await runCleanupStep('receiver.disconnect', () async {
        if (receiver != null) {
          await receiver.disconnect();
          await receiver.waitUntilDisconnected(receiverDisconnectTimeout);
        }
      });
      await runCleanupStep(
          'sender.dispose', () async => await sender?.dispose());
      await runCleanupStep(
        'receiver.dispose',
        () async => await receiver?.dispose(),
      );
      await runCleanupStep(
          'stream.dispose', () async => await stream?.dispose());
      await runCleanupStep(
        'videoTrack.dispose',
        () async => await videoTrack?.dispose(),
      );

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
      sender.errors,
      isEmpty,
      reason: 'sender で接続エラーイベントが発生しないこと。',
    );
    expect(
      receiver.errors,
      isEmpty,
      reason: 'receiver で接続エラーイベントが発生しないこと。',
    );
  });
}
