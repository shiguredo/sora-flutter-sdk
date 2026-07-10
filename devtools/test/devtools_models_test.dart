import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_models.dart';

void main() {
  test('ログ検索は大文字小文字を無視した部分一致で絞り込む', () {
    final notifier = DevToolsPageNotifier()
      ..addLog('[2026-01-01] connection: CONNECTED')
      ..addLog('[2026-01-01] connection: disconnected')
      ..addLog('[2026-01-01] stats: bytes=100');

    notifier.logSearchQuery = 'connected';

    expect(notifier.filteredSelectedLogs, <String>[
      '[2026-01-01] connection: CONNECTED',
      '[2026-01-01] connection: disconnected',
    ]);
  });

  test('空の検索語句では全ログを返す', () {
    final notifier = DevToolsPageNotifier()..addLog('any log');

    expect(notifier.filteredSelectedLogs, <String>['any log']);
  });

  test('該当しない検索語句では空の一覧を返す', () {
    final notifier = DevToolsPageNotifier()..addLog('connected');
    notifier.logSearchQuery = 'error';

    expect(notifier.filteredSelectedLogs, isEmpty);
  });
}
