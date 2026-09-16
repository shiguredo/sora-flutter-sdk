#!/usr/bin/env dart
// devtools/lib/configs/environment.example.dart を environment.dart に一時コピーし、
// devtools/ ディレクトリで flutter analyze を実行した後、一時コピーを削除するヘルパースクリプト。
// prek の flutter-analyze-devtools フックから起動されることを前提としている。
// OS に依存しない dart run 方式を採用することで、Windows / Unix 両方で動作する。

import 'dart:io';

import 'package:path/path.dart' as p;

final scriptDir = File(Platform.script.toFilePath()).parent;
final rootDir = scriptDir.parent;
final examplePath = p.join(
  rootDir.path,
  'devtools',
  'lib',
  'configs',
  'environment.example.dart',
);
final envPath = p.join(
  rootDir.path,
  'devtools',
  'lib',
  'configs',
  'environment.dart',
);

Future<int> runAnalyze(String workingDir) async {
  final flutterExecutable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final result = await Process.run(flutterExecutable, [
    'analyze',
    '--fatal-infos',
    'lib',
    'test',
  ], workingDirectory: workingDir);

  stdout.write(result.stdout);
  stderr.write(result.stderr);

  return result.exitCode;
}

Future<int> main(List<String> args) async {
  final exampleFile = File(examplePath);
  if (!exampleFile.existsSync()) {
    stderr.writeln('environment.example.dart が見つかりません: $examplePath');
    return 1;
  }

  try {
    // environment.example.dart を environment.dart にコピーする
    exampleFile.copySync(envPath);
  } on FileSystemException catch (e) {
    stderr.writeln('environment.dart へのコピーに失敗しました: $e');
    return 1;
  }

  int exitCode;
  try {
    // devtools/ ディレクトリで flutter analyze を実行する
    final devtoolsDir = p.join(rootDir.path, 'devtools');
    exitCode = await runAnalyze(devtoolsDir);
  } finally {
    // 一時コピーした environment.dart を削除する
    final envFile = File(envPath);
    if (envFile.existsSync()) {
      envFile.deleteSync();
    }
  }

  return exitCode;
}
