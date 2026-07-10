import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'package:sora_devtools/main.dart';
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

  testWidgets('未接続でも Video タブの Audio Track / Video Track を切り替えられる', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DevToolsApp());

    await tester.tap(_findTabText('Video'));
    await tester.pumpAndSettle();

    // Audio Track / Video Track のテキストを直接含む Row の子孫から Switch を特定する
    final audioRow = find
        .ancestor(of: find.text('Audio Track'), matching: find.byType(Row))
        .first;
    final videoRow = find
        .ancestor(of: find.text('Video Track'), matching: find.byType(Row))
        .first;
    final audioSwitch = find.descendant(
      of: audioRow,
      matching: find.byType(Switch),
    );
    final videoSwitch = find.descendant(
      of: videoRow,
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
    expect(find.text('No video'), findsOneWidget);

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

    // Stats タブに切り替えて Get Stats ボタンを確認する
    await tester.tap(find.byType(DropdownButtonFormField<DevToolsLogTab>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats').last);
    await tester.pumpAndSettle();
    expect(find.text('Get Stats'), findsOneWidget);
  });
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
