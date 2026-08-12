// ダミーウィンドウを ScreenCaptureKit でキャプチャし、受信側の stats で
// 映像が届くことを検証する E2E。
//
// macOS ローカル専用。SCStream の開始には画面収録権限が必要なため、
// CI では実行できない。ローカルでシステム設定から画面収録権限を
// 付与してから実行する。

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

/// ダミーウィンドウの表示・破棄を制御する MethodChannel。
const _dummyWindowChannel = MethodChannel('e2e_test_app/dummy_window');

/// ダミーウィンドウのタイトル。AppDelegate 側のタイトルと一致させる。
const _dummyWindowTitle = 'Sora E2E Dummy Window';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'window-capture: ダミーウィンドウの映像が receiver に届くことを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-windowcapture',
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
      LocalVideoTrack? videoTrack;
      VideoOutboundStats? firstOutbound;
      VideoOutboundStats? secondOutbound;
      VideoInboundStats? firstInbound;
      VideoInboundStats? secondInbound;
      Object? bodyError;

      try {
        // ダミーウィンドウを表示し、SCShareableContent に反映されるまで待つ
        await _dummyWindowChannel.invokeMethod<void>('show');
        final source = await _waitForDummyWindowSource(tester);
        logE2eMessage(
          'stage=dummy_window_ready channelId=$channelId '
          'sourceId=${source.id} title=${source.title}',
        );

        receiver = await ObservedConnection.create(
          name: 'receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'sender',
          config: senderConfig,
        );

        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createWindowVideoTrack(source);
        expect(
          videoTrack.captureType,
          VideoTrackCaptureType.window,
          reason:
              'createWindowVideoTrack で作成したトラックの captureType が window であること。',
        );
        stream.addTrack(videoTrack);

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
          secondInbound.bytesReceived,
          greaterThan(firstInbound.bytesReceived),
          reason:
              'receiver 2 回目取得時に video inbound-rtp の bytesReceived が増えていること。',
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

        await runCleanupStep('dummyWindow.hide', () async {
          await _dummyWindowChannel.invokeMethod<void>('hide');
        });
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
    },
  );
}

/// ダミーウィンドウが SCShareableContent に反映されるまで列挙を待つ。
Future<WindowCaptureSource> _waitForDummyWindowSource(
  WidgetTester tester,
) async {
  const maxAttempts = 30;
  const interval = Duration(milliseconds: 500);

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final sources = await MediaDevices.enumerateWindowCaptureSources();
    for (final source in sources) {
      if (source.title == _dummyWindowTitle) {
        return source;
      }
    }
    logE2eMessage(
      'stage=enumerate_window_sources attempt=${attempt + 1} '
      'found=${sources.length}',
    );
    await tester.pump(interval);
  }

  throw StateError(
    'ダミーウィンドウを列挙できませんでした。'
    '画面収録権限が付与されていることを確認してください。',
  );
}
