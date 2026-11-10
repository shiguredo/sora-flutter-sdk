#!/usr/bin/env dart
// native_deps.json の Apple 向け XCFramework 設定を
// iOS / macOS の Package.swift へ同期するスクリプト。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final scriptDir = File(Platform.script.toFilePath()).parent;
final rootDir = scriptDir.parent;
final manifestPath = File(p.join(scriptDir.path, 'native_deps.json'));

const packageSwiftPaths = [
  'ios/sora_sdk/Package.swift',
  'macos/sora_sdk/Package.swift',
];

class AppleNativeBinary {
  AppleNativeBinary({
    required this.version,
    required this.baseUrl,
    required this.artifact,
    required this.checksum,
  });

  final String version;
  final String baseUrl;
  final String artifact;
  final String checksum;

  String get url => '$baseUrl/$version/$artifact';
}

void failWith(String message) {
  stderr.writeln(message);
  exit(1);
}

AppleNativeBinary loadManifest() {
  if (!manifestPath.existsSync()) {
    failWith('File not found: ${manifestPath.path}');
  }

  final dynamic decodedValue = jsonDecode(manifestPath.readAsStringSync());
  if (decodedValue is! Map<String, dynamic>) {
    failWith('Failed to parse manifest: ${manifestPath.path}');
  }
  final Map<String, dynamic> decoded = decodedValue as Map<String, dynamic>;

  final dynamic libwebrtcCValue = decoded['libwebrtc_c'];
  if (libwebrtcCValue is! Map<String, dynamic>) {
    failWith('libwebrtc_c is not set in ${manifestPath.path}');
  }
  final Map<String, dynamic> libwebrtcC =
      libwebrtcCValue as Map<String, dynamic>;
  final libwebrtcCBaseUrl = (libwebrtcC['base_url'] as String?)?.trim() ?? '';
  if (libwebrtcCBaseUrl.isEmpty) {
    failWith('libwebrtc_c.base_url is not set in ${manifestPath.path}');
  }

  final dynamic sectionValue = libwebrtcC['apple_xcframework'];
  if (sectionValue is! Map<String, dynamic>) {
    failWith(
      'libwebrtc_c.apple_xcframework is not set in ${manifestPath.path}',
    );
  }
  final Map<String, dynamic> section = sectionValue as Map<String, dynamic>;

  String requireField(String key) {
    final value = (section[key] as String?)?.trim() ?? '';
    if (value.isEmpty) {
      failWith('$key is not set in ${manifestPath.path}');
    }
    return value;
  }

  return AppleNativeBinary(
    version: (libwebrtcC['version'] as String?)?.trim().isNotEmpty == true
        ? (libwebrtcC['version'] as String).trim()
        : _failVersion(),
    baseUrl: (section['base_url'] as String?)?.trim().isNotEmpty == true
        ? (section['base_url'] as String).trim()
        : libwebrtcCBaseUrl,
    artifact: requireField('artifact'),
    checksum: requireField('checksum'),
  );
}

String _failVersion() {
  failWith('libwebrtc_c.version is not set in ${manifestPath.path}');
  throw StateError('unreachable');
}

void updatePackageSwift(String relativePath, AppleNativeBinary config) {
  final file = File(p.join(rootDir.path, relativePath));
  if (!file.existsSync()) {
    failWith('File not found: ${file.path}');
  }

  var content = file.readAsStringSync();
  final urlPattern = RegExp(r'let libwebrtcCXCFrameworkURL =\n  "([^"]+)"');
  final checksumPattern = RegExp(
    r'let libwebrtcCXCFrameworkChecksum =\n  "([^"]+)"',
  );

  if (!urlPattern.hasMatch(content)) {
    failWith('Failed to find XCFramework URL in ${file.path}');
  }
  if (!checksumPattern.hasMatch(content)) {
    failWith('Failed to find XCFramework checksum in ${file.path}');
  }

  content = content.replaceFirst(
    urlPattern,
    'let libwebrtcCXCFrameworkURL =\n  "${config.url}"',
  );
  content = content.replaceFirst(
    checksumPattern,
    'let libwebrtcCXCFrameworkChecksum =\n  "${config.checksum}"',
  );

  file.writeAsStringSync(content);
}

Future<void> main(List<String> args) async {
  if (args.isNotEmpty) {
    failWith('Usage: dart run scripts/update_apple_native_binary.dart');
  }

  final updated = loadManifest();

  for (final relativePath in packageSwiftPaths) {
    updatePackageSwift(relativePath, updated);
  }

  stdout.writeln('Updated Apple native binary configuration.');
}
