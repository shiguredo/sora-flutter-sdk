import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/rpc_test_helpers.dart';

void main() {
  group('buildRpcJwt', () {
    test('HS256 の header / payload / 署名を生成する', () {
      final token = buildRpcJwt(
        secretKey: 'test-secret',
        channelId: 'e2e-channel',
        method: '2025.2.0/PutSignalingNotifyMetadata',
      );
      final parts = token.split('.');
      expect(parts, hasLength(3));
      final header = _decodeSegment(parts[0]);
      final payload = _decodeSegment(parts[1]);
      expect(header['alg'], 'HS256');
      expect(header['typ'], 'JWT');
      expect(payload['channel_id'], 'e2e-channel');
      expect(
        payload['rpc_methods'],
        <String>['2025.2.0/PutSignalingNotifyMetadata'],
      );
      final expectedSignature = base64Url
          .encode(
            Hmac(
              sha256,
              utf8.encode('test-secret'),
            ).convert(utf8.encode('${parts[0]}.${parts[1]}')).bytes,
          )
          .replaceAll('=', '');
      expect(parts[2], expectedSignature);
      expect(
        token,
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
        'eyJjaGFubmVsX2lkIjoiZTJlLWNoYW5uZWwiLCJycGNfbWV0aG9kcyI6'
        'WyIyMDI1LjIuMC9QdXRTaWduYWxpbmdOb3RpZnlNZXRhZGF0YSJdfQ.'
        'cYHXM9SGkP02Dej-zpU5GxBqfsio7GXBM158s5Hcg8E',
      );
    });

    test('空の署名鍵を拒否する', () {
      expect(
        () => buildRpcJwt(secretKey: '', channelId: 'c', method: 'm'),
        throwsArgumentError,
      );
    });

    test('空の channelId / method を拒否する', () {
      expect(
        () => buildRpcJwt(secretKey: 's', channelId: '', method: 'm'),
        throwsArgumentError,
      );
      expect(
        () => buildRpcJwt(secretKey: 's', channelId: 'c', method: ''),
        throwsArgumentError,
      );
    });
  });

  group('offer の RPC 判定', () {
    const method = '2025.2.0/PutSignalingNotifyMetadata';

    test('rpc ラベルと対象メソッドが揃うと skip しない', () {
      expect(
        rpcOfferSkipReason(
          offerData: <String, Object?>{
            'data_channels': <Object?>[
              <String, Object?>{'label': 'rpc'},
            ],
            'rpc_methods': <Object?>[method],
          },
          method: method,
        ),
        isNull,
      );
    });

    test('rpc ラベルが無いと skip する', () {
      final reason = rpcOfferSkipReason(
        offerData: <String, Object?>{},
        method: method,
      );
      expect(reason, isNotNull);
      expect(reason, contains('rpc ラベル'));
    });

    test('rpc_methods に対象メソッドが無いと skip する', () {
      final reason = rpcOfferSkipReason(
        offerData: <String, Object?>{
          'data_channels': <Object?>[
            <String, Object?>{'label': 'rpc'},
          ],
          'rpc_methods': <Object?>['other'],
        },
        method: method,
      );
      expect(reason, isNotNull);
      expect(reason, contains('rpc_methods'));
    });

    test('disconnect 用は rpc ラベルと rpc_methods が無ければ skip しない', () {
      expect(rpcDisconnectSkipReason(<String, Object?>{}), isNull);
    });

    test('disconnect 用は rpc ラベルがあると skip する', () {
      final reason = rpcDisconnectSkipReason(<String, Object?>{
        'data_channels': <Object?>[
          <String, Object?>{'label': 'rpc'},
        ],
      });
      expect(reason, isNotNull);
    });

    test('disconnect 用は rpc_methods があると skip する', () {
      final reason = rpcDisconnectSkipReason(<String, Object?>{
        'rpc_methods': <Object?>[method],
      });
      expect(reason, isNotNull);
    });

    test('disconnect 用は rpc_methods が空リストなら skip しない', () {
      expect(
        rpcDisconnectSkipReason(<String, Object?>{
          'rpc_methods': <Object?>[],
        }),
        isNull,
      );
    });
  });

  group('jsonContainsMismatches', () {
    test('ネストした Map / List の期待キーが一致すると空', () {
      expect(
        jsonContainsMismatches(
          <String, Object?>{
            'a': 1,
            'b': <Object?>[
              <String, Object?>{'c': 'd'},
            ],
            'extra': true,
          },
          <String, Object?>{
            'a': 1,
            'b': <Object?>[
              <String, Object?>{'c': 'd'},
            ],
          },
        ),
        isEmpty,
      );
    });

    test('キー欠落・値不一致・List 長不一致を報告する', () {
      final mismatches = jsonContainsMismatches(
        <String, Object?>{
          'a': 1,
          'b': <Object?>[1],
        },
        <String, Object?>{
          'a': 2,
          'b': <Object?>[1, 2],
          'c': true,
        },
      );
      expect(mismatches, isNotEmpty);
      final joined = mismatches.join('\n');
      expect(joined, contains(r'$.a'));
      expect(joined, contains(r'$.b'));
      expect(joined, contains(r'$.c'));
    });

    test('Map / List の型不一致を報告する', () {
      expect(
        jsonContainsMismatches(1, <String, Object?>{'a': 1}),
        contains(r'$ must be a Map'),
      );
      expect(
        jsonContainsMismatches(<String, Object?>{}, <Object?>[1]),
        contains(r'$ must be a List'),
      );
    });

    test('path を指定すると不一致箇所に接頭辞が付く', () {
      final mismatches = jsonContainsMismatches(
        <String, Object?>{},
        <String, Object?>{'a': 1},
        path: r'$.x',
      );
      expect(mismatches, contains(r'$.x.a is missing'));
    });
  });
}

Map<String, dynamic> _decodeSegment(String segment) {
  final padded = segment.padRight((segment.length + 3) ~/ 4 * 4, '=');
  return jsonDecode(utf8.decode(base64Url.decode(padded)))
      as Map<String, dynamic>;
}
