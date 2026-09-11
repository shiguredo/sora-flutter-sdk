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

  /// offer が不正
  ///
  /// Sora から受け取った offer の SDP が null、または PeerConnection を
  /// 用意できないときに emit される。
  static const String offerInvalid = 'offer_invalid';

  /// re-offer が不正
  ///
  /// Sora から受け取った re-offer の SDP が null、または再利用する
  /// PeerConnection が無いときに emit される。
  static const String reofferInvalid = 'reoffer_invalid';

  /// リモート SDP の設定に失敗
  ///
  /// `setRemoteDescription` が失敗したときに emit される。
  static const String setRemoteDescriptionFailed =
      'set_remote_description_failed';

  /// answer の生成に失敗
  ///
  /// `createAnswer` が失敗したときに emit される。
  static const String createAnswerFailed = 'create_answer_failed';

  /// ローカル SDP の設定に失敗
  ///
  /// answer を `setLocalDescription` で設定する処理が失敗したときに
  /// emit される。
  static const String setLocalDescriptionFailed =
      'set_local_description_failed';

  /// PeerConnection の生成に失敗
  ///
  /// `createPeerConnection` が失敗、または null を返したときに emit される。
  static const String createPeerConnectionFailed =
      'create_peer_connection_failed';

  /// audio トラックの追加に失敗
  ///
  /// `pcAddTrack` によるローカル audio トラックの追加、または追加後の
  /// sender 取得に失敗したときに emit される。
  static const String addAudioTrackFailed = 'add_audio_track_failed';

  /// video トラックの追加に失敗
  ///
  /// `pcAddTrack` によるローカル video トラックの追加、または追加後の
  /// sender 取得に失敗したときに emit される。
  static const String addVideoTrackFailed = 'add_video_track_failed';

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
