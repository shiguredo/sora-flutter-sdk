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
}
