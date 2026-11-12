// RPC の正常系と異常系を確認する E2E。
// RPC JWT を使うテストは、テストサーバーが JWT の private claims で
// rpc_methods を払い出す環境を前提とする。
// rpc_disconnect_pending テストは共通環境変数のみを使い、RPC JWT を必要としない。
// rpc_disconnect_in_flight テストは RPC JWT を使い、rpc DataChannel の open 後に
// rpc() と disconnect() を競合させる。
// RPC JWT は crypto の HMAC-SHA256 と dart:convert の base64Url で生成する。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/rpc_test_helpers.dart';
import 'helpers/test_helpers.dart';

const Duration _stageTimeout = Duration(seconds: 10);
const int _rpcTimeoutMs = 5000;
// Sora には「応答しないメソッド」が存在しないため、応答より先に timeout
// タイマーを発火させる目的で 1 ms を指定する。1 ms 以内に応答が返る環境では
// TimeoutException にならず失敗する。
const int _rpcTimeoutForTimeoutTestMs = 1;
const String _putSignalingNotifyMetadataSuffix = 'PutSignalingNotifyMetadata';
const List<String> _unsupportedRpcMethodSuffixes = <String>[
  'RequestSimulcastRid',
  'RequestSpotlightRid',
  'ResetSpotlightRid',
];
const String _missingJwtEnvSkipReason =
    'RPC JWT テスト用の環境変数 (TEST_SECRET_KEY / TEST_SIGNALING_URLS / '
    'TEST_CHANNEL_ID_PREFIX / TEST_RPC_SUCCESS_*) が未設定のためスキップします。';
