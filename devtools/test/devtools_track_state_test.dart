import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_track_state.dart';

void main() {
  group('currentTrackEnabled', () {
    test('track がないとき fallback を返す', () {
      expect(currentTrackEnabled(null, fallback: true), isTrue);
      expect(currentTrackEnabled(const <bool>[], fallback: false), isFalse);
    });

    test('最初の track の enabled 状態を返す', () {
      expect(currentTrackEnabled(<bool>[false], fallback: true), isFalse);
      expect(currentTrackEnabled(<bool>[true, false], fallback: false), isTrue);
    });
  });
}
