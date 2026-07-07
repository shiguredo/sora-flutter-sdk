// sendonly で Sora にダミー映像を送信し、getStats の送信量を検証する E2E。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sendonly: ダミー映像を送信し getStats の送信量を検証する', (
    WidgetTester tester,
  ) async {
    final secretKey = Platform.environment['TEST_SECRET_KEY']?.trim();
    final urlsRaw = Platform.environment['TEST_SIGNALING_URLS']?.trim();
    final channelPrefix =
        Platform.environment['TEST_CHANNEL_ID_PREFIX']?.trim();

    expect(secretKey, isNotNull, reason: 'TEST_SECRET_KEY を設定してください。');
    expect(urlsRaw, isNotNull, reason: 'TEST_SIGNALING_URLS を設定してください。');
    expect(
      channelPrefix,
      isNotNull,
      reason: 'TEST_CHANNEL_ID_PREFIX を設定してください。',
    );
    expect(
      secretKey!.isNotEmpty,
      isTrue,
      reason: 'TEST_SECRET_KEY は空文字列ではないこと。',
    );

    final signalingUrls = parseSignalingUrls(urlsRaw!);
    expect(
      signalingUrls,
      isNotEmpty,
      reason: 'TEST_SIGNALING_URLS には 1 件以上の URL が必要です。',
    );

    final channelId = buildChannelId(channelPrefix!, suffix: '-sendonly');
    final metadata = metadataFromSecretKey(secretKey);

    final config = SoraConnectionConfig(
      signalingUrls: signalingUrls,
      channelId: channelId,
      role: SoraRole.sendonly,
      video: true,
      audio: false,
      useAudioDevice: false,
      metadata: metadata,
    );

    SoraConnection? connection;
    StreamSubscription<SoraConnectionEvent>? sub;
    LocalMediaStream? stream;
    LocalVideoTrack? videoTrack;
    ColorBarVideoSource? videoSource;
    final errors = <SoraConnectionErrorEvent>[];
    final connected = Completer<void>();

    try {
      stream = MediaDevices.createMediaStream();
      videoTrack = MediaDevices.createExternalVideoTrack();
      stream.addTrack(videoTrack);
      videoSource = ColorBarVideoSource(width: 320, height: 180, frameRate: 30);

      connection = await Sora.createConnection(config);
      sub = connection.events.listen((SoraConnectionEvent event) {
        if (event is SoraConnectionStateChangedEvent) {
          if (event.state is SoraConnectedState && !connected.isCompleted) {
            connected.complete();
          }
        } else if (event is SoraConnectionErrorEvent) {
          errors.add(event);
          if (!connected.isCompleted) {
            connected.completeError(
              StateError(
                'Connection error: code=${event.code} message=${event.message}',
              ),
            );
          }
        }
      });

      await connection.connect(stream);
      await connected.future.timeout(
        config.timeoutOptions.connectionTimeout + const Duration(seconds: 15),
      );
      videoSource.start(videoTrack);
      await tester.pump(const Duration(seconds: 1));

      final sendDurationSec =
          int.tryParse(Platform.environment['TEST_SEND_DURATION'] ?? '');
      if (sendDurationSec != null && sendDurationSec > 0) {
        // ignore: avoid_print
        print(
          '[stats] send duration mode: ${sendDurationSec}s '
          'channelId=$channelId',
        );
        await _runWithDuration(
          tester,
          connection,
          Duration(seconds: sendDurationSec),
        );
      }

      final first = await waitForVideoOutboundStats(
        tester,
        connection,
      );
      final second = await waitForVideoOutboundStats(
        tester,
        connection,
        previous: first,
      );

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
    } finally {
      videoSource?.stop();
      await sub?.cancel();
      await connection?.dispose();
      await stream?.dispose();
      await videoTrack?.dispose();
    }

    expect(
      errors,
      isEmpty,
      reason: '接続エラーイベントが発生しないこと。',
    );
  });
}

/// TEST_SEND_DURATION が設定されているときに指定秒数だけ送信を継続し、
/// stats を定期的に出力する。
Future<void> _runWithDuration(
  WidgetTester tester,
  SoraConnection connection,
  Duration totalDuration,
) async {
  const printInterval = Duration(seconds: 10);

  VideoOutboundStats? prevStats;
  DateTime? prevTime;
  var elapsed = Duration.zero;

  while (elapsed < totalDuration) {
    await tester.pump(printInterval);
    elapsed += printInterval;
    if (elapsed > totalDuration) {
      elapsed = totalDuration;
    }

    final raw = await connection.getStats();
    if (raw == null || raw.isEmpty) {
      continue;
    }
    final stats = extractVideoOutboundStats(raw);
    if (stats == null) {
      continue;
    }

    final now = DateTime.now();
    final elapsedSec = elapsed.inSeconds;
    final codec = stats.mimeType ?? 'unknown';
    final resolution = stats.width != null && stats.height != null
        ? '${stats.width}x${stats.height}'
        : 'unknown';

    String bitrateInfo = '';
    String fpsInfo = '';
    if (prevStats != null && prevTime != null) {
      final dtSec = now.difference(prevTime).inMicroseconds / 1000000;
      if (dtSec > 0) {
        final deltaBytes = stats.bytesSent - prevStats.bytesSent;
        final deltaFrames =
            (stats.framesEncoded ?? 0) - (prevStats.framesEncoded ?? 0);
        final bitrate = (deltaBytes * 8 / dtSec).round();
        final fps = deltaFrames / dtSec;
        bitrateInfo = ' bitrate=${bitrate}bps';
        fpsInfo = ' fps=${fps.toStringAsFixed(1)}';
      }
    }

    // ignore: avoid_print
    print(
      '[stats] elapsed=${elapsedSec}s '
      'codec=$codec resolution=$resolution '
      'bytesSent=${stats.bytesSent} packetsSent=${stats.packetsSent} '
      'framesEncoded=${stats.framesEncoded ?? 0}$bitrateInfo$fpsInfo',
    );

    prevStats = stats;
    prevTime = now;
  }

  final raw = await connection.getStats();
  if (raw != null && raw.isNotEmpty) {
    final stats = extractVideoOutboundStats(raw);
    if (stats != null) {
      final codec = stats.mimeType ?? 'unknown';
      final resolution = stats.width != null && stats.height != null
          ? '${stats.width}x${stats.height}'
          : 'unknown';
      // ignore: avoid_print
      print(
        '[stats] final elapsed=${totalDuration.inSeconds}s '
        'codec=$codec resolution=$resolution '
        'bytesSent=${stats.bytesSent} packetsSent=${stats.packetsSent} '
        'framesEncoded=${stats.framesEncoded ?? 0}',
      );
    }
  }
}
