// signalingNotifyMetadata を含む接続で connection.created notify を検証する E2E。
// sender 側に設定した signalingNotifyMetadata が receiver 側で受信した
// connection.created notify の authn_metadata または
// signaling_notify_metadata に含まれることを確認する。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // signalingNotifyMetadata に設定するテスト用の値。
  const testNotifyMetadataKey = 'e2e_test_key';
  const testNotifyMetadataValue = 'e2e_test_value';
  const pushWaitTimeout = Duration(seconds: 30);

  testWidgets(
    'notify_metadata: signalingNotifyMetadata が connection.created notify '
    'の payload に含まれることを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId =
          buildChannelId(env.channelPrefix, suffix: '-notifymetadata');

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
        signalingNotifyMetadata: <String, Object?>{
          testNotifyMetadataKey: testNotifyMetadataValue,
        },
      );

      final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);
      const receiverNotifyTimeout = Duration(seconds: 30);

      // push 検証は環境変数 TEST_PUSH_EXPECTED_TYPE が設定されている場合のみ実施する。
      final pushExpectedType =
          Platform.environment['TEST_PUSH_EXPECTED_TYPE']?.trim();

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

        // receiver 側で sender 由来の connection.created notify を待つ。
        final notifyPayload = await receiver.waitForNotifyCreatedEvent(
          tester,
          connectionId: senderConnectionId!,
          timeout: receiverNotifyTimeout,
        );
        logE2eMessage(
          'stage=receiver_notify_created channelId=$channelId '
          'connectionId=$senderConnectionId '
          'event_type=${notifyPayload['event_type']}',
        );

        // notify payload に authn_metadata または signaling_notify_metadata が
        // 含まれることを確認する。SDK は connect メッセージの
        // signaling_notify_metadata として送信するが、サーバー実装によって
        // notify  payload 上での key 名が異なるため両方を試す。
        var metadataMap =
            notifyPayload['authn_metadata'] as Map<String, Object?>?;
        metadataMap ??=
            notifyPayload['signaling_notify_metadata'] as Map<String, Object?>?;
        expect(
          metadataMap,
          isNotNull,
          reason: 'connection.created notify の payload に '
              'authn_metadata または signaling_notify_metadata が '
              '含まれていること。',
        );
        expect(
          metadataMap![testNotifyMetadataKey],
          testNotifyMetadataValue,
          reason: 'signalingNotifyMetadata に設定した key/value が '
              'notify payload に含まれていること。',
        );
        logE2eMessage(
          'stage=notify_metadata_verified '
          'key=$testNotifyMetadataKey '
          'value=$testNotifyMetadataValue',
        );

        // push 検証（環境変数 TEST_PUSH_EXPECTED_TYPE が設定されている場合のみ）
        if (pushExpectedType != null && pushExpectedType.isNotEmpty) {
          logE2eMessage(
            'stage=push_wait_start channelId=$channelId '
            'expectedType=$pushExpectedType',
          );
          // event_type で照合する。Sora サーバーの push メッセージは
          // event_type フィールドで種類を区別する。
          final pushPayload = await sender.waitForPushEvent(
            tester,
            timeout: pushWaitTimeout,
            predicate: (message) => message['event_type'] == pushExpectedType,
          );
          logE2eMessage(
            'stage=push_received channelId=$channelId '
            'event_type=${pushPayload['event_type']}',
          );
          expect(
            pushPayload['event_type'],
            pushExpectedType,
            reason: 'SoraPushEvent の event_type が TEST_PUSH_EXPECTED_TYPE '
                'と一致すること。',
          );
        } else {
          logE2eMessage(
            'stage=push_skipped '
            'reason=TEST_PUSH_EXPECTED_TYPE が未設定のため push 検証をスキップする',
          );
        }
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

        try {
          videoSource?.stop();
        } catch (e) {
          cleanupErrors.add('videoSource.stop: $e');
          logE2eMessage('stage=cleanup_error step=videoSource.stop error=$e');
        }
        await runCleanupStep(cleanupErrors, 'sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender.waitUntilDisconnected(senderDisconnectTimeout);
          }
        });
        await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver.waitUntilDisconnected(receiverDisconnectTimeout);
          }
        });
        await runCleanupStep(
          cleanupErrors,
          'receiver.dispose',
          () async => await receiver?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'sender.dispose',
          () async => await sender?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'stream.dispose',
          () async => await stream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
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
