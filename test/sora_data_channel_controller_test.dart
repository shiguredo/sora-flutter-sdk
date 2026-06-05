import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/library_loader.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';
import 'package:sora_sdk/src/sora_data_channel_controller.dart';
import 'package:sora_sdk/src/sora_data_channel_event.dart';

/// libwebrtc-c が利用可能か確認する。
bool _ffiAvailable() {
  try {
    final lib = LibWebrtcC(loadLibWebrtcC());
    final f = lib.createBuiltinVideoEncoderFactory();
    if (f != nullptr) {
      lib.videoEncoderFactoryUniqueDelete(f);
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

/// テスト用に DataChannelController を生成する。
/// webrtcClient は FFI 依存のため dynamic で迂回する。

void main() {
  group('deflateDecompress', () {
    const testText = 'hello data channel';
    final plainBytes = Uint8List.fromList(utf8.encode(testText));

    Uint8List compress({required bool raw}) =>
        Uint8List.fromList(ZLibCodec(raw: raw).encoder.convert(plainBytes));

    test('raw=false のデータを preferred=null で展開すると raw=false を検出する', () {
      final input = compress(raw: false);
      final result = DataChannelController.deflateDecompress(input, null);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, false);
    });

    test('raw=true のデータを preferred=null で展開すると raw=true を検出する', () {
      final input = compress(raw: true);
      final result = DataChannelController.deflateDecompress(input, null);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, true);
    });

    test('raw=false のデータを preferred=false で展開すると detectedRaw=false を返す', () {
      final input = compress(raw: false);
      final result = DataChannelController.deflateDecompress(input, false);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, false);
    });

    test('raw=true のデータを preferred=true で展開すると detectedRaw=true を返す', () {
      final input = compress(raw: true);
      final result = DataChannelController.deflateDecompress(input, true);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, true);
    });

    test('raw=false のデータを誤った preferred=true で渡すと !preferred へ fallback する', () {
      final input = compress(raw: false);
      final result = DataChannelController.deflateDecompress(input, true);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, false);
    });

    test('raw=true のデータを誤った preferred=false で渡すと !preferred へ fallback する', () {
      final input = compress(raw: true);
      final result = DataChannelController.deflateDecompress(input, false);
      expect(result.output, plainBytes);
      expect(result.detectedRaw, true);
    });

    test('不正なデータを preferred=null で渡すと FormatException を投げる', () {
      final invalid = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(
        () => DataChannelController.deflateDecompress(invalid, null),
        throwsA(isA<FormatException>()),
      );
    });

    test('不正なデータを preferred 指定で渡すと fallback 後も失敗し FormatException を投げる', () {
      final invalid = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      expect(
        () => DataChannelController.deflateDecompress(invalid, true),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('findDataChannelConfig', () {
    final payload = <String, Object?>{
      'data_channels': [
        {'label': 'notify', 'compress': true, 'direction': 'upstream'},
        {'label': 'push', 'compress': false},
        {'label': '#custom1', 'compress': true},
      ],
    };

    test('存在するラベルの config を返す', () {
      final config = DataChannelController.findDataChannelConfig(
        payload,
        label: 'notify',
      );
      expect(config, isNotNull);
      expect(config!['compress'], true);
      expect(config['direction'], 'upstream');
    });

    test('存在するラベルの compress=false を正しく返す', () {
      final config = DataChannelController.findDataChannelConfig(
        payload,
        label: 'push',
      );
      expect(config, isNotNull);
      expect(config!['compress'], false);
    });

    test('存在しないラベルは null を返す', () {
      final config = DataChannelController.findDataChannelConfig(
        payload,
        label: 'signaling',
      );
      expect(config, isNull);
    });

    test('data_channels が List でない場合は null を返す', () {
      final config = DataChannelController.findDataChannelConfig(
        <String, Object?>{'data_channels': 'invalid'},
        label: 'notify',
      );
      expect(config, isNull);
    });

    test('data_channels が空リストの場合は null を返す', () {
      final config = DataChannelController.findDataChannelConfig(
        <String, Object?>{'data_channels': <Map<String, Object?>>[]},
        label: 'notify',
      );
      expect(config, isNull);
    });

    test('data_channels キーがない場合は null を返す', () {
      final config = DataChannelController.findDataChannelConfig(
        <String, Object?>{},
        label: 'notify',
      );
      expect(config, isNull);
    });
  });

  group('updateCompressFlagIfPresent', () {
    test('ラベルが存在する場合、compress フラグを更新する', () {
      final payload = <String, Object?>{
        'data_channels': [
          {'label': 'notify', 'compress': true},
        ],
      };
      var flag = false;
      DataChannelController.updateCompressFlagIfPresent(
        payload,
        'notify',
        (v) => flag = v,
      );
      expect(flag, true);
    });

    test('ラベルが存在しない場合、フラグを更新しない', () {
      final payload = <String, Object?>{
        'data_channels': [
          {'label': 'notify', 'compress': true},
        ],
      };
      var flag = false;
      DataChannelController.updateCompressFlagIfPresent(
        payload,
        'signaling',
        (v) => flag = v,
      );
      expect(flag, false);
    });

    test('data_channels が無い場合、フラグを更新しない', () {
      var flag = false;
      DataChannelController.updateCompressFlagIfPresent(
        <String, Object?>{},
        'notify',
        (v) => flag = v,
      );
      expect(flag, false);
    });

    test('data_channels が List でない場合、フラグを更新しない', () {
      var flag = false;
      DataChannelController.updateCompressFlagIfPresent(
        <String, Object?>{'data_channels': 'invalid'},
        'notify',
        (v) => flag = v,
      );
      expect(flag, false);
    });
  });

  group('resolveCustomChannelCompress', () {
    test('# プレフィックスのラベルをキャッシュする', () {
      final payload = <String, Object?>{
        'data_channels': [
          {'label': '#custom1', 'compress': true},
          {'label': '#custom2', 'compress': false},
          {'label': 'notify', 'compress': true},
        ],
      };
      final result = DataChannelController.resolveCustomChannelCompress(
        payload,
      );
      expect(result['#custom1'], true);
      expect(result['#custom2'], false);
      expect(result.containsKey('notify'), false);
      expect(result.containsKey('#missing'), false);
    });

    test('data_channels が無い場合は空 map を返す', () {
      final result = DataChannelController.resolveCustomChannelCompress(
        <String, Object?>{},
      );
      expect(result, isEmpty);
    });
  });

  group('applyOfferMessage 回帰シナリオ', () {
    test('初回 offer で signalingCompress=true → re-offer 欠落後も維持', () {
      var signalingCompress = false;

      // 初回 offer: signaling label が data_channels に存在
      final initialOffer = <String, Object?>{
        'data_channels': [
          {'label': 'signaling', 'compress': true},
          {'label': 'notify', 'compress': false},
        ],
      };
      DataChannelController.updateCompressFlagIfPresent(
        initialOffer,
        'signaling',
        (v) => signalingCompress = v,
      );
      expect(signalingCompress, true);

      // re-offer: data_channels が空（signaling ラベル欠落）
      final reoffer = <String, Object?>{};
      DataChannelController.updateCompressFlagIfPresent(
        reoffer,
        'signaling',
        (v) => signalingCompress = v,
      );
      // 欠落時は更新されない → true のまま維持
      expect(signalingCompress, true);
    });

    test('初回 offer で compress=false → re-offer 欠落後も維持', () {
      var notifyCompress = false;

      final initialOffer = <String, Object?>{
        'data_channels': [
          {'label': 'notify', 'compress': false},
        ],
      };
      DataChannelController.updateCompressFlagIfPresent(
        initialOffer,
        'notify',
        (v) => notifyCompress = v,
      );
      expect(notifyCompress, false);

      final reoffer = <String, Object?>{};
      DataChannelController.updateCompressFlagIfPresent(
        reoffer,
        'notify',
        (v) => notifyCompress = v,
      );
      expect(notifyCompress, false);
    });

    test('re-offer で compress 値が変更された場合は反映される', () {
      var signalingCompress = false;

      final initialOffer = <String, Object?>{
        'data_channels': [
          {'label': 'signaling', 'compress': true},
        ],
      };
      DataChannelController.updateCompressFlagIfPresent(
        initialOffer,
        'signaling',
        (v) => signalingCompress = v,
      );
      expect(signalingCompress, true);

      // re-offer で compress が false に変更
      final reoffer = <String, Object?>{
        'data_channels': [
          {'label': 'signaling', 'compress': false},
        ],
      };
      DataChannelController.updateCompressFlagIfPresent(
        reoffer,
        'signaling',
        (v) => signalingCompress = v,
      );
      expect(signalingCompress, false);
    });

    test('re-offer の data_channels に label があっても compress キー欠落時は維持', () {
      var signalingCompress = true;

      // re-offer: label はあるが compress キーがない
      final reoffer = <String, Object?>{
        'data_channels': [
          {'label': 'signaling'},
        ],
      };
      DataChannelController.updateCompressFlagIfPresent(
        reoffer,
        'signaling',
        (v) => signalingCompress = v,
      );
      // containsKey('compress') = false のため更新されない
      expect(signalingCompress, true);
    });
  });

  group('applyOfferMessage → emitDataChannelAvailable (FFI)', () {
    late bool ffiAvailable;

    setUpAll(() {
      ffiAvailable = _ffiAvailable();
    });

    test('re-offer 欠落後も open event の compress が維持される', () {
      if (!ffiAvailable) return;
      final openEvents = <SoraDataChannelEvent>[];

      final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      final ctrl = DataChannelController(
        webrtcClient: wc,
        onDebugMessage: (_) {},
        onPushMessage: (_) {},
        onNotifyMessage: (_) {},
        onDataChannelMessageEvent: (_) {},
        onDataChannelOpenEvent: (e) => openEvents.add(e),
        onSignalingEvent: (_, _, _) {},
        onLogEvent: (_, [_]) {},
        onSignalingClose: (_, _) async {},
        onConnectionCreated: (_) {},
        decodeJsonMap: (_) async => null,
        decodeJson: (_) async => null,
      );

      try {
        // 初回 offer: signaling と custom に compress あり
        ctrl.applyOfferMessage({
          'data_channels': [
            {'label': 'signaling', 'compress': true},
            {'label': '#custom', 'compress': true},
          ],
        });
        expect(ctrl.signalingCompress, true);

        // re-offer: data_channels 欠落 → compress は維持される
        ctrl.applyOfferMessage({});
        expect(ctrl.signalingCompress, true);

        // open 通知の compress は実動作と一致する
        ctrl.emitDataChannelAvailable('signaling');
        ctrl.emitDataChannelAvailable('#custom');

        expect(openEvents.length, 2);
        final sigEvent = openEvents.firstWhere((e) => e.label == 'signaling');
        final customEvent = openEvents.firstWhere((e) => e.label == '#custom');
        expect(sigEvent.compress, true);
        expect(customEvent.compress, true);
      } finally {
        wc.dispose();
      }
    });
  });

  group('signaling メッセージ順序', () {
    late bool ffiAvailable;

    setUpAll(() {
      ffiAvailable = _ffiAvailable();
    });

    test(
      '大きい signaling の decode が Isolate offload でも入力順に close を処理する',
      () async {
        if (!ffiAvailable) return;
        final closeReasons = <String?>[];
        final debugMessages = <String>[];
        final largeReason = 'a' * (33 * 1024);
        final largeText = jsonEncode(<String, Object?>{
          'type': 'close',
          'code': 4100,
          'reason': largeReason,
        });
        final smallText = jsonEncode(<String, Object?>{
          'type': 'close',
          'code': 4101,
          'reason': 'small',
        });

        final wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
        final ctrl = DataChannelController(
          webrtcClient: wc,
          onDebugMessage: (message) => debugMessages.add(message),
          onPushMessage: (_) {},
          onNotifyMessage: (_) {},
          onDataChannelMessageEvent: (_) {},
          onDataChannelOpenEvent: (_) {},
          onSignalingEvent: (_, _, _) {},
          onLogEvent: (_, [_]) {},
          onSignalingClose: (_, reason) async {
            closeReasons.add(reason);
          },
          onConnectionCreated: (_) {},
          decodeJsonMap: (text) async {
            if (text.length > 32 * 1024) {
              return Isolate.run<Map<String, Object?>?>(() {
                final decoded = jsonDecode(text);
                if (decoded is! Map) {
                  return null;
                }
                return Map<String, Object?>.from(
                  decoded.map(
                    (Object? key, Object? value) => MapEntry('$key', value),
                  ),
                );
              });
            }
            final decoded = jsonDecode(text);
            if (decoded is! Map) {
              return null;
            }
            return Map<String, Object?>.from(
              decoded.map(
                (Object? key, Object? value) => MapEntry('$key', value),
              ),
            );
          },
          decodeJson: (_) async => null,
        );

        try {
          await Future.wait<void>([
            ctrl.handleMessage('signaling', largeText),
            ctrl.handleMessage('signaling', smallText),
          ]);

          expect(closeReasons.length, 2);
          expect(closeReasons[0], largeReason);
          expect(closeReasons[1], 'small');
          expect(
            debugMessages.any(
              (message) => message.contains('dc(signaling) recv'),
            ),
            isTrue,
          );
        } finally {
          wc.dispose();
        }
      },
    );
  });
}
