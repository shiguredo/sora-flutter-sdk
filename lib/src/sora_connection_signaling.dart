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
          (Object? message) => _enqueueWebSocketMessage(message),
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
        _closeFailedSignalingCandidate(channel);
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
        _closeFailedSignalingCandidate(channel);
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

  /// 接続に失敗した候補の WebSocket を非同期で閉じる。
  ///
  /// 接続未確立の channel では `sink.close()` が完了しない場合があるため、
  /// 後始末の完了を待つと次のシグナリング URL へのフェイルオーバーが止まる。
  void _closeFailedSignalingCandidate(WebSocketChannel? channel) {
    if (channel == null) {
      return;
    }
    unawaited(() async {
      try {
        await channel.sink.close();
      } catch (error) {
        _emitDebugMessage('ws failed candidate cleanup failed: $error');
      }
    }());
  }

  /// WebSocket シグナリングメッセージを受信順に直列化するために、
  /// `_signalingState.webSocketMessageTail` へ append する。
  ///
  /// tail による直列化のセマンティクスは DataChannel 側の
  /// `_enqueueSignalingDataChannelMessage` と対称的で、両者とも:
  ///
  /// - `channel.stream.listen` / `handleMessage` から受信したメッセージを
  ///   tail Future に chain する
  /// - 先行メッセージの失敗でチェーンが停止しないよう `.catchError((_,_) {})`
  ///   を挟む
  /// - 32KiB を超える payload の Isolate.run offload 中に後続の小さな
  ///   payload が追い抜くのを防ぐ
  ///
  /// **エラー吸収の場所は非対称**: WebSocket は本ヘルパ内で try/catch する
  /// 一方で、DataChannel 側は caller (`SoraConnection._handleWebrtcEvent`
  /// 内の `_dataChannelController.handleMessage(...).catchError(...)`) が
  /// 吸収を担う。理由は listen コールバックが返り Future を discard する
  /// 制約に合わせるため。DC 側と揃えて WS 側 try/catch を外すと、単発
  /// enqueue で `_handleWebSocketMessage` が throw した場合に zone unhandled
  /// error が再発する。この非対称性は意図的なので削除しないこと。
  ///
  /// redirect による channel 切替時も、tail の破棄やキャンセルは行わない。
  /// 単一の tail チェーンに old / new 両 channel のメッセージを順次 append
  /// することで、redirect 直前の old channel からのメッセージが new channel
  /// のメッセージと並行処理されないことを保証する。
  ///
  /// tail のライフサイクル詳細は `SignalingSessionState.webSocketMessageTail`
  /// のフィールド docstring を参照。
  Future<void> _enqueueWebSocketMessage(Object? message) async {
    final previous =
        _signalingState.webSocketMessageTail ?? Future<void>.value();
    final current = previous
        .catchError((Object _, StackTrace _) {
          // 先行メッセージ失敗でチェーン全体が停止しないようにする。
        })
        .then((_) => _handleWebSocketMessage(message));
    _signalingState.webSocketMessageTail = current;
    try {
      await current;
    } catch (error) {
      _emitDebugMessage('ws message handler failed: $error');
    }
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
    // 切断ハンドラから参照できるよう、ignore_disconnect_websocket の値を
    // セッション状態へ保存する。
    _signalingState.ignoreDisconnectWebSocket =
        payload['ignore_disconnect_websocket'] == true;
    _emitDebugMessage('switched: signaling switched to datachannel');
    _emitSwitchedMessage(payload);
    final ignoreDisconnectWebSocket = _signalingState.ignoreDisconnectWebSocket;
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
    // payload['location'] は String 想定だが、サーバー実装バグや改ざんで
    // 別の型が届く可能性がある。`as String?` は同期 throw して zone
    // unhandled error になるため、型判定を先に済ませて統一経路で拒否する。
    final rawLocation = payload['location'];
    if (rawLocation != null && rawLocation is! String) {
      _emitDebugMessage(
        'redirect: invalid location type: ${rawLocation.runtimeType}',
      );
      await _failRedirect(
        errorMessage:
            'Invalid redirect location type: ${rawLocation.runtimeType}',
      );
      return;
    }
    final location = rawLocation as String?;
    if (location == null) {
      _emitDebugMessage('redirect: missing location');
      return;
    }
    _emitDebugMessage('redirect: reconnecting to $location');

    // サーバー由来の location を先に検証する。不正な URL を Uri.parse や
    // WebSocketChannel.connect に渡すと FormatException / ArgumentError が
    // 発生し、listen が discard することで zone unhandled error になる。
    final redirectUrl = parseSignalingUrl(location);
    if (redirectUrl == null) {
      _emitDebugMessage('redirect: invalid location: $location');
      await _failRedirect(errorMessage: 'Invalid redirect location: $location');
      return;
    }

    // 既存の WebSocket を閉じる。cancel / close の同期 throw が
    // `_handleRedirectMessage` の Future を rejected にすると、
    // 呼び出し元 listen コールバックが discard して zone unhandled error に
    // なる (本関数群が防ぐバグそのものを残さないため必ず防護する)。
    final oldChannel = _signalingState.webSocketChannel;
    _signalingState.webSocketChannel = null;
    try {
      await _signalingState.webSocketSubscription?.cancel();
    } catch (cancelError) {
      _emitDebugMessage('redirect: subscription cancel failed: $cancelError');
    }
    _signalingState.webSocketSubscription = null;
    // 確立済み channel の close は同期 throw が稀だが、close の Future が
    // 内部で error を投げる可能性もあるため try/catch で保護する。
    try {
      await oldChannel?.sink.close();
    } catch (closeError) {
      _emitDebugMessage('redirect: old channel close failed: $closeError');
    }

    // 新しい WebSocket に接続する。WebSocketChannel.connect(...) 自体が
    // 同期的に throw する可能性があるため、接続確立の全体を try/catch で包む。
    WebSocketChannel? newChannel;
    try {
      newChannel = WebSocketChannel.connect(redirectUrl);
      _signalingState.webSocketChannel = newChannel;
      _signalingState.webSocketClosedCompleter =
          Completer<SoraDisconnectCloseInfo?>();
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
        (Object? message) => _enqueueWebSocketMessage(message),
        onError: (Object error, StackTrace stackTrace) {
          _handleWebSocketError(error, stackTrace, newChannel);
        },
        onDone: () {
          _handleWebSocketDone(newChannel, name: 'Redirect WebSocket');
        },
      );
    } on TimeoutException catch (timeoutError, timeoutStackTrace) {
      _emitDebugMessage('redirect: connection timed out: $timeoutError');
      _failConnectReady(
        StateError('Redirect signaling candidate timeout: $timeoutError'),
        timeoutStackTrace,
      );
      _emitConnectionErrorEvent(
        code: SoraErrorCode.signalingCandidateTimeout,
        message: timeoutError.toString(),
      );
      _finalizeRedirectFailure(newChannel);
      return;
    } catch (error, stackTrace) {
      _emitDebugMessage('redirect: connection failed: $error');
      _failConnectReady(error, stackTrace);
      _emitConnectionErrorEvent(
        code: SoraErrorCode.websocketError,
        message: error.toString(),
      );
      _finalizeRedirectFailure(newChannel);
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

  /// redirect の payload 検証失敗時の共通後処理。
  ///
  /// 旧 subscription を先に cancel してから、connect() 側の completer に
  /// 具体的な原因を伝える `_failConnectReady` を発火し、異常終了経路で
  /// `SoraDisconnectedState` まで進める。旧 channel は `_handleAbnormalTermination`
  /// が非同期で走らせる `_closeSignalingTransport` で確実に閉じられるが、
  /// 呼び出し元 return 時点で open のまま残さないよう、この関数からも
  /// 明示的に `_closeFailedSignalingCandidate` で fire-and-forget close する。
  ///
  /// `_failConnectReady` は本関数で先に呼ぶことに意味がある。`_handleAbnormalTermination`
  /// 冒頭でも `_failConnectReady(StateError('Abnormal connection termination'))`
  /// が呼ばれるため、順序を逆にすると先発の generic error で completer が確定し、
  /// 「Redirect failed」情報が後発の completer 完了ガードによって no-op になり
  /// caller へ届かなくなる。
  Future<void> _failRedirect({required String errorMessage}) async {
    _emitConnectionErrorEvent(
      code: SoraErrorCode.websocketError,
      message: errorMessage,
    );
    // 旧 subscription / channel を先に切り離す。cancel と close は、失敗しても
    // 続く `_handleAbnormalTermination` に必ず到達するよう try/catch で保護する
    // (subscription.cancel() が同期 throw すると caller への Future が rejected
    // になり、上位 listen コールバックが discard して zone unhandled error に
    // なる。本関数群が防ぐバグそのものを残さないため必ず防護する)。
    final oldChannel = _signalingState.webSocketChannel;
    _signalingState.webSocketChannel = null;
    try {
      await _signalingState.webSocketSubscription?.cancel();
    } catch (cancelError) {
      _emitDebugMessage('redirect: subscription cancel failed: $cancelError');
    }
    _signalingState.webSocketSubscription = null;
    _closeFailedSignalingCandidate(oldChannel);
    // `_connectWebSocket` の failure 経路 (`_completeWebSocketClosedCompleter(null);`
    // → null 化) と同じ規約に揃える。`disconnect()` が redirect と並行して走り
    // `_waitForWebSocketCloseInfo` で completer.future を握っている場合、未完了
    // のまま null 化すると `disconnectWaitTimeout` まで hang する。
    _completeWebSocketClosedCompleter(null);
    _signalingState.webSocketClosedCompleter = null;
    // connect() 呼び出し側で generic な例外を受け取らないよう、具体的な
    // 原因を持った StateError を completer に載せる。
    _failConnectReady(StateError('Redirect failed: $errorMessage'));
    unawaited(
      _handleAbnormalTermination().catchError((Object e, StackTrace st) {
        _emitDebugMessage('abnormal termination failed: $e');
      }),
    );
  }

  /// redirect の接続確立に失敗した場合の共通後処理。
  ///
  /// 本関数は同期的に `_signalingState` の transport 参照を切り、後始末
  /// (candidate close と `_handleAbnormalTermination`) を fire-and-forget する。
  /// caller から見た「完了時点」は `SoraDisconnectedState` 受信で判定する。
  ///
  /// **前提**: subscription は未設定 (`_handleRedirectMessage` の try ブロックが
  /// listen 登録に到達する前に例外を投げた時点で呼ばれる)。将来 catch のスコープ
  /// が広がって subscription 設定後に呼ばれる可能性が生じた場合は、subscription
  /// cancel を追加すること。
  ///
  /// **caller 責務**: 呼び出す前に `_failConnectReady` を発火しておくこと
  /// (`_failRedirect` docstring と同じ理由。`_handleAbnormalTermination` が
  /// 冒頭で generic error を completer に載せる前に、具体的な原因を先に
  /// 完了させる必要がある)。
  ///
  /// 未確立 channel の `sink.close()` は返らない場合があり、await すると
  /// `_handleAbnormalTermination` が起動できないため、`_closeFailedSignalingCandidate`
  /// で fire-and-forget close する。
  void _finalizeRedirectFailure(WebSocketChannel? candidate) {
    _signalingState.webSocketChannel = null;
    // `_failRedirect` と同じく、`disconnect()` との race で hang しないよう、
    // 未完了 completer を先に null で解決してから null 化する。
    _completeWebSocketClosedCompleter(null);
    _signalingState.webSocketClosedCompleter = null;
    _closeFailedSignalingCandidate(candidate);
    unawaited(
      _handleAbnormalTermination().catchError((Object e, StackTrace st) {
        _emitDebugMessage('abnormal termination failed: $e');
      }),
    );
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

    if (currentChannel == channel) {
      if (_signalingState.signalingSwitched) {
        // DataChannel シグナリングへ切り替え済みの場合は、
        // ignore_disconnect_websocket の値に応じて接続維持または
        // 異常終了処理を分岐する。
        if (!_signalingState.ignoreDisconnectWebSocket) {
          if (_peerConnectionConnected) {
            // RTCPeerConnection がまだ生きている場合は DataChannel 経由で
            // 理由付き disconnect を送信してから終了する。
            unawaited(
              _handleAbnormalTermination(
                disconnectReason: SoraDisconnectReason.websocketOnClose,
              ).catchError((Object e, StackTrace st) {
                _emitDebugMessage('abnormal termination failed: $e');
              }),
            );
          } else {
            // 既に failed している場合は disconnect を送信せず終了する。
            unawaited(
              _handleAbnormalTermination().catchError((
                Object e,
                StackTrace st,
              ) {
                _emitDebugMessage('abnormal termination failed: $e');
              }),
            );
          }
        }
        // ignore_disconnect_websocket が true の場合は何もしない。
      } else if (closeCode != null) {
        _emitDebugMessage(
          'ws closed: triggering server_disconnect code=$closeCode reason=$closeReason',
        );
        _webrtcClient.handleDisconnect();
      } else if (_peerConnectionConnected) {
        // close frame なしの異常切断は server_disconnect として処理できない
        // ため、共通の異常終了処理で終了する。
        unawaited(
          _handleAbnormalTermination().catchError((Object e, StackTrace st) {
            _emitDebugMessage('abnormal termination failed: $e');
          }),
        );
      }
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
    if (channel == null || _signalingState.webSocketChannel != channel) {
      // 現役 channel 以外の onerror は無視する。
      // 旧 channel の遅延 onerror で誤った切断処理を実行しないため。
      return;
    }
    if (_signalingState.signalingSwitched) {
      // DataChannel シグナリングへ切り替え済みの場合は、
      // ignore_disconnect_websocket の値に応じて接続維持または
      // 異常終了処理を分岐する。
      if (!_signalingState.ignoreDisconnectWebSocket) {
        _emitConnectionErrorEvent(
          code: SoraErrorCode.websocketError,
          message: error.toString(),
        );
        if (_peerConnectionConnected) {
          // RTCPeerConnection がまだ生きている場合は DataChannel 経由で
          // 理由付き disconnect を送信してから終了する。
          unawaited(
            _handleAbnormalTermination(
              disconnectReason: SoraDisconnectReason.websocketOnError,
            ).catchError((Object e, StackTrace st) {
              _emitDebugMessage('abnormal termination failed: $e');
            }),
          );
        } else {
          // 既に failed している場合は disconnect を送信せず終了する。
          unawaited(
            _handleAbnormalTermination().catchError((Object e, StackTrace st) {
              _emitDebugMessage('abnormal termination failed: $e');
            }),
          );
        }
      }
      // ignore_disconnect_websocket が true の場合は何もしない。
      return;
    }
    _emitConnectionErrorEvent(
      code: SoraErrorCode.websocketError,
      message: error.toString(),
    );
    if (!_disconnecting && !_peerConnectionConnected) {
      _failConnectReady(error, stackTrace);
    } else if (_peerConnectionConnected) {
      // 接続確立後の onerror は共通の異常終了処理で終了する。
      unawaited(
        _handleAbnormalTermination().catchError((Object e, StackTrace st) {
          _emitDebugMessage('abnormal termination failed: $e');
        }),
      );
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
  Object? _optionalAudioConnectValue() =>
      buildOptionalAudioConnectValue(config);

  /// connect メッセージ用の `video` 値。未指定かつオプションも無い場合は null（キー自体を送らない）
  Object? _optionalVideoConnectValue() =>
      buildOptionalVideoConnectValue(config);

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
