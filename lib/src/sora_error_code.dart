/// WebRTC 接続のエラーコード
abstract final class SoraErrorCode {
  /// イベントチャネルエラー
  static const String eventChannelError = 'event_channel_error';

  /// WebSocket エラー
  static const String websocketError = 'websocket_error';

  /// WebRTC 接続確立タイムアウト
  static const String connectionTimeout = 'connection_timeout';

  /// 切断処理タイムアウト
  static const String disconnectTimeout = 'disconnect_timeout';

  /// シグナリング候補 URL 接続タイムアウト
  static const String signalingCandidateTimeout = 'signaling_candidate_timeout';

  /// observer bridge 生成失敗
  static const String observerBridgeCreationFailed =
      'observer_bridge_creation_failed';

  /// PeerConnectionObserver 生成失敗
  static const String observerBridgeObserverCreationFailed =
      'observer_bridge_observer_creation_failed';

  /// iOS 音声入力初期化失敗
  static const String audioInputInitializationFailed =
      'audio_input_initialization_failed';

  /// カメラオープン失敗
  static const String cameraOpenError = 'camera_open_error';

  /// native から想定外のイベントが届いた
  ///
  /// remote track 系イベントの必須フィールド欠落や Sora フォーマット外の
  /// trackId を検出したときに使う。SDK が無音のまま壊れるのを防ぎ、
  /// エラーイベントとデバッグメッセージで通知する。
  static const String unexpectedNativeEvent = 'unexpected_native_event';
}

/// Sora に送信する `disconnect` メッセージの理由コード
abstract final class SoraDisconnectReason {
  /// 正常切断
  static const String noError = 'NO-ERROR';

  /// WebSocket の onclose による切断
  static const String websocketOnClose = 'WEBSOCKET-ONCLOSE';

  /// WebSocket の onerror による切断
  static const String websocketOnError = 'WEBSOCKET-ONERROR';
}
