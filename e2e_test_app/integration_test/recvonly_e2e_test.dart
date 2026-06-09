// recvonly で Sora に接続し、接続状態と getStats を検証する E2E。
// Linux デスクトップの MethodChannel 実装が揃ったら -d linux で同じテストを実行できる。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('recvonly: connect and verify stats suggest DTLS/ICE', (
    WidgetTester tester,
  ) async {
    final secretKey = Platform.environment['TEST_SECRET_KEY']?.trim();
    final urlsRaw = Platform.environment['TEST_SIGNALING_URLS']?.trim();
    final channelPrefix =
        Platform.environment['TEST_CHANNEL_ID_PREFIX']?.trim();

    expect(secretKey, isNotNull, reason: 'Set TEST_SECRET_KEY for E2E.');
    expect(
      urlsRaw,
      isNotNull,
      reason: 'Set TEST_SIGNALING_URLS (comma-separated wss:// URLs) for E2E.',
    );
    expect(channelPrefix, isNotNull,
        reason: 'Set TEST_CHANNEL_ID_PREFIX for E2E.');
    expect(secretKey!.isNotEmpty, isTrue);

    final signalingUrls = parseSignalingUrls(urlsRaw!);
    expect(
      signalingUrls,
      isNotEmpty,
      reason: 'TEST_SIGNALING_URLS must contain at least one URL.',
    );

    final channelId = buildChannelId(channelPrefix!, suffix: '-recvonly');
    final metadata = metadataFromSecretKey(secretKey);

    final config = SoraConnectionConfig(
      signalingUrls: signalingUrls,
      channelId: channelId,
      role: SoraRole.recvonly,
      metadata: metadata,
    );

    final connection = await Sora.createConnection(config);
    final errors = <SoraConnectionErrorEvent>[];

    final connected = Completer<void>();
    late final StreamSubscription<SoraConnectionEvent> sub;
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

    try {
      await connection.connect();
      await connected.future.timeout(
        config.timeoutOptions.connectionTimeout + const Duration(seconds: 15),
      );

      final statsRaw = await connection.getStats();
      expect(statsRaw, isNotNull);
      expect(statsRaw, isNotEmpty);
      expect(
        statsJsonSuggestsMediaPathUp(statsRaw!),
        isTrue,
        reason:
            'Expected getStats JSON to include connected DTLS or succeeded ICE pair.',
      );
    } finally {
      await sub.cancel();
      await connection.dispose();
    }

    expect(errors, isEmpty);
  });
}
