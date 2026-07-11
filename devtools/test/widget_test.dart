import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'package:sora_devtools/main.dart';
import 'package:sora_devtools/src/devtools_input_validation.dart';
import 'package:sora_devtools/src/devtools_local_preview_policy.dart';
import 'package:sora_devtools/src/devtools_models.dart';
import 'package:sora_devtools/src/devtools_settings_sections.dart';

void main() {
  testWidgets('初期表示では接続タブに接続操作に必要な UI を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    expect(find.text('sora_sdk DevTools'), findsOneWidget);
    expect(find.text('Connect'), findsWidgets);
    expect(_findTabText('Video'), findsOneWidget);
    expect(_findTabText('RPC'), findsOneWidget);
    expect(_findTabText('Diagnostics'), findsOneWidget);
    expect(find.text('Media'), findsOneWidget);
    expect(find.text('State: disconnected'), findsOneWidget);
    expect(find.text('RPC Request'), findsNothing);
    expect(find.text('No video'), findsNothing);
    expect(find.text('Log Type'), findsNothing);
  });

  testWidgets('狭い幅でも Connect タブで右 overflow が発生しない', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DevToolsApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('State: disconnected'), findsOneWidget);
  });

  testWidgets('Video タブに Audio Track / Video Track の切り替えスイッチが表示される', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.tap(_findTabText('Video'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Audio Track'), findsOneWidget);
    expect(find.text('Video Track'), findsOneWidget);
  });

  testWidgets('390 px 幅の Video タブでも右 overflow が発生しない', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DevToolsApp());
    await tester.tap(_findTabText('Video'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Audio Track'), findsOneWidget);
    expect(find.text('Video Track'), findsOneWidget);
    expect(find.text('Mirror Preview'), findsOneWidget);
  });

  testWidgets('狭い幅でも Send Beep Audio は 1 個だけ表示する', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const DevToolsApp());
    await tester.ensureVisible(find.text('Send Beep Audio'));
    await tester.pumpAndSettle();

    expect(find.text('Send Beep Audio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('接続状態と接続操作を全タブ共通の AppBar に表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    expect(find.text('disconnected'), findsOneWidget);
    expect(find.byTooltip('Connect'), findsOneWidget);

    await tester.tap(_findTabText('Messages'));
    await tester.pumpAndSettle();

    expect(find.text('disconnected'), findsOneWidget);
    expect(find.byTooltip('Connect'), findsOneWidget);
  });

  testWidgets('未接続でも Video タブの Audio Track / Video Track を切り替えられる', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.tap(_findTabText('Video'));
    await tester.pumpAndSettle();

    // ラベルとスイッチを結び付ける SwitchListTile ごとに操作対象を特定する。
    final audioSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Audio Track'),
      matching: find.byType(Switch),
    );
    final videoSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Video Track'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(audioSwitch).value, isTrue);
    expect(tester.widget<Switch>(videoSwitch).value, isTrue);

    await tester.tap(audioSwitch);
    await tester.pumpAndSettle();
    await tester.tap(videoSwitch);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(audioSwitch).value, isFalse);
    expect(tester.widget<Switch>(videoSwitch).value, isFalse);
  });

  testWidgets('DataChannel の詳細設定を個別に切り替えられる', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    expect(find.text('DataChannel Signaling'), findsNothing);
    expect(find.text('Ignore WebSocket Disconnect'), findsNothing);

    await tester.ensureVisible(find.text('DataChannel'));
    await tester.tap(find.text('DataChannel'));
    await tester.pumpAndSettle();
    expect(find.text('DataChannel Signaling'), findsOneWidget);
    expect(find.text('Ignore WebSocket Disconnect'), findsOneWidget);

    final dataChannelSignalingSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'DataChannel Signaling'),
      matching: find.byType(Switch),
    );
    final ignoreDisconnectWebSocketSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Ignore WebSocket Disconnect'),
      matching: find.byType(Switch),
    );
    expect(tester.widget<Switch>(dataChannelSignalingSwitch).value, isFalse);
    expect(
      tester.widget<Switch>(ignoreDisconnectWebSocketSwitch).value,
      isFalse,
    );

    await tester.ensureVisible(dataChannelSignalingSwitch);
    await tester.tap(dataChannelSignalingSwitch);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(dataChannelSignalingSwitch).value, isTrue);
    expect(
      tester.widget<Switch>(ignoreDisconnectWebSocketSwitch).value,
      isFalse,
    );

    await tester.ensureVisible(ignoreDisconnectWebSocketSwitch);
    await tester.tap(ignoreDisconnectWebSocketSwitch);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Switch>(ignoreDisconnectWebSocketSwitch).value,
      isTrue,
    );
    expect(tester.widget<Switch>(dataChannelSignalingSwitch).value, isTrue);
  });

  testWidgets('dataChannels を有効化した場合だけ詳細を設定できる', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.ensureVisible(find.text('dataChannels'));
    await tester.tap(find.text('dataChannels'));
    await tester.pumpAndSettle();

    expect(find.text('Enable DataChannels'), findsOneWidget);
    expect(find.text('label'), findsNothing);
    expect(find.text('direction'), findsNothing);

    final enabledSwitch = find.descendant(
      of: find.widgetWithText(SwitchListTile, 'Enable DataChannels'),
      matching: find.byType(Switch),
    );
    await tester.tap(enabledSwitch);
    await tester.pumpAndSettle();

    expect(find.text('label'), findsOneWidget);
    expect(find.text('direction'), findsOneWidget);
    expect(find.text('Ordered delivery'), findsOneWidget);
    expect(find.text('Compression'), findsOneWidget);

    await tester.tap(enabledSwitch);
    await tester.pumpAndSettle();

    expect(find.text('label'), findsNothing);
    expect(find.text('direction'), findsNothing);
  });

  testWidgets('接続中の Audio Track / Video Track toggle は操作できる', (
    WidgetTester tester,
  ) async {
    var audioEnabled = true;
    var videoEnabled = true;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return DevToolsActionSection(
                busy: false,
                isConnecting: false,
                isConnected: true,
                audioEnabled: audioEnabled,
                videoEnabled: videoEnabled,
                canToggleAudioEnabled: true,
                canToggleVideoEnabled: true,
                onConnectionButtonPressed: () {},
                onToggleAudioEnabled: () {
                  setState(() {
                    audioEnabled = !audioEnabled;
                  });
                },
                onToggleVideoEnabled: () {
                  setState(() {
                    videoEnabled = !videoEnabled;
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isFalse);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).value, isTrue);
  });

  testWidgets('connecting 状態では Audio Track / Video Track toggle を操作できない', (
    WidgetTester tester,
  ) async {
    var audioToggled = false;
    var videoToggled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsActionSection(
            busy: true,
            isConnecting: true,
            isConnected: false,
            audioEnabled: true,
            videoEnabled: true,
            canToggleAudioEnabled: false,
            canToggleVideoEnabled: false,
            onConnectionButtonPressed: () {},
            onToggleAudioEnabled: () {
              audioToggled = true;
            },
            onToggleVideoEnabled: () {
              videoToggled = true;
            },
          ),
        ),
      ),
    );

    expect(tester.widget<Switch>(find.byType(Switch).at(0)).onChanged, isNull);
    expect(tester.widget<Switch>(find.byType(Switch).at(1)).onChanged, isNull);

    await tester.tap(find.byType(Switch).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch).at(1));
    await tester.pumpAndSettle();

    expect(audioToggled, isFalse);
    expect(videoToggled, isFalse);
  });

  testWidgets('未接続で Connect Video を Disabled にすると preview clear を要求する', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const _ConnectionSettingsHarness(hasRetainedConnection: false),
    );
    await _ensureMediaSettingsVisible(tester);

    await _selectBoolDropdown(tester, index: 1, valueLabel: 'Disabled');

    final state = tester.state<_ConnectionSettingsHarnessState>(
      find.byType(_ConnectionSettingsHarness),
    );
    expect(state.clearLocalPreviewCount, 1);
    expect(state.connectVideo, isFalse);
  });

  testWidgets(
    '接続オブジェクト保持中に Connect Video を Disabled にしても preview clear を要求しない',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const _ConnectionSettingsHarness(hasRetainedConnection: true),
      );
      await _ensureMediaSettingsVisible(tester);

      await _selectBoolDropdown(tester, index: 1, valueLabel: 'Disabled');

      final state = tester.state<_ConnectionSettingsHarnessState>(
        find.byType(_ConnectionSettingsHarness),
      );
      expect(state.clearLocalPreviewCount, 0);
      expect(state.connectVideo, isFalse);
    },
  );

  testWidgets(
    '未接続で Connect Audio を Disabled にし、Connect Video も Disabled なら preview clear を要求する',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const _ConnectionSettingsHarness(
          hasRetainedConnection: false,
          initialConnectVideo: false,
        ),
      );
      await _ensureMediaSettingsVisible(tester);

      await _selectBoolDropdown(tester, index: 0, valueLabel: 'Disabled');

      final state = tester.state<_ConnectionSettingsHarnessState>(
        find.byType(_ConnectionSettingsHarness),
      );
      expect(state.clearLocalPreviewCount, 1);
      expect(state.connectAudio, isFalse);
    },
  );

  testWidgets(
    '接続オブジェクト保持中に Connect Audio を Disabled にし、Connect Video も Disabled でも preview clear を要求しない',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const _ConnectionSettingsHarness(
          hasRetainedConnection: true,
          initialConnectVideo: false,
        ),
      );
      await _ensureMediaSettingsVisible(tester);

      await _selectBoolDropdown(tester, index: 0, valueLabel: 'Disabled');

      final state = tester.state<_ConnectionSettingsHarnessState>(
        find.byType(_ConnectionSettingsHarness),
      );
      expect(state.clearLocalPreviewCount, 0);
      expect(state.connectAudio, isFalse);
    },
  );

  testWidgets('タブで Video / RPC / Diagnostics を切り替えられる', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.tap(_findTabText('Video'));
    await tester.pumpAndSettle();
    expect(_findTabText('Video'), findsOneWidget);
    expect(find.text('Show Local Preview'), findsOneWidget);
    expect(find.text('Switch Camera'), findsOneWidget);
    expect(find.text('Local preview is not started'), findsOneWidget);

    await tester.tap(_findTabText('RPC'));
    await tester.pumpAndSettle();
    expect(_findTabText('RPC'), findsOneWidget);
    expect(find.text('RPC Request'), findsOneWidget);
    expect(find.text('RPC Params (JSON)'), findsOneWidget);
    expect(find.text('Send RPC'), findsOneWidget);

    await tester.tap(_findTabText('Diagnostics'));
    await tester.pumpAndSettle();
    expect(_findTabText('Diagnostics'), findsOneWidget);
    expect(find.text('Log Type'), findsOneWidget);
    expect(find.text('Search Logs'), findsOneWidget);
    expect(find.text('No logs yet'), findsOneWidget);
    expect(find.text('Follow latest'), findsOneWidget);
    expect(find.text('Clear Logs'), findsOneWidget);

    // Stats タブに切り替えて Get Stats ボタンを確認する
    await tester.tap(find.byType(DropdownButtonFormField<DevToolsLogTab>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats').last);
    await tester.pumpAndSettle();
    expect(find.text('Get Stats'), findsOneWidget);
  });

  testWidgets('未接続の Messages タブに送信可能にする操作を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.tap(_findTabText('Messages'));
    await tester.pumpAndSettle();

    expect(find.text('Connect タブで接続するとメッセージを送信できます。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('接続操作では不正な Signaling URL と空の Channel ID を表示する', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Signaling URL'),
      'https://example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Channel ID'),
      '',
    );
    await tester.tap(find.byTooltip('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('ws:// または wss:// で始まる URL を入力してください'), findsOneWidget);
    expect(find.text('Channel ID を入力してください'), findsOneWidget);
    expect(find.text('Connect Settings'), findsNothing);
  });

  testWidgets('接続確認には実際に生成する主要設定を表示する', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Signaling URL'),
      'wss://example.com/signaling',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Channel ID'),
      'test-channel',
    );
    await tester.tap(find.byTooltip('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Settings'), findsOneWidget);
    expect(find.text('audio: true'), findsOneWidget);
    expect(find.text('video: true'), findsOneWidget);
    expect(find.text('data_channels: Disabled'), findsOneWidget);
    expect(find.text('data_channel_label: #chat'), findsNothing);
    expect(find.text('ignore_disconnect_websocket: false'), findsOneWidget);
  });

  testWidgets('Messages タブから有効な設定で接続確認を開ける', (WidgetTester tester) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Signaling URL'),
      'wss://example.com/signaling',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Channel ID'),
      'test-channel',
    );
    await tester.tap(_findTabText('Messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Connect'));
    await tester.pumpAndSettle();

    expect(find.text('Connect Settings'), findsOneWidget);
    expect(
      find.text('signaling_url: wss://example.com/signaling'),
      findsOneWidget,
    );
    expect(find.text('channel_id: test-channel'), findsOneWidget);
  });

  test('接続設定の入力値を仕様に沿って検証する', _verifyInputValidation);
}

