// sender / receiver の 2 接続で remote track の追加と削除イベントを検証する E2E。
// stats や remoteMediaStreams の grouping は検証対象外。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'track_event: sender 接続後に SoraTrackEvent、切断後に '
    'SoraRemoveTrackEvent が届くことを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(env.channelPrefix);

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
      const receiverRemoveTimeout = Duration(seconds: 30);

      ObservedConnection? sender;
      ObservedConnection? receiver;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      ColorBarVideoSource? videoSource;
      Object? bodyError;

      try {
        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createExternalVideoTrack();
        stream.addTrack(videoTrack);
        videoSource =
            ColorBarVideoSource(width: 320, height: 180, frameRate: 30);

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

        // sender の接続完了後にフレーム投入を開始し、receiver の track event を待つ。
        videoSource.start(videoTrack);
        await tester.pump(const Duration(seconds: 1));

        final addObservation = await receiver.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: senderConnectionId!,
          timeout: receiverTrackTimeout,
        );
        logE2eMessage(
          'stage=receiver_track_added channelId=$channelId '
          'trackId=${addObservation.trackId} '
          'connectionId=${addObservation.connectionId}',
        );

        // 同一 track に対する SoraTrackEvent の重複発火がないことを確認するため、
        // 少し待機して receiver.trackEvents の最終状態を確定させる。
        await tester.pump(const Duration(seconds: 3));

        expect(
          addObservation.kind,
          'video',
          reason: 'sender 由来の track は kind=video であること。',
        );
        expect(
          addObservation.connectionId,
          senderConnectionId,
          reason:
              'SoraTrackEvent の connectionId が sender の connectionId と一致すること。',
        );
        expect(
          addObservation.trackId,
          isNotEmpty,
          reason: 'SoraTrackEvent の trackId が空文字列でないこと。',
        );

        // 同一 connection 由来の video track の SoraTrackEvent が 1 回だけ発火したことを確認する。
        final videoTrackEventsFromSender = receiver.trackEvents
            .where(
              (RemoteTrackObservation o) =>
                  o.kind == 'video' && o.connectionId == senderConnectionId,
            )
            .toList();
        expect(
          videoTrackEventsFromSender.length,
          1,
          reason:
              '同一 remote video track に対する SoraTrackEvent は 1 回だけ発火すること。',
        );

        // sender を切断し、receiver で SoraRemoveTrackEvent を待つ。
        logE2eMessage(
          'stage=sender_disconnect_start channelId=$channelId',
        );
        await sender.disconnect();
        await sender.waitUntilDisconnected(senderDisconnectTimeout);
        logE2eMessage(
          'stage=sender_disconnected channelId=$channelId',
        );

        // sender 切断後、receiver 側の subscription は生存したまま remove event を待つ。
        final removeObservation =
            await receiver.waitForRemoteVideoTrackRemoved(
          tester,
          remoteConnectionId: senderConnectionId,
          timeout: receiverRemoveTimeout,
        );
        logE2eMessage(
          'stage=receiver_track_removed channelId=$channelId '
          'trackId=${removeObservation.trackId} '
          'connectionId=${removeObservation.connectionId}',
        );

        // 同一 track に対する SoraRemoveTrackEvent の漏れがないことを確認するため、
        // 少し待機して receiver.removeTrackEvents の最終状態を確定させる。
        await tester.pump(const Duration(seconds: 3));

        expect(
          removeObservation.kind,
          'video',
          reason: '削除された track は kind=video であること。',
        );
        expect(
          removeObservation.connectionId,
          senderConnectionId,
          reason:
              'SoraRemoveTrackEvent の connectionId が sender の connectionId と一致すること。',
        );
        expect(
          removeObservation.trackId,
          isNotEmpty,
          reason: 'SoraRemoveTrackEvent の trackId が空文字列でないこと。',
        );
        expect(
          removeObservation.trackId,
          addObservation.trackId,
          reason:
              'SoraRemoveTrackEvent の trackId が SoraTrackEvent の trackId と一致すること。',
        );

        final videoRemoveEventsFromSender = receiver.removeTrackEvents
            .where(
              (RemoteTrackObservation o) =>
                  o.kind == 'video' && o.connectionId == senderConnectionId,
            )
            .toList();
        expect(
          videoRemoveEventsFromSender.length,
          1,
          reason:
              '同一 remote video track に対する SoraRemoveTrackEvent が漏れなく 1 回発火すること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        if (sender != null || receiver != null) {
          logE2eMessage(
            'stage=cleanup_start '
            'sender=${sender?.debugSummary()} '
            'receiver=${receiver?.debugSummary()}',
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
        await runCleanupStep('receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver.waitUntilDisconnected(receiverDisconnectTimeout);
          }
        });
        await runCleanupStep(
          'receiver.dispose',
          () async => await receiver?.dispose(),
        );
        await runCleanupStep(
          'sender.dispose',
          () async => await sender?.dispose(),
        );
        await runCleanupStep(
          'stream.dispose',
          () async => await stream?.dispose(),
        );
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
    },
  );
}
