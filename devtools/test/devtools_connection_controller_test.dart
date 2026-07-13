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

    test('接続設定の追加項目を SDK 設定へ型を保って伝搬する', () {
      final config = buildSoraConnectionConfig(
        _createConnectRequest(
          dataChannelSignaling: false,
          ignoreDisconnectWebSocket: false,
          dataChannels: const <Map<String, Object?>>[],
          beepAudioEnabled: true,
          useAudioDevice: true,
          clientId: 'client-id',
          bundleId: 'bundle-id',
          metadata: <String, Object?>{'key': 'value'},
          signalingNotifyMetadata: <Object?>['notification'],
          selectedAudioCodecType: 'OPUS',
          selectedAudioBitRate: 64000,
          videoVp9Params: <String, Object?>{'profile': 0},
          videoH264Params: <String, Object?>{'profile_level_id': '42e01f'},
          videoH265Params: <String, Object?>{'profile_id': 1},
          videoAv1Params: <String, Object?>{'profile': 0},
          forwardingFilters: <Map<String, Object?>>[
            <String, Object?>{'name': 'filter'},
          ],
          timeoutOptions: const SoraTimeoutOptions(
            connectionTimeout: Duration(seconds: 20),
            disconnectWaitTimeout: Duration(seconds: 8),
            signalingCandidateTimeout: Duration(seconds: 3),
          ),
        ),
      );

      expect(config.useAudioDevice, isTrue);
      expect(config.clientId, 'client-id');
      expect(config.bundleId, 'bundle-id');
      expect(config.metadata, <String, Object?>{'key': 'value'});
      expect(config.signalingNotifyMetadata, <Object?>['notification']);
      expect(config.audioCodecType, AudioCodecType.opus);
      expect(config.audioBitRate, 64000);
      expect(config.videoVp9Params, <String, Object?>{'profile': 0});
      expect(config.videoH264Params, <String, Object?>{
        'profile_level_id': '42e01f',
      });
      expect(config.videoH265Params, <String, Object?>{'profile_id': 1});
      expect(config.videoAv1Params, <String, Object?>{'profile': 0});
      expect(config.forwardingFilters, <Map<String, Object?>>[
        <String, Object?>{'name': 'filter'},
      ]);
      expect(
        config.timeoutOptions.connectionTimeout,
        const Duration(seconds: 20),
      );
      expect(
        config.timeoutOptions.disconnectWaitTimeout,
        const Duration(seconds: 8),
      );
      expect(
        config.timeoutOptions.signalingCandidateTimeout,
        const Duration(seconds: 3),
      );
    });
  });
}

DevToolsConnectRequest _createConnectRequest({
  required bool dataChannelSignaling,
  required bool ignoreDisconnectWebSocket,
  required List<Map<String, Object?>> dataChannels,
  bool beepAudioEnabled = false,
  bool useAudioDevice = false,
  String? clientId,
  String? bundleId,
  Object? metadata,
  Object? signalingNotifyMetadata,
  String? selectedAudioCodecType,
  int? selectedAudioBitRate,
  Map<String, Object?>? videoVp9Params,
  Map<String, Object?>? videoH264Params,
  Map<String, Object?>? videoH265Params,
  Map<String, Object?>? videoAv1Params,
  List<Map<String, Object?>>? forwardingFilters,
  SoraTimeoutOptions timeoutOptions = const SoraTimeoutOptions(),
}) {
  return DevToolsConnectRequest(
    signalingUrls: const <String>['wss://example.com/signaling'],
    channelId: 'test-channel',
    role: SoraRole.sendrecv,
    configuredAudio: true,
    configuredVideo: true,
    beepAudioEnabled: beepAudioEnabled,
    useAudioDevice: useAudioDevice,
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
    clientId: clientId,
    bundleId: bundleId,
    metadata: metadata,
    signalingNotifyMetadata: signalingNotifyMetadata,
    selectedAudioCodecType: selectedAudioCodecType,
    selectedAudioBitRate: selectedAudioBitRate,
    videoVp9Params: videoVp9Params,
    videoH264Params: videoH264Params,
    videoH265Params: videoH265Params,
    videoAv1Params: videoAv1Params,
    forwardingFilters: forwardingFilters,
    timeoutOptions: timeoutOptions,
  );
}
