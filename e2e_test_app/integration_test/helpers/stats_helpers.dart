import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

/// getStats の JSON を再帰的に走査し、DTLS connected または candidate-pair succeeded を探す。
bool statsJsonSuggestsMediaPathUp(String raw) {
  try {
    final decoded = jsonDecode(raw) as Object?;
    return _walk(decoded);
  } on FormatException {
    return false;
  }
}

bool _walk(Object? node) {
  if (node is Map) {
    final type = node['type'];
    final dtls = node['dtlsState'];
    if (dtls == 'connected') {
      return true;
    }
    if (type == 'candidate-pair' && node['state'] == 'succeeded') {
      return true;
    }
    for (final Object? value in node.values) {
      if (_walk(value)) {
        return true;
      }
    }
  } else if (node is List) {
    for (final Object? item in node) {
      if (_walk(item)) {
        return true;
      }
    }
  }
  return false;
}

/// [getStats] の JSON 全体から stats report らしい Map を再帰的に集める。
///
/// SDK や platform ごとに report の入れ子構造が変わっても、`type` を持つ
/// report を抽出できるようにする。
List<Map<Object?, Object?>> statsReports(String raw) {
  final decoded = jsonDecode(raw) as Object?;
  final reports = <Map<Object?, Object?>>[];

  void collect(Object? node) {
    if (node is Map) {
      if (node['type'] != null) {
        reports.add(node);
      }
      for (final Object? value in node.values) {
        collect(value);
      }
    } else if (node is List) {
      for (final Object? item in node) {
        collect(item);
      }
    }
  }

  collect(decoded);
  return reports;
}

/// [getStats] の JSON 全体から report ID と report の対応を集める。
///
/// WebRTC の RTP report は `mimeType` を直接持たず、`codecId` で codec
/// report を参照する場合がある。JSON の map key と report 内の `id` のどちらの
/// 形式でも参照できるようにする。
Map<String, Map<Object?, Object?>> statsReportsById(String raw) {
  final decoded = jsonDecode(raw) as Object?;
  final reports = <String, Map<Object?, Object?>>{};

  void collect(Object? node) {
    if (node is Map) {
      if (node['type'] != null) {
        final reportId = node['id'];
        if (reportId is String && reportId.isNotEmpty) {
          reports[reportId] = node;
        }
      }
      for (final MapEntry<Object?, Object?> entry in node.entries) {
        final value = entry.value;
        if (value is Map && value['type'] != null && entry.key is String) {
          reports[entry.key as String] = value;
        }
        collect(value);
      }
    } else if (node is List) {
      for (final Object? item in node) {
        collect(item);
      }
    }
  }

  collect(decoded);
  return reports;
}

/// RTP report 自身または `codecId` が参照する codec report から MIME type を返す。
String? videoMimeTypeForRtpReport(
  Map<Object?, Object?> report,
  Map<String, Map<Object?, Object?>> reportsById,
) {
  final directMimeType = report['mimeType'];
  if (directMimeType is String && directMimeType.isNotEmpty) {
    return directMimeType;
  }

  final codecId = report['codecId'];
  if (codecId is! String || codecId.isEmpty) {
    return null;
  }

  final codecReport = reportsById[codecId];
  final codecMimeType = codecReport?['mimeType'];
  if (codecMimeType is String && codecMimeType.isNotEmpty) {
    return codecMimeType;
  }
  return null;
}

/// stats report の数値を [int] として取り出す。
///
/// native stats の型は platform によって int / double / String に揺れる。
/// 検証側では整数として比較したいため、受け入れられる型だけ変換する。
int? intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

/// video outbound-rtp の送信統計。
final class VideoOutboundStats {
  const VideoOutboundStats({
    required this.bytesSent,
    required this.packetsSent,
    required this.framesEncoded,
    required this.framesSent,
    this.mimeType,
    this.width,
    this.height,
  });

  final int bytesSent;
  final int packetsSent;
  final int? framesEncoded;
  final int? framesSent;
  final String? mimeType;
  final int? width;
  final int? height;

  @override
  String toString() {
    return 'VideoOutboundStats('
        'bytesSent=$bytesSent, '
        'packetsSent=$packetsSent, '
        'framesEncoded=$framesEncoded, '
        'framesSent=$framesSent, '
        'mimeType=$mimeType, '
        'width=$width, '
        'height=$height)';
  }
}

/// video inbound-rtp の受信統計。
final class VideoInboundStats {
  const VideoInboundStats({
    required this.bytesReceived,
    required this.packetsReceived,
    required this.framesDecoded,
    required this.framesReceived,
    this.mimeType,
    this.width,
    this.height,
  });

  final int bytesReceived;
  final int packetsReceived;
  final int? framesDecoded;
  final int? framesReceived;
  final String? mimeType;
  final int? width;
  final int? height;

  @override
  String toString() {
    return 'VideoInboundStats('
        'bytesReceived=$bytesReceived, '
        'packetsReceived=$packetsReceived, '
        'framesDecoded=$framesDecoded, '
        'framesReceived=$framesReceived, '
        'mimeType=$mimeType, '
        'width=$width, '
        'height=$height)';
  }
}

