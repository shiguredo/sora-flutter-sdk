// SoraErrorCode と SoraDisconnectReason の定数値を検証するテスト。
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  group('SoraErrorCode', () {
    test('エラーコード定数が定義されていること', () {
      expect(SoraErrorCode.eventChannelError, 'event_channel_error');
      expect(SoraErrorCode.websocketError, 'websocket_error');
      expect(SoraErrorCode.connectionTimeout, 'connection_timeout');
      expect(SoraErrorCode.disconnectTimeout, 'disconnect_timeout');
      expect(
        SoraErrorCode.signalingCandidateTimeout,
        'signaling_candidate_timeout',
      );
      expect(
        SoraErrorCode.observerBridgeCreationFailed,
        'observer_bridge_creation_failed',
      );
      expect(
        SoraErrorCode.observerBridgeObserverCreationFailed,
        'observer_bridge_observer_creation_failed',
      );
      expect(
        SoraErrorCode.audioInputInitializationFailed,
        'audio_input_initialization_failed',
      );
      expect(SoraErrorCode.cameraOpenError, 'camera_open_error');
    });
  });

  group('SoraDisconnectReason', () {
    test('disconnect メッセージの理由コード定数が定義されていること', () {
      expect(SoraDisconnectReason.noError, 'NO-ERROR');
      expect(SoraDisconnectReason.websocketOnClose, 'WEBSOCKET-ONCLOSE');
      expect(SoraDisconnectReason.websocketOnError, 'WEBSOCKET-ONERROR');
    });
  });
}
