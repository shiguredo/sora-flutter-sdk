// sender / receiver の 2 接続で remoteMediaStreams の grouping を検証する E2E。
// connectionId ごとに audioTrack / videoTrack が束ねられること、
// オブジェクト同一性が維持されること、切断後に map から消えることを確認する。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'remote_media_stream: remoteMediaStreams の grouping を検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-rms',
      );

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
        audio: true,
        useAudioDevice: false,
        video: true,
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
      LocalAudioTrack? audioTrack;
      LocalVideoTrack? videoTrack;
      ColorBarVideoSource? videoSource;
      Object? bodyError;

      try {
        stream = MediaDevices.createMediaStream();

        audioTrack = await MediaDevices.createAudioTrack();
        stream.addTrack(audioTrack);

        videoTrack = MediaDevices.createExternalVideoTrack();
        stream.addTrack(videoTrack);
        videoSource = ColorBarVideoSource(
          width: 320,
          height: 180,
          frameRate: 30,
        );

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

        // sender の接続完了後にフレーム投入を開始する。
        videoSource.start(videoTrack);
        await tester.pump(const Duration(seconds: 1));

        // ---------------------------------------------------------------
        // Phase 1: remoteMediaStreams に sender.connectionId のエントリが
        //          生成されるのを確認する。audio/video の到着順は問わない。
        // ---------------------------------------------------------------
        final streamBeforeBoth = await receiver.waitForRemoteMediaStreamEntry(
          tester,
          connectionId: senderConnectionId!,
          timeout: receiverTrackTimeout,
        );
        logE2eMessage(
          'stage=phase1 entry_created '
          'connectionId=${streamBeforeBoth.connectionId} '
          'hasAudio=${streamBeforeBoth.audioTrack != null} '
          'hasVideo=${streamBeforeBoth.videoTrack != null}',
        );

        // ---------------------------------------------------------------
        // Phase 2: audioTrack と videoTrack の両方がそろうのを待ち、
        //          同一オブジェクトに束ねられ、到着前後でインスタンス
        //          同一性が維持されていることを確認する。
        // ---------------------------------------------------------------
        final streamAfterBoth =
            await receiver.waitForRemoteMediaStreamBothTracks(
          tester,
          connectionId: senderConnectionId,
          timeout: receiverTrackTimeout,
        );
        expect(
          identical(streamBeforeBoth, streamAfterBoth),
          isTrue,
          reason: 'audio/video 到着前後で RemoteMediaStream の Dart オブジェクト'
              '同一性が維持されていること。',
        );

        expect(
          streamAfterBoth.audioTrack,
          isNotNull,
          reason: 'RemoteMediaStream に audioTrack が設定されていること。',
        );
        expect(
          streamAfterBoth.videoTrack,
          isNotNull,
          reason: 'RemoteMediaStream に videoTrack が設定されていること。',
        );
        expect(
          streamAfterBoth.audioTrack!.kind,
          'audio',
          reason: 'audioTrack の kind が audio であること。',
        );
        expect(
          streamAfterBoth.videoTrack!.kind,
          'video',
          reason: 'videoTrack の kind が video であること。',
        );
        expect(
          streamAfterBoth.audioTrack!.connectionId,
          senderConnectionId,
          reason: 'audioTrack の connectionId が sender の connectionId と一致すること。',
        );
        expect(
          streamAfterBoth.videoTrack!.connectionId,
          senderConnectionId,
          reason: 'videoTrack の connectionId が sender の connectionId と一致すること。',
        );

        logE2eMessage(
          'stage=phase2 both_tracks_ready '
          'audioTrackId=${streamAfterBoth.audioTrack!.trackId} '
          'videoTrackId=${streamAfterBoth.videoTrack!.trackId}',
        );

        // ---------------------------------------------------------------
        // Phase 3: sender 切断後に remoteMediaStreams から当該エントリが
        //          削除されることを確認する。
        // ---------------------------------------------------------------
        logE2eMessage(
          'stage=sender_disconnect_start channelId=$channelId',
        );
        await sender.disconnect();
        await sender.waitUntilDisconnected(senderDisconnectTimeout);
        logE2eMessage(
          'stage=sender_disconnected channelId=$channelId',
        );

        await receiver.waitForRemoteMediaStreamRemoved(
          tester,
          connectionId: senderConnectionId,
          timeout: receiverRemoveTimeout,
        );
        expect(
          receiver.connection.remoteMediaStreams
              .containsKey(senderConnectionId),
          isFalse,
          reason: 'sender 切断後に remoteMediaStreams から当該エントリが'
              '削除されていること。',
        );
        logE2eMessage(
          'stage=phase3 entry_removed channelId=$channelId',
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
        await runCleanupStep(
          'audioTrack.dispose',
          () async => await audioTrack?.dispose(),
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