/// [getStats] の JSON 文字列から video outbound-rtp の送信統計を取り出す。
///
/// 複数の video outbound-rtp report がある場合は、送信量とフレーム数を合算する。
/// 最初の report から codec と解像度情報も取得する。
VideoOutboundStats? extractVideoOutboundStats(String raw) {
  final reports = statsReports(raw);
  final reportsById = statsReportsById(raw);
  var bytesSent = 0;
  var packetsSent = 0;
  int? framesEncoded;
  int? framesSent;
  String? mimeType;
  int? width;
  int? height;
  var found = false;

  for (final report in reports) {
    final type = report['type'];
    final kind = report['kind'] ?? report['mediaType'];
    if (type != 'outbound-rtp' || kind != 'video') {
      continue;
    }

    found = true;
    bytesSent += intValue(report['bytesSent']) ?? 0;
    packetsSent += intValue(report['packetsSent']) ?? 0;

    final reportFramesEncoded = intValue(report['framesEncoded']);
    if (reportFramesEncoded != null) {
      framesEncoded = (framesEncoded ?? 0) + reportFramesEncoded;
    }

    final reportFramesSent = intValue(report['framesSent']);
    if (reportFramesSent != null) {
      framesSent = (framesSent ?? 0) + reportFramesSent;
    }

    mimeType ??= videoMimeTypeForRtpReport(report, reportsById);
    width ??= intValue(report['frameWidth']);
    height ??= intValue(report['frameHeight']);
  }

  if (!found) {
    return null;
  }
  return VideoOutboundStats(
    bytesSent: bytesSent,
    packetsSent: packetsSent,
    framesEncoded: framesEncoded,
    framesSent: framesSent,
    mimeType: mimeType,
    width: width,
    height: height,
  );
}

/// [getStats] の JSON 文字列から video inbound-rtp の受信統計を取り出す。
///
/// 複数の video inbound-rtp report がある場合は、受信量とフレーム数を合算する。
VideoInboundStats? extractVideoInboundStats(String raw) {
  final reports = statsReports(raw);
  final reportsById = statsReportsById(raw);
  var bytesReceived = 0;
  var packetsReceived = 0;
  int? framesDecoded;
  int? framesReceived;
  String? mimeType;
  int? width;
  int? height;
  var found = false;

  for (final report in reports) {
    final type = report['type'];
    final kind = report['kind'] ?? report['mediaType'];
    if (type != 'inbound-rtp' || kind != 'video') {
      continue;
    }

    found = true;
    bytesReceived += intValue(report['bytesReceived']) ?? 0;
    packetsReceived += intValue(report['packetsReceived']) ?? 0;

    final reportFramesDecoded = intValue(report['framesDecoded']);
    if (reportFramesDecoded != null) {
      framesDecoded = (framesDecoded ?? 0) + reportFramesDecoded;
    }

    final reportFramesReceived = intValue(report['framesReceived']);
    if (reportFramesReceived != null) {
      framesReceived = (framesReceived ?? 0) + reportFramesReceived;
    }

    mimeType ??= videoMimeTypeForRtpReport(report, reportsById);
    width ??= intValue(report['frameWidth']);
    height ??= intValue(report['frameHeight']);
  }

  if (!found) {
    return null;
  }
  return VideoInboundStats(
    bytesReceived: bytesReceived,
    packetsReceived: packetsReceived,
    framesDecoded: framesDecoded,
    framesReceived: framesReceived,
    mimeType: mimeType,
    width: width,
    height: height,
  );
}

/// video outbound-rtp の送信量が確認できるまで [getStats] を待ち合わせる。
///
/// [previous] を指定した場合は、前回取得した送信量より `bytesSent` と
/// `packetsSent` が増えるまで待つ。フレーム投入は `Timer` で進むため、
/// 待機中は [tester] で時間を進める。
Future<VideoOutboundStats> waitForVideoOutboundStats(
  WidgetTester tester,
  SoraConnection connection, {
  VideoOutboundStats? previous,
}) async {
  const maxAttempts = 30;
  const interval = Duration(milliseconds: 500);
  VideoOutboundStats? lastStats;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final raw = await connection.getStats();
    if (raw != null && raw.isNotEmpty) {
      final stats = extractVideoOutboundStats(raw);
      if (stats != null) {
        lastStats = stats;
        final hasTraffic = stats.bytesSent > 0 && stats.packetsSent > 0;
        final hasGrowth = previous == null ||
            (stats.bytesSent > previous.bytesSent &&
                stats.packetsSent > previous.packetsSent);
        if (hasTraffic && hasGrowth) {
          return stats;
        }
      }
    }

    await tester.pump(interval);
  }

  if (lastStats == null) {
    throw StateError(
      'Timed out: no video outbound-rtp report found. '
      'Check that the external video track is sending frames.',
    );
  }
  throw StateError(
    'Timed out: video outbound-rtp found but no traffic. '
    'previous=$previous last=$lastStats',
  );
}

/// video inbound-rtp の受信量が確認できるまで [getStats] を待ち合わせる。
///
/// [previous] を指定した場合は、前回取得した受信量より `bytesReceived` と
/// `packetsReceived` が増えるまで待つ。
Future<VideoInboundStats> waitForVideoInboundStats(
  WidgetTester tester,
  SoraConnection connection, {
  VideoInboundStats? previous,
}) async {
  const maxAttempts = 30;
  const interval = Duration(milliseconds: 500);
  VideoInboundStats? lastStats;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final raw = await connection.getStats();
    if (raw != null && raw.isNotEmpty) {
      final stats = extractVideoInboundStats(raw);
      if (stats != null) {
        lastStats = stats;
        final hasTraffic = stats.bytesReceived > 0 && stats.packetsReceived > 0;
        final hasGrowth = previous == null ||
            (stats.bytesReceived > previous.bytesReceived &&
                stats.packetsReceived > previous.packetsReceived);
        if (hasTraffic && hasGrowth) {
          return stats;
        }
      }
    }

    await tester.pump(interval);
  }

  if (lastStats == null) {
    throw StateError(
      'Timed out: no video inbound-rtp report found. '
      'Check that the receiver has subscribed to the sender video.',
    );
  }
  throw StateError(
    'Timed out: video inbound-rtp found but no traffic. '
    'previous=$previous last=$lastStats',
  );
}
