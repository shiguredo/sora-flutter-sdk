import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_models.dart';
import 'package:sora_sdk/sora_sdk.dart';

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

  test('選択中のログだけを消去する', () {
    final notifier = DevToolsPageNotifier()
      ..addLog('app log')
      ..addEventLog('event log');

    notifier.clearSelectedLogs();

    expect(notifier.logs, isEmpty);
    expect(notifier.eventLogs, <String>['event log']);
  });

  test('切断後は接続状態を戻しつつエラーと close info を保持する', () {
    final notifier = DevToolsPageNotifier()
      ..state = const SoraConnectedState()
      ..disconnectCloseInfo = const SoraDisconnectCloseInfo(
        code: 1011,
        reason: 'internal error',
      )
      ..connectionErrorCode = 'CONNECTION_TIMEOUT'
      ..connectionErrorMessage = 'timed out'
      ..peerConnectionStateLabel = 'connected'
      ..iceStateLabel = 'connected'
      ..dtlsStateLabel = 'connected';

    notifier.resetAfterDisconnect(
      audioEnabledValue: true,
      videoEnabledValue: true,
      notify: false,
    );

    expect(notifier.state, isA<SoraDisconnectedState>());
    expect(notifier.disconnectCloseInfo?.code, 1011);
    expect(notifier.disconnectCloseInfo?.reason, 'internal error');
    expect(notifier.connectionErrorCode, 'CONNECTION_TIMEOUT');
    expect(notifier.connectionErrorMessage, 'timed out');
    expect(notifier.peerConnectionStateLabel, 'disconnected');
    expect(notifier.iceStateLabel, 'unknown');
    expect(notifier.dtlsStateLabel, 'unknown');
  });
}
