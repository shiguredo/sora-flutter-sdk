// 非ゼロ PCM を送信し、相手側まで音声 RTP が届くことを検証する E2E。
// remote audio track の存在確認だけでは検出できない PushAudioDevice、Opus、
// SFU 転送、受信デコードの経路をまとめて通す。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/push_audio_track.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'audio_media: トーン PCM の Opus payload と受信 energy を検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-audio-media',
      );
      final receiverConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        audio: true,
        video: false,
        useAudioDevice: false,
        metadata: env.metadata,
      );
      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: true,
        video: false,
        useAudioDevice: false,
        metadata: env.metadata,
      );
      final receiverTimeout = connectionStageTimeout(receiverConfig);
      final senderTimeout = connectionStageTimeout(senderConfig);
      const remoteTrackTimeout = Duration(seconds: 30);

      ObservedConnection? receiver;
      ObservedConnection? sender;
      LocalMediaStream? stream;
      E2ePushAudioTrack? pushAudioTrack;
      LocalAudioTrack? audioTrack;
      Object? bodyError;

      try {
        receiver = await ObservedConnection.create(
          name: 'audio-receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'audio-sender',
          config: senderConfig,
        );

        stream = MediaDevices.createMediaStream();
        pushAudioTrack = await E2ePushAudioTrack.create();
        audioTrack = pushAudioTrack.audioTrack;
        stream.addTrack(audioTrack);

        await receiver.connect();
        await receiver.waitUntilConnected(receiverTimeout);
        receiver.throwIfHasErrors();

        await sender.connect(stream);
        await sender.waitUntilConnected(senderTimeout);
        sender.throwIfHasErrors();
        pushAudioTrack.start();

        final senderConnectionId = sender.connectionId;
        expect(senderConnectionId, isNotNull);
        final remoteTrack = await receiver.waitForRemoteAudioTrackFrom(
          tester,
          remoteConnectionId: senderConnectionId!,
          timeout: remoteTrackTimeout,
        );
        expect(remoteTrack.kind, 'audio');

        // PushAudioDevice のデバイスレス playout が受信音声を 10 ms ごとに pull する。
        // 同じ接続で無音とトーンを一定時間ずつ送り、Opus payload の増加に加えて、
        // デコード後 PCM から算出される energy の増加を確認する。
        final silentOutboundBefore = await waitForAudioOutboundStats(
          tester,
          sender.connection,
        );
        final silentInboundBefore = await waitForAudioInboundStats(
          tester,
          receiver.connection,
        );
        final silentDecodedBefore = pushAudioTrack.decodedAudioObservation;
        await tester.pump(const Duration(seconds: 3));
        final silentOutboundAfter = await waitForAudioOutboundStats(
          tester,
          sender.connection,
          previous: silentOutboundBefore,
        );
        final silentInboundAfter = await waitForAudioInboundStats(
          tester,
          receiver.connection,
          previous: silentInboundBefore,
        );
        final silentDecodedAfter = pushAudioTrack.decodedAudioObservation;

        pushAudioTrack.startTone();
        await tester.pump(const Duration(seconds: 1));
        final toneOutboundBefore = await waitForAudioOutboundStats(
          tester,
          sender.connection,
          previous: silentOutboundAfter,
        );
        final toneInboundBefore = await waitForAudioInboundStats(
          tester,
          receiver.connection,
          previous: silentInboundAfter,
        );
        final toneDecodedBefore = pushAudioTrack.decodedAudioObservation;
        await tester.pump(const Duration(seconds: 3));
        final toneOutboundAfter = await waitForAudioOutboundStats(
          tester,
          sender.connection,
          previous: toneOutboundBefore,
        );
        final toneInboundAfter = await waitForAudioInboundStats(
          tester,
          receiver.connection,
          previous: toneInboundBefore,
        );
        final toneDecodedAfter = pushAudioTrack.decodedAudioObservation;

        final silentOutboundPayload = _averagePayloadBytes(
          beforeBytes: silentOutboundBefore.bytesSent,
          afterBytes: silentOutboundAfter.bytesSent,
          beforePackets: silentOutboundBefore.packetsSent,
          afterPackets: silentOutboundAfter.packetsSent,
        );
        final toneOutboundPayload = _averagePayloadBytes(
          beforeBytes: toneOutboundBefore.bytesSent,
          afterBytes: toneOutboundAfter.bytesSent,
          beforePackets: toneOutboundBefore.packetsSent,
          afterPackets: toneOutboundAfter.packetsSent,
        );
        final silentInboundPayload = _averagePayloadBytes(
          beforeBytes: silentInboundBefore.bytesReceived,
          afterBytes: silentInboundAfter.bytesReceived,
          beforePackets: silentInboundBefore.packetsReceived,
          afterPackets: silentInboundAfter.packetsReceived,
        );
        final toneInboundPayload = _averagePayloadBytes(
          beforeBytes: toneInboundBefore.bytesReceived,
          afterBytes: toneInboundAfter.bytesReceived,
          beforePackets: toneInboundBefore.packetsReceived,
          afterPackets: toneInboundAfter.packetsReceived,
        );
        final silentDecodedEnergy = _averageDecodedAudioEnergy(
          before: silentDecodedBefore,
          after: silentDecodedAfter,
        );
        final toneDecodedEnergy = _averageDecodedAudioEnergy(
          before: toneDecodedBefore,
          after: toneDecodedAfter,
        );

        expect(
          silentOutboundAfter.mimeType?.toLowerCase(),
          'audio/opus',
          reason: 'sender が Opus で音声を符号化すること。',
        );
        expect(
          silentInboundAfter.mimeType?.toLowerCase(),
          'audio/opus',
          reason: 'receiver が Opus RTP を受信すること。',
        );
        expect(
          toneOutboundPayload,
          greaterThan(silentOutboundPayload * 1.5),
          reason: 'sender のトーン PCM が無音より大きな Opus payload になること。',
        );
        expect(
          toneInboundPayload,
          greaterThan(silentInboundPayload * 1.5),
          reason: 'receiver まで届くトーンの Opus payload が無音より大きいこと。',
        );
        expect(
          toneDecodedEnergy,
          greaterThan(0.001),
          reason: 'receiver が非ゼロのトーン PCM をデコードすること。',
        );
        expect(
          toneDecodedEnergy,
          greaterThan(silentDecodedEnergy * 5),
          reason: 'デコード後のトーン energy が無音より十分に大きいこと。',
        );
        expect(
          toneOutboundAfter.bytesSent,
          greaterThan(toneOutboundBefore.bytesSent),
          reason: 'sender の audio bytesSent が継続増加すること。',
        );
        expect(
          toneInboundAfter.bytesReceived,
          greaterThan(toneInboundBefore.bytesReceived),
          reason: 'receiver の audio bytesReceived が継続増加すること。',
        );
        sender.throwIfHasErrors();
        receiver.throwIfHasErrors();
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        pushAudioTrack?.dispose();
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

/// 指定区間に増加した RTP payload の 1 packet あたりの平均バイト数を返す。
double _averagePayloadBytes({
  required int beforeBytes,
  required int afterBytes,
  required int beforePackets,
  required int afterPackets,
}) {
  final packetDelta = afterPackets - beforePackets;
  if (packetDelta <= 0) {
    throw StateError('RTP packet が増加していません。');
  }
  return (afterBytes - beforeBytes) / packetDelta;
}

/// 指定区間にデコードした PCM の平均 energy を返す。
double _averageDecodedAudioEnergy({
  required DecodedAudioObservation before,
  required DecodedAudioObservation after,
}) {
  final sampleDelta = after.totalSamples - before.totalSamples;
  final energyDelta = after.totalEnergy - before.totalEnergy;
  if (sampleDelta <= 0 || energyDelta < 0) {
    throw StateError(
      'デコード後の PCM を取得できませんでした: '
      'energyDelta=$energyDelta sampleDelta=$sampleDelta',
    );
  }
  return energyDelta / sampleDelta;
}
