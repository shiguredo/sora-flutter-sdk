import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connection_failover: DNS 解決不能な先頭 URL から後続 URL へ接続できることを確認する',
    (WidgetTester _) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(env.channelPrefix, suffix: '-failover');

      final config = SoraConnectionConfig(
        signalingUrls: <String>[
          'wss://sora-failover.invalid/signaling',
          ...env.signalingUrls,
        ],
        channelId: channelId,
        role: SoraRole.recvonly,
        useAudioDevice: false,
        metadata: env.metadata,
        timeoutOptions: const SoraTimeoutOptions(
          connectionTimeout: Duration(seconds: 15),
          signalingCandidateTimeout: Duration(seconds: 2),
        ),
      );

      final conn = await ObservedConnection.create(
        name: 'dns-failover',
        config: config,
      );
      final timeout = connectionStageTimeout(config);

      try {
        logE2eMessage('stage=connect_start type=dns_failover');
        await conn.connect();
        await conn.waitUntilConnected(timeout);
        conn.throwIfHasErrors();
        logE2eMessage(
          'stage=connect_finished type=dns_failover '
          'connectionId=${conn.connectionId}',
        );
      } finally {
        logE2eMessage('stage=cleanup type=dns_failover');
        await conn.dispose();
      }
    },
  );
}
