// ユーザー定義 DataChannel (#test-channel) の open と送受信、および
// DataChannel signaling の switched イベントを検証する E2E 。
// 2 クライアント間で #test-channel の open を確認し、バイナリメッセージの
// 送受信が成功することを確認する。また、dataChannelSignaling 有効時に
// SoraSwitchedEvent が発火し、switched 後も signaling が継続することを確認する。

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'custom_data_channel: #test-channel の open とメッセージ送受信、'
        'SoraSwitchedEvent の発火を検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(env.channelPrefix, suffix: '-custom-dc');

      const testLabel = '#test-channel';
      // sender が送り、receiver が受信したことを確認するための固定 payload。
      final senderPayload = Uint8List.fromList(
        <int>[0x01, 0x02, 0x03, 0xFE, 0xFF],
      );

      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: false,
        video: false,
        dataChannelSignaling: true,
        dataChannels: const [
          {'label': testLabel, 'direction': 'sendrecv', 'compress': true},
        ],
        metadata: env.metadata,
      );
      final receiverConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: false,
        video: false,
        dataChannelSignaling: true,
        dataChannels: const [
          {'label': testLabel, 'direction': 'sendrecv', 'compress': true},
        ],
        metadata: env.metadata,
      );

      final senderTimeout = connectionStageTimeout(senderConfig);
      final receiverTimeout = connectionStageTimeout(receiverConfig);

      ObservedConnection? sender;
      ObservedConnection? receiver;
      Object? bodyError;

      try {
        // receiver を先に接続し、sender が後から join する。
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
        await receiver.waitUntilConnected(receiverTimeout);
        receiver.throwIfHasErrors();
        logE2eMessage(
          'stage=receiver_connected channelId=$channelId '
          'connectionId=${receiver.connectionId}',
        );

        // dataChannelSignaling 有効時に SoraSwitchedEvent が発火することを確認する。
        logE2eMessage('stage=receiver_wait_switched channelId=$channelId');
        await receiver.waitForSwitched(
          tester,
          timeout: receiverTimeout,
        );
        logE2eMessage('stage=receiver_switched channelId=$channelId');

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId '
          'bundleId=${sender.connection.bundleId}',
        );
        await sender.connect();
        await sender.waitUntilConnected(senderTimeout);
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_connected channelId=$channelId '
          'connectionId=${sender.connectionId}',
        );

        // sender 側でも SoraSwitchedEvent が発火することを確認する。
        logE2eMessage('stage=sender_wait_switched channelId=$channelId');
        await sender.waitForSwitched(
          tester,
          timeout: senderTimeout,
        );
        logE2eMessage('stage=sender_switched channelId=$channelId');

        // sender / receiver 双方で #test-channel の open を待つ。
        final senderDcEvent = await sender.waitForDataChannelOpen(
          tester,
          label: testLabel,
          timeout: senderTimeout,
        );
        logE2eMessage(
          'stage=sender_data_channel_open channelId=$channelId '
          'label=${senderDcEvent.label} '
          'compress=${senderDcEvent.compress}',
        );

        final receiverDcEvent = await receiver.waitForDataChannelOpen(
          tester,
          label: testLabel,
          timeout: receiverTimeout,
        );
        logE2eMessage(
          'stage=receiver_data_channel_open channelId=$channelId '
          'label=${receiverDcEvent.label} '
          'compress=${receiverDcEvent.compress}',
        );

        // 双方の open event で label / compress を検証する。
        expect(
          senderDcEvent.label,
          testLabel,
          reason: 'sender 側で open した DataChannel の label が '
              '$testLabel であること。',
        );
        expect(
          senderDcEvent.compress,
          isTrue,
          reason: 'sender 側で open した DataChannel の compress が '
              'true であること。',
        );
        expect(
          receiverDcEvent.label,
          testLabel,
          reason: 'receiver 側で open した DataChannel の label が '
              '$testLabel であること。',
        );
        expect(
          receiverDcEvent.compress,
          isTrue,
          reason: 'receiver 側で open した DataChannel の compress が '
              'true であること。',
        );

        // 双方で SoraSwitchedEvent が 1 回だけ発火したことを確認する。
        expect(
          sender.switchedEvents.length,
          1,
          reason: 'sender で SoraSwitchedEvent が 1 回発火すること。',
        );
        expect(
          receiver.switchedEvents.length,
          1,
          reason: 'receiver で SoraSwitchedEvent が 1 回発火すること。',
        );

        // sender -> receiver へのメッセージ送信。
        logE2eMessage(
          'stage=sender_send_message channelId=$channelId '
          'label=$testLabel payload=${senderPayload}',
        );
        sender.connection.sendDataChannelMessage(testLabel, senderPayload);

        // receiver 側でメッセージを受信するまで待つ。
        final receivedMessage = await receiver.waitForDataChannelMessage(
          tester,
          label: testLabel,
          timeout: receiverTimeout,
        );
        logE2eMessage(
          'stage=receiver_received_message channelId=$channelId '
          'label=${receivedMessage.label} '
          'payload=${receivedMessage.data}',
        );

        expect(
          receivedMessage.label,
          testLabel,
          reason: 'receiver が受信したメッセージの label が '
              '$testLabel であること。',
        );
        expect(
          receivedMessage.data,
          senderPayload,
          reason: 'receiver が受信した payload が sender の送信内容と'
              '一致すること。',
        );

        // receiver -> sender への往復メッセージ送信（双方向性の確認）。
        final receiverPayload = Uint8List.fromList(
          <int>[0xFF, 0xFE, 0xFD, 0x01, 0x00],
        );
        logE2eMessage(
          'stage=receiver_send_message channelId=$channelId '
          'label=$testLabel payload=${receiverPayload}',
        );
        receiver.connection.sendDataChannelMessage(testLabel, receiverPayload);

        final receivedRoundtrip = await sender.waitForDataChannelMessage(
          tester,
          label: testLabel,
          timeout: senderTimeout,
        );
        logE2eMessage(
          'stage=sender_received_roundtrip channelId=$channelId '
          'label=${receivedRoundtrip.label} '
          'payload=${receivedRoundtrip.data}',
        );

        expect(
          receivedRoundtrip.label,
          testLabel,
          reason: 'sender が受信した往復メッセージの label が '
              '$testLabel であること。',
        );
        expect(
          receivedRoundtrip.data,
          receiverPayload,
          reason: 'sender が受信した往復 payload が receiver の送信内容と'
              '一致すること。',
        );

        logE2eMessage('stage=disconnect_start');
        await sender.disconnect();
        await sender.waitUntilDisconnected(senderTimeout);
        await receiver.disconnect();
        await receiver.waitUntilDisconnected(receiverTimeout);
        logE2eMessage('stage=disconnected');
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

        await runCleanupStep(cleanupErrors, 'sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender.waitUntilDisconnected(senderTimeout);
          }
        });
        await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver.waitUntilDisconnected(receiverTimeout);
          }
        });
        await runCleanupStep(cleanupErrors, 'sender.dispose', () async {
          await sender?.dispose();
        });
        await runCleanupStep(cleanupErrors, 'receiver.dispose', () async {
          await receiver?.dispose();
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
