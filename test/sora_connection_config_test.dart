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
        'audioStreamingLanguageCode': null,
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
        'audioOpusParamsChannels': null,
        'audioOpusParamsMaxplaybackrate': null,
        'audioOpusParamsMinptime': null,
        'audioOpusParamsPtime': null,
        'audioOpusParamsStereo': null,
        'audioOpusParamsSpropStereo': null,
        'audioOpusParamsUseinbandfec': null,
        'audioOpusParamsUsedtx': null,
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
      'audioStreamingLanguageCode': null,
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
      'audioOpusParamsChannels': null,
      'audioOpusParamsMaxplaybackrate': null,
      'audioOpusParamsMinptime': null,
      'audioOpusParamsPtime': null,
      'audioOpusParamsStereo': null,
      'audioOpusParamsSpropStereo': null,
      'audioOpusParamsUseinbandfec': null,
      'audioOpusParamsUsedtx': null,
      'dataChannels': null,
      'forwardingFilters': null,
      'useAudioDevice': true,
    });
  });

  test('audioStreamingLanguageCode を設定 Map に保存する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioStreamingLanguageCode: 'ja-JP',
    );

    expect(config.toMap()['audioStreamingLanguageCode'], 'ja-JP');
  });

  test('ビットレートを kbps のまま設定 Map に保存する', () {
    final config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioBitRate: 64,
      videoBitRate: 2500,
    );

    final map = config.toMap();
    expect(map['audioBitRate'], 64);
    expect(map['videoBitRate'], 2500);
  });

  test('ビットレートの境界値と未指定値を受け入れる', () {
    final minimumConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioBitRate: 6,
      videoBitRate: 1,
    );
    final maximumConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioBitRate: 510,
      videoBitRate: 50000,
    );
    final unspecifiedConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
    );

    expect(minimumConfig.toMap()['audioBitRate'], 6);
    expect(minimumConfig.toMap()['videoBitRate'], 1);
    expect(maximumConfig.toMap()['audioBitRate'], 510);
    expect(maximumConfig.toMap()['videoBitRate'], 50000);
    expect(unspecifiedConfig.toMap()['audioBitRate'], isNull);
    expect(unspecifiedConfig.toMap()['videoBitRate'], isNull);
  });

  test('範囲外のビットレートに RangeError を送出する', () {
    for (final value in <int>[5, 511]) {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.sendrecv,
        audioBitRate: value,
      );

      expect(() => config.toMap(), throwsRangeError);
    }

    for (final value in <int>[0, 50001]) {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.sendrecv,
        videoBitRate: value,
      );

      expect(() => config.toMap(), throwsRangeError);
    }
  });

  test('無効なメディアや recvonly でもビットレートを検証する', () {
    final disabledAudioConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: false,
      audioBitRate: 5,
    );
    final disabledVideoConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      video: false,
      videoBitRate: 0,
    );
    final recvonlyConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.recvonly,
      audioBitRate: 511,
      videoBitRate: 50001,
    );

    expect(() => disabledAudioConfig.toMap(), throwsRangeError);
    expect(() => disabledVideoConfig.toMap(), throwsRangeError);
    expect(() => recvonlyConfig.toMap(), throwsRangeError);
  });

  test('const コンストラクターでビットレート未指定の設定を作成できる', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.recvonly,
    );

    expect(config.audioBitRate, isNull);
    expect(config.videoBitRate, isNull);
  });

  test('Opus 詳細パラメーターを設定 Map に保存する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsChannels: 2,
      audioOpusParamsMaxplaybackrate: 48000,
      audioOpusParamsMinptime: 10,
      audioOpusParamsPtime: 20,
      audioOpusParamsStereo: true,
      audioOpusParamsSpropStereo: false,
      audioOpusParamsUseinbandfec: true,
      audioOpusParamsUsedtx: false,
    );

    final map = config.toMap();
    expect(map['audioOpusParamsChannels'], 2);
    expect(map['audioOpusParamsMaxplaybackrate'], 48000);
    expect(map['audioOpusParamsMinptime'], 10);
    expect(map['audioOpusParamsPtime'], 20);
    expect(map['audioOpusParamsStereo'], true);
    expect(map['audioOpusParamsSpropStereo'], false);
    expect(map['audioOpusParamsUseinbandfec'], true);
    expect(map['audioOpusParamsUsedtx'], false);
  });

  test('Opus 詳細パラメーターの境界値を受け入れる', () {
    const minimumConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsChannels: 1,
      audioOpusParamsMaxplaybackrate: 8000,
      audioOpusParamsMinptime: 3,
    );
    const maximumConfig = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsChannels: 8,
      audioOpusParamsMaxplaybackrate: 48000,
      audioOpusParamsMinptime: 120,
    );

    expect(minimumConfig.toMap()['audioOpusParamsChannels'], 1);
    expect(maximumConfig.toMap()['audioOpusParamsChannels'], 8);
    expect(minimumConfig.toMap()['audioOpusParamsMaxplaybackrate'], 8000);
    expect(maximumConfig.toMap()['audioOpusParamsMaxplaybackrate'], 48000);
    expect(minimumConfig.toMap()['audioOpusParamsMinptime'], 3);
    expect(maximumConfig.toMap()['audioOpusParamsMinptime'], 120);
  });

  test('範囲外の Opus 詳細パラメーターに RangeError を送出する', () {
    for (final value in <int>[0, 9]) {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.sendrecv,
        audioOpusParamsChannels: value,
      );

      expect(() => config.toMap(), throwsRangeError);
    }

    for (final value in <int>[7999, 48001]) {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.sendrecv,
        audioOpusParamsMaxplaybackrate: value,
      );

      expect(() => config.toMap(), throwsRangeError);
    }

    for (final value in <int>[2, 121]) {
      final config = SoraConnectionConfig(
        signalingUrls: <String>['wss://example.com/signaling'],
        channelId: 'test-channel',
        role: SoraRole.sendrecv,
        audioOpusParamsMinptime: value,
      );

      expect(() => config.toMap(), throwsRangeError);
    }
  });

  test('範囲が定義されていない ptime は検証せず送信する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsPtime: 999,
    );

    expect(config.toMap()['audioOpusParamsPtime'], 999);
  });

  test('audio が false でも Opus 詳細パラメーターを検証する', () {
    final config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: false,
      audioOpusParamsChannels: 9,
    );

    expect(() => config.toMap(), throwsRangeError);
  });
}