void _verifyInputValidation() {
  // Widget テストファイル内でも、接続前に利用する各検証条件を固定する。
  expect(validateSignalingUrl('wss://example.com/signaling'), isNull);
  expect(validateSignalingUrl('https://example.com'), isNotNull);
  expect(validateChannelId(''), isNotNull);
  expect(validateDataChannelLabel('#chat'), isNull);
  expect(validateDataChannelLabel('chat'), isNotNull);
  expect(validateMaxPacketLifeTime('0'), isNull);
  expect(validateMaxPacketLifeTime('65535'), isNull);
  expect(validateMaxPacketLifeTime('65536'), isNotNull);
}

Finder _findTabText(String label) {
  return find.descendant(of: find.byType(Tab), matching: find.text(label));
}

Future<void> _ensureMediaSettingsVisible(WidgetTester tester) async {
  // Media グループは initiallyExpanded: true のため展開済み
  // labelText で Connect Audio ドロップダウンを特定してスクロールする
  await tester.ensureVisible(find.text('Connect Audio'));
  await tester.pumpAndSettle();
}

Future<void> _selectBoolDropdown(
  WidgetTester tester, {
  required int index,
  required String valueLabel,
}) async {
  await tester.tap(find.byType(DropdownButtonFormField<bool>).at(index));
  await tester.pumpAndSettle();
  await tester.tap(find.text(valueLabel).last);
  await tester.pumpAndSettle();
}

