import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

/// カンマまたは空白区切りのシグナリング URL をリストにする。
///
/// CI の secrets やローカル実行では区切り文字が揺れやすいため、
/// カンマと空白のどちらでも複数 URL を指定できるようにする。
List<String> parseSignalingUrls(String raw) {
  return raw
      .split(RegExp(r'[\s,]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
}

/// CI では [GITHUB_RUN_ID] と OS 名を付与し、ローカルでは時刻でユニーク化する。
///
/// CI では同じ workflow run 内の値を使い、ログ上で追跡しやすくする。
/// 同じテストが複数 OS で並列実行されても、OS 名によって channel を分離する。
/// ローカルでは連続実行しても channelId が衝突しないよう、現在時刻を付ける。
/// [suffix] を指定すると channel ID の末尾に付与する。CI の matrix 並列実行時に
/// テスト間で channel ID が衝突するのを防ぐために使う。
String buildChannelId(
  String prefix, {
  String suffix = '',
  Map<String, String>? environment,
  String? operatingSystem,
}) {
  final currentEnvironment = environment ?? Platform.environment;
  final currentOperatingSystem = operatingSystem ?? Platform.operatingSystem;
  final runId = currentEnvironment['GITHUB_RUN_ID']?.trim();
  if (runId != null && runId.isNotEmpty) {
    return '$prefix$runId-$currentOperatingSystem$suffix';
  }
  return '$prefix${DateTime.now().microsecondsSinceEpoch}$suffix';
}

/// [TEST_SECRET_KEY] を connect の metadata に載せる。
///
/// - `{` で始まる場合は JSON オブジェクトとして解釈する
/// - JWT 風の 3 セグメントなら文字列のまま渡す
/// - それ以外は access_token ラップ（検証環境に合わせて変更可）
Object? metadataFromSecretKey(String secretKey) {
  final t = secretKey.trim();
  if (t.isEmpty) {
    return null;
  }
  if (t.startsWith('{')) {
    try {
      return jsonDecode(t) as Object?;
    } on FormatException {
      // JSON でなければ access_token 扱いへ落とす
    }
  }
  if (_looksLikeCompactJwt(t)) {
    return t;
  }
  return <String, Object?>{'access_token': t};
}

/// 値が compact JWT 形式に見えるかどうかを返す。
///
/// compact JWT は header.payload.signature の 3 パートで構成される。
bool _looksLikeCompactJwt(String value) {
  final parts = value.split('.');
  if (parts.length != 3) {
    return false;
  }
  return parts.every((String p) => p.isNotEmpty);
}

/// E2E テストで共有する接続情報。
final class E2eEnvironment {
  const E2eEnvironment({
    required this.secretKey,
    required this.signalingUrls,
    required this.channelPrefix,
    required this.metadata,
  });

  final String secretKey;
  final List<String> signalingUrls;
  final String channelPrefix;
  final Object? metadata;
}

/// 必須環境変数を読み込み、E2E テスト用の設定を返す。
E2eEnvironment loadE2eEnvironment() {
  final secretKey = Platform.environment['TEST_SECRET_KEY']?.trim();
  final urlsRaw = Platform.environment['TEST_SIGNALING_URLS']?.trim();
  final channelPrefix = Platform.environment['TEST_CHANNEL_ID_PREFIX']?.trim();

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

  return E2eEnvironment(
    secretKey: secretKey,
    signalingUrls: signalingUrls,
    channelPrefix: channelPrefix!,
    metadata: metadataFromSecretKey(secretKey),
  );
}

/// 接続待ちに使う標準 timeout を返す。
Duration connectionStageTimeout(SoraConnectionConfig config) {
  return config.timeoutOptions.connectionTimeout + const Duration(seconds: 15);
}

/// E2E テストの進捗や診断情報を英語ログで出力する。
void logE2eMessage(String message) {
  // ignore: avoid_print
  print('[e2e] $message');
}

/// Cleanup step を実行し、エラーを収集する。
///
/// [cleanupErrors] にエラー文言を追記する。例外が発生しても cleanup を中断
/// せずに次の step へ進むことを可能にする。
Future<void> runCleanupStep(
  List<String> cleanupErrors,
  String name,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    cleanupErrors.add('$name: $e');
    logE2eMessage('stage=cleanup_error step=$name error=$e');
  }
}
