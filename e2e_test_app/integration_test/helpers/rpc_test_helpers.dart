import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'test_helpers.dart';

/// RPC E2E の共通環境変数。
final class RpcCommonEnvironment {
  const RpcCommonEnvironment({
    required this.secretKey,
    required this.signalingUrls,
    required this.channelPrefix,
  });

  final String secretKey;
  final List<String> signalingUrls;
  final String channelPrefix;
}

/// RPC JWT を使うテストの環境変数。
final class RpcJwtE2eEnvironment {
  const RpcJwtE2eEnvironment({
    required this.common,
    required this.successMethod,
    required this.successParams,
    required this.successExpected,
    required this.errorParams,
    required this.errorExpectedCode,
    required this.errorExpectedMessage,
    required this.errorExpectedData,
  });

  final RpcCommonEnvironment common;
  final String successMethod;
  final Object? successParams;
  final Object? successExpected;
  final Object? errorParams;
  final int? errorExpectedCode;
  final String? errorExpectedMessage;
  final Object? errorExpectedData;
}

/// RPC E2E の共通環境変数を読み込む。
///
/// 必須変数が欠けている場合は null を返し、呼び出し側でスキップする。
/// 既存 E2E の `loadE2eEnvironment()` は expect で失敗するため、RPC では
/// 接続前にスキップできるよう別の loader を使う。
RpcCommonEnvironment? loadRpcE2eEnvironment() {
  final secretKey = _env('TEST_SECRET_KEY');
  final urlsRaw = _env('TEST_SIGNALING_URLS');
  final channelPrefixRaw = Platform.environment['TEST_CHANNEL_ID_PREFIX'];
  if (secretKey == null || urlsRaw == null || channelPrefixRaw == null) {
    return null;
  }
  final signalingUrls = parseSignalingUrls(urlsRaw);
  if (signalingUrls.isEmpty) {
    return null;
  }
  return RpcCommonEnvironment(
    secretKey: secretKey,
    signalingUrls: signalingUrls,
    // 既存 E2E と同じく空文字の prefix も許容し、buildChannelId に任せる。
    channelPrefix: channelPrefixRaw.trim(),
  );
}

/// RPC JWT を使うテストの環境変数を読み込む。
///
/// 共通変数に加えて `TEST_RPC_SUCCESS_*` が揃っていない場合は null を返す。
/// JSON の形式が不正な場合は、設定ミスを隠さないように例外にする。
RpcJwtE2eEnvironment? loadRpcJwtE2eEnvironment(RpcCommonEnvironment common) {
  final successMethod = _env('TEST_RPC_SUCCESS_METHOD');
  final successParamsRaw = _env('TEST_RPC_SUCCESS_PARAMS_JSON');
  final successExpectedRaw = _env('TEST_RPC_SUCCESS_EXPECTED_JSON');
  if (successMethod == null ||
      successParamsRaw == null ||
      successExpectedRaw == null) {
    return null;
  }

  final successParams = _parseRequiredJson(
    successParamsRaw,
    name: 'TEST_RPC_SUCCESS_PARAMS_JSON',
  );
  final successExpected = _parseRequiredJson(
    successExpectedRaw,
    name: 'TEST_RPC_SUCCESS_EXPECTED_JSON',
  );
  final errorParamsRaw = _env('TEST_RPC_ERROR_PARAMS_JSON');
  final errorExpectedCodeRaw = _env('TEST_RPC_ERROR_EXPECTED_CODE');
  final errorExpectedMessageRaw = _env('TEST_RPC_ERROR_EXPECTED_MESSAGE');
  final errorExpectedDataRaw = _env('TEST_RPC_ERROR_EXPECTED_DATA_JSON');

  return RpcJwtE2eEnvironment(
    common: common,
    successMethod: successMethod,
    successParams: successParams,
    successExpected: successExpected,
    errorParams: _buildErrorParams(successParams, errorParamsRaw),
    errorExpectedCode: _parseOptionalInt(
      errorExpectedCodeRaw,
      name: 'TEST_RPC_ERROR_EXPECTED_CODE',
    ),
    errorExpectedMessage: errorExpectedMessageRaw,
    errorExpectedData: _parseOptionalJson(
      errorExpectedDataRaw,
      name: 'TEST_RPC_ERROR_EXPECTED_DATA_JSON',
    ),
  );
}

/// HS256 JWT を生成する。
///
/// JWT 専用ライブラリは使わず、`crypto` の HMAC-SHA256 と
/// `dart:convert` の base64Url だけで header / payload / signature を組み立てる。
/// テストサーバーは `metadata.access_token` の JWT を検証し、private claims の
/// `rpc_methods` を認証成功時の RPC 許可に反映する。
String buildRpcJwt({
  required String secretKey,
  required String channelId,
  required String method,
}) {
  if (secretKey.isEmpty) {
    // secret 値はエラーメッセージに含めない。
    throw ArgumentError('secretKey must not be empty');
  }
  if (channelId.isEmpty) {
    throw ArgumentError.value(channelId, 'channelId', 'must not be empty');
  }
  if (method.isEmpty) {
    throw ArgumentError.value(method, 'method', 'must not be empty');
  }
  final header = <String, Object?>{
    'alg': 'HS256',
    'typ': 'JWT',
  };
  final payload = <String, Object?>{
    'channel_id': channelId,
    'rpc_methods': <String>[method],
  };
  final headerPart = _base64UrlNoPadding(utf8.encode(jsonEncode(header)));
  final payloadPart = _base64UrlNoPadding(utf8.encode(jsonEncode(payload)));
  final signingInput = '$headerPart.$payloadPart';
  final signature = Hmac(
    sha256,
    utf8.encode(secretKey),
  ).convert(utf8.encode(signingInput)).bytes;
  return '$signingInput.${_base64UrlNoPadding(signature)}';
}

