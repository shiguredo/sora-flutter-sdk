import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';

void main() {
  // FFI を呼ばない純粋関数のため、ネイティブライブラリ無しで実行できる。
  group('resolveRecordingDeviceIndex', () {
    // guid 一致 / labelHint フォールバック / default (labelHint) の
    // 優先順位を 1 つの一覧で検証できるようにする。
    const devices = <({int index, String guid, String name})>[
      (index: 0, guid: '{guid-mic}', name: 'マイク (USB)'),
      (index: 1, guid: '{guid-default-mic}', name: 'default (マイク (USB))'),
      (index: 2, guid: '', name: 'Built-in Mic'),
    ];

    test('guid の完全一致でそのインデックスを返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{guid-mic}',
      );
      expect(index, 0);
    });

    test('name の完全一致でそのインデックスを返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: 'Built-in Mic',
      );
      expect(index, 2);
    });

    test('完全一致は labelHint の一致より優先される', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{guid-default-mic}',
        labelHint: 'マイク (USB)',
      );
      expect(index, 1);
    });

    test('完全一致が無い場合は labelHint 一致のインデックスを返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'Built-in Mic',
      );
      expect(index, 2);
    });

    test('labelHint が複数一致する場合は先頭を返す', () {
      const duplicates = <({int index, String guid, String name})>[
        (index: 0, guid: '{a}', name: 'Speaker'),
        (index: 1, guid: '{b}', name: 'Speaker'),
      ];
      final index = resolveRecordingDeviceIndex(
        devices: duplicates,
        deviceId: '{unknown}',
        labelHint: 'Speaker',
      );
      expect(index, 0);
    });

    test('preferDefaultDevice は default (labelHint) を優先する', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'マイク (USB)',
        preferDefaultDevice: true,
      );
      expect(index, 1);
    });

    test('preferDefaultDevice が false なら default (labelHint) を選ばない', () {
      // true 側との対比。default (マイク (USB)) が存在しても labelHint の
      // 一致を優先する。
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'マイク (USB)',
      );
      expect(index, 0);
    });

    test('preferDefaultDevice でも完全一致が default (labelHint) より優先される', () {
      // 完全一致 (index 2)、default (labelHint) (index 1)、labelHint 一致
      // (index 0) を別々に置き、完全一致が勝つことを検証する。
      const split = <({int index, String guid, String name})>[
        (index: 0, guid: '{plain}', name: 'Speaker'),
        (index: 1, guid: '{default}', name: 'default (Speaker)'),
        (index: 2, guid: '{exact}', name: 'Speaker USB'),
      ];
      final index = resolveRecordingDeviceIndex(
        devices: split,
        deviceId: '{exact}',
        labelHint: 'Speaker',
        preferDefaultDevice: true,
      );
      expect(index, 2);
    });

    test('labelHint が null なら preferDefaultDevice でも null を返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        preferDefaultDevice: true,
      );
      expect(index, isNull);
    });

    test('preferDefaultDevice でも default (labelHint) が無ければ labelHint を使う', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'Built-in Mic',
        preferDefaultDevice: true,
      );
      expect(index, 2);
    });

    test('default (labelHint) は完全一致のみで部分一致しない', () {
      // labelHint が 'マイク' のとき 'default (マイク (USB))' は一致しない。
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'マイク',
        preferDefaultDevice: true,
      );
      expect(index, isNull);
    });

    test('一致が無い場合は null を返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: devices,
        deviceId: '{unknown}',
        labelHint: 'unknown label',
      );
      expect(index, isNull);
    });

    test('一覧が空の場合は null を返す', () {
      final index = resolveRecordingDeviceIndex(
        devices: const <({int index, String guid, String name})>[],
        deviceId: '{unknown}',
      );
      expect(index, isNull);
    });

    test('一覧の位置ではなく ADM のインデックスを返す', () {
      // 読み取りに失敗したデバイスを除いて詰めた一覧を想定し、一覧の位置
      // 2 が ADM のインデックス 5 を指すケースを検証する。
      const compacted = <({int index, String guid, String name})>[
        (index: 0, guid: '{a}', name: 'mic-a'),
        (index: 2, guid: '{b}', name: 'mic-b'),
        (index: 5, guid: '{c}', name: 'mic-c'),
      ];
      expect(
        resolveRecordingDeviceIndex(devices: compacted, deviceId: '{c}'),
        5,
      );
      expect(
        resolveRecordingDeviceIndex(
          devices: compacted,
          deviceId: '{unknown}',
          labelHint: 'mic-c',
        ),
        5,
      );
    });
  });
}
