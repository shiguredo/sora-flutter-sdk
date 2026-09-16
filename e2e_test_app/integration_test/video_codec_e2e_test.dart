// Video Codec ごとに sender / receiver の 2 接続を立ち上げ、指定した Codec で
// 映像を送受信できることを検証する E2E。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // CI 環境（GitHub Actions 等）では HEVC ハードウェアデコーダが利用できず
  // H.265 の E2E が失敗するため、H.265 を除くコーデックのみテストする。
  // ローカルでは全コーデックをテストする。
  final isCi = Platform.environment['CI'] == 'true';

  for (final codec in VideoCodecType.values) {
    if (isCi && codec == VideoCodecType.h265) {
      continue;
    }
    testWidgets('${codec.value}: 指定した Video Codec で映像を送受信できる', (
      WidgetTester tester,
    ) async {
      await _verifyVideoCodec(tester, codec);
    }, skip: !Platform.isMacOS);
  }
}

Future<void> _verifyVideoCodec(
  WidgetTester tester,
  VideoCodecType codec,
) async {
  final env = loadE2eEnvironment();
  final channelId = buildChannelId(
    env.channelPrefix,
    suffix: '-videocodec-${codec.value.toLowerCase()}',
  );

  final receiverConfig = SoraConnectionConfig(
    signalingUrls: env.signalingUrls,
    channelId: channelId,
    role: SoraRole.recvonly,
    video: true,
    audio: false,
    videoCodecType: codec,
    useAudioDevice: false,
    metadata: env.metadata,
  );
  final senderConfig = SoraConnectionConfig(
    signalingUrls: env.signalingUrls,
    channelId: channelId,
    role: SoraRole.sendonly,
    video: true,
    audio: false,
    videoCodecType: codec,
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
  ColorBarVideoSource? videoSource;
  VideoOutboundStats? firstOutbound;
  VideoOutboundStats? secondOutbound;
  VideoInboundStats? firstInbound;
  VideoInboundStats? secondInbound;
  Object? bodyError;

  try {
    receiver = await ObservedConnection.create(
      name: 'receiver-${codec.value}',
      config: receiverConfig,
    );
    sender = await ObservedConnection.create(
      name: 'sender-${codec.value}',
      config: senderConfig,
    );

    stream = MediaDevices.createMediaStream();
    videoTrack = MediaDevices.createExternalVideoTrack();
    stream.addTrack(videoTrack);
    videoSource = ColorBarVideoSource(width: 320, height: 180, frameRate: 30);

    logE2eMessage(
      'stage=receiver_connect_start codec=${codec.value} channelId=$channelId '
      'bundleId=${receiver.connection.bundleId}',
    );
    await receiver.connect();
    await receiver.waitUntilConnected(receiverConnectTimeout);
    receiver.throwIfHasErrors();
    logE2eMessage(
      'stage=receiver_connected codec=${codec.value} channelId=$channelId '
      'receiverConnectionId=${receiver.connectionId}',
    );

    logE2eMessage(
      'stage=sender_connect_start codec=${codec.value} channelId=$channelId '
      'bundleId=${sender.connection.bundleId}',
    );
    await sender.connect(stream);
    await sender.waitUntilConnected(senderConnectTimeout);
    sender.throwIfHasErrors();
    logE2eMessage(
      'stage=sender_connected codec=${codec.value} channelId=$channelId '
      'senderConnectionId=${sender.connectionId}',
    );

    final senderConnectionId = sender.connectionId;
    expect(
      senderConnectionId,
      isNotNull,
      reason: 'sender connected 後に connectionId が確定していること。',
    );

    // sender の接続完了後にフレーム投入を開始し、receiver の映像到達を待つ。
    videoSource.start(videoTrack);
    await tester.pump(const Duration(seconds: 1));

    final remoteTrack = await receiver.waitForRemoteVideoTrackFrom(
      tester,
      remoteConnectionId: senderConnectionId!,
      timeout: receiverTrackTimeout,
    );
    expect(
      remoteTrack.kind,
      'video',
      reason: 'receiver で sender 由来の video track が 1 回到達すること。',
    );

    firstOutbound = await waitForVideoOutboundStats(tester, sender.connection);
    secondOutbound = await waitForVideoOutboundStats(
      tester,
      sender.connection,
      previous: firstOutbound,
    );
    firstInbound = await waitForVideoInboundStats(tester, receiver.connection);
    secondInbound = await waitForVideoInboundStats(
      tester,
      receiver.connection,
      previous: firstInbound,
    );
    sender.throwIfHasErrors();
    receiver.throwIfHasErrors();
    logE2eMessage(
      'stage=stats_ready codec=${codec.value} channelId=$channelId '
      'outbound=$secondOutbound inbound=$secondInbound',
    );

    _expectOutboundTraffic(firstOutbound, secondOutbound);
    _expectInboundTraffic(firstInbound, secondInbound);
    _expectCodecMatches(secondOutbound.mimeType, codec, direction: 'sender');
    _expectCodecMatches(secondInbound.mimeType, codec, direction: 'receiver');
  } catch (e) {
    bodyError = e;
    rethrow;
  } finally {
    if (sender != null || receiver != null) {
      logE2eMessage(
        'stage=cleanup_start codec=${codec.value} '
        'sender=${sender?.debugSummary()} '
        'receiver=${receiver?.debugSummary()} '
        'senderOutboundLast=$secondOutbound '
        'receiverInboundLast=$secondInbound',
      );
    }

    final cleanupErrors = <String>[];

    try {
      videoSource?.stop();
    } catch (e) {
      cleanupErrors.add('videoSource.stop: $e');
      logE2eMessage(
        'stage=cleanup_error codec=${codec.value} step=videoSource.stop error=$e',
      );
    }
    await runCleanupStep(cleanupErrors, 'sender.disconnect', () async {
      if (sender != null) {
        await sender.disconnect();
        await sender!.waitUntilDisconnected(senderDisconnectTimeout);
      }
    });
    await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
      if (receiver != null) {
        await receiver.disconnect();
        await receiver!.waitUntilDisconnected(receiverDisconnectTimeout);
      }
    });
    await runCleanupStep(
      cleanupErrors,
      'sender.dispose',
      () async => await sender?.dispose(),
    );
    await runCleanupStep(
      cleanupErrors,
      'receiver.dispose',
      () async => await receiver?.dispose(),
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
        'stage=cleanup_finished codec=${codec.value} status=failed '
        'errors=${cleanupErrors.join(" | ")}',
      );
      if (bodyError == null) {
        throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
      }
    } else {
      logE2eMessage(
        'stage=cleanup_finished codec=${codec.value} status=ok',
      );
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
}

