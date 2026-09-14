// Windows の実音声デバイス (Windows CoreAudio ADM) で送受信を検証する E2E。
//
// 物理マイクと実スピーカーが必要なため、GitHub Actions の Hosted Runner では
// 実行せず、Windows 実機または self-hosted runner で実行する。
// TEST_SECRET_KEY / TEST_SIGNALING_URLS / TEST_CHANNEL_ID_PREFIX が必要。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'windows_audio_real_device: 実マイクの音声を送信し、recvonly 側で受信できることを確認する',
    (WidgetTester tester) async {
      // Windows 以外ではテストをスキップする
      if (!Platform.isWindows) {
        return;
      }

      final env = loadE2eEnvironment();
      final inputDevices = await MediaDevices.enumerateAudioInputDevices();
      expect(
        inputDevices,
        isNotEmpty,
        reason: '音声入力デバイスが存在しないため送受信テストを実行できません。',
      );

      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-windows-real-audio',
      );
      final receiverConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        audio: true,
        video: false,
        useAudioDevice: true,
        metadata: env.metadata,
      );
      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: true,
        video: false,
        useAudioDevice: true,
        metadata: env.metadata,
      );
      final receiverTimeout = connectionStageTimeout(receiverConfig);
      final senderTimeout = connectionStageTimeout(senderConfig);
      const remoteTrackTimeout = Duration(seconds: 30);

      ObservedConnection? receiver;
      ObservedConnection? sender;
      LocalMediaStream? stream;
      LocalAudioTrack? audioTrack;
      Object? bodyError;

      try {
        // createConnection で useAudioDevice: true が共有 factory へ反映される。
        receiver = await ObservedConnection.create(
          name: 'windows-real-audio-receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'windows-real-audio-sender',
          config: senderConfig,
        );

        stream = MediaDevices.createMediaStream();
        audioTrack = await MediaDevices.createAudioTrack();
        stream.addTrack(audioTrack);

        await receiver.connect();
        await receiver.waitUntilConnected(receiverTimeout);
        receiver.throwIfHasErrors();

        await sender.connect(stream);
        await sender.waitUntilConnected(senderTimeout);
        sender.throwIfHasErrors();

        final senderConnectionId = sender.connectionId;
        expect(senderConnectionId, isNotNull);
        final remoteTrack = await receiver.waitForRemoteAudioTrackFrom(
          tester,
          remoteConnectionId: senderConnectionId!,
          timeout: remoteTrackTimeout,
        );
        expect(remoteTrack.kind, 'audio');

        // 実マイクの音声が Opus で送信され、受信側まで届くことを確認する。
        final outbound = await waitForAudioOutboundStats(
          tester,
          sender.connection,
        );
        expect(outbound.packetsSent, greaterThan(0));
        final inbound = await waitForAudioInboundStats(
          tester,
          receiver.connection,
        );
        expect(inbound.packetsReceived, greaterThan(0));

        sender.throwIfHasErrors();
        receiver.throwIfHasErrors();
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        await runCleanupStep(cleanupErrors, 'sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender!.waitUntilDisconnected(senderTimeout);
          }
        });
        await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver!.waitUntilDisconnected(receiverTimeout);
          }
        });
        await runCleanupStep(
          cleanupErrors,
          'sender.dispose',
          () async => sender?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'receiver.dispose',
          () async => receiver?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'stream.dispose',
          () async => stream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'audioTrack.dispose',
          () async => audioTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty && bodyError == null) {
          throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
        }
      }
    },
  );
}
