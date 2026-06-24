// ignore_for_file: public_member_api_docs
// シグナリング WebSocket の接続管理とメッセージハンドリングを担当する内部モジュール。
//
// connectReady やイベント emit が SoraConnection と密結合しており、
// controller 化するほどの抽象化に耐えないため、part としている。
part of 'sora_connection.dart';

extension _SoraConnectionSignaling on SoraConnection {
  /// 複数のシグナリング URL を順番に試行して WebSocket 接続する
  Future<WebSocketChannel> _connectWebSocket() async {
    Object? lastError;
    for (final urlString in config.signalingUrls) {
      // 不正な URL が指定されている場合は接続自体をエラーとする
      final url = parseSignalingUrl(urlString);
      if (url == null) {
        throw ArgumentError.value(
          urlString,
          'signalingUrls',
          'Invalid signaling URL',
        );
      }
      WebSocketChannel? channel;
      try {
        _emitDebugMessage('ws connecting: $url');
        channel = WebSocketChannel.connect(url);
        _signalingState.connectingWebSocketChannel = channel;
        _signalingState.webSocketClosedCompleter =
            Completer<SoraDisconnectCloseInfo?>();
        // シグナリング URL ごとの接続タイムアウト。
        // channel.ready が完了しない場合、次のシグナリング URL に移る
        await channel.ready.timeout(
          config.timeoutOptions.signalingCandidateTimeout,
          onTimeout: () {
            throw TimeoutException(
              'Signaling connection timeout after ${config.timeoutOptions.signalingCandidateTimeout.inSeconds}s',
              config.timeoutOptions.signalingCandidateTimeout,
            );
          },
        );
        // WebSocket ストリームを購読し、受信・エラー・切断の各ハンドラを設定する。
        // channel.ready 成功後に購読することで、接続失敗時の error event が
        // _handleWebSocketError 経由で漏れることを防ぐ
        _signalingState.webSocketSubscription = channel.stream.listen(
          (Object? message) => _handleWebSocketMessage(message),
          onError: (Object error, StackTrace stackTrace) {
            _handleWebSocketError(error, stackTrace, channel);
          },
          onDone: () {
            _handleWebSocketDone(channel);
          },
        );
        _emitDebugMessage('ws connected: $url');
        return channel;
      } on TimeoutException catch (error) {
        // タイムアウトした URL の Completer・channel を後始末し、
        // lastError に記録して次の候補 URL へ進む。ここでは throw しない。
        // channel.ready 成功前に catch に到達するため subscription は未設定。
        _emitDebugMessage('ws connect timeout: $url error=$error');
        lastError = error;
        _completeWebSocketClosedCompleter(null);
        _signalingState.webSocketClosedCompleter = null;
        if (identical(_signalingState.connectingWebSocketChannel, channel)) {
          _signalingState.connectingWebSocketChannel = null;
        }
        await channel?.sink.close();
      } catch (error) {
        // タイムアウト以外の接続エラー。TimeoutException 時同様に後始末して次の候補 URL へ進む
        // channel.ready 成功前に catch に到達するため subscription は未設定。
        _emitDebugMessage('ws connect failed: $url error=$error');
        lastError = error;
        _completeWebSocketClosedCompleter(null);
        _signalingState.webSocketClosedCompleter = null;
        if (identical(_signalingState.connectingWebSocketChannel, channel)) {
          _signalingState.connectingWebSocketChannel = null;
        }
        await channel?.sink.close();
      }
    }
    if (lastError is TimeoutException) {
      // 全てのシグナリング URL でタイムアウトとなった場合
      throw TimeoutException(
        'Signaling connection timeout for all URLs',
        config.timeoutOptions.signalingCandidateTimeout,
      );
    }
    throw lastError ?? Exception('No signaling URLs configured');
  }

