import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_signaling_session_state.dart';

void main() {
  group('hasActiveTransport', () {
    test('signalingSwitched = true かつ WebSocket null で true を返す', () {
      final state = SignalingSessionState();
      state.signalingSwitched = true;
      // webSocketChannel / webSocketSubscription はデフォルト null
      expect(state.hasActiveTransport, true);
    });

    test('全フィールド null / signalingSwitched = false で false を返す', () {
      final state = SignalingSessionState();
      expect(state.hasActiveTransport, false);
    });

    test('resetSession() 後に signalingSwitched = false で false に戻る', () {
      final state = SignalingSessionState();
      state.signalingSwitched = true;
      expect(state.hasActiveTransport, true);
      state.resetSession();
      expect(state.signalingSwitched, false);
      expect(state.hasActiveTransport, false);
    });
  });
}
