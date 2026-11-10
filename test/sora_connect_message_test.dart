import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';
import 'package:sora_sdk/src/sora_connect_message.dart';

void main() {
  test('ビットレートを kbps のまま connect メッセージへ設定する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.recvonly,
      audio: true,
      video: true,
      audioBitRate: 64,
      videoBitRate: 2500,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'bit_rate': 64,
    });
    expect(buildOptionalVideoConnectValue(config), <String, Object?>{
      'bit_rate': 2500,
    });
  });

  test('audio と video が false の場合はビットレートを含めない', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: false,
      video: false,
      audioBitRate: 64,
      videoBitRate: 2500,
    );

    expect(buildOptionalAudioConnectValue(config), isFalse);
    expect(buildOptionalVideoConnectValue(config), isFalse);
  });

  test('audio と video が未指定で追加オプションもない場合は値を省略する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
    );

    expect(buildOptionalAudioConnectValue(config), isNull);
    expect(buildOptionalVideoConnectValue(config), isNull);
  });

  test('audio 未指定でも Opus パラメーターを指定すると audio オブジェクトを生成する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsChannels: 2,
      audioOpusParamsStereo: true,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{'channels': 2, 'stereo': true},
    });
  });

  test('audio: true を明示しても opus_params を含める', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: true,
      audioOpusParamsChannels: 2,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{'channels': 2},
    });
  });

  test('audio: true で Opus パラメーター未指定の場合は true を返す', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: true,
    );

    expect(buildOptionalAudioConnectValue(config), isTrue);
  });

  test('audio: false の場合は opus_params を含めず false を返す', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: false,
      audioOpusParamsChannels: 2,
    );

    expect(buildOptionalAudioConnectValue(config), isFalse);
  });

  test('指定した Opus パラメーターだけを opus_params に含める', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsMaxplaybackrate: 48000,
      audioOpusParamsMinptime: 10,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{
        'maxplaybackrate': 48000,
        'minptime': 10,
      },
    });
  });

  test('Opus の boolean パラメーターの true と false が欠落せず送信される', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsStereo: true,
      audioOpusParamsSpropStereo: false,
      audioOpusParamsUseinbandfec: true,
      audioOpusParamsUsedtx: false,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{
        'stereo': true,
        'sprop_stereo': false,
        'useinbandfec': true,
        'usedtx': false,
      },
    });
  });

  test('ptime を opus_params に含める', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audioOpusParamsPtime: 20,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{'ptime': 20},
    });
  });

  test('8 種類の Opus パラメーターをすべて opus_params に含める', () {
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

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'opus_params': <String, Object?>{
        'channels': 2,
        'maxplaybackrate': 48000,
        'minptime': 10,
        'ptime': 20,
        'stereo': true,
        'sprop_stereo': false,
        'useinbandfec': true,
        'usedtx': false,
      },
    });
  });

  test('既存の codec_type と bit_rate に opus_params を併記する', () {
    const config = SoraConnectionConfig(
      signalingUrls: <String>['wss://example.com/signaling'],
      channelId: 'test-channel',
      role: SoraRole.sendrecv,
      audio: true,
      audioCodecType: AudioCodecType.opus,
      audioBitRate: 64,
      audioOpusParamsChannels: 2,
    );

    expect(buildOptionalAudioConnectValue(config), <String, Object?>{
      'codec_type': 'OPUS',
      'bit_rate': 64,
      'opus_params': <String, Object?>{'channels': 2},
    });
  });
}