  /// WebSocket シグナリングメッセージを処理する
  Future<void> _handleWebSocketMessage(Object? message) async {
    if (message is! String) {
      return;
    }
    _emitDebugMessage('ws recv: $message');
    final payload = await _decodeJsonMapMaybeOffloaded(message);
    if (payload == null) {
      return;
    }
    _emitSignalingEvent('websocket', 'received', payload);
    if (payload['type'] == 'offer') {
      _emitLogEvent('SIGNALING OFFER MESSAGE', payload);
      if (payload['sdp'] case final sdp?) {
        _emitLogEvent('OFFER SDP', sdp);
      }
      // offer が current signaling session を確定させるので、
      // サーバーから割り当てられた接続情報もここへ集約する。
      _signalingState.connectionId = payload['connection_id'] as String?;
      _signalingState.serverClientId = payload['client_id'] as String?;
      _signalingState.bundleId = payload['bundle_id'] as String?;
      _signalingState.sessionId = payload['session_id'] as String?;
      _emitDebugMessage(
        'offer: connectionId=${_signalingState.connectionId} clientId=${_signalingState.serverClientId} bundleId=${_signalingState.bundleId} sessionId=${_signalingState.sessionId}',
      );

      _dataChannelController.applyOfferMessage(payload);
    }
    if (payload['type'] == 'ping') {
      final wantStats = payload['stats'] == true;
      if (wantStats) {
        String? statsJson;
        try {
          statsJson = await _webrtcClient.getStats();
        } catch (_) {
          // getStats() がエラーとなった場合は stats なしで pong を送信する
        }
        final pongMessage = <String, Object?>{
          'type': 'pong',
          if (statsJson != null)
            'stats': await _decodeJsonMaybeOffloaded(statsJson),
        };
        _emitDebugMessage('ws send: pong (with stats)');
        _signalingState.webSocketChannel?.sink.add(jsonEncode(pongMessage));
      } else {
        const pongMessage = <String, Object?>{'type': 'pong'};
        _emitDebugMessage('ws send: ${jsonEncode(pongMessage)}');
        _signalingState.webSocketChannel?.sink.add(jsonEncode(pongMessage));
      }
      return;
    }
    if (payload['type'] == 'notify') {
      _handleNotifyMessage(payload);
    }
    if (payload['type'] == 'push') {
      _emitPushMessage(payload);
    }
    if (payload['type'] == 're-offer') {
      _dataChannelController.applyOfferMessage(payload);
      _emitLogEvent('SIGNALING RE OFFER MESSAGE', payload);
      if (payload['sdp'] case final sdp?) {
        _emitLogEvent('RE OFFER SDP', sdp);
      }
    }

    // シグナリングメッセージを dart:ffi で処理する
    final type = payload['type'] as String?;
    if (type == 'offer') {
      _webrtcClient.handleOffer(payload);
    } else if (type == 're-offer') {
      _webrtcClient.handleReOffer(payload);
    } else if (type == 'candidate') {
      _webrtcClient.handleCandidate(payload);
    } else if (type == 'disconnect') {
      _webrtcClient.handleDisconnect();
    } else if (type == 'switched') {
      _handleSwitchedMessage(payload);
    } else if (type == 'redirect') {
      await _handleRedirectMessage(payload);
    }
  }

  /// notify メッセージを処理する
  void _handleNotifyMessage(Map<String, Object?> payload) {
    _emitNotifyMessage(payload);
    _handleSelfConnectionCreated(payload);
  }

  /// switched メッセージを処理する
  void _handleSwitchedMessage(Map<String, Object?> payload) {
    _signalingState.signalingSwitched = true;
    _emitDebugMessage('switched: signaling switched to datachannel');
    _emitSwitchedMessage(payload);
    final ignoreDisconnectWebSocket =
        payload['ignore_disconnect_websocket'] == true;
    if (ignoreDisconnectWebSocket) {
      _emitDebugMessage(
        'switched: closing websocket (ignore_disconnect_websocket=true)',
      );
      final channel = _signalingState.webSocketChannel;
      _signalingState.webSocketChannel = null;
      _signalingState.webSocketSubscription?.cancel();
      _signalingState.webSocketSubscription = null;
      channel?.sink.close();
    }
  }

  void _handleWebSocketTimeout() {
    _emitTimeoutEvent();
  }

