import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';
import 'package:sora_sdk/src/sora_media_devices.dart';
import 'package:sora_sdk/src/sora_media_stream.dart';

import 'support/ffi_test_environment.dart';

void main() {
  group('validateExternalVideoFrame', () {
    // 幅と高さのケースで使いまわす最小限の有効なプレーンデータ。
    Uint8List largeEnoughPlane(int width, int height, int stride) =>
        Uint8List(stride * height);

    // 有効なフレームを作るヘルパー。
    ExternalVideoFrame validFrame({int width = 640, int height = 480}) {
      final yStride = width;
      final uvStride = (width + 1) ~/ 2;
      return ExternalVideoFrame(
        width: width,
        height: height,
        yPlane: largeEnoughPlane(width, height, yStride),
        uPlane: largeEnoughPlane(width, height, uvStride),
        vPlane: largeEnoughPlane(width, height, uvStride),
        yStride: yStride,
        uStride: uvStride,
        vStride: uvStride,
      );
    }

    test('有効なフレームは例外を投げない', () {
      expect(() => validateExternalVideoFrame(validFrame()), returnsNormally);
    });

    // ---- width / height <= 0 ----

    test('幅が 0 の場合に StateError を投げる', () {
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: 0,
            height: 480,
            yPlane: Uint8List(0),
            uPlane: Uint8List(0),
            vPlane: Uint8List(0),
            yStride: 0,
            uStride: 0,
            vStride: 0,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame width and height must be positive.',
          ),
        ),
      );
    });

    test('高さが 0 の場合に StateError を投げる', () {
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: 640,
            height: 0,
            yPlane: Uint8List(0),
            uPlane: Uint8List(0),
            vPlane: Uint8List(0),
            yStride: 640,
            uStride: 320,
            vStride: 320,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame width and height must be positive.',
          ),
        ),
      );
    });

    test('幅が負の場合に StateError を投げる', () {
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: -1,
            height: 480,
            yPlane: Uint8List(0),
            uPlane: Uint8List(0),
            vPlane: Uint8List(0),
            yStride: -1,
            uStride: 0,
            vStride: 0,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame width and height must be positive.',
          ),
        ),
      );
    });

    test('高さが負の場合に StateError を投げる', () {
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: 640,
            height: -1,
            yPlane: Uint8List(0),
            uPlane: Uint8List(0),
            vPlane: Uint8List(0),
            yStride: 640,
            uStride: 320,
            vStride: 320,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame width and height must be positive.',
          ),
        ),
      );
    });

    // ---- yStride < width ----

    test('yStride が幅より小さい場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const yStride = 639;
      final uvStride = (width + 1) ~/ 2;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: Uint8List(yStride * height),
            uPlane: largeEnoughPlane(width, height, uvStride),
            vPlane: largeEnoughPlane(width, height, uvStride),
            yStride: yStride,
            uStride: uvStride,
            vStride: uvStride,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame yStride is too small.',
          ),
        ),
      );
    });

    test('yStride が幅と等しい場合は例外を投げない', () {
      expect(
        () => validateExternalVideoFrame(validFrame(width: 640, height: 480)),
        returnsNormally,
      );
    });

    // ---- chroma stride (uStride / vStride) < chromaWidth ----

    test('uStride が chromaWidth より小さい場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const chromaWidth = (width + 1) ~/ 2;
      final yStride = width;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: largeEnoughPlane(width, height, yStride),
            uPlane: Uint8List(chromaWidth * ((height + 1) ~/ 2)),
            vPlane: largeEnoughPlane(width, height, chromaWidth),
            yStride: yStride,
            uStride: chromaWidth - 1,
            vStride: chromaWidth,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame chroma stride is too small.',
          ),
        ),
      );
    });

    test('vStride が chromaWidth より小さい場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const chromaWidth = (width + 1) ~/ 2;
      final yStride = width;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: largeEnoughPlane(width, height, yStride),
            uPlane: largeEnoughPlane(width, height, chromaWidth),
            vPlane: Uint8List(chromaWidth * ((height + 1) ~/ 2)),
            yStride: yStride,
            uStride: chromaWidth,
            vStride: chromaWidth - 1,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame chroma stride is too small.',
          ),
        ),
      );
    });

    // ---- プレーンバッファ長不足 ----

    test('yPlane が yStride * height より短い場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const yStride = 640;
      final uvStride = (width + 1) ~/ 2;
      final uvHeight = (height + 1) ~/ 2;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: Uint8List(yStride * height - 1),
            uPlane: Uint8List(uvStride * uvHeight),
            vPlane: Uint8List(uvStride * uvHeight),
            yStride: yStride,
            uStride: uvStride,
            vStride: uvStride,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame yPlane is too short.',
          ),
        ),
      );
    });

    test('uPlane が uStride * chromaHeight より短い場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const yStride = 640;
      final uvStride = (width + 1) ~/ 2;
      final uvHeight = (height + 1) ~/ 2;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: Uint8List(yStride * height),
            uPlane: Uint8List(uvStride * uvHeight - 1),
            vPlane: Uint8List(uvStride * uvHeight),
            yStride: yStride,
            uStride: uvStride,
            vStride: uvStride,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame uPlane is too short.',
          ),
        ),
      );
    });

    test('vPlane が vStride * chromaHeight より短い場合に StateError を投げる', () {
      const width = 640;
      const height = 480;
      const yStride = 640;
      final uvStride = (width + 1) ~/ 2;
      final uvHeight = (height + 1) ~/ 2;
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: Uint8List(yStride * height),
            uPlane: Uint8List(uvStride * uvHeight),
            vPlane: Uint8List(uvStride * uvHeight - 1),
            yStride: yStride,
            uStride: uvStride,
            vStride: uvStride,
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'ExternalVideoFrame vPlane is too short.',
          ),
        ),
      );
    });

    // ---- 境界値: stride > width のケース ----

    test('yStride が幅より大きい場合は許容される', () {
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: 640,
            height: 480,
            yPlane: Uint8List(1280 * 480),
            uPlane: largeEnoughPlane(640, 480, 320),
            vPlane: largeEnoughPlane(640, 480, 320),
            yStride: 1280,
            uStride: 320,
            vStride: 320,
          ),
        ),
        returnsNormally,
      );
    });

    test('奇数幅の chroma stride 計算が切り上げられる', () {
      // width=639 の場合: chromaWidth = (639+1)~/2 = 320
      // width=638 の場合: chromaWidth = (638+1)~/2 = 319
      const width = 639;
      const height = 480;
      const chromaWidth = (width + 1) ~/ 2; // 320
      final yStride = width; // 639
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: largeEnoughPlane(width, height, yStride),
            uPlane: largeEnoughPlane(width, height, chromaWidth),
            vPlane: largeEnoughPlane(width, height, chromaWidth),
            yStride: yStride,
            uStride: chromaWidth,
            vStride: chromaWidth,
          ),
        ),
        returnsNormally,
      );
      // chromaStride=319 では足りない
      expect(
        () => validateExternalVideoFrame(
          ExternalVideoFrame(
            width: width,
            height: height,
            yPlane: largeEnoughPlane(width, height, yStride),
            uPlane: largeEnoughPlane(width, height, chromaWidth),
            vPlane: largeEnoughPlane(width, height, chromaWidth),
            yStride: yStride,
            uStride: chromaWidth - 1,
            vStride: chromaWidth,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('copyPlane', () {
    // source に既知のパターンを埋めておき、コピー結果を検証する。
    Uint8List filled(int length, int startValue) =>
        Uint8List.fromList(List<int>.generate(length, (i) => startValue + i));

    test('source stride == destination stride で全行をコピーする', () {
      const width = 4;
      const height = 3;
      const stride = 4;
      final source = filled(stride * height, 10);
      final destination = Uint8List(stride * height);

      copyI420Plane(
        source: source,
        requiredWidth: width,
        requiredHeight: height,
        sourceStride: stride,
        destination: destination,
        destinationStride: stride,
      );

      // 各行の width 分だけコピーされている
      expect(destination[0], 10);
      expect(destination[3], 13);
      expect(destination[4], 14);
      expect(destination[7], 17);
      expect(destination[8], 18);
      expect(destination[11], 21);
    });

    test('source stride > destination stride でコピーする', () {
      const width = 3;
      const height = 2;
      const sourceStride = 5;
      const destStride = 3;
      // 2 行 × sourceStride=5 のバッファ。行 0: 0,1,2,3,4、行 1: 5,6,7,8,9
      final source = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      final destination = Uint8List(destStride * height);

      copyI420Plane(
        source: source,
        requiredWidth: width,
        requiredHeight: height,
        sourceStride: sourceStride,
        destination: destination,
        destinationStride: destStride,
      );

      // 行 0: dest[0..2] ← source[0..2] = [0,1,2]
      expect(destination[0], 0);
      expect(destination[1], 1);
      expect(destination[2], 2);
      // destStride=3 のため dest[3] は行 1 先頭
      // 行 1: dest[3..5] ← source[5..7] = [5,6,7]
      expect(destination[3], 5);
      expect(destination[4], 6);
      expect(destination[5], 7);
      // パディング領域（sourceStride の余り部分）はコピーされない
      // dest[2] 以降で source の行末 padding が入っていない
    });

    test('source stride < destination stride でコピーする', () {
      const width = 3;
      const height = 2;
      const sourceStride = 3;
      const destStride = 5;
      final source = Uint8List.fromList([10, 11, 12, 20, 21, 22]);
      final destination = Uint8List(destStride * height);

      copyI420Plane(
        source: source,
        requiredWidth: width,
        requiredHeight: height,
        sourceStride: sourceStride,
        destination: destination,
        destinationStride: destStride,
      );

      // 行 0: dest[0..2] ← source[0..2]
      expect(destination[0], 10);
      expect(destination[1], 11);
      expect(destination[2], 12);
      // destStride=5 のため dest[3..4] は未変更
      expect(destination[3], 0);
      expect(destination[4], 0);
      // 行 1: dest[5..7] ← source[3..5]
      expect(destination[5], 20);
      expect(destination[6], 21);
      expect(destination[7], 22);
    });

    test('幅が 0 の場合は何もコピーしない', () {
      final source = filled(16, 1);
      final destination = Uint8List(16);

      copyI420Plane(
        source: source,
        requiredWidth: 0,
        requiredHeight: 4,
        sourceStride: 4,
        destination: destination,
        destinationStride: 4,
      );

      // destination は全要素 0 のまま
      expect(destination.every((e) => e == 0), isTrue);
    });

    test('高さが 0 の場合は何もコピーしない', () {
      final source = filled(16, 1);
      final destination = Uint8List(16);

      copyI420Plane(
        source: source,
        requiredWidth: 4,
        requiredHeight: 0,
        sourceStride: 4,
        destination: destination,
        destinationStride: 4,
      );

      expect(destination.every((e) => e == 0), isTrue);
    });

    test('行単位で requiredWidth だけをコピーし、stride の残りは触らない', () {
      const width = 2;
      const height = 2;
      const sourceStride = 4;
      const destStride = 4;
      final source = Uint8List.fromList([1, 2, 99, 99, 3, 4, 99, 99]);
      final destination = Uint8List.fromList([0, 0, 0, 0, 0, 0, 0, 0]);

      copyI420Plane(
        source: source,
        requiredWidth: width,
        requiredHeight: height,
        sourceStride: sourceStride,
        destination: destination,
        destinationStride: destStride,
      );

      // 行 0: dest[0..1] ← [1,2]、dest[2..3] は変更なし
      expect(destination[0], 1);
      expect(destination[1], 2);
      expect(destination[2], 0);
      expect(destination[3], 0);
      // 行 1: dest[4..5] ← [3,4]
      expect(destination[4], 3);
      expect(destination[5], 4);
      expect(destination[6], 0);
      expect(destination[7], 0);
    });
  });

  group('LocalMediaStream track cache の参照管理 (FFI)', () {
    late WebrtcClient wc;
    late LocalMediaStream stream;

    setUpAll(() {
      // Linux CI ランナーは headless で audio subsystem を持たないため、
      // real ADM の audioDeviceModuleInit が rc=-1 で失敗する。共有 factory
      // 初期化前に push ADM（push_audio_device.cc の実装は無条件で rc=0 を
      // 返す）へ切り替えることで環境依存を回避する。track cache の参照管理
      // を検証する本 group ではマイク入力を必要としないため、挙動としても
      // 意図を損なわない。共有 factory は createMediaStream / createAudioTrack
      // / connect などの初回呼び出しで生成され、setUseAudioDevice は生成後
      // には呼べない。値変更は方向を問わず拒否されるため、同ファイル内で
      // real ADM を必要とするテストは追加しないこと。
      MediaDevices.setUseAudioDevice(false);
      // createMediaStream / track 生成には共有 factory が必要なため、
      // 事前に WebrtcClient を生成して FFI を初期化する。
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
    });

    setUp(() {
      stream = MediaDevices.createMediaStream();
    });

    tearDown(() {
      stream.dispose();
    });

    tearDownAll(() {
      wc.dispose();
    });

    test('cache-hit では同じインスタンスが返る', () async {
      final audioTrack = await MediaDevices.createAudioTrack();
      stream.addTrack(audioTrack);
      try {
        final first = stream.getAudioTracks().single;
        final second = stream.getAudioTracks().single;
        // cache-hit では同一インスタンスを再利用する。
        expect(identical(first, second), isTrue);
        // 参照管理が破綻していなければ例外なく列挙できる。
        expect(first.trackId, second.trackId);
      } finally {
        await audioTrack.dispose();
      }
    });

    test('cache 入れ替わりで新規インスタンスが生成される', () async {
      final firstTrack = await MediaDevices.createAudioTrack();
      final secondTrack = await MediaDevices.createAudioTrack();
      stream.addTrack(firstTrack);
      try {
        final first = stream.getAudioTracks().single;
        // removeTrack で native 側から track を外し、別の track を追加すると
        // cache が入れ替わり、再取得では新規インスタンスが返る。
        stream.removeTrack(firstTrack);
        stream.addTrack(secondTrack);
        final second = stream.getAudioTracks().single;
        expect(identical(first, second), isFalse);
      } finally {
        await firstTrack.dispose();
        await secondTrack.dispose();
      }
    });

    test('track が消えた後の再取得で新規インスタンスが生成される', () async {
      final audioTrack = await MediaDevices.createAudioTrack();
      stream.addTrack(audioTrack);
      try {
        final first = stream.getAudioTracks().single;
        // removeTrack で native 側から track を外すと cache も破棄され、
        // 再取得は空になる。ここで crash / 例外が発生しないことを確認する。
        stream.removeTrack(audioTrack);
        expect(stream.getAudioTracks(), isEmpty);
        expect(first.isDisposed, isFalse);
      } finally {
        await audioTrack.dispose();
      }
    });

    test('dispose 済み track は cache から再利用されない', () async {
      final audioTrack = await MediaDevices.createAudioTrack();
      stream.addTrack(audioTrack);
      try {
        final first = stream.getAudioTracks().single;
        await audioTrack.dispose();
        // dispose 済み wrapper が cache に残っていても再利用せず、
        // 新規 wrapper を生成して例外を出さない。
        // native 側から track が外れていない場合は新規インスタンスが返る。
        final afterDispose = stream.getAudioTracks();
        if (afterDispose.isNotEmpty) {
          expect(identical(afterDispose.single, first), isFalse);
        }
      } finally {
        // dispose 済みのため二重 dispose は安全に無視される。
        await audioTrack.dispose();
      }
    });

    test('video track の cache-hit で同じインスタンスが返る', () {
      final videoTrack = MediaDevices.createExternalVideoTrack();
      stream.addTrack(videoTrack);
      try {
        final first = stream.getVideoTracks().single;
        // 2 回目の列挙は cache-hit で同じインスタンスを返す。
        final second = stream.getVideoTracks().single;
        expect(identical(first, second), isTrue);
      } finally {
        videoTrack.dispose();
      }
    });
  }, skip: prepareFfiTestEnvironment().skipReason);

  group('LocalVideoTrack.dispose の非同期契約 (FFI)', () {
    late WebrtcClient wc;

    setUpAll(() {
      // 前 group と設定を合わせ、共有 factory が push ADM で構築される
      // ようにする (後段の setter は factory 生成後は変更を拒否する)。
      MediaDevices.setUseAudioDevice(false);
      // 共有 dylib のロードなど FFI 経路の事前初期化を走らせる。
      // native の共有 factory は `MediaDevices.createExternalVideoTrack`
      // 初回呼び出しで lazy に生成される。
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
    });

    tearDownAll(() {
      wc.dispose();
    });

    test('接続にアタッチ中の dispose は Future.error として StateError を返す', () async {
      // 非同期契約 (throw は Future.error にラップされる) を直接検証する。
      final videoTrack = MediaDevices.createExternalVideoTrack();
      videoTrack.attachToConnection(1);
      try {
        await expectLater(
          videoTrack.dispose(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('attached to a connection'),
            ),
          ),
        );
        // throw 経路では `_disposed` に触らず、detach 後に通常経路で
        // dispose できることを memoization 不変式として直接確認する。
        expect(videoTrack.isDisposed, isFalse);
      } finally {
        // detach してから正常に dispose して native リソースを解放する。
        videoTrack.detachFromConnection(1);
        await videoTrack.dispose();
      }
    });

    test(
      'unawaited(dispose().catchError(...)) で StateError を捕捉し zone に漏れない',
      () async {
        // dartdoc が推奨する unawaited パターンで、Future.error を
        // .catchError で捕捉できることと、zone unhandled error に漏れない
        // ことの両方を検証する。sync throw だとどちらも成立しない。
        final videoTrack = MediaDevices.createExternalVideoTrack();
        videoTrack.attachToConnection(1);
        try {
          Object? caught;
          final zoneErrors = <Object>[];
          await runZonedGuarded(
            () async {
              unawaited(
                videoTrack.dispose().catchError((Object error) {
                  caught = error;
                }),
              );
              // 非同期エラーが catchError まで届くのを待つ。
              await pumpEventQueue();
            },
            (error, _) {
              zoneErrors.add(error);
            },
          );
          expect(caught, isA<StateError>());
          expect(zoneErrors, isEmpty);
        } finally {
          // detach してから正常 dispose で native リソースを解放する。
          videoTrack.detachFromConnection(1);
          await videoTrack.dispose();
        }
      },
    );
  }, skip: prepareFfiTestEnvironment().skipReason);
}