const String _missingCommonEnvSkipReason =
    'RPC disconnect テスト用の環境変数 (TEST_SECRET_KEY / TEST_SIGNALING_URLS / '
    'TEST_CHANNEL_ID_PREFIX) が未設定のためスキップします。';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final commonEnv = loadRpcE2eEnvironment();
  RpcJwtE2eEnvironment? jwtEnv;
  var jwtEnvLoaded = false;

  RpcJwtE2eEnvironment? loadJwtEnv() {
    final common = commonEnv;
    if (common == null) {
      return null;
    }
    if (jwtEnvLoaded) {
      return jwtEnv;
    }
    // JSON の形式不正などはテスト実行時の失敗として扱い、main の登録時に
    // disconnect テストまで巻き込まない。
    jwtEnv = loadRpcJwtE2eEnvironment(common);
    jwtEnvLoaded = true;
    return jwtEnv;
  }

  testWidgets('rpc_normal: 正常応答を検証する', (WidgetTester tester) async {
    final env = loadJwtEnv();
    if (env == null) {
      markTestSkipped(_missingJwtEnvSkipReason);
      return;
    }

    ObservedConnection? connection;
    try {
      connection = await _connectRpc(tester, env, suffix: '-rpc-normal');
      logE2eMessage(
        'stage=rpc_send test=rpc_normal method=${env.successMethod}',
      );
      final result = await connection.connection
          .rpc(
            env.successMethod,
            params: env.successParams,
            options: const SoraRpcOptions(timeout: _rpcTimeoutMs),
          )
          .timeout(_stageTimeout);
      _expectRpcSuccess(result, env);
      connection.throwIfHasErrors();
      logE2eMessage('stage=rpc_result test=rpc_normal result=$result');
    } on _RpcSkip catch (e) {
      markTestSkipped(e.reason);
    } finally {
      await _disposeConnection(connection);
    }
  });

  testWidgets('rpc_timeout: TimeoutException を検証する', (
    WidgetTester tester,
  ) async {
    final env = loadJwtEnv();
    if (env == null) {
      markTestSkipped(_missingJwtEnvSkipReason);
      return;
    }

    ObservedConnection? connection;
    try {
      connection = await _connectRpc(tester, env, suffix: '-rpc-timeout');
      // RPC の 1 ms timeout が動かない退行を検出するため、待機側は 10 秒で
      // 打ち切る。expectLater に .timeout を付けても matcher の outstanding
      // work は完了しないため、RPC の Future 自体を bound し、外側の打ち切りは
      // TimeoutException 以外の例外にして matcher の偽陽性を避ける。
      await expectLater(
        connection.connection
            .rpc(
              env.successMethod,
              params: env.successParams,
              options: const SoraRpcOptions(
                timeout: _rpcTimeoutForTimeoutTestMs,
              ),
            )
            .timeout(
              _stageTimeout,
              onTimeout: () => throw StateError(
                'rpc() did not complete within $_stageTimeout',
              ),
            ),
        throwsA(isA<TimeoutException>()),
      );
      connection.throwIfHasErrors();
      logE2eMessage('stage=rpc_timeout test=rpc_timeout');
    } on _RpcSkip catch (e) {
      markTestSkipped(e.reason);
    } finally {
      await _disposeConnection(connection);
    }
  });

  testWidgets('rpc_notification: notification が null で即完了することを検証する', (
    WidgetTester tester,
  ) async {
    final env = loadJwtEnv();
    if (env == null) {
      markTestSkipped(_missingJwtEnvSkipReason);
      return;
    }

    ObservedConnection? connection;
    try {
      connection = await _connectRpc(
        tester,
        env,
        suffix: '-rpc-notification',
      );
      // notification は応答を待たない契約なので、応答待ちに退行した場合に
      // ハングしないよう外側で打ち切る。即時性も 2 秒以内で確認する。
      final stopwatch = Stopwatch()..start();
      final result = await connection.connection
          .rpc(
            env.successMethod,
            params: env.successParams,
            options: const SoraRpcOptions(notification: true),
          )
          .timeout(
            _stageTimeout,
            onTimeout: () => fail(
              'notification が $_stageTimeout 以内に完了しませんでした。',
            ),
          );
      stopwatch.stop();
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 2)),
        reason: 'notification は応答を待たずに即完了すること。',
      );
      expect(
        result,
        isNull,
        reason: 'notification は応答を待たずに null で完了すること。',
      );
      connection.throwIfHasErrors();
      logE2eMessage('stage=rpc_notification test=rpc_notification result=null');
    } on _RpcSkip catch (e) {
      markTestSkipped(e.reason);
    } finally {
      await _disposeConnection(connection);
    }
  });

  testWidgets('rpc_error: SoraRpcError を検証する', (WidgetTester tester) async {
    final env = loadJwtEnv();
    if (env == null) {
      markTestSkipped(_missingJwtEnvSkipReason);
      return;
    }

    ObservedConnection? connection;
    try {
      connection = await _connectRpc(tester, env, suffix: '-rpc-error');
      try {
        await connection.connection
            .rpc(
              env.successMethod,
              params: env.errorParams,
              options: const SoraRpcOptions(timeout: _rpcTimeoutMs),
            )
            .timeout(_stageTimeout);
        markTestSkipped(
          'Sora サーバーが不正 params を拒否しなかったためスキップします。',
        );
        return;
      } on SoraRpcError catch (e) {
        _expectRpcError(e, env);
        connection.throwIfHasErrors();
        logE2eMessage(
          'stage=rpc_error code=${e.code} message=${e.message} data=${e.data}',
        );
      }
    } on _RpcSkip catch (e) {
      markTestSkipped(e.reason);
    } finally {
      await _disposeConnection(connection);
    }
  });

  testWidgets('rpc_disconnect_pending: disconnect で pending をキャンセルする', (
    WidgetTester tester,
  ) async {
    final env = commonEnv;
    if (env == null) {
      markTestSkipped(_missingCommonEnvSkipReason);
      return;
    }

    final config = _buildDisconnectConfig(
      env,
      suffix: '-rpc-disconnect-pending',
    );
    final testName = _testNameFromSuffix('-rpc-disconnect-pending');
    ObservedConnection? connection;
    try {
      connection = await ObservedConnection.create(
        name: testName,
        config: config,
      );
      logE2eMessage(
        'stage=connect_start test=$testName channelId=${config.channelId}',
      );
      await connection.connect();
      await connection.waitUntilConnected(connectionStageTimeout(config));
      final offer = await connection.waitForOffer(
        tester,
        timeout: _stageTimeout,
      );
      final skipReason = rpcDisconnectSkipReason(offer);
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // rpc DataChannel がないため sendRpcMessage は送信せず、pending だけが残る。
      // clear() が動かない退行でテストがハングしないよう、pending を 10 秒で bound する。
      final pending = connection.connection.rpc('test.method').timeout(
            _stageTimeout,
            onTimeout: () => throw StateError(
              'pending RPC did not complete within $_stageTimeout',
            ),
          );
      final expectation = expectLater(
        pending,
        throwsA(
          isA<SoraRpcError>()
              .having((e) => e.code, 'code', -1)
              .having((e) => e.message, 'message', 'Disconnected'),
        ),
      );
      // expectation が disconnect() の完了より先に失敗しても unhandled error に
      // ならないよう、すぐに listener を付ける。
      Object? expectationError;
      StackTrace? expectationStackTrace;
      final expectationCompletion = expectation.then<void>(
        (_) {},
        onError: (Object e, StackTrace st) {
          expectationError = e;
          expectationStackTrace = st;
        },
      );
      Object? disconnectError;
      StackTrace? disconnectStackTrace;
      try {
        await connection.disconnect();
      } catch (e, st) {
        disconnectError = e;
        disconnectStackTrace = st;
      }
      // disconnect() が例外でも expectation を必ず await し、未処理 Future を
      // 残さない。
      await expectationCompletion;
      if (disconnectError != null) {
        Error.throwWithStackTrace(disconnectError, disconnectStackTrace!);
      }
      if (expectationError != null) {
        Error.throwWithStackTrace(expectationError!, expectationStackTrace!);
      }
      connection.throwIfHasErrors();
      logE2eMessage(
        'stage=rpc_disconnect_pending test=rpc_disconnect_pending',
      );
    } finally {
      await _disposeConnection(connection);
    }
  });

  testWidgets('rpc_disconnect_in_flight: 送信済み RPC が 10 秒以内に終端する', (
    WidgetTester tester,
  ) async {
    final env = loadJwtEnv();
    if (env == null) {
      markTestSkipped(_missingJwtEnvSkipReason);
      return;
    }

    ObservedConnection? connection;
    try {
      connection = await _connectRpc(
        tester,
        env,
        suffix: '-rpc-disconnect-in-flight',
      );
      final pending = connection.connection.rpc(
        env.successMethod,
        params: env.successParams,
        options: const SoraRpcOptions(timeout: _rpcTimeoutMs),
      );
      // 応答・エラー・timeout のいずれでもよいので、Future が終端することを
      // 監視する。issue の設計どおり終端理由は問わない。clear() の検証は
      // rpc_disconnect_pending が担う。
      final termination = pending.then<void>((_) {}, onError: (Object _) {});
      await connection.disconnect();
      await termination.timeout(_stageTimeout);
      connection.throwIfHasErrors();
      logE2eMessage(
        'stage=rpc_disconnect_in_flight test=rpc_disconnect_in_flight',
      );
    } on _RpcSkip catch (e) {
      markTestSkipped(e.reason);
    } finally {
      await _disposeConnection(connection);
    }
  });
}

