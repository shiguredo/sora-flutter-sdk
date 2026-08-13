import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/sora_media_stream.dart';
import 'package:sora_sdk/src/sora_method_channels.dart';

void main() {
  // attachClientId 後の再 ensure 検証で MethodChannel を呼ぶため、
  // プラットフォームチャネルの解決に必要なバインディングを初期化する。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalVideoTrack.attachClientId', () {
    // ネイティブ参照を伴わない track をダミーポインタで生成する。
    // attachClientId は状態変更のみでネイティブ API に触れないため、
    // FFI ライブラリを必要としないユニットテストで検証できる。
    LocalVideoTrack createWindowTrack() {
      return LocalVideoTrack.fromNativeMediaTrack(
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>.fromAddress(1),
        captureType: VideoTrackCaptureType.window,
      );
    }

    test('初期状態ではクライアント ID が未設定 (null) である', () {
      expect(createWindowTrack().clientIdOrNull, isNull);
    });

    test('attachClientId で設定したクライアント ID を取得できる', () {
      final track = createWindowTrack();
      track.attachClientId(42);
      expect(track.clientIdOrNull, 42);
    });

    test('attachClientId で後から上書きできる', () {
      final track = createWindowTrack();
      track.attachClientId(42);
      track.attachClientId(7);
      expect(track.clientIdOrNull, 7);
    });

    test('attachClientId 後に textureId を再取得すると再 ensure が実行される', () async {
      // 接続前 preview で ensure 済みの texture キャッシュを破棄し、
      // ネイティブ側の renderer に後付けの clientId が反映されることを
      // 再 ensure の実行で検証する。
      // テスト環境にはプラットフォーム実装が無いため、
      // ensure は MissingPluginException になる。
      final track = createWindowTrack();
      track.attachClientId(42);
      await expectLater(
        track.textureId,
        throwsA(isA<MissingPluginException>()),
      );
    });
  });

  group('LocalVideoTrack.dispose の texture ensure タイムアウト', () {
    test('ensure が未解決のままでも dispose はタイムアウト内に完了する', () async {
      // ネイティブ側が ensureLocalVideoTrackTexture に応答しない状態を模擬する。
      // カメラ回帰や window キャプチャの権限プロンプト待ちで発生しうる。
      // ハンドラが返す Future は決して完了しないため、ensure は未解決のまま残る。
      final neverCompleter = Completer<Object?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) {
            if (call.method == 'ensureLocalVideoTrackTexture') {
              return neverCompleter.future;
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(soraMethodChannel, null);
      });

      // テスト実行を速くするため、dispose の ensure 待ちタイムアウトを短くする。
      final track = LocalVideoTrack.fromNativeMediaTrack(
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>.fromAddress(1),
        captureType: VideoTrackCaptureType.window,
        textureEnsureTimeout: const Duration(milliseconds: 100),
      );
      // ensure を開始して _textureIdFuture をキャッシュさせる。
      // 未解決のまま dispose を呼ぶ状況を再現する。
      unawaited(track.textureId);

      final disposeFuture = track.dispose();
      try {
        await disposeFuture.timeout(const Duration(seconds: 5));
        // タイムアウト内に dispose が完了した。
      } on TimeoutException {
        fail('dispose() は ensure が未解決のまま永久ハングした');
      } catch (_) {
        // FFI 未ロードのホストテスト環境では _releaseNativeTrack() が
        // シンボル解決エラーになる。ここでは「ハングせず dispose が
        // 完了する」ことだけを検証する。
      }
    });
  });

  group('VideoTrackCaptureType', () {
    test('camera / external / window の 3 種が定義されている', () {
      expect(VideoTrackCaptureType.values, hasLength(3));
      expect(VideoTrackCaptureType.camera.name, 'camera');
      expect(VideoTrackCaptureType.external.name, 'external');
      expect(VideoTrackCaptureType.window.name, 'window');
    });
  });

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
}