void _expectOutboundTraffic(
  VideoOutboundStats first,
  VideoOutboundStats second,
) {
  expect(
    first.bytesSent,
    greaterThan(0),
    reason: '初回取得時に video outbound-rtp の bytesSent が増えていること。',
  );
  expect(
    first.packetsSent,
    greaterThan(0),
    reason: '初回取得時に video outbound-rtp の packetsSent が増えていること。',
  );
  expect(
    second.bytesSent,
    greaterThan(first.bytesSent),
    reason: '2 回目取得時に video outbound-rtp の bytesSent が増えていること。',
  );
  expect(
    second.packetsSent,
    greaterThan(first.packetsSent),
    reason: '2 回目取得時に video outbound-rtp の packetsSent が増えていること。',
  );

  final framesEncoded = second.framesEncoded;
  if (framesEncoded != null) {
    expect(
      framesEncoded,
      greaterThan(0),
      reason: 'framesEncoded が存在する場合は 0 より大きいこと。',
    );
  }

  final framesSent = second.framesSent;
  if (framesSent != null) {
    expect(
      framesSent,
      greaterThan(0),
      reason: 'framesSent が存在する場合は 0 より大きいこと。',
    );
  }
}

void _expectInboundTraffic(
  VideoInboundStats first,
  VideoInboundStats second,
) {
  expect(
    first.bytesReceived,
    greaterThan(0),
    reason: '初回取得時に video inbound-rtp の bytesReceived が増えていること。',
  );
  expect(
    first.packetsReceived,
    greaterThan(0),
    reason: '初回取得時に video inbound-rtp の packetsReceived が増えていること。',
  );
  expect(
    second.bytesReceived,
    greaterThan(first.bytesReceived),
    reason: '2 回目取得時に video inbound-rtp の bytesReceived が増えていること。',
  );
  expect(
    second.packetsReceived,
    greaterThan(first.packetsReceived),
    reason: '2 回目取得時に video inbound-rtp の packetsReceived が増えていること。',
  );

  final framesDecoded = second.framesDecoded;
  if (framesDecoded != null) {
    expect(
      framesDecoded,
      greaterThan(0),
      reason: 'framesDecoded が存在する場合は 0 より大きいこと。',
    );
  }

  final framesReceived = second.framesReceived;
  if (framesReceived != null) {
    expect(
      framesReceived,
      greaterThan(0),
      reason: 'framesReceived が存在する場合は 0 より大きいこと。',
    );
  }
}

void _expectCodecMatches(
  String? mimeType,
  VideoCodecType expected, {
  required String direction,
}) {
  expect(
    mimeType,
    isNotNull,
    reason: '$direction の video RTP 統計から MIME type を取得できること。',
  );
  expect(
    _codecNameFromMimeType(mimeType!),
    expected.value,
    reason: '$direction が指定した ${expected.value} で映像を処理すること。',
  );
}

/// RTP 統計の MIME type を Sora の VideoCodecType と比較できる名前へ正規化する。
String _codecNameFromMimeType(String mimeType) {
  final mediaType = mimeType.split(';').first.trim();
  final separatorIndex = mediaType.indexOf('/');
  final codecName =
      separatorIndex >= 0 ? mediaType.substring(separatorIndex + 1) : mediaType;
  return codecName.trim().toUpperCase();
}