/// RPC JWT を使うテストの接続を確立し、rpc DataChannel の open まで待つ。
///
/// rpc ラベルまたは対象メソッドが offer にない場合は [_RpcSkip] を投げ、
/// 呼び出し側でテストをスキップする。
Future<ObservedConnection> _connectRpc(
  WidgetTester tester,
  RpcJwtE2eEnvironment env, {
  required String suffix,
}) async {
  for (final methodSuffix in _unsupportedRpcMethodSuffixes) {
    if (env.successMethod.endsWith('/$methodSuffix')) {
      throw _RpcSkip(
        '$methodSuffix は simulcast / spotlight 用の追加 claims と接続設定が'
        '必要なため、このテストでは扱いません。',
      );
    }
  }
  final config = _buildRpcConfig(env, suffix: suffix);
  final testName = _testNameFromSuffix(suffix);
  final connection = await ObservedConnection.create(
    name: testName,
    config: config,
  );
  try {
    logE2eMessage(
      'stage=connect_start test=$testName channelId=${config.channelId}',
    );
    await connection.connect();
    await connection.waitUntilConnected(connectionStageTimeout(config));
    // offer は switched より前に受信済みなので、先に RPC の払い出しを確認する。
    final offer = await connection.waitForOffer(
      tester,
      timeout: _stageTimeout,
    );
    final skipReason = rpcOfferSkipReason(
      offerData: offer,
      method: env.successMethod,
    );
    if (skipReason != null) {
      throw _RpcSkip(skipReason);
    }
    await connection.waitForSwitched(tester, timeout: _stageTimeout);
    final dcEvent = await connection.waitForDataChannelOpen(
      tester,
      label: 'rpc',
      timeout: _stageTimeout,
    );
    connection.throwIfHasErrors();
    logE2eMessage(
      'stage=connected test=$testName channelId=${config.channelId} '
      'rpcLabel=${dcEvent.label}',
    );
    return connection;
  } catch (e, st) {
    await _disposeConnection(connection);
    Error.throwWithStackTrace(e, st);
  }
}

