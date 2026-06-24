import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signaling_failover: 先頭 URL 失敗後に後続 URL で接続成功することを確認する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId =
          buildChannelId(env.channelPrefix, suffix: '-failover');

      // 1 件目: 確実に失敗する localhost URL
      // 2 件目以降: 有効な URL
      final config = SoraConnectionConfig(
        signalingUrls: <String>[
          'wss://localhost:1/signaling',
          ...env.signalingUrls,
        ],
        channelId: channelId,
        role: SoraRole.recvonly,
        metadata: env.metadata,
        timeoutOptions: const SoraTimeoutOptions(
          connectionTimeout: Duration(seconds: 10),
          signalingCandidateTimeout: Duration(seconds: 2),
        ),
      );

      final conn = await ObservedConnection.create(
        name: 'failover',
        config: config,
      );
      final timeout = connectionStageTimeout(config);

      try {
        logE2eMessage('stage=connect_start type=failover_success');
        await conn.connect();

        logE2eMessage(
          'stage=wait_connected type=failover_success '
          'errors=${conn.errorSummaries()}',
        );
        // 失敗 URL を経由しても最終的に接続成功することを確認する
        await conn.waitUntilConnected(timeout);

        logE2eMessage(
          'stage=connect_finished type=failover_success '
          'connectionId=${conn.connectionId} '
          'errors=${conn.errorSummaries()}',
        );

        expect(conn.connectionId, isNotNull,
            reason: 'フェイルオーバー後に connectionId が取得できること');

        // 1 件目の失敗は内部で握りつぶされ、全体エラーとして観測されないことを確認する
        expect(conn.errors, isEmpty,
            reason:
                'フェイルオーバー成功時に SoraConnectionErrorEvent が発火しないこと');
      } finally {
        logE2eMessage('stage=cleanup type=failover_success');
        await conn.dispose();
      }
    },
  );
}
