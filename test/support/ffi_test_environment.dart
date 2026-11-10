import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sora_sdk/src/ffi/bindings.dart';

const _libraryPathEnvironmentKey = 'SORA_FFI_TEST_LIBRARY_PATH';

/// FFI 依存テストを実行できる環境かどうかを表します。
final class FfiTestEnvironment {
  const FfiTestEnvironment._({required this.skipReason});

  /// FFI 依存テストを skip する理由です。
  ///
  /// null の場合はテストを実行します。
  final String? skipReason;
}

/// FFI 依存テストの実行環境を同期的に検証します。
///
/// 環境変数が未指定の場合だけ理由付き skip を許可します。
/// 明示されたライブラリの準備や初期化に失敗した場合は、テストファイルの
/// 読み込みを失敗させます。
FfiTestEnvironment prepareFfiTestEnvironment() {
  final libraryPath = Platform.environment[_libraryPathEnvironmentKey];
  if (libraryPath == null || libraryPath.isEmpty) {
    return const FfiTestEnvironment._(
      skipReason: 'SORA_FFI_TEST_LIBRARY_PATH が未指定のため FFI 依存テストを skip します。',
    );
  }

  if (!path.isAbsolute(libraryPath)) {
    throw TestFailure(
      'SORA_FFI_TEST_LIBRARY_PATH には絶対パスを指定してください: $libraryPath',
    );
  }
  if (!File(libraryPath).existsSync()) {
    throw TestFailure('FFI テスト用ライブラリが存在しません: $libraryPath');
  }

  try {
    final lib = LibWebrtcC(DynamicLibrary.open(libraryPath));
    final factory = lib.createBuiltinVideoEncoderFactory();
    if (factory == nullptr) {
      throw TestFailure('FFI テスト用の video encoder factory を生成できません。');
    }
    lib.videoEncoderFactoryUniqueDelete(factory);
  } on TestFailure {
    rethrow;
  } catch (error) {
    throw TestFailure('FFI テスト用ライブラリの初期化に失敗しました: $libraryPath: $error');
  }

  return const FfiTestEnvironment._(skipReason: null);
}