/// RPC JWT を使うテストの接続設定を作る。
///
/// `no_media` を避けるため recvonly で音声・映像を有効にする。ローカル stream は
/// 使わず、RPC と DataChannel の確立だけを目的とする。
SoraConnectionConfig _buildRpcConfig(
  RpcJwtE2eEnvironment env, {
  required String suffix,
}) {
  final common = env.common;
  final channelId = buildChannelId(common.channelPrefix, suffix: suffix);
  final jwt = buildRpcJwt(
    secretKey: common.secretKey,
    channelId: channelId,
    method: env.successMethod,
  );
  return SoraConnectionConfig(
    signalingUrls: common.signalingUrls,
    channelId: channelId,
    role: SoraRole.recvonly,
    audio: true,
    video: true,
    useAudioDevice: false,
    dataChannelSignaling: true,
    ignoreDisconnectWebSocket: true,
    metadata: <String, Object?>{'access_token': jwt},
  );
}

/// disconnect テスト用の、DataChannel シグナリングを使わない接続設定を作る。
///
/// rpc DataChannel を払い出さないよう `dataChannelSignaling: false` にし、
/// RPC JWT ではなく raw の `TEST_SECRET_KEY` を access_token として送る。
SoraConnectionConfig _buildDisconnectConfig(
  RpcCommonEnvironment env, {
  required String suffix,
}) {
  return SoraConnectionConfig(
    signalingUrls: env.signalingUrls,
    channelId: buildChannelId(env.channelPrefix, suffix: suffix),
    role: SoraRole.recvonly,
    audio: true,
    video: true,
    useAudioDevice: false,
    dataChannelSignaling: false,
    metadata: <String, Object?>{'access_token': env.secretKey},
  );
}

/// 正常応答の result を期待 JSON と比較する。
///
/// `PutSignalingNotifyMetadata` は result が設定後の metadata 全体なので
/// 完全一致にする。それ以外のメソッドは Map のキー部分一致、List の要素数・
/// 各要素、スカラーの一致を比較する。
void _expectRpcSuccess(Object? actual, RpcJwtE2eEnvironment env) {
  final expected = env.successExpected;
  if (env.successMethod.endsWith('/$_putSignalingNotifyMetadataSuffix')) {
    expect(
      actual,
      equals(expected),
      reason: 'RPC の正常応答が期待 JSON と一致すること。',
    );
    return;
  }
  final mismatches = jsonContainsMismatches(actual, expected);
  expect(
    mismatches,
    isEmpty,
    reason: 'RPC の正常応答が期待 JSON のキー・配列・スカラーと一致すること。\n'
        '${mismatches.join('\n')}',
  );
}

/// error response の code / message / data を検証する。
///
/// SDK が code を補完した `SoraRpcError` は、サーバーの JSON-RPC error ではない
/// ため失敗させる。`TEST_RPC_ERROR_EXPECTED_CODE=-1` を明示した場合だけ許可する。
void _expectRpcError(SoraRpcError error, RpcJwtE2eEnvironment env) {
  final expectedCode = env.errorExpectedCode;
  if (error.code == -1 && expectedCode != -1) {
    fail('SDK が code を補完した SoraRpcError をサーバーの JSON-RPC error とみなさないこと。');
  }
  expect(
    error.code,
    isNot(0),
    reason: 'SoraRpcError.code が 0 以外であること。',
  );
  expect(
    error.message,
    isNotEmpty,
    reason: 'SoraRpcError.message が空でないこと。',
  );
  if (expectedCode != null) {
    expect(
      error.code,
      expectedCode,
      reason: 'SoraRpcError.code が期待値と一致すること。',
    );
  }
  final expectedMessage = env.errorExpectedMessage;
  if (expectedMessage != null) {
    expect(
      error.message,
      expectedMessage,
      reason: 'SoraRpcError.message が期待値と一致すること。',
    );
  }
  final expectedData = env.errorExpectedData;
  if (expectedData != null) {
    expect(
      error.data,
      equals(expectedData),
      reason: 'SoraRpcError.data が期待値と一致すること。',
    );
  }
}

/// suffix からテスト名とログ用の識別子を作る。
String _testNameFromSuffix(String suffix) {
  final name = suffix.startsWith('-') ? suffix.substring(1) : suffix;
  return name.replaceAll('-', '_');
}

/// 接続を破棄する。
///
/// cleanup の例外で元のテスト失敗を上書きしないよう、ログに留める。
Future<void> _disposeConnection(ObservedConnection? connection) async {
  if (connection == null) {
    return;
  }
  try {
    await connection.dispose();
  } catch (e) {
    logE2eMessage('stage=cleanup_failed error=$e');
  }
}

/// RPC の前提を満たさない場合にテストをスキップするための例外。
final class _RpcSkip implements Exception {
  const _RpcSkip(this.reason);

  final String reason;

  @override
  String toString() => reason;
}
