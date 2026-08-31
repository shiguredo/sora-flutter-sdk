import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_validator.dart';

void main() {
  group('parseSignalingUrl', () {
    test('正しい wss URL から Uri を返す', () {
      final result = parseSignalingUrl('wss://example.com/signaling');
      expect(result, isNotNull);
      expect(result!.scheme, 'wss');
      expect(result.host, 'example.com');
      expect(result.path, '/signaling');
    });

    test('正しい ws URL から Uri を返す', () {
      final result = parseSignalingUrl('ws://localhost:5000/signaling');
      expect(result, isNotNull);
      expect(result!.scheme, 'ws');
      expect(result.host, 'localhost');
      expect(result.port, 5000);
    });

    test('不正なスキームの場合は null を返す', () {
      expect(parseSignalingUrl('https://example.com/signaling'), isNull);
      expect(parseSignalingUrl('http://example.com/signaling'), isNull);
      expect(parseSignalingUrl('ftp://example.com/signaling'), isNull);
    });

    test('ホストが空の場合は null を返す', () {
      expect(parseSignalingUrl('wss:///signaling'), isNull);
    });

    test('URL の形式が不正な場合は null を返す', () {
      expect(parseSignalingUrl('not-a-url'), isNull);
      expect(parseSignalingUrl(''), isNull);
    });
  });
}
