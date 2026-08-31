import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/library_loader.dart';
import 'package:sora_sdk/src/ffi/simulcast_video_encoder_factory.dart'
    show SimulcastVideoEncoderFactory;

import 'support/ffi_test_environment.dart';

/// テスト用に builtin factory を生成する。
Pointer<WebrtcVideoEncoderFactoryUnique> _createBuiltinFactory(LibWebrtcC lib) {
  final factory = lib.createBuiltinVideoEncoderFactory();
  if (factory == nullptr) {
    throw TestFailure('テスト用の video encoder factory を生成できません。');
  }
  return factory;
}

void main() {
  final ffiTestEnvironment = prepareFfiTestEnvironment();

  group('SimulcastVideoEncoderFactory onNativeDestroy', () {
    test('does not crash with nullptr', () {
      expect(
        () => SimulcastVideoEncoderFactory.onNativeDestroy(nullptr),
        returnsNormally,
      );
    });

    test('does not free valid userData (ownership in _cleanup)', () {
      const blockSize = 1024;
      final block = calloc<Uint8>(blockSize);
      try {
        block[0] = 0xAB;
        block[blockSize - 1] = 0xCD;
        expect(
          () =>
              SimulcastVideoEncoderFactory.onNativeDestroy(block.cast<Void>()),
          returnsNormally,
        );
        expect(block[0], 0xAB);
        expect(block[blockSize - 1], 0xCD);
      } finally {
        calloc.free(block);
      }
    });

    test('can be called twice safely', () {
      final block = calloc<Uint8>(64);
      try {
        SimulcastVideoEncoderFactory.onNativeDestroy(block.cast<Void>());
        expect(
          () =>
              SimulcastVideoEncoderFactory.onNativeDestroy(block.cast<Void>()),
          returnsNormally,
        );
      } finally {
        calloc.free(block);
      }
    });
  });

  group('SimulcastVideoEncoderFactory dispose (FFI)', () {
    late LibWebrtcC lib;

    setUpAll(() {
      lib = LibWebrtcC(loadLibWebrtcC());
    });

    test('dispose() once does not throw', () {
      final inner = _createBuiltinFactory(lib);
      final factory = SimulcastVideoEncoderFactory(lib, inner);
      factory.dispose();
      // _cleanup() が 1 回目の dispose で例外を投げなければ OK。
    });

    test('dispose() twice does not throw', () {
      final inner = _createBuiltinFactory(lib);
      final factory = SimulcastVideoEncoderFactory(lib, inner);
      factory.dispose();
      // _cleaned フラグにより 2 回目の _cleanup() は早期 return する。
      expect(() => factory.dispose(), returnsNormally);
    });

    test('_cleanup() runs safely on normal construction', () {
      final inner = _createBuiltinFactory(lib);
      // 正常構築→dispose の経路で _cleanup() がクラッシュせず完了すれば
      // _cbs / _native / _inner / _userData が正しく解放されている。
      // コンストラクタ途中失敗経路の検証は、コードレビューで
      // `catch (_) { _cleanup(); rethrow; }` の到達性を確認する。
      final factory = SimulcastVideoEncoderFactory(lib, inner);
      factory.dispose();
    });
  }, skip: ffiTestEnvironment.skipReason);
}
