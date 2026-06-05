import 'dart:io';

import 'package:hooks/hooks.dart';

/// hook/build.dart
///
/// 以下の処理を実行する:
///   1. scripts/generate_sdk_version.dart → lib/src/sora_sdk_version.g.dart を生成
///   2. scripts/update_apple_native_binary.dart → ios/macos の Package.swift を更新
/// エラーが発生してもビルドは中断しない。
void main(List<String> args) async {
  try {
    await build(args, (input, output) async {
      final packageRoot = input.packageRoot.toFilePath();
      await Process.run('dart', [
        '$packageRoot/scripts/generate_sdk_version.dart',
        packageRoot,
      ], workingDirectory: packageRoot);
      await Process.run('dart', [
        '$packageRoot/scripts/update_apple_native_binary.dart',
      ], workingDirectory: packageRoot);
    });
  } catch (e) {
    stderr.writeln('Warning: hook/build.dart failed: $e');
  }
}
