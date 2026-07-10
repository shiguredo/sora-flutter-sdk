// sendrecv で Sora に接続し、ダミー映像を送信、明示切断までを検証する smoke E2E。
// 単一接続で接続→送信→切断の最小経路が壊れていないことを確認する。
// 2 接続での受信成立確認や remoteMediaStreams の検証は未対応。

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

  testWidgets('sendrecv: ダミー映像を送信し明示切断までを検証する', (
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

    final channelId = buildChannelId(channelPrefix!, suffix: '-sendrecv');
    final metadata = metadataFromSecretKey(secretKey);

    // sendrecv で external video track を使う場合、connect(stream) が
    // audio / video を両方 null と判断しないよう明示的に指定する。
    final config = SoraConnectionConfig(
      signalingUrls: signalingUrls,
      channelId: channelId,
      role: SoraRole.sendrecv,
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
    final disconnected = Completer<void>();

    try {
      // 接続生成より前にメディアを生成しても、音声デバイス設定が反映されることを確認する。
      MediaDevices.setUseAudioDevice(false);
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
          if (event.state is SoraDisconnectedState &&
              !disconnected.isCompleted) {
            disconnected.complete();
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
          if (!disconnected.isCompleted) {
            disconnected.completeError(
              StateError(
                'Connection error during disconnect: code=${event.code} message=${event.message}',
              ),
            );
          }
        }
      });

      await connection.connect(stream);
      await connected.future.timeout(
        config.timeoutOptions.connectionTimeout + const Duration(seconds: 15),
      );

      // 接続確立後にカラーバーのフレーム投入を開始する。
      videoSource.start(videoTrack);
      await tester.pump(const Duration(seconds: 1));

      // getStats で DTLS / ICE が成立していることを確認する。
      final statsRaw = await connection.getStats();
      expect(statsRaw, isNotNull);
      expect(statsRaw, isNotEmpty);
      expect(
        statsJsonSuggestsMediaPathUp(statsRaw!),
        isTrue,
        reason:
            'getStats に DTLS connected または ICE candidate-pair succeeded が含まれること。',
      );

      // video outbound-rtp の送信量が出始めることを確認する。
      final first = await waitForVideoOutboundStats(
        tester,
        connection,
      );
      // 2 回目は 1 回目より送信量が増えることを確認する。
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

      // disconnect() を呼び、SoraDisconnectedState への到達を確認する。
      await connection.disconnect();
      await disconnected.future.timeout(
        config.timeoutOptions.connectionTimeout + const Duration(seconds: 15),
      );
    } finally {
      // 切断完了確認後に後始末を行う。
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
