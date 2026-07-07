// sender / receiver の 2 接続で local track の有効/無効切り替えを検証する E2E。
// video toggle と audio toggle は別 test case に分け、
// 切り替え前後で isVideoEnabled / isAudioEnabled と local track の enabled が
// 一致して変化すること、および getStats が切断なく取得できることを確認する。

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
    'local_media_toggle_video: setVideoEnabled の切り替えを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-toggle-video',
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
        audio: false,
        video: true,
        useAudioDevice: false,
        metadata: env.metadata,
      );

      final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);

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
          'stage=receiver_connect_start channelId=$channelId',
        );
        await receiver.connect();
        await receiver.waitUntilConnected(receiverConnectTimeout);
        receiver.throwIfHasErrors();

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId',
        );
        await sender.connect(stream);
        await sender.waitUntilConnected(senderConnectTimeout);
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_connected channelId=$channelId '
          'senderConnectionId=${sender.connectionId}',
        );

        // 接続確立後にフレーム投入を開始する。
        videoSource.start(videoTrack);
        await tester.pump(const Duration(seconds: 1));

        // toggle 前の状態を確認する。
        expect(
          sender.connection.isVideoEnabled,
          isTrue,
          reason: 'setVideoEnabled 呼び出し前は isVideoEnabled が true であること。',
        );
        expect(
          stream.currentVideoTrackOrNull?.enabled,
          isTrue,
          reason: 'setVideoEnabled 呼び出し前は local video track の enabled が '
              'true であること。',
        );

        // getStats で DTLS / ICE が成立していることを確認する。
        final statsBefore = await sender.connection.getStats();
        expect(statsBefore, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsBefore!),
          isTrue,
          reason: 'toggle 前の getStats に DTLS connected または ICE candidate-pair '
              'succeeded が含まれること。',
        );

        // setVideoEnabled(false) で無効化する。
        logE2eMessage(
          'stage=toggle_video_off channelId=$channelId',
        );
        sender.connection.setVideoEnabled(false);

        // pump で状態反映を待つ。
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          sender.connection.isVideoEnabled,
          isFalse,
          reason: 'setVideoEnabled(false) 後に isVideoEnabled が false であること。',
        );
        expect(
          stream.currentVideoTrackOrNull?.enabled,
          isFalse,
          reason: 'setVideoEnabled(false) 後に local video track の enabled が '
              'false であること。',
        );

        // 切断していないことを getStats で確認する。
        final statsAfterOff = await sender.connection.getStats();
        expect(statsAfterOff, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsAfterOff!),
          isTrue,
          reason: 'toggle off 後の getStats にも DTLS connected または ICE '
              'candidate-pair succeeded が含まれること。',
        );

        // setVideoEnabled(true) で再有効化する。
        logE2eMessage(
          'stage=toggle_video_on channelId=$channelId',
        );
        sender.connection.setVideoEnabled(true);

        await tester.pump(const Duration(milliseconds: 500));

        expect(
          sender.connection.isVideoEnabled,
          isTrue,
          reason: 'setVideoEnabled(true) 後に isVideoEnabled が true であること。',
        );
        expect(
          stream.currentVideoTrackOrNull?.enabled,
          isTrue,
          reason: 'setVideoEnabled(true) 後に local video track の enabled が '
              'true であること。',
        );

        // 再度 getStats で切断していないことを確認する。
        final statsAfterOn = await sender.connection.getStats();
        expect(statsAfterOn, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsAfterOn!),
          isTrue,
          reason: 'toggle on 後の getStats にも DTLS connected または ICE '
              'candidate-pair succeeded が含まれること。',
        );

        logE2eMessage(
          'stage=toggle_video_completed channelId=$channelId',
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
          logE2eMessage(
            'stage=cleanup_error step=videoSource.stop error=$e',
          );
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

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed '
            'errors=${cleanupErrors.join(" | ")}',
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

  testWidgets(
    'local_media_toggle_audio: setAudioEnabled の切り替えを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-toggle-audio',
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
        video: false,
        metadata: env.metadata,
      );

      final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);

      ObservedConnection? sender;
      ObservedConnection? receiver;
      LocalMediaStream? stream;
      LocalAudioTrack? audioTrack;
      Object? bodyError;

      try {
        stream = MediaDevices.createMediaStream();

        audioTrack = await MediaDevices.createAudioTrack();
        stream.addTrack(audioTrack);

        receiver = await ObservedConnection.create(
          name: 'receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'sender',
          config: senderConfig,
        );

        logE2eMessage(
          'stage=receiver_connect_start channelId=$channelId',
        );
        await receiver.connect();
        await receiver.waitUntilConnected(receiverConnectTimeout);
        receiver.throwIfHasErrors();

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId',
        );
        await sender.connect(stream);
        await sender.waitUntilConnected(senderConnectTimeout);
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_connected channelId=$channelId '
          'senderConnectionId=${sender.connectionId}',
        );

        await tester.pump(const Duration(seconds: 1));

        // toggle 前の状態を確認する。
        expect(
          sender.connection.isAudioEnabled,
          isTrue,
          reason: 'setAudioEnabled 呼び出し前は isAudioEnabled が true であること。',
        );
        expect(
          stream.currentAudioTrackOrNull?.enabled,
          isTrue,
          reason: 'setAudioEnabled 呼び出し前は local audio track の enabled が '
              'true であること。',
        );

        // getStats で DTLS / ICE が成立していることを確認する。
        final statsBefore = await sender.connection.getStats();
        expect(statsBefore, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsBefore!),
          isTrue,
          reason: 'toggle 前の getStats に DTLS connected または ICE candidate-pair '
              'succeeded が含まれること。',
        );

        // setAudioEnabled(false) で無効化する。
        logE2eMessage(
          'stage=toggle_audio_off channelId=$channelId',
        );
        sender.connection.setAudioEnabled(false);

        await tester.pump(const Duration(milliseconds: 500));

        expect(
          sender.connection.isAudioEnabled,
          isFalse,
          reason: 'setAudioEnabled(false) 後に isAudioEnabled が false であること。',
        );
        expect(
          stream.currentAudioTrackOrNull?.enabled,
          isFalse,
          reason: 'setAudioEnabled(false) 後に local audio track の enabled が '
              'false であること。',
        );

        // 切断していないことを getStats で確認する。
        final statsAfterOff = await sender.connection.getStats();
        expect(statsAfterOff, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsAfterOff!),
          isTrue,
          reason: 'toggle off 後の getStats にも DTLS connected または ICE '
              'candidate-pair succeeded が含まれること。',
        );

        // setAudioEnabled(true) で再有効化する。
        logE2eMessage(
          'stage=toggle_audio_on channelId=$channelId',
        );
        sender.connection.setAudioEnabled(true);

        await tester.pump(const Duration(milliseconds: 500));

        expect(
          sender.connection.isAudioEnabled,
          isTrue,
          reason: 'setAudioEnabled(true) 後に isAudioEnabled が true であること。',
        );
        expect(
          stream.currentAudioTrackOrNull?.enabled,
          isTrue,
          reason: 'setAudioEnabled(true) 後に local audio track の enabled が '
              'true であること。',
        );

        // 再度 getStats で切断していないことを確認する。
        final statsAfterOn = await sender.connection.getStats();
        expect(statsAfterOn, isNotNull);
        expect(
          statsJsonSuggestsMediaPathUp(statsAfterOn!),
          isTrue,
          reason: 'toggle on 後の getStats にも DTLS connected または ICE '
              'candidate-pair succeeded が含まれること。',
        );

        logE2eMessage(
          'stage=toggle_audio_completed channelId=$channelId',
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
          'audioTrack.dispose',
          () async => await audioTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed '
            'errors=${cleanupErrors.join(" | ")}',
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