/// offer の内容から RPC JWT を使うテストをスキップすべき理由を返す。
///
/// rpc ラベルまたは対象メソッドが offer にない場合は、サーバーが RPC を
/// 払い出していないためテストをスキップする。
String? rpcOfferSkipReason({
  required Map<String, Object?> offerData,
  required String method,
}) {
  if (!_hasRpcDataChannel(offerData)) {
    return 'Sora サーバーが rpc ラベルの DataChannel を払い出さないためスキップします。';
  }
  final rpcMethods = _rpcMethods(offerData);
  if (rpcMethods == null || !rpcMethods.contains(method)) {
    return 'Sora サーバーが $method を rpc_methods に含めないためスキップします。';
  }
  return null;
}

/// disconnect テストで rpc DataChannel が払い出されていないことを確認する。
///
/// `dataChannelSignaling: false` では通常 rpc DataChannel は払い出されないが、
/// サーバーが想定外に払い出した場合は pending と応答のレースを避けられないため
/// スキップする。
String? rpcDisconnectSkipReason(Map<String, Object?> offerData) {
  final rpcMethods = _rpcMethods(offerData);
  if (_hasRpcDataChannel(offerData) ||
      (rpcMethods != null && rpcMethods.isNotEmpty)) {
    return 'rpc DataChannel が払い出される接続では pending と応答のレースを避けられないためスキップします。';
  }
  return null;
}

/// [expected] に含まれるキーが [actual] に存在し、値が一致しない箇所を返す。
///
/// Map は期待キーの部分一致、List は要素数と各要素の一致を要求する。
/// E2E の結果比較をテスト可能な純粋関数に切り出したもの。
List<String> jsonContainsMismatches(
  Object? actual,
  Object? expected, {
  String path = r'$',
}) {
  final mismatches = <String>[];
  _collectJsonContainsMismatches(actual, expected, path, mismatches);
  return mismatches;
}

void _collectJsonContainsMismatches(
  Object? actual,
  Object? expected,
  String path,
  List<String> mismatches,
) {
  if (expected is Map) {
    if (actual is! Map) {
      mismatches.add('$path must be a Map');
      return;
    }
    for (final entry in expected.entries) {
      final key = entry.key;
      if (!actual.containsKey(key)) {
        mismatches.add('$path.$key is missing');
        continue;
      }
      _collectJsonContainsMismatches(
        actual[key],
        entry.value,
        '$path.$key',
        mismatches,
      );
    }
    return;
  }
  if (expected is List) {
    if (actual is! List) {
      mismatches.add('$path must be a List');
      return;
    }
    if (actual.length != expected.length) {
      mismatches
          .add('$path length is ${actual.length}, expected ${expected.length}');
    }
    final length =
        actual.length < expected.length ? actual.length : expected.length;
    for (var i = 0; i < length; i++) {
      _collectJsonContainsMismatches(
        actual[i],
        expected[i],
        '$path[$i]',
        mismatches,
      );
    }
    return;
  }
  if (actual != expected) {
    mismatches.add('$path is actual=$actual, expected=$expected');
  }
}

bool _hasRpcDataChannel(Map<String, Object?> offerData) {
  final dataChannels = offerData['data_channels'];
  return dataChannels is List &&
      dataChannels.any((channel) {
        return channel is Map && channel['label'] == 'rpc';
      });
}

List<Object?>? _rpcMethods(Map<String, Object?> offerData) {
  final rpcMethods = offerData['rpc_methods'];
  return rpcMethods is List ? rpcMethods : null;
}

Object? _buildErrorParams(Object? successParams, String? errorParamsRaw) {
  if (errorParamsRaw != null) {
    return _parseRequiredJson(
      errorParamsRaw,
      name: 'TEST_RPC_ERROR_PARAMS_JSON',
    );
  }
  if (successParams is Map) {
    return <String, Object?>{
      ...Map<String, Object?>.from(successParams),
      'invalid_param': true,
    };
  }
  // success params が JSON オブジェクトでない場合は、error 用の params を
  // 明示するのが本来の運用。未指定時は最小限の不正 params を送る。
  return <String, Object?>{'invalid_param': true};
}

int? _parseOptionalInt(String? raw, {required String name}) {
  if (raw == null) {
    return null;
  }
  final value = int.tryParse(raw);
  if (value == null) {
    throw FormatException('$name must be an integer: $raw');
  }
  return value;
}

Object? _parseOptionalJson(String? raw, {required String name}) {
  if (raw == null) {
    return null;
  }
  return _parseRequiredJson(raw, name: name);
}

Object? _parseRequiredJson(String raw, {required String name}) {
  try {
    return jsonDecode(raw);
  } on FormatException catch (e) {
    throw FormatException('$name contains invalid JSON: $e');
  }
}

String? _env(String name) {
  return _nonEmpty(Platform.environment[name]?.trim());
}

String? _nonEmpty(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return raw;
}

String _base64UrlNoPadding(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