  /// redirect メッセージを処理する
  Future<void> _handleRedirectMessage(Map<String, Object?> payload) async {
    final location = payload['location'] as String?;
    if (location == null) {
      _emitDebugMessage('redirect: missing location');
      return;
    }
    _emitDebugMessage('redirect: reconnecting to $location');

    // 既存の WebSocket を閉じる
    final oldChannel = _signalingState.webSocketChannel;
    _signalingState.webSocketChannel = null;
    await _signalingState.webSocketSubscription?.cancel();
    _signalingState.webSocketSubscription = null;
    await oldChannel?.sink.close();

    // 新しい WebSocket に接続する
    final newChannel = WebSocketChannel.connect(Uri.parse(location));
    _signalingState.webSocketChannel = newChannel;
    _signalingState.webSocketClosedCompleter =
        Completer<SoraDisconnectCloseInfo?>();
    try {
      await newChannel.ready.timeout(
        config.timeoutOptions.signalingCandidateTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Redirect signaling connection timeout after '
            '${config.timeoutOptions.signalingCandidateTimeout.inSeconds}s',
            config.timeoutOptions.signalingCandidateTimeout,
          );
        },
      );
      // ready 成功後に subscription を設定することで、接続失敗時の error event が
      // _handleWebSocketError 経由で漏れることを防ぐ
      _signalingState.webSocketSubscription = newChannel.stream.listen(
        (Object? message) => _handleWebSocketMessage(message),
        onError: (Object error, StackTrace stackTrace) {
          _handleWebSocketError(error, stackTrace, newChannel);
        },
        onDone: () {
          _handleWebSocketDone(newChannel, name: 'Redirect WebSocket');
        },
      );
    } on TimeoutException catch (e, st) {
      _failConnectReady(
        StateError('Redirect signaling candidate timeout: $e'),
        st,
      );
      _emitConnectionErrorEvent(
        code: SoraErrorCode.signalingCandidateTimeout,
        message: e.toString(),
      );
      // 到達時点では subscription 未設定のため cancel 不要
      _signalingState.webSocketChannel = null;
      _signalingState.webSocketClosedCompleter = null;
      await newChannel.sink.close();
      return;
    }

    // redirect フラグ付きで connect メッセージを送信する
    final connectMessage = _buildConnectMessage();
    connectMessage['redirect'] = true;
    _emitLogEvent('SIGNALING CONNECT MESSAGE', connectMessage);
    _emitDebugMessage('ws send: ${jsonEncode(connectMessage)}');
    _emitSignalingEvent('websocket', 'sent', connectMessage);
    newChannel.sink.add(jsonEncode(connectMessage));
  }

  /// WebSocket の onDone 共通処理。
  ///
  /// [name] はエラーメッセージに含める識別名（通常は 'WebSocket'、redirect 時は 'Redirect WebSocket'）。
  void _handleWebSocketDone(
    WebSocketChannel? channel, {
    String name = 'WebSocket',
  }) {
    final closeCode = channel?.closeCode;
    final closeReason = channel?.closeReason;
    _emitDebugMessage('ws closed: code=$closeCode reason=$closeReason');

    // 新しい channel に切り替わっている場合、旧 channel の遅延 onDone は無視する。
    // webSocketChannel が null の場合は disconnect フローで意図的に null 化された
    // ケースであり、completer の完了が必要なため早期 return しない。
    final currentChannel = _signalingState.webSocketChannel;
    if (currentChannel != null && currentChannel != channel) {
      return;
    }

    if (currentChannel == channel && closeCode != null) {
      _emitDebugMessage(
        'ws closed: triggering server_disconnect code=$closeCode reason=$closeReason',
      );
      _webrtcClient.handleDisconnect();
    }
    if (currentChannel == channel &&
        !_disconnecting &&
        !_peerConnectionConnected) {
      _failConnectReady(
        StateError(
          '$name closed before PeerConnection connected: '
          'code=$closeCode reason=$closeReason',
        ),
      );
    }
    SoraDisconnectCloseInfo? closeInfo;
    if (closeCode != null) {
      closeInfo = SoraDisconnectCloseInfo(code: closeCode, reason: closeReason);
    }
    // switched 後に null 化された旧 channel の onDone では state を更新しない。
    // disconnect フロー (signalingSwitched == false) と現役 channel の close は処理する。
    if (currentChannel == channel || !_signalingState.signalingSwitched) {
      if (closeInfo != null) {
        _signalingState.pendingDisconnectCloseInfo = closeInfo;
      }
      _completeWebSocketClosedCompleter(closeInfo);
    }
    if (currentChannel == channel &&
        !_disconnecting &&
        closeReason == 'TIMEOUT' &&
        !_peerConnectionConnected) {
      _handleWebSocketTimeout();
    }
  }

  /// WebSocket の onError 共通処理。
  void _handleWebSocketError(
    Object error,
    StackTrace stackTrace,
    WebSocketChannel? channel,
  ) {
    _emitConnectionErrorEvent(
      code: SoraErrorCode.websocketError,
      message: error.toString(),
    );
    if (channel != null &&
        _signalingState.webSocketChannel == channel &&
        !_disconnecting &&
        !_peerConnectionConnected) {
      _failConnectReady(error, stackTrace);
    }
  }

  /// Sora に渡す接続設定を構築する
  Map<String, Object?> _buildConnectMessage() {
    final message = <String, Object?>{
      'type': 'connect',
      'role': config.role.value,
      'channel_id': config.channelId,
      'sora_client': 'Sora Flutter SDK ${SoraSDKVersionGen.sdkVersion}',
      'libwebrtc': SoraSDKVersionGen.libwebrtc,
      'environment': _environmentName(),
    };
    if (_optionalVideoConnectValue() case final v?) {
      message['video'] = v;
    }
    if (_optionalAudioConnectValue() case final v?) {
      message['audio'] = v;
    }
    if (config.clientId case final clientId?) {
      message['client_id'] = clientId;
    }
    if (config.bundleId case final bundleId?) {
      message['bundle_id'] = bundleId;
    }
    if (config.metadata case final metadata?) {
      message['metadata'] = metadata;
    }
    if (config.signalingNotifyMetadata case final m?) {
      message['signaling_notify_metadata'] = m;
    }
    if (config.dataChannelSignaling case final v?) {
      message['data_channel_signaling'] = v;
    }
    if (config.ignoreDisconnectWebSocket case final v?) {
      message['ignore_disconnect_websocket'] = v;
    }
    if (config.spotlight case final v?) {
      message['spotlight'] = v;
    }
    if (config.spotlightFocusRid case final v?) {
      message['spotlight_focus_rid'] = v.value;
    }
    if (config.spotlightUnfocusRid case final v?) {
      message['spotlight_unfocus_rid'] = v.value;
    }
    if (config.simulcast case final v?) {
      message['simulcast'] = v;
    }
    if (config.simulcastRequestRid case final v?) {
      message['simulcast_request_rid'] = v.value;
    }
    if (config.dataChannels case final v?) {
      message['data_channels'] = v;
    }
    if (config.forwardingFilters case final v?) {
      message['forwarding_filters'] = v;
    }
    return message;
  }

  /// connect メッセージ用の `audio` 値。未指定かつオプションも無い場合は null（キー自体を送らない）
  Object? _optionalAudioConnectValue() {
    switch (config.audio) {
      case false:
        return false;
      case true:
        return _audioConnectValueWhenExplicitlyOn();
      case null:
        final audio = <String, Object?>{};
        if (config.audioCodecType case final v?) {
          audio['codec_type'] = v.value;
        }
        if (config.audioBitRate case final v?) {
          audio['bit_rate'] = v;
        }
        if (audio.isEmpty) {
          return null;
        }
        return audio;
    }
  }

  Object _audioConnectValueWhenExplicitlyOn() {
    final audio = <String, Object?>{};
    if (config.audioCodecType case final v?) {
      audio['codec_type'] = v.value;
    }
    if (config.audioBitRate case final v?) {
      audio['bit_rate'] = v;
    }

    if (audio.isEmpty) {
      return true;
    }
    return audio;
  }

  /// connect メッセージ用の `video` 値。未指定かつオプションも無い場合は null（キー自体を送らない）
  Object? _optionalVideoConnectValue() {
    switch (config.video) {
      case false:
        return false;
      case true:
        return _videoConnectValueWhenExplicitlyOn();
      case null:
        final video = <String, Object?>{};
        if (config.videoCodecType case final v?) {
          video['codec_type'] = v.value;
        }
        if (config.videoBitRate case final v?) {
          video['bit_rate'] = v;
        }
        if (config.videoVp9Params case final v?) {
          video['vp9_params'] = v;
        }
        if (config.videoH264Params case final v?) {
          video['h264_params'] = v;
        }
        if (config.videoH265Params case final v?) {
          video['h265_params'] = v;
        }
        if (config.videoAv1Params case final v?) {
          video['av1_params'] = v;
        }
        if (video.isEmpty) {
          return null;
        }
        return video;
    }
  }

  /// 明示的に有効にする映像パラメータ
  Object _videoConnectValueWhenExplicitlyOn() {
    final video = <String, Object?>{};
    if (config.videoCodecType case final v?) {
      video['codec_type'] = v.value;
    }
    if (config.videoBitRate case final v?) {
      video['bit_rate'] = v;
    }
    if (config.videoVp9Params case final v?) {
      video['vp9_params'] = v;
    }
    if (config.videoH264Params case final v?) {
      video['h264_params'] = v;
    }
    if (config.videoH265Params case final v?) {
      video['h265_params'] = v;
    }
    if (config.videoAv1Params case final v?) {
      video['av1_params'] = v;
    }

    if (video.isEmpty) {
      return true;
    }
    return video;
  }

  /// 環境(プラットフォーム)名
  String _environmentName() {
    if (Platform.isMacOS) {
      return 'macos';
    }
    if (Platform.isIOS) {
      return 'ios';
    }
    if (Platform.isAndroid) {
      return 'android';
    }
    if (Platform.isLinux) {
      return 'linux';
    }
    if (Platform.isWindows) {
      return 'windows';
    }
    return 'unknown';
  }
}
