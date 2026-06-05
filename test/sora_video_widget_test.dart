import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  group('SoraRemoteVideoWidget', () {
    /// テスト用の映像トラックを作成する
    const testTrack = RemoteMediaStreamTrack(
      trackId: 'test-track',
      kind: 'video',
      connectionId: 'test-conn',
      textureId: 123,
    );

    const testTrack2 = RemoteMediaStreamTrack(
      trackId: 'test-track',
      kind: 'video',
      connectionId: 'test-conn',
      textureId: 456,
    );

    /// Widget を pump するヘルパー
    ///
    /// [placeholder] が null の場合は Widget 側の既定値を使用する。
    Future<void> pumpRemoteWidget(
      WidgetTester tester, {
      required RemoteMediaStreamTrack track,
      BoxFit fit = BoxFit.contain,
      bool mirror = false,
      Widget? placeholder,
    }) async {
      final child = placeholder != null
          ? SoraRemoteVideoWidget(
              track: track,
              fit: fit,
              mirror: mirror,
              placeholder: placeholder,
            )
          : SoraRemoteVideoWidget(track: track, fit: fit, mirror: mirror);
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: child),
      );
    }

    testWidgets('textureId が非 null のとき Texture が存在する', (tester) async {
      await pumpRemoteWidget(tester, track: testTrack);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('textureId が null のときプレースホルダーが表示される', (tester) async {
      await pumpRemoteWidget(
        tester,
        track: const RemoteMediaStreamTrack(
          trackId: 't',
          kind: 'video',
          connectionId: 'c',
        ),
        placeholder: const Text('no video'),
      );
      expect(find.text('no video'), findsOneWidget);
    });

    testWidgets('track を別インスタンスに差し替えた後も Texture が存在し表示が維持される', (tester) async {
      await pumpRemoteWidget(tester, track: testTrack);
      expect(find.byType(Texture), findsOneWidget);

      await pumpRemoteWidget(tester, track: testTrack2);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('fit: BoxFit.fill の指定時に内部 ClipRect が存在する', (tester) async {
      await pumpRemoteWidget(tester, track: testTrack, fit: BoxFit.fill);
      expect(find.byType(ClipRect), findsOneWidget);
    });

    testWidgets('fit: BoxFit.contain （既定値） の指定時には内部 ClipRect が存在しない', (
      tester,
    ) async {
      await pumpRemoteWidget(tester, track: testTrack);
      expect(find.byType(ClipRect), findsNothing);
    });

    testWidgets('mirror が true のとき内部に Transform が存在し matrix が水平反転である', (
      tester,
    ) async {
      await pumpRemoteWidget(tester, track: testTrack, mirror: true);
      final transform = tester.widget<Transform>(find.byType(Transform));
      // Matrix4.diagonal3Values(-1, 1, 1) の storage[0] == -1
      expect(transform.transform.storage[0], -1.0);
      expect(transform.transform.storage[5], 1.0);
    });

    testWidgets('mirror が false（既定値）のとき内部に Transform が存在しない', (tester) async {
      await pumpRemoteWidget(tester, track: testTrack);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('placeholder パラメータ指定時に null textureId で指定 Widget が表示される', (
      tester,
    ) async {
      await pumpRemoteWidget(
        tester,
        track: const RemoteMediaStreamTrack(
          trackId: 't',
          kind: 'video',
          connectionId: 'c',
        ),
        placeholder: const Placeholder(),
      );
      expect(find.byType(Placeholder), findsOneWidget);
    });

    testWidgets('kind が audio の RemoteMediaStreamTrack を渡すと assert エラーになる', (
      tester,
    ) async {
      expect(
        () => SoraRemoteVideoWidget(
          track: const RemoteMediaStreamTrack(
            trackId: 't',
            kind: 'audio',
            connectionId: 'c',
          ),
        ),
        throwsAssertionError,
      );
    });

    testWidgets('textureId が null かつ placeholder 未指定のとき既定の ColoredBox が表示される', (
      tester,
    ) async {
      await pumpRemoteWidget(
        tester,
        track: const RemoteMediaStreamTrack(
          trackId: 't',
          kind: 'video',
          connectionId: 'c',
        ),
      );
      expect(find.byType(ColoredBox), findsOneWidget);
    });
  });

  group('SoraLocalVideoWidget', () {
    /// Widget を pump するヘルパー
    ///
    /// [placeholder] が null の場合は Widget 側の既定値を使用する。
    Future<void> pumpLocalWidget(
      WidgetTester tester, {
      required int? textureId,
      BoxFit fit = BoxFit.contain,
      bool mirror = false,
      Widget? placeholder,
    }) async {
      final child = placeholder != null
          ? SoraLocalVideoWidget(
              textureId: textureId,
              fit: fit,
              mirror: mirror,
              placeholder: placeholder,
            )
          : SoraLocalVideoWidget(
              textureId: textureId,
              fit: fit,
              mirror: mirror,
            );
      await tester.pumpWidget(
        Directionality(textDirection: TextDirection.ltr, child: child),
      );
    }

    testWidgets('textureId が非 null のとき Texture が存在する', (tester) async {
      await pumpLocalWidget(tester, textureId: 123);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('textureId が null のときプレースホルダーが表示される', (tester) async {
      await pumpLocalWidget(
        tester,
        textureId: null,
        placeholder: const Text('no video'),
      );
      expect(find.text('no video'), findsOneWidget);
    });

    testWidgets('textureId を非 null → 別の非 null 値に変更した後も Texture が存在し表示が維持される', (
      tester,
    ) async {
      await pumpLocalWidget(tester, textureId: 123);
      expect(find.byType(Texture), findsOneWidget);

      await pumpLocalWidget(tester, textureId: 456);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('textureId を null → 非 null に変更したとき Texture が 0 → 1 に変化する', (
      tester,
    ) async {
      await pumpLocalWidget(tester, textureId: null);
      expect(find.byType(Texture), findsNothing);

      await pumpLocalWidget(tester, textureId: 123);
      expect(find.byType(Texture), findsOneWidget);
    });

    testWidgets('fit: BoxFit.fill の指定時に内部 ClipRect が存在する', (tester) async {
      await pumpLocalWidget(tester, textureId: 123, fit: BoxFit.fill);
      expect(find.byType(ClipRect), findsOneWidget);
    });

    testWidgets('fit: BoxFit.contain （既定値） の指定時には内部 ClipRect が存在しない', (
      tester,
    ) async {
      await pumpLocalWidget(tester, textureId: 123);
      expect(find.byType(ClipRect), findsNothing);
    });

    testWidgets('mirror が true のとき内部に Transform が存在し matrix が水平反転である', (
      tester,
    ) async {
      await pumpLocalWidget(tester, textureId: 123, mirror: true);
      final transform = tester.widget<Transform>(find.byType(Transform));
      // Matrix4.diagonal3Values(-1, 1, 1) の storage[0] == -1
      expect(transform.transform.storage[0], -1.0);
      expect(transform.transform.storage[5], 1.0);
    });

    testWidgets('mirror が false（既定値）のとき内部に Transform が存在しない', (tester) async {
      await pumpLocalWidget(tester, textureId: 123);
      expect(find.byType(Transform), findsNothing);
    });

    testWidgets('placeholder パラメータ指定時に null textureId で指定 Widget が表示される', (
      tester,
    ) async {
      await pumpLocalWidget(
        tester,
        textureId: null,
        placeholder: const Placeholder(),
      );
      expect(find.byType(Placeholder), findsOneWidget);
    });

    testWidgets('textureId が null かつ placeholder 未指定のとき既定の ColoredBox が表示される', (
      tester,
    ) async {
      await pumpLocalWidget(tester, textureId: null);
      expect(find.byType(ColoredBox), findsOneWidget);
    });
  });
}
