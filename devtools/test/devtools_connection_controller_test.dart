import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_connection_controller.dart';
import 'package:sora_devtools/src/devtools_connection_subscription_controller.dart';
import 'package:sora_devtools/src/devtools_models.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  group('DevToolsConnectionController.setTrackEnabled', () {
    test('audio の enabled 状態を connection へ反映する', () {
      final connection = _FakeSoraConnection(audioEnabled: true);
      final controller = _createController();

      final actualEnabled = controller.setTrackEnabled(
        DevToolsSetTrackEnabledRequest(
          connection: connection,
          enabled: false,
          isAudio: true,
        ),
      );

      expect(connection.setAudioEnabledCalls, 1);
      expect(connection.lastAudioEnabled, isFalse);
      expect(actualEnabled, isFalse);
    });

    test('video の enabled 状態を connection へ反映する', () {
      final connection = _FakeSoraConnection(videoEnabled: false);
      final controller = _createController();

      final actualEnabled = controller.setTrackEnabled(
        DevToolsSetTrackEnabledRequest(
          connection: connection,
          enabled: true,
          isAudio: false,
        ),
      );

      expect(connection.setVideoEnabledCalls, 1);
      expect(connection.lastVideoEnabled, isTrue);
      expect(actualEnabled, isTrue);
    });

    test('audio track がない場合は実際の enabled 状態として false を返す', () {
      final connection = _FakeSoraConnection(hasAudioTrack: false);
      final controller = _createController();

      final actualEnabled = controller.setTrackEnabled(
        DevToolsSetTrackEnabledRequest(
          connection: connection,
          enabled: true,
          isAudio: true,
        ),
      );

      expect(connection.setAudioEnabledCalls, 1);
      expect(actualEnabled, isFalse);
    });

    test('video track がない場合は実際の enabled 状態として false を返す', () {
      final connection = _FakeSoraConnection(hasVideoTrack: false);
      final controller = _createController();

      final actualEnabled = controller.setTrackEnabled(
        DevToolsSetTrackEnabledRequest(
          connection: connection,
          enabled: true,
          isAudio: false,
        ),
      );

      expect(connection.setVideoEnabledCalls, 1);
      expect(actualEnabled, isFalse);
    });
  });
}

DevToolsConnectionController _createController() {
  return DevToolsConnectionController(
    pageNotifier: DevToolsPageNotifier(),
    sdkMethodChannel: const MethodChannel('test/sora_sdk'),
    permissionChannel: const MethodChannel('test/permissions'),
    subscriptionController: DevToolsConnectionSubscriptionController(
      isMounted: () => true,
      onEvent: (_) {},
      onDebugEvent: (_) {},
      onLocalVideo: (_) {},
      onDebugMessage: (_) {},
    ),
    appendLog: (_) {},
    appendEventLog: (_) {},
    disposeLocalStream: (_) async {},
  );
}

class _FakeSoraConnection implements SoraConnection {
  _FakeSoraConnection({
    bool audioEnabled = true,
    bool videoEnabled = true,
    this.hasAudioTrack = true,
    this.hasVideoTrack = true,
  }) : _audioEnabled = audioEnabled,
       _videoEnabled = videoEnabled;

  final bool hasAudioTrack;
  final bool hasVideoTrack;
  bool _audioEnabled;
  bool _videoEnabled;
  int setAudioEnabledCalls = 0;
  int setVideoEnabledCalls = 0;
  bool? lastAudioEnabled;
  bool? lastVideoEnabled;

  @override
  bool get isAudioEnabled => hasAudioTrack ? _audioEnabled : false;

  @override
  bool get isVideoEnabled => hasVideoTrack ? _videoEnabled : false;

  @override
  void setAudioEnabled(bool enabled) {
    setAudioEnabledCalls++;
    lastAudioEnabled = enabled;
    if (hasAudioTrack) {
      _audioEnabled = enabled;
    }
  }

  @override
  void setVideoEnabled(bool enabled) {
    setVideoEnabledCalls++;
    lastVideoEnabled = enabled;
    if (hasVideoTrack) {
      _videoEnabled = enabled;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
