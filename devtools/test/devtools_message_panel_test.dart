import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_message_panel.dart';
import 'package:sora_devtools/src/devtools_message_send_policy.dart';
import 'package:sora_devtools/src/devtools_models.dart';

void main() {
  testWidgets('末尾表示中は新着メッセージへ追従する', (WidgetTester tester) async {
    await tester.pumpWidget(const _MessagePanelHarness());

    await tester.tap(find.text('Add messages'));
    await tester.pumpAndSettle();

    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(controller.offset, controller.position.maxScrollExtent);
  });

  testWidgets('過去を表示中は新着メッセージで末尾へ移動しない', (WidgetTester tester) async {
    await tester.pumpWidget(const _MessagePanelHarness());
    await tester.tap(find.text('Add messages'));
    await tester.pumpAndSettle();

    final listView = find.byType(ListView);
    final controller = tester.widget<ListView>(listView).controller!;
    await tester.drag(listView, const Offset(0, 400));
    await tester.pumpAndSettle();
    final offsetBeforeNewMessage = controller.offset;
    expect(
      offsetBeforeNewMessage,
      lessThan(controller.position.maxScrollExtent - 48),
    );

    await tester.tap(find.text('Add one'));
    await tester.pumpAndSettle();

    expect(controller.offset, offsetBeforeNewMessage);
  });

  testWidgets('DataChannel が open していない間はメッセージを送信できない', (
    WidgetTester tester,
  ) async {
    var sent = false;
    const guidance = 'DataChannel が open するまでメッセージを送信できません。';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsMessagePanel(
            label: '#chat',
            messages: const <DevToolsMessageEntry>[],
            sendEnabled: false,
            sendGuidance: guidance,
            onSend: (_) {
              sent = true;
            },
          ),
        ),
      ),
    );

    expect(find.text(guidance), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(sent, isFalse);
  });

  test('open 済みの custom DataChannel だけ送信できる', () {
    expect(
      canSendDataChannelMessage(
        isConnected: true,
        hasConnection: true,
        dataChannelsEnabled: true,
        hasDataChannelConfig: true,
        label: '#chat',
        openedDataChannelLabels: <String>{'#chat'},
      ),
      isTrue,
    );
    expect(
      canSendDataChannelMessage(
        isConnected: true,
        hasConnection: true,
        dataChannelsEnabled: true,
        hasDataChannelConfig: true,
        label: '#chat',
        openedDataChannelLabels: <String>{},
      ),
      isFalse,
    );
    expect(
      canSendDataChannelMessage(
        isConnected: true,
        hasConnection: true,
        dataChannelsEnabled: false,
        hasDataChannelConfig: true,
        label: '#chat',
        openedDataChannelLabels: <String>{'#chat'},
      ),
      isFalse,
    );
    expect(
      canSendDataChannelMessage(
        isConnected: true,
        hasConnection: true,
        dataChannelsEnabled: true,
        hasDataChannelConfig: false,
        label: '#chat',
        openedDataChannelLabels: <String>{'#chat'},
      ),
      isFalse,
    );
  });

  test('無効な dataChannels に対する設定案内を返す', () {
    expect(
      buildDataChannelMessageSendGuidance(
        isConnected: true,
        dataChannelsEnabled: false,
        hasDataChannelConfig: false,
        label: null,
        openedDataChannelLabels: <String>{},
      ),
      'Connect タブで dataChannels を有効にし、label を設定してから再接続してください。',
    );
  });

  test('メッセージ履歴は件数と一件当たりのサイズを制限する', () {
    final notifier = DevToolsPageNotifier();
    final longText = 'a' * (DevToolsMessageHistory.maxMessageBytes + 1);
    notifier.addSentMessage(
      DevToolsMessageEntry(
        timestamp: DateTime(2026, 7, 11),
        label: '#chat',
        text: longText,
        isSent: true,
      ),
    );
    expect(notifier.messages.single.text, contains('[truncated 1 bytes]'));

    final receivedText = DevToolsMessageHistory.decodeReceivedMessage(
      Uint8List.fromList(
        List<int>.filled(DevToolsMessageHistory.maxMessageBytes + 1, 0x61),
      ),
    );
    notifier.addReceivedMessage(
      DevToolsMessageEntry(
        timestamp: DateTime(2026, 7, 11),
        label: '#chat',
        text: receivedText,
        isSent: false,
      ),
    );
    expect(notifier.messages.last.text, endsWith('[truncated 1 bytes]'));

    for (var index = 0; index <= DevToolsMessageHistory.maxEntries; index++) {
      notifier.addReceivedMessage(
        DevToolsMessageEntry(
          timestamp: DateTime(2026, 7, 11),
          label: '#chat',
          text: 'message $index',
          isSent: false,
        ),
      );
    }

    expect(notifier.messages, hasLength(DevToolsMessageHistory.maxEntries));
    expect(notifier.messages.first.text, 'message 1');
  });
}

class _MessagePanelHarness extends StatefulWidget {
  const _MessagePanelHarness();

  @override
  State<_MessagePanelHarness> createState() => _MessagePanelHarnessState();
}

class _MessagePanelHarnessState extends State<_MessagePanelHarness> {
  final List<DevToolsMessageEntry> _messages = <DevToolsMessageEntry>[];

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: DevToolsMessagePanel(
                label: '#chat',
                messages: _messages,
                sendEnabled: true,
                sendGuidance: null,
                onSend: _sendMessage,
              ),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      for (var index = 0; index < 50; index++) {
                        _messages.add(_message(index));
                      }
                    });
                  },
                  child: const Text('Add messages'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _messages.add(_message(_messages.length));
                    });
                  },
                  child: const Text('Add one'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // テスト表示用の実データを生成する。
  DevToolsMessageEntry _message(int index) {
    return DevToolsMessageEntry(
      timestamp: DateTime(2026, 7, 11, 12, 0, index % 60),
      label: '#chat',
      text: 'message $index',
      isSent: false,
    );
  }

  // 入力欄から送った内容も実際の履歴へ追加する。
  void _sendMessage(String text) {
    setState(() {
      _messages.add(
        DevToolsMessageEntry(
          timestamp: DateTime(2026, 7, 11, 12),
          label: '#chat',
          text: text,
          isSent: true,
        ),
      );
    });
  }
}
