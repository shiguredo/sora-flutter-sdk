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

  group('audio RTP 統計', () {
    test('送受信量と MIME type を取得する', () {
      const raw = '''
{
  "outbound": {
    "type": "outbound-rtp",
    "kind": "audio",
    "codecId": "audio-codec",
    "bytesSent": 1200,
    "packetsSent": 12
  },
  "inbound": {
    "type": "inbound-rtp",
    "mediaType": "audio",
    "codecId": "audio-codec",
    "bytesReceived": "1100",
    "packetsReceived": 11
  },
  "audio-codec": {
    "type": "codec",
    "mimeType": "audio/opus"
  }
}
''';

      final outbound = extractAudioOutboundStats(raw);
      final inbound = extractAudioInboundStats(raw);

      expect(outbound, isNotNull);
      expect(outbound!.bytesSent, 1200);
      expect(outbound.packetsSent, 12);
      expect(outbound.mimeType, 'audio/opus');
      expect(inbound, isNotNull);
      expect(inbound!.bytesReceived, 1100);
      expect(inbound.packetsReceived, 11);
      expect(inbound.mimeType, 'audio/opus');
    });
  });
}
