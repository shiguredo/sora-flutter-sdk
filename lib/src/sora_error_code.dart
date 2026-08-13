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

  /// ウィンドウキャプチャ失敗
  static const String windowCaptureError = 'window_capture_error';

  /// ウィンドウキャプチャ開始時の画面収録権限拒否
  ///
  /// `MediaDevices.enumerateWindowCaptureSources()` の失敗時は
  /// `PlatformException.code` にこの値が入る。
  static const String windowCapturePermissionDenied =
      'screen_capture_permission_denied';

  /// ウィンドウキャプチャ開始時のウィンドウ消失
  static const String windowCaptureWindowNotFound =
      'window_capture_window_not_found';

  /// ウィンドウキャプチャ開始失敗
  static const String windowCaptureStartFailed = 'window_capture_start_failed';

  /// ウィンドウキャプチャ開始キャンセル
  static const String windowCaptureStartCancelled =
      'window_capture_start_cancelled';
}
