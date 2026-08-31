import 'package:flutter_test/flutter_test.dart';

import '../integration_test/helpers/test_helpers.dart';

void main() {
  group('channel ID の分離', () {
    test('CI では workflow run ID に OS 名を付与する', () {
      final linuxChannelId = buildChannelId(
        'e2e-',
        suffix: '-audio',
        environment: const <String, String>{'GITHUB_RUN_ID': '12345'},
        operatingSystem: 'linux',
      );
      final windowsChannelId = buildChannelId(
        'e2e-',
        suffix: '-audio',
        environment: const <String, String>{'GITHUB_RUN_ID': '12345'},
        operatingSystem: 'windows',
      );

      expect(linuxChannelId, 'e2e-12345-linux-audio');
      expect(windowsChannelId, 'e2e-12345-windows-audio');
      expect(linuxChannelId, isNot(windowsChannelId));
    });
  });
}