class _ConnectionSettingsHarness extends StatefulWidget {
  const _ConnectionSettingsHarness({
    required this.hasRetainedConnection,
    this.initialConnectVideo = true,
  });

  final bool hasRetainedConnection;
  final bool initialConnectVideo;

  @override
  State<_ConnectionSettingsHarness> createState() =>
      _ConnectionSettingsHarnessState();
}

class _ConnectionSettingsHarnessState
    extends State<_ConnectionSettingsHarness> {
  late final TextEditingController signalingUrlController;
  late final TextEditingController channelIdController;
  late bool connectAudio;
  late bool connectVideo;
  int clearLocalPreviewCount = 0;

  @override
  void initState() {
    super.initState();
    signalingUrlController = TextEditingController();
    channelIdController = TextEditingController();
    connectAudio = true;
    connectVideo = widget.initialConnectVideo;
  }

  @override
  void dispose() {
    signalingUrlController.dispose();
    channelIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DevToolsConnectionSettingsSection(
            signalingUrlController: signalingUrlController,
            channelIdController: channelIdController,
            selectedRole: SoraRole.sendrecv,
            simulcastEnabled: false,
            selectedSimulcastRid: null,
            spotlightEnabled: false,
            selectedSpotlightFocusRid: null,
            selectedSpotlightUnfocusRid: null,
            connectAudio: connectAudio,
            connectVideo: connectVideo,
            beepAudioEnabled: false,
            needsCamera: connectVideo,
            canEditSimulcastRequestRid: false,
            canEditSpotlightRid: false,
            selectedVideoCodecType: null,
            selectedVideoBitRate: null,
            selectedResolutionIndex: null,
            selectedFrameRate: null,
            simulcastRidOptions: const <String>['r0', 'r1', 'r2'],
            videoCodecTypeOptions: const <String>['VP8', 'VP9', 'AV1', 'H264'],
            videoBitRateOptions: const <int>[500, 1000, 2000],
            frameRateOptions: const <int>[15, 30, 60],
            resolutionLabels: const <String>['640x480'],
            onRoleChanged: (_) {},
            onSimulcastEnabledChanged: (_) {},
            onSimulcastRidChanged: (_) {},
            onSpotlightEnabledChanged: (_) {},
            onSpotlightFocusRidChanged: (_) {},
            onSpotlightUnfocusRidChanged: (_) {},
            onConnectAudioChanged: _changeConnectAudio,
            onConnectVideoChanged: _changeConnectVideo,
            onBeepAudioEnabledChanged: (_) {},
            onVideoCodecTypeChanged: (_) {},
            onVideoBitRateChanged: (_) {},
            onResolutionChanged: (_) {},
            onFrameRateChanged: (_) {},
          ),
        ),
      ),
    );
  }

  void _changeConnectAudio(bool value) {
    setState(() {
      connectAudio = value;
      if (shouldClearLocalPreviewForConnectAudioChange(
        hasRetainedConnection: widget.hasRetainedConnection,
        nextConnectAudio: value,
        connectVideo: connectVideo,
      )) {
        clearLocalPreviewCount++;
      }
    });
  }

  void _changeConnectVideo(bool value) {
    setState(() {
      connectVideo = value;
      if (shouldClearLocalPreviewForConnectVideoChange(
        hasRetainedConnection: widget.hasRetainedConnection,
      )) {
        clearLocalPreviewCount++;
      }
    });
  }
}
