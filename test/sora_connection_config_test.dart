import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  test(
    'SoraConnectionConfig serializes flat media options to a standard codec friendly map',
    () {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.recvonly,
        audio: false,
        simulcast: true,
        simulcastRequestRid: SimulcastRequestRid.r1,
        audioCodecType: AudioCodecType.opus,
        clientId: 'client-1',
        metadata: <String, Object?>{'foo': 'bar'},
      );

      expect(config.toMap(), <String, Object?>{
        'signalingUrls': <String>['wss://example.com/signaling'],
        'channelId': 'test-channel',
        'role': 'recvonly',
        'video': null,
        'audio': false,
        'clientId': 'client-1',
        'bundleId': null,
        'metadata': <String, Object?>{'foo': 'bar'},
        'signalingNotifyMetadata': null,
        'dataChannelSignaling': null,
        'ignoreDisconnectWebSocket': null,
        'spotlight': null,
        'spotlightFocusRid': null,
        'spotlightUnfocusRid': null,
        'simulcast': true,
        'simulcastRequestRid': 'r1',
        'audioCodecType': 'OPUS',
        'videoCodecType': null,
        'audioBitRate': null,
        'videoBitRate': null,
        'videoVp9Params': null,
        'videoH264Params': null,
        'videoH265Params': null,
        'videoAv1Params': null,
        'dataChannels': null,
        'forwardingFilters': null,
        'useAudioDevice': true,
      });
    },
  );

  test('SoraConnectionConfig uses sensible defaults', () {
    final config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.recvonly,
    );

    expect(config.toMap(), <String, Object?>{
      'signalingUrls': <String>['wss://example.com/signaling'],
      'channelId': 'test-channel',
      'role': 'recvonly',
      'video': null,
      'audio': null,
      'clientId': null,
      'bundleId': null,
      'metadata': null,
      'signalingNotifyMetadata': null,
      'dataChannelSignaling': null,
      'ignoreDisconnectWebSocket': null,
      'spotlight': null,
      'spotlightFocusRid': null,
      'spotlightUnfocusRid': null,
      'simulcast': null,
      'simulcastRequestRid': null,
      'audioCodecType': null,
      'videoCodecType': null,
      'audioBitRate': null,
      'videoBitRate': null,
      'videoVp9Params': null,
      'videoH264Params': null,
      'videoH265Params': null,
      'videoAv1Params': null,
      'dataChannels': null,
      'forwardingFilters': null,
      'useAudioDevice': true,
    });
  });
}
