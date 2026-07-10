import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/stats_helpers.dart';

void main() {
  group('video RTP 統計の Codec 解決', () {
    test('RTP report が直接持つ MIME type を取得する', () {
      const raw = '''
{
  "outbound": {
    "type": "outbound-rtp",
    "kind": "video",
    "mimeType": "video/VP8",
    "bytesSent": 100,
    "packetsSent": 10
  }
}
''';

      final stats = extractVideoOutboundStats(raw);

      expect(stats, isNotNull);
      expect(stats!.mimeType, 'video/VP8');
    });

    test('codecId が参照する codec report の MIME type を取得する', () {
      const raw = '''
{
  "outbound": {
    "type": "outbound-rtp",
    "kind": "video",
    "codecId": "codec-outbound",
    "bytesSent": 100,
    "packetsSent": 10
  },
  "inbound": {
    "type": "inbound-rtp",
    "kind": "video",
    "codecId": "codec-inbound",
    "bytesReceived": 90,
    "packetsReceived": 9
  },
  "codec-outbound": {
    "type": "codec",
    "mimeType": "video/H264"
  },
  "codec-inbound": {
    "id": "codec-inbound",
    "type": "codec",
    "mimeType": "video/H264"
  }
}
''';

      final outbound = extractVideoOutboundStats(raw);
      final inbound = extractVideoInboundStats(raw);

      expect(outbound, isNotNull);
      expect(outbound!.mimeType, 'video/H264');
      expect(inbound, isNotNull);
      expect(inbound!.mimeType, 'video/H264');
    });
  });
}
