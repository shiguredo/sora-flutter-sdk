import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_connection_controller.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  group('buildSoraConnectionConfig', () {
    test('DataChannel signaling を DataChannel 設定とは独立して伝搬する', () {
      final configWithSignaling = buildSoraConnectionConfig(
        _createConnectRequest(
          dataChannelSignaling: true,
          ignoreDisconnectWebSocket: true,
          dataChannels: const <Map<String, Object?>>[],
        ),
      );
      final configWithoutSignaling = buildSoraConnectionConfig(
        _createConnectRequest(
          dataChannelSignaling: false,
          ignoreDisconnectWebSocket: false,
          dataChannels: const <Map<String, Object?>>[
            <String, Object?>{'label': '#chat'},
          ],
        ),
      );

      expect(configWithSignaling.dataChannelSignaling, isTrue);
      expect(configWithSignaling.ignoreDisconnectWebSocket, isTrue);
      expect(configWithSignaling.dataChannels, isEmpty);
      expect(configWithoutSignaling.dataChannelSignaling, isFalse);
      expect(configWithoutSignaling.ignoreDisconnectWebSocket, isFalse);
      expect(configWithoutSignaling.dataChannels, hasLength(1));
    });
  });
}

DevToolsConnectRequest _createConnectRequest({
  required bool dataChannelSignaling,
  required bool ignoreDisconnectWebSocket,
  required List<Map<String, Object?>> dataChannels,
}) {
  return DevToolsConnectRequest(
    signalingUrls: const <String>['wss://example.com/signaling'],
    channelId: 'test-channel',
    role: SoraRole.sendrecv,
    configuredAudio: true,
    configuredVideo: true,
    beepAudioEnabled: false,
    selectedVideoCodecType: null,
    selectedVideoBitRate: null,
    simulcastEnabled: false,
    selectedSimulcastRid: null,
    spotlightEnabled: false,
    selectedSpotlightFocusRid: null,
    selectedSpotlightUnfocusRid: null,
    usesSimulcastRequestRid: false,
    usesSpotlightRid: false,
    selectedAudioOutputDeviceId: null,
    selectedAudioInputDeviceId: null,
    selectedVideoInputDeviceId: null,
    selectedResolution: null,
    selectedFrameRate: null,
    existingLocalStream: null,
    dataChannelSignaling: dataChannelSignaling,
    ignoreDisconnectWebSocket: ignoreDisconnectWebSocket,
    dataChannels: dataChannels,
  );
}
