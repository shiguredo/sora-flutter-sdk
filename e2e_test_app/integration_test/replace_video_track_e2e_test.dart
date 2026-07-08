// sender と receiver の 2 接続を立ち上げ、接続中に replaceVideoTrack で
// 映像トラックを差し替えても送信・受信の stats が継続増加することを検証する E2E。
// 併せて replace が SoraRemoveTrackEvent を不要に発火させないことを確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('replaceVideoTrack: 差し替え前後で送受信 stats が継続増加することを検証する', (
    WidgetTester tester,
  ) async {
    final env = loadE2eEnvironment();
    final channelId =
        buildChannelId(env.channelPrefix, suffix: '-replacevideotrack');

    final receiverConfig = SoraConnectionConfig(
      signalingUrls: env.signalingUrls,
      channelId: channelId,
      role: SoraRole.recvonly,
      useAudioDevice: false,
      metadata: env.metadata,
    );
    final senderConfig = SoraConnectionConfig(
      signalingUrls: env.signalingUrls,
      channelId: channelId,
      role: SoraRole.sendonly,
      video: true,
      audio: false,
      useAudioDevice: false,
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
    LocalVideoTrack? videoTrack1;
    LocalVideoTrack? videoTrack2;
    ColorBarVideoSource? videoSource1;
    ColorBarVideoSource? videoSource2;
    VideoOutboundStats? outboundBeforeReplace;
    VideoOutboundStats? outboundAfterReplace;
    VideoInboundStats? inboundBeforeReplace;
    VideoInboundStats? inboundAfterReplace;
    int removeTrackEventCountBeforeReplace = 0;
    Object? bodyError;

    try {
      receiver = await ObservedConnection.create(
        name: 'receiver',
        config: receiverConfig,
      );
      sender = await ObservedConnection.create(
        name: 'sender',
        config: senderConfig,
      );

      stream = MediaDevices.createMediaStream();
      videoTrack1 = MediaDevices.createExternalVideoTrack();
      stream.addTrack(videoTrack1);
      videoTrack2 = MediaDevices.createExternalVideoTrack();
      videoSource1 =
          ColorBarVideoSource(width: 320, height: 180, frameRate: 30);
      videoSource2 =
          ColorBarVideoSource(width: 320, height: 180, frameRate: 30);

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

      // sender の接続完了後に 1 本目のフレーム投入を開始し、受信待ちに入る。
      videoSource1.start(videoTrack1);
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
      expect(
        remoteTrack.kind,
        'video',
        reason: 'receiver で sender 由来の video track が 1 回到達すること。',
      );

      // replace 前に送受信 stats を取得し、removeTrackEvents の現在件数を記録する。
      outboundBeforeReplace =
          await waitForVideoOutboundStats(tester, sender.connection);
      inboundBeforeReplace =
          await waitForVideoInboundStats(tester, receiver.connection);
      removeTrackEventCountBeforeReplace = receiver.removeTrackEvents.length;
      sender.throwIfHasErrors();
      receiver.throwIfHasErrors();
      logE2eMessage(
        'stage=before_replace channelId=$channelId '
        'outbound=$outboundBeforeReplace inbound=$inboundBeforeReplace '
        'removeTrackEventCount=$removeTrackEventCountBeforeReplace',
      );

      // replaceVideoTrack を実行する。
      // replaceVideoTrack 内部で stream の track 差し替えが行われるため、
      // 事前に stream.addTrack(videoTrack2) を呼ぶ必要はない。
      // 差し替え後は古い videoSource1 を停止して新しい videoSource2 でフレーム投入を開始する。
      await sender.connection.replaceVideoTrack(stream, videoTrack2);
      videoSource1.stop();
      videoSource2.start(videoTrack2);
      await tester.pump(const Duration(seconds: 3));
      logE2eMessage(
        'stage=after_replace channelId=$channelId '
        'action=replaceVideoTrack completed',
      );

      // replace 後に送受信 stats が継続増加することを確認する。
      outboundAfterReplace = await waitForVideoOutboundStats(
        tester,
        sender.connection,
        previous: outboundBeforeReplace,
      );
      inboundAfterReplace = await waitForVideoInboundStats(
        tester,
        receiver.connection,
        previous: inboundBeforeReplace,
      );
      sender.throwIfHasErrors();
      receiver.throwIfHasErrors();
      logE2eMessage(
        'stage=after_stats channelId=$channelId '
        'outbound=$outboundAfterReplace inbound=$inboundAfterReplace',
      );

      expect(
        outboundBeforeReplace.bytesSent,
        greaterThan(0),
        reason: 'replace 前に video outbound-rtp の bytesSent が増えていること。',
      );
      expect(
        outboundBeforeReplace.packetsSent,
        greaterThan(0),
        reason: 'replace 前に video outbound-rtp の packetsSent が増えていること。',
      );
      expect(
        outboundAfterReplace.bytesSent,
        greaterThan(outboundBeforeReplace.bytesSent),
        reason: 'replace 後も video outbound-rtp の bytesSent が継続増加すること。',
      );
      expect(
        outboundAfterReplace.packetsSent,
        greaterThan(outboundBeforeReplace.packetsSent),
        reason: 'replace 後も video outbound-rtp の packetsSent が継続増加すること。',
      );

      expect(
        inboundBeforeReplace.bytesReceived,
        greaterThan(0),
        reason: 'replace 前に video inbound-rtp の bytesReceived が増えていること。',
      );
      expect(
        inboundBeforeReplace.packetsReceived,
        greaterThan(0),
        reason: 'replace 前に video inbound-rtp の packetsReceived が増えていること。',
      );
      expect(
        inboundAfterReplace.bytesReceived,
        greaterThan(inboundBeforeReplace.bytesReceived),
        reason: 'replace 後も video inbound-rtp の bytesReceived が継続増加すること。',
      );
      expect(
        inboundAfterReplace.packetsReceived,
        greaterThan(inboundBeforeReplace.packetsReceived),
        reason: 'replace 後も video inbound-rtp の packetsReceived が継続増加すること。',
      );

      // replace 実行だけで SoraRemoveTrackEvent が不要に発火しないことを確認する。
      expect(
        receiver.removeTrackEvents.length,
        removeTrackEventCountBeforeReplace,
        reason: 'replaceVideoTrack の実行前後で SoraRemoveTrackEvent の件数が'
            '増加しないこと。',
      );
      expect(
        receiver.removeTrackEvents.every(
          (e) => e.connectionId == senderConnectionId,
        ),
        isTrue,
        reason: 'removeTrackEvents が全て senderConnectionId 由来であること。',
      );

      // receiver 側の trackEvents 件数が replace 前後で変わらず、
      // remote track が作り直されていないことを補助確認する。
      expect(
        receiver.trackEvents.length,
        1,
        reason: 'replaceVideoTrack の実行前後で SoraTrackEvent の件数が'
            ' 1 件のまま増加しないこと（remote track が作り直されないこと）。',
      );
      expect(
        receiver.trackEvents.first.connectionId,
        senderConnectionId,
        reason: 'trackEvents が senderConnectionId 由来であること。',
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
          'outboundLast=$outboundAfterReplace '
          'inboundLast=$inboundAfterReplace',
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
        videoSource1?.stop();
      } catch (e) {
        cleanupErrors.add('videoSource1.stop: $e');
        logE2eMessage('stage=cleanup_error step=videoSource1.stop error=$e');
      }
      try {
        videoSource2?.stop();
      } catch (e) {
        cleanupErrors.add('videoSource2.stop: $e');
        logE2eMessage('stage=cleanup_error step=videoSource2.stop error=$e');
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
        'videoTrack1.dispose',
        () async => await videoTrack1?.dispose(),
      );
      await runCleanupStep(
        'videoTrack2.dispose',
        () async => await videoTrack2?.dispose(),
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
