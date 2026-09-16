// ignore_for_file: public_member_api_docs
import 'dart:async';

import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'sora_connection_state.dart';

/// シグナリングセッションのランタイム状態を保持する内部クラス。
///
/// WebSocket ハンドル、サーバー割り当て識別子、切断情報、シグナリング切替状態を
/// 束ね、`resetSession()` による一括リセットを提供する。
/// イベント発火は `SoraConnection` 側の責務であり、本クラスは状態保持を担当する。
@internal
class SignalingSessionState {
  // 接続済み WebSocket と、その接続試行中ハンドル。
  WebSocketChannel? webSocketChannel;
  WebSocketChannel? connectingWebSocketChannel;

  // 現在の WebSocket 購読と、close frame 情報の受け渡し用 completer。
  StreamSubscription<dynamic>? webSocketSubscription;
  Completer<SoraDisconnectCloseInfo?>? webSocketClosedCompleter;

  // signaling transport が DataChannel へ切り替わったかどうか。
  bool signalingSwitched = false;

  // switched メッセージで確定した ignore_disconnect_websocket の値。
  // 切り替え前の接続では false として扱う。
  bool ignoreDisconnectWebSocket = false;

  // Sora サーバーが現在の接続セッションへ割り当てた識別子。
  String? connectionId;
  String? serverClientId;
  String? bundleId;
  String? sessionId;

  // WebSocket close frame や signaling close から復元した切断情報。
  SoraDisconnectCloseInfo? pendingDisconnectCloseInfo;

  // closeInfo 付き disconnected を直前に通知済みかどうか。
  bool emittedDisconnectedWithCloseInfo = false;

  // WebSocket シグナリングメッセージを受信順に処理するための tail Future。
  //
  // ライフサイクル: append と直列化のメカニズムは `_enqueueWebSocketMessage`
  // (`sora_connection_signaling.dart`) を参照。`resetSession()` で null に
  // 戻し、次回セッションへ前回の tail チェーンを持ち越さない。
  // DataChannel 側の `_signalingMessageTail` と役割上対称。
  Future<void>? webSocketMessageTail;

  // 現在の接続セッションにひも付く signaling state を初期化する。
  //
  // transport の close/cancel 自体は呼び出し側で行い、その後の状態リセットだけを
  // ここでまとめて扱う。
  void resetSession() {
    connectionId = null;
    serverClientId = null;
    bundleId = null;
    sessionId = null;
    signalingSwitched = false;
    ignoreDisconnectWebSocket = false;
    pendingDisconnectCloseInfo = null;
    emittedDisconnectedWithCloseInfo = false;
    webSocketMessageTail = null;
  }

  /// connect() 前に「前回の signaling transport が残っているか」を判定する。
  /// WebSocket が生存しているケースに加え、DataChannel signaling に
  /// 切り替わった後 (signalingSwitched = true) もアクティブとみなす。
  bool get hasActiveTransport =>
      webSocketChannel != null ||
      webSocketSubscription != null ||
      signalingSwitched;
}
