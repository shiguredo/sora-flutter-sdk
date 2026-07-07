// サーバー主導の timeout による SoraTimeoutEvent の検証は環境依存のため
// このファイルでは対象外とする。

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

/// 収集されたエラーイベントの message が全て非 null かつ非空であることを検証する。
///
/// 認証失敗テストと全 URL 不達テストの両方で同じ検証ロジックを使うため抽出した。
void _assertErrorMessagesAreNonEmpty(List<SoraConnectionErrorEvent> errors) {
  for (final error in errors) {
    expect(error.message, isNotNull);
    expect(error.message!.isNotEmpty, isTrue);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'connection_failure: 認証失敗で接続が成功しないことを確認する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(env.channelPrefix, suffix: '-authfail');

      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        useAudioDevice: false,
        metadata: <String, Object?>{
          'access_token': 'invalid_token_for_e2e_test',
        },
        timeoutOptions: const SoraTimeoutOptions(
          connectionTimeout: Duration(seconds: 10),
        ),
      );

      final conn = await ObservedConnection.create(
        name: 'auth-fail',
        config: config,
      );
      final timeout = connectionStageTimeout(config);

      try {
        logE2eMessage('stage=connect_start type=auth_failure');
        try {
          await conn.connect();
        } catch (_) {}

        // ObservedConnection._connected は SoraConnectionErrorEvent 受信時に
        // completeError されるため、waitUntilConnected は throw する
        try {
          await conn.waitUntilConnected(timeout);
        } catch (_) {}

        logE2eMessage(
          'stage=connect_finished type=auth_failure '
          'errors=${conn.errorSummaries()}',
        );

        final actualCodes =
            conn.errors.map((SoraConnectionErrorEvent e) => e.code).toList();
        expect(actualCodes, isNotEmpty,
            reason: '認証失敗時に SoraConnectionErrorEvent が発火すること');
        _assertErrorMessagesAreNonEmpty(conn.errors);
      } finally {
        logE2eMessage('stage=cleanup type=auth_failure');
        await conn.dispose();
      }
    },
  );

  testWidgets(
    'connection_failure: 全 URL 不達で signalingCandidateTimeout が発生することを確認する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();

      final config = SoraConnectionConfig(
        signalingUrls: <String>[
          'wss://localhost:1/signaling',
          'wss://localhost:2/signaling',
        ],
        channelId: buildChannelId(env.channelPrefix, suffix: '-timeout'),
        role: SoraRole.recvonly,
        useAudioDevice: false,
        metadata: env.metadata,
        timeoutOptions: const SoraTimeoutOptions(
          connectionTimeout: Duration(seconds: 10),
          signalingCandidateTimeout: Duration(seconds: 2),
        ),
      );

      final conn = await ObservedConnection.create(
        name: 'timeout',
        config: config,
      );
      final timeout = connectionStageTimeout(config);

      try {
        logE2eMessage('stage=connect_start type=signaling_candidate_timeout');
        try {
          await conn.connect();
        } catch (_) {}

        try {
          await conn.waitUntilConnected(timeout);
        } catch (_) {}

        logE2eMessage(
          'stage=connect_finished type=signaling_candidate_timeout '
          'errors=${conn.errorSummaries()}',
        );

        expect(conn.errors, isNotEmpty,
            reason: '全 URL 不達時に SoraConnectionErrorEvent が発火すること');

        final actualCodes =
            conn.errors.map((SoraConnectionErrorEvent e) => e.code).toList();
        expect(
          actualCodes,
          contains(SoraErrorCode.signalingCandidateTimeout),
          reason: 'エラーコード一覧 $actualCodes に signaling_candidate_timeout が含まれること',
        );

        _assertErrorMessagesAreNonEmpty(conn.errors);
      } finally {
        logE2eMessage('stage=cleanup type=signaling_candidate_timeout');
        await conn.dispose();
      }
    },
  );
}
