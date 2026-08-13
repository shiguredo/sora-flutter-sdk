/// Sora との接続ライフサイクルを管理するモジュール
///
/// シグナリング WebSocket の接続・PeerConnection の制御・
/// メディアストリームや DataChannel の管理を行います。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'ffi/bindings.dart';
import 'ffi/webrtc_client.dart';
import 'media/sora_media_device_platform.dart' as media_device_platform;
import 'sora_connection_config.dart';
import 'sora_connection_event.dart';
import 'sora_connection_state.dart';
import 'sora_data_channel_controller.dart';
import 'sora_data_channel_event.dart';
import 'sora_data_channel_message.dart';
import 'sora_debug_event.dart';
import 'sora_error_code.dart';
import 'sora_local_video_handle.dart';
import 'sora_log_event.dart';
import 'sora_media_stream.dart';
import 'sora_method_channels.dart';
import 'sora_remote_media_stream.dart';
import 'sora_remote_track.dart';
import 'sora_remote_track_manager.dart';
import 'sora_role.dart';
import 'sora_rpc.dart';
import 'sora_sdk_version.g.dart';
import 'sora_signaling_event.dart';
import 'sora_signaling_session_state.dart';
import 'sora_timeline_event.dart';
import 'sora_validator.dart';

// signaling は connectReady やイベント emit が SoraConnection と密結合しており、
// controller 化するほどの抽象化に耐えないため、part としている。
part 'sora_connection_signaling.dart';

/// `Isolate.run()` で実行する JSON decode 本体をトップレベル関数へ分離する。
Object? _decodeJsonInIsolate(String text) => jsonDecode(text);

/// Sora との接続を管理するオブジェクトです。
class SoraConnection {
  SoraConnection._({
    required this.config,
    required this.id,
    required this.eventChannelName,
    required WebrtcClient webrtcClient,
  }) : _webrtcClient = webrtcClient {
    // EventChannel はカメラ・レンダリングのプラットフォームイベント用に残す
    _signalingState = SignalingSessionState();
    _remoteTrackManager = RemoteTrackManager(
      clientId: id,
      soraMethodChannel: soraMethodChannel,
      onDebugMessage: _emitDebugMessage,
      onTrackEvent: _emitTrackEvent,
      onRemoveTrackEvent: _emitRemoveTrackEvent,
    );
    _dataChannelController = DataChannelController(
      webrtcClient: webrtcClient,
      onDebugMessage: _emitDebugMessage,
      onPushMessage: _emitPushMessage,
      onNotifyMessage: _emitNotifyMessage,
      onDataChannelMessageEvent: _emitDataChannelMessageEvent,
      onDataChannelOpenEvent: _emitDataChannelOpenEvent,
      onSignalingEvent: _emitSignalingEvent,
      onLogEvent: _emitLogEvent,
      onSignalingClose: (code, reason) async {
        // DataChannel signaling の close は server 主導の切断完了通知として扱う。
        // graceful disconnect の送信は行わず、native teardown と state reset、
        // closeInfo 付き disconnected 通知だけをここで一本化する。
        final channel = _signalingState.webSocketChannel;
        _signalingState.webSocketChannel = null;
        await channel?.sink.close();
        await _signalingState.webSocketSubscription?.cancel();
        _signalingState.webSocketSubscription = null;
        _disconnecting = true;
        await _teardownNativeSession();
        _resetConnectionSessionState();
        final closeCode = _parseDisconnectCode(code);
        if (closeCode != null) {
          _emitDisconnectedWithCloseInfo(code: closeCode, reason: reason);
        } else {
          _emitConnectionStateEvent(const SoraDisconnectedState());
        }
      },
      onConnectionCreated: _handleSelfConnectionCreated,
      decodeJsonMap: _decodeJsonMapMaybeOffloaded,
      decodeJson: _decodeJsonMaybeOffloaded,
    );
    _eventChannel = EventChannel(eventChannelName);
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (Object? event) => _handlePlatformEvent(event),
      onError: (Object error, StackTrace stackTrace) {
        _emitConnectionErrorEvent(
          code: SoraErrorCode.eventChannelError,
          message: error.toString(),
        );
      },
    );
  }

  /// [SoraConnection] 初期化時に指定した設定
  final SoraConnectionConfig config;

  /// Flutter SDK の SoraConnection のローカル ID
  /// プラットフォーム側で [SoraConnection] インスタンスを識別するために割り当てられる。
  final int id;

  /// プラットフォーム側 EventChannel のチャネル名
  /// カメラやレンダリングのプラットフォームイベント受信に使う。
  final String eventChannelName;

  /// FFI 経由の libwebrtc クライアント
  final WebrtcClient _webrtcClient;

  /// DataChannel のシグナリング・メッセージング制御を担当するコントローラ
  late final DataChannelController _dataChannelController;

  /// プラットフォームからのカメラ・レンダリングイベント受信用 Flutter EventChannel
  late final EventChannel _eventChannel;

  /// 接続イベント (状態遷移・エラー・切断・トラック通知等) のブロードキャストストリーム
  final StreamController<SoraConnectionEvent> _events =
      StreamController<SoraConnectionEvent>.broadcast();

  /// デバッグイベントのブロードキャストストリーム
  final StreamController<SoraDebugEvent> _debugEvents =
      StreamController<SoraDebugEvent>.broadcast();

  /// ローカル映像ハンドル (Texture ID) 通知のブロードキャストストリーム
  final StreamController<SoraLocalVideoHandle> _localVideo =
      StreamController<SoraLocalVideoHandle>.broadcast();

  /// デバッグメッセージ (主に WebSocket 生ログ) のブロードキャストストリーム
  final StreamController<String> _debugMessages =
      StreamController<String>.broadcast();

  /// EventChannel の購読ハンドル
  StreamSubscription<dynamic>? _subscription;

  /// WebSocket シグナリング のセッション状態
  late final SignalingSessionState _signalingState;

  /// 並列 connect() を直列化する非同期ロックの末尾
  Future<void> _connectLockTail = Future<void>.value();

  /// PeerConnection の connected 通知を待つ completer
  /// 世代タグ付きの接続完了待機。
  ({Completer<void> completer, int generation})? _connectReadyCompleter;

  /// 接続試行ごとの世代カウンター。disconnect() / dispose() でインクリメントされ、
  /// 進行中の connect() は await 復帰後に世代が変わっていれば中断する
  int _connectGeneration = 0;

  /// connect() ごとに進行するセッション世代。native PC イベントの所属セッション判定に使う。
  /// disconnect() / dispose() では進行しない。
  int _sessionGeneration = 0;

  /// 進行中の `disconnect()` を共有する (二重切断や状態競合を防ぐ)
  Future<void>? _ongoingDisconnect;

  /// dispose 済みか
  bool _disposed = false;

  /// ローカルの `MediaStream`
  LocalMediaStream? _localStream;

  /// 現在保持しているのローカル音声トラック
  LocalAudioTrack? _currentAudioTrack;

  /// 現在保持しているのローカル映像トラック
  LocalVideoTrack? _currentVideoTrack;

  /// PeerConnection が connected になったかどうか
  bool _peerConnectionConnected = false;

  /// signaling からの disconnect メッセージ受信による切断
  static const _disconnectReasonServerDisconnect = 'server_disconnect';

  /// native PeerConnection observer 由来の切断 (ICE failure 等)
  static const _disconnectReasonPeerConnectionClosed = 'peer_connection_closed';

  /// `_teardownNativeSession()` 経由で native disconnect を開始したかどうか
  /// `_handleWebrtcEvent` からの重複 disconnected を抑制するために使う
  bool _disconnecting = false;

  /// WebSocket / DataChannel 両経路から届く connection.created notify を
  /// 自分の接続として判定し、デバッグログを記録する。
  /// `SoraConnectedState` の発火は PeerConnection の `state_changed: connected`
  /// 経路に一本化している。
  void _handleSelfConnectionCreated(Map<String, Object?> payload) {
    if (payload['event_type'] == 'connection.created' &&
        _signalingState.connectionId != null &&
        payload['connection_id'] == _signalingState.connectionId) {
      _emitDebugMessage('connected: self connection.created received');
    }
  }

  /// サーバーから割り当てられた接続 ID
  String? get connectionId => _signalingState.connectionId;

  /// サーバーから返されたクライアント ID
  String? get serverClientId => _signalingState.serverClientId;

  /// バンドル ID
  String? get bundleId => _signalingState.bundleId;

  /// セッション ID
  String? get sessionId => _signalingState.sessionId;

  /// 音声トラックの有効/無効を切り替える
  void setAudioEnabled(bool enabled) {
    _ensureNotDisposed();
    _currentAudioTrack?.enabled = enabled;
  }

  /// 音声トラックが有効かどうかを返す
  bool get isAudioEnabled => _currentAudioTrack?.enabled ?? false;

  /// 映像トラックの有効/無効を切り替える
  void setVideoEnabled(bool enabled) {
    _ensureNotDisposed();
    _currentVideoTrack?.enabled = enabled;
  }

  /// 映像トラックが有効かどうかを返す
  bool get isVideoEnabled => _currentVideoTrack?.enabled ?? false;

  /// Remote track 管理サブシステム
  late final RemoteTrackManager _remoteTrackManager;

  /// 32 KiB 以上の JSON は UI スレッド滞留を避けるため別 isolate で decode する。
  static const int _jsonDecodeOffloadThreshold = 32 * 1024;

  /// リモート接続ごとの MediaStream 一覧を返す
  Map<String, RemoteMediaStream> get remoteMediaStreams =>
      _remoteTrackManager.remoteMediaStreams;

  /// SDK 内部でのみ利用する接続生成 API です。
  @internal
  static Future<SoraConnection> internalCreate(
    SoraConnectionConfig config,
  ) async {
    // プラットフォーム側でカメラインフラを準備する
    final Map<Object?, Object?> response =
        (await soraMethodChannel.invokeMethod<Map<Object?, Object?>>(
          'createClient',
          <String, Object?>{'config': config.toMap()},
        )) ??
        <Object?, Object?>{};
    final clientId = response['clientId']! as int;
    final eventChannelName = response['eventChannelName']! as String;

    // WebRTC クライアントを dart:ffi で作成する
    late final SoraConnection soraConnection;
    WebrtcClient.useAudioDevice = config.useAudioDevice;
    final webrtcClient = WebrtcClient.create(
      config: config.toMap(),
      onEvent: (String type, Map<String, Object?> data) {
        soraConnection._handleWebrtcEvent(type, data);
      },
    );

    soraConnection = SoraConnection._(
      config: config,
      id: clientId,
      eventChannelName: eventChannelName,
      webrtcClient: webrtcClient,
    );
    return soraConnection;
  }

  /// 統合イベント Stream
  ///
  /// 接続状態、リモートトラックの追加・削除、シグナリング、DataChannel (通知・メッセージング・RPC 等)、タイムアウトを購読できる。
  Stream<SoraConnectionEvent> get events => _events.stream;

  /// デバッグイベントを受け取る Stream
  Stream<SoraDebugEvent> get debugEvents => _debugEvents.stream;

  /// ローカル映像の表示に使うハンドルを受け取る Stream
  Stream<SoraLocalVideoHandle> get localVideo => _localVideo.stream;

  /// デバッグ用の文字列メッセージを受け取る Stream
  Stream<String> get debugMessages => _debugMessages.stream;

  /// 非同期排他制御。body を直列化して実行する。
  ///
  /// Future のチェーンで呼び出しを直列化し、前の body 完了後に次の body を開始する。
  Future<void> _runExclusive(Future<void> Function() body) async {
    final previous = _connectLockTail;
    final current = Completer<void>();
    _connectLockTail = current.future;
    await previous;
    try {
      return await body();
    } finally {
      current.complete();
      if (identical(_connectLockTail, current.future)) {
        _connectLockTail = Future<void>.value();
      }
    }
  }

  /// MediaStream を使って接続する。
  ///
  /// recvonly、または audio / video がともに `false`、またはともに未指定（`null`）のときは stream を渡さず、
  /// それ以外の sendonly / sendrecv では config に応じた track を含む stream を渡す。
  Future<void> connect([LocalMediaStream? stream]) async {
    _ensureNotDisposed();
    return _runExclusive(() async {
      if (_disposed) {
        throw StateError('SoraConnection disposed');
      }
      _validateConnectStream(stream);
      if (_signalingState.hasActiveTransport) {
        await disconnect();
      }
      _localStream = stream;
      _currentAudioTrack = stream?.currentAudioTrackOrNull;
      _currentVideoTrack = stream?.currentVideoTrackOrNull;
      _remoteTrackManager.invalidateGeneration();
      final currentGeneration = ++_connectGeneration;
      final currentSessionGeneration = ++_sessionGeneration;
      _connectReadyCompleter = (
        completer: Completer<void>(),
        generation: currentSessionGeneration,
      );
      try {
        await _connectWithTimeout(currentGeneration);
      } finally {
        _resetConnectReady();
      }
    });
  }

  /// タイムアウト付きの接続 internal 処理
  Future<void> _connectWithTimeout(int generation) async {
    // signaling 接続確立だけでなく、PeerConnection が connected になるまでを
    // connectionTimeout の対象に含める。
    try {
      await _connect(generation).timeout(
        config.timeoutOptions.connectionTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Connection timeout after ${config.timeoutOptions.connectionTimeout.inSeconds}s',
            config.timeoutOptions.connectionTimeout,
          );
        },
      );
    } on TimeoutException catch (e, st) {
      // 切断後始末とエラー通知を行い、元のスタックトレースを保って再スローする。
      // TimeoutException 以外はここを通らず、呼び出し元へそのまま伝播する。
      _failConnectReady(e, st);
      await disconnect();
      _emitConnectionErrorEvent(
        code: SoraErrorCode.connectionTimeout,
        message: e.toString(),
      );
      Error.throwWithStackTrace(e, st);
    }
  }

  /// 接続試行の中断チェック。
  ///
  /// 新しい `connect()` 呼び出しで `_connectGeneration` が進むと、
  /// 前回の非同期処理が再開した際に generation 不一致で中断させる。
  ///
  /// generation 不一致となるケース
  /// - 接続中に新たな `connect()` が呼ばれた
  /// - 接続中に `disconnect()` が呼ばれた
  /// - 接続中に `dispose()` が呼ばれた
  void _ensureConnectNotCancelled(int generation) {
    if (_connectGeneration != generation) {
      throw StateError('Connection cancelled');
    }
  }

  /// WebSocket 接続を確立し、WebRTC 接続開始から connected 待機まで進める。
  Future<void> _connect(int generation) async {
    WebSocketChannel channel;
    try {
      channel = await _connectWebSocket();
    } on TimeoutException catch (e, st) {
      // signalingCandidateTimeout は connectionTimeout とは区別してハンドリングする
      _failConnectReady(e, st);
      await disconnect();
      _emitConnectionErrorEvent(
        code: SoraErrorCode.signalingCandidateTimeout,
        message: e.toString(),
      );
      throw StateError('Signaling candidate timeout: $e');
    }

    try {
      _ensureConnectNotCancelled(generation);
      if (_disposed) {
        throw StateError('SoraConnection disposed');
      }
      _signalingState.webSocketChannel = channel;
      if (identical(_signalingState.connectingWebSocketChannel, channel)) {
        _signalingState.connectingWebSocketChannel = null;
      }
    } catch (e) {
      if (identical(_signalingState.connectingWebSocketChannel, channel)) {
        _signalingState.connectingWebSocketChannel = null;
      }
      await channel.sink.close();
      rethrow;
    }

    try {
      final audioTrackRef = _currentAudioTrack?.retainNativeTrackRefcounted();
      final videoTrackRef = _currentVideoTrack?.retainNativeTrackRefcounted();

      // dart:ffi で WebRTC 接続を開始する
      _webrtcClient.connect(
        localAudioTrackRef: audioTrackRef,
        localVideoTrackRef: videoTrackRef,
        localStreamId: _localStream?.id,
        sessionGeneration: _sessionGeneration,
      );

      // 映像送信がある場合のみ映像入力経路を開始する。
      if (_currentVideoTrack != null) {
        await _applyVideoCaptureBackend(_currentVideoTrack!);
      }

      _ensureConnectNotCancelled(generation);

      final connectMessage = _buildConnectMessage();
      _emitLogEvent('SIGNALING CONNECT MESSAGE', connectMessage);
      _emitDebugMessage('ws send: ${jsonEncode(connectMessage)}');
      _emitSignalingEvent('websocket', 'sent', connectMessage);
      channel.sink.add(jsonEncode(connectMessage));

      await _waitForConnected();
    } catch (e, st) {
      _failConnectReady(e, st);
      await disconnect();
      Error.throwWithStackTrace(e, st);
    }
  }

  /// PeerConnection の connected 通知を待つ。
  Future<void> _waitForConnected() async {
    final entry = _connectReadyCompleter;
    if (entry == null) {
      return;
    }
    await entry.completer.future;
  }

  /// 接続完了待機を成功で完了させる。
  void _completeConnectReady() {
    final entry = _connectReadyCompleter;
    if (entry == null) return;
    if (entry.generation != _sessionGeneration) {
      _emitDebugMessage(
        'Ignore complete-connect-ready: '
        'entry_gen=${entry.generation} current_gen=$_sessionGeneration',
      );
      return;
    }
    if (!entry.completer.isCompleted) {
      entry.completer.complete();
    }
  }

  /// 接続完了待機を失敗で完了させる。
  void _failConnectReady(Object error, [StackTrace? stackTrace]) {
    final entry = _connectReadyCompleter;
    if (entry == null) return;
    if (entry.generation != _sessionGeneration) {
      _emitDebugMessage(
        'Ignore fail-connect-ready: '
        'entry_gen=${entry.generation} current_gen=$_sessionGeneration',
      );
      return;
    }
    if (!entry.completer.isCompleted) {
      entry.completer.completeError(error, stackTrace ?? StackTrace.current);
    }
  }

  /// 接続完了待機の completer を破棄する。
  void _resetConnectReady() {
    _connectReadyCompleter = null;
  }

  /// 進行中の connect を打ち切りつつ、切断処理を 1 本に直列化して実行する。
  ///
  /// graceful disconnect message の送信、transport close、native teardown、
  /// セッション state reset はこの経路でまとめて扱う。
  Future<void> disconnect() async {
    final existing = _ongoingDisconnect;
    if (existing != null) {
      await existing;
      return;
    }
    _connectGeneration++;
    _remoteTrackManager.invalidateGeneration();
    _failConnectReady(StateError('disconnect() called during connect'));
    final completer = Completer<void>();
    _ongoingDisconnect = completer.future;
    try {
      await _disconnectWithTimeout();
      completer.complete();
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _ongoingDisconnect = null;
    }
  }

  /// Sora 切断処理をタイムアウト付きで実行する internal 処理
  Future<void> _disconnectWithTimeout() async {
    try {
      await _disconnectBody().timeout(
        config.timeoutOptions.disconnectWaitTimeout,
        onTimeout: () {
          throw TimeoutException(
            'Disconnect timeout after ${config.timeoutOptions.disconnectWaitTimeout.inSeconds}s',
            config.timeoutOptions.disconnectWaitTimeout,
          );
        },
      );
    } on TimeoutException catch (e, st) {
      // _disconnectBody() が _waitForWebSocketCloseInfo() で hang した場合の
      // 緊急 cleanup。Dart の .timeout() は元の非同期計算を中断しないため、
      // ここで catch 句から直接 cleanup を実行する。
      // timeout 後に _disconnectBody() が遅れて復帰する可能性があるため、
      // この経路の native teardown が発火させる disconnected を抑止する。
      // 後から復帰した _disconnectBody() 側の二重 disconnected は現状受容する。
      _disconnecting = true;
      await _signalingState.webSocketSubscription?.cancel();
      _signalingState.webSocketSubscription = null;
      _signalingState.webSocketClosedCompleter = null;
      final connectingChannel = _signalingState.connectingWebSocketChannel;
      _signalingState.connectingWebSocketChannel = null;
      final channel = _signalingState.webSocketChannel;
      _signalingState.webSocketChannel = null;
      if (connectingChannel != null && !identical(connectingChannel, channel)) {
        await connectingChannel.sink.close();
      }
      await channel?.sink.close();
      await _teardownNativeSession();
      _resetConnectionSessionState();
      _emitConnectionErrorEvent(
        code: SoraErrorCode.disconnectTimeout,
        message: e.toString(),
      );
      Error.throwWithStackTrace(e, st);
    }
  }

  /// シグナリングチャネルの状態に応じてメッセージを送信する。
  ///
  /// [msgMap] は内部で JSON 文字列に変換される。
  /// WebSocket でのみ扱うメッセージタイプについてはこの関数を通す必要はない。
  void _sendSignalingMessage(Map<String, Object?> msgMap) {
    final text = jsonEncode(msgMap);
    if (_signalingState.signalingSwitched) {
      _emitDebugMessage('dc(signaling) send: $text');
      _emitSignalingEvent('datachannel', 'sent', msgMap);
      final encoded = utf8.encode(text);
      final Uint8List sendData;
      if (_dataChannelController.signalingCompress) {
        sendData = _dataChannelController.deflateEncode(encoded);
      } else {
        sendData = encoded;
      }
      try {
        _webrtcClient.sendSignalingMessage(sendData);
      } catch (error) {
        _emitDebugMessage('dc(signaling) send failed: $error');
      }
    } else {
      _emitDebugMessage('ws send: $text');
      _emitSignalingEvent('websocket', 'sent', msgMap);
      _signalingState.webSocketChannel?.sink.add(text);
    }
  }

  /// Sora 切断の internal 処理
  Future<void> _disconnectBody() async {
    final disconnectMessage = <String, Object?>{
      'type': 'disconnect',
      'reason': 'NO-ERROR',
    };
    final text = jsonEncode(disconnectMessage);
    _emitLogEvent('SIGNALING DISCONNECT MESSAGE', disconnectMessage);

    // 切断メッセージ送信中および後続の teardown 処理中に
    // _handleWebrtcEvent への再入を防ぐ。
    _disconnecting = true;

    if (_signalingState.signalingSwitched) {
      // DataChannel に switch 済みのため
      // DataChannel シグナリング経由で disconnect を送信する
      _sendSignalingMessage(disconnectMessage);
    } else {
      final channel = _signalingState.webSocketChannel;
      _signalingState.webSocketChannel = null;
      if (channel != null) {
        _emitDebugMessage('ws send: $text');
        _emitSignalingEvent('websocket', 'sent', disconnectMessage);
        channel.sink.add(text);
        await channel.sink.close();
        await _waitForWebSocketCloseInfo();
      }
    }

    // disconnect メッセージ送信後のシグナリング状態を後始末する。
    // WebSocket 購読の解除と、state 内の channel / completer を破棄する。
    await _signalingState.webSocketSubscription?.cancel();
    _signalingState.webSocketSubscription = null;
    _signalingState.webSocketClosedCompleter = null;
    final connectingChannel = _signalingState.connectingWebSocketChannel;
    _signalingState.connectingWebSocketChannel = null;
    final channel = _signalingState.webSocketChannel;
    _signalingState.webSocketChannel = null;
    if (connectingChannel != null && !identical(connectingChannel, channel)) {
      await connectingChannel.sink.close();
    }
    await channel?.sink.close();

    await _teardownNativeSession();

    // _resetConnectionSessionState() 内の resetSession() で
    // pendingDisconnectCloseInfo が null 化されるため事前に退避する。
    final savedCloseInfo = _signalingState.pendingDisconnectCloseInfo;
    _resetConnectionSessionState();
    // _disconnecting = true により _handleWebrtcEvent 内の SoraDisconnectedState
    // emit が抑制されるため、ここで明示的に発行する。
    _emitConnectionStateEvent(SoraDisconnectedState(closeInfo: savedCloseInfo));
  }

  /// native PeerConnection と remote track の teardown を行う。
  ///
  /// `disconnect()` と server-initiated close の両方で共有する。
  Future<void> _teardownNativeSession() async {
    try {
      await _remoteTrackManager.detachAllRemoteVideoTracks();
    } catch (_) {
      // PeerConnection 切断前のデタッチはベストエフォート
      // (切断処理全体を中断するデメリットの方が大きいため)
    }
    _webrtcClient.disconnect();
  }

  /// 接続セッション固有の状態をリセットする。
  ///
  /// `disconnect()` と server-initiated close の両方で共有する。
  /// transport 切断・disconnect message 送信・native teardown は
  /// 呼び出し側の責務とする。
  void _resetConnectionSessionState() {
    _signalingState.resetSession();
    _peerConnectionConnected = false;
    _disconnecting = false;
    _localStream = null;
    _currentAudioTrack = null;
    _currentVideoTrack = null;
    _dataChannelController.clear();
    _remoteTrackManager.clear();
  }

  /// WebRTC 統計情報を取得する
  // W3C WebRTC の `RTCPeerConnection.getStats()` と
  // 名前をそろえるため、`get` をあえて残している。
  Future<String?> getStats() async {
    _ensureNotDisposed();
    return _webrtcClient.getStats();
  }

  /// 接続中の audio sender に新しい track を設定する。
  Future<void> replaceAudioTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) async {
    _ensureNotDisposed();
    _validateReplaceAudioTrack(stream, track);

    final audioTrack = track as LocalAudioTrack;
    if (_currentAudioTrack?.nativeTrackAddress ==
        audioTrack.nativeTrackAddress) {
      _emitDebugMessage(
        'The provided audio track is already attached. Skipping replaceAudioTrack.',
      );
      return;
    }

    final previousTrack = _currentAudioTrack;
    if (previousTrack != null) {
      audioTrack.enabled = previousTrack.enabled;
    }

    audioTrack.withNativeTrackRefcounted((
      Pointer<WebrtcAudioTrackInterfaceRefcounted> trackRef,
    ) {
      _webrtcClient.replaceAudioTrack(trackRef);
      return 0;
    });

    if (previousTrack != null &&
        _streamContainsAudioTrack(stream, previousTrack)) {
      stream.removeTrack(previousTrack);
    }
    if (!_streamContainsAudioTrack(stream, audioTrack)) {
      stream.addTrack(audioTrack);
    }
    _currentAudioTrack = audioTrack;
  }

  /// 接続中の video sender に新しい track を設定する。
  Future<void> replaceVideoTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) async {
    _ensureNotDisposed();
    _validateReplaceVideoTrack(stream, track);

    final videoTrack = track as LocalVideoTrack;
    if (_currentVideoTrack?.nativeTrackAddress ==
        videoTrack.nativeTrackAddress) {
      _emitDebugMessage(
        'The provided video track is already attached. Skipping replaceVideoTrack.',
      );
      return;
    }

    final previousTrack = _currentVideoTrack;
    if (previousTrack != null) {
      videoTrack.enabled = previousTrack.enabled;
    }

    videoTrack.withNativeTrackRefcounted((
      Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef,
    ) {
      _webrtcClient.replaceVideoTrack(trackRef);
      return 0;
    });

    try {
      await _applyVideoCaptureBackend(videoTrack).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
            '_applyVideoCaptureBackend timed out after 10 seconds',
            const Duration(seconds: 10),
          );
        },
      );
    } catch (e) {
      if (videoTrack.captureType == VideoTrackCaptureType.camera) {
        try {
          await media_device_platform
              .stopCameraCapturer(videoSourcePtr: videoTrack.videoSourceAddress)
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // ベストエフォート
        }
      } else if (videoTrack.captureType == VideoTrackCaptureType.window) {
        try {
          await media_device_platform
              .stopWindowCapturer(videoSourcePtr: videoTrack.videoSourceAddress)
              .timeout(const Duration(seconds: 5));
        } catch (_) {
          // ベストエフォート
        }
      }
      if (previousTrack != null) {
        if (previousTrack.isDisposed) {
          throw StateError(
            'Failed to apply video capture backend: $e '
            '(cannot rollback: previous track is disposed)',
          );
        }
        try {
          previousTrack.withNativeTrackRefcounted((
            Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef,
          ) {
            _webrtcClient.replaceVideoTrack(trackRef);
            return 0;
          });
        } catch (rollbackError) {
          throw StateError(
            'Failed to rollback video track: $rollbackError (original: $e)',
          );
        }
        if (_streamContainsVideoTrack(stream, videoTrack)) {
          stream.removeTrack(videoTrack);
        }
        if (!_streamContainsVideoTrack(stream, previousTrack)) {
          stream.addTrack(previousTrack);
        }
        _currentVideoTrack = previousTrack;
      }
      if (e is TimeoutException) {
        throw StateError('Failed to apply video capture backend: timeout');
      }
      rethrow;
    }

    if (previousTrack != null &&
        _streamContainsVideoTrack(stream, previousTrack)) {
      stream.removeTrack(previousTrack);
    }
    if (!_streamContainsVideoTrack(stream, videoTrack)) {
      stream.addTrack(videoTrack);
    }
    _currentVideoTrack = videoTrack;
  }

  /// 接続中の audio sender から track を外す。
  Future<void> removeAudioTrack(LocalMediaStream stream) async {
    _ensureNotDisposed();
    _validateRemoveAudioTrack(stream);

    final currentTrack = _currentAudioTrack;
    if (currentTrack == null ||
        !_streamContainsAudioTrack(stream, currentTrack)) {
      _emitDebugMessage(
        'Audio track is not attached to the stream. Skipping removeAudioTrack.',
      );
      return;
    }

    _webrtcClient.removeAudioTrack();
    stream.removeTrack(currentTrack);
    _currentAudioTrack = null;
  }

  /// 接続中の video sender から track を外す。
  Future<void> removeVideoTrack(LocalMediaStream stream) async {
    _ensureNotDisposed();
    _validateRemoveVideoTrack(stream);

    final currentTrack = _currentVideoTrack;
    if (currentTrack == null ||
        !_streamContainsVideoTrack(stream, currentTrack)) {
      _emitDebugMessage(
        'Video track is not attached to the stream. Skipping removeVideoTrack.',
      );
      return;
    }

    _webrtcClient.removeVideoTrack();
    stream.removeTrack(currentTrack);
    _currentVideoTrack = null;
  }

  /// カスタム DataChannel 経由でメッセージを送信する
  void sendDataChannelMessage(String label, Uint8List data) {
    _ensureNotDisposed();
    _dataChannelController.sendDataChannelMessage(label, data);
  }

  /// JSON-RPC リクエストを rpc DataChannel 経由で送信する
  Future<Object?> rpc(
    String method, {
    Object? params,
    SoraRpcOptions options = const SoraRpcOptions(),
  }) async {
    _ensureNotDisposed();
    return _dataChannelController.rpc(
      method,
      params: params,
      isNotification: options.notification,
      timeoutMs: options.timeout,
    );
  }

  /// 接続と関連リソースを順序付きで解放する。
  ///
  /// `disconnect()`、MethodChannel の `disposeClient`、購読中 Stream の close を
  /// 含むため非同期で完了する。通常は `await connection.dispose()` を推奨する。
  /// `State.dispose()` のように await できない文脈では
  /// `unawaited(connection.dispose())` のように明示的に扱う。
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _connectGeneration++;
    _failConnectReady(StateError('dispose() called during connect'));
    try {
      await disconnect();
    } catch (_) {
      // graceful な切断を試みるが、失敗しても後段 cleanup を継続するため dispose 全体は止めない
    }
    try {
      await _remoteTrackManager.detachAllRemoteVideoTracks();
    } catch (_) {
      // graceful な cleanup を試みるが、失敗しても後段 cleanup を継続するため dispose 全体は止めない
    }
    Object? eventChannelCancelError;
    try {
      // プラットフォーム側で EventChannel の handler を解除する前に、
      // Dart 側の購読 cancel を先に完了させる。
      // これを逆順にすると cancel の送信先が失われ、
      // MissingPluginException(No implementation found for method cancel)
      // で dispose が失敗する。
      try {
        await _subscription?.cancel();
      } catch (e) {
        // cleanup 中の購読解除失敗では native client 解放を止めない。
        eventChannelCancelError = e;
      }
      _subscription = null;
      _webrtcClient.dispose();
      await soraMethodChannel.invokeMethod<void>(
        'disposeClient',
        <String, Object?>{'clientId': id},
      );
    } finally {
      final connectingChannel = _signalingState.connectingWebSocketChannel;
      _signalingState.connectingWebSocketChannel = null;
      final channel = _signalingState.webSocketChannel;
      _signalingState.webSocketChannel = null;
      await _signalingState.webSocketSubscription?.cancel();
      if (connectingChannel != null && !identical(connectingChannel, channel)) {
        await connectingChannel.sink.close();
      }
      await channel?.sink.close();
      await _events.close();
      await _debugEvents.close();
      await _localVideo.close();
      await _debugMessages.close();
      if (eventChannelCancelError != null) {
        _emitDebugMessage(
          'event channel cancel failed during dispose: '
          '$eventChannelCancelError',
        );
      }
    }
  }

  /// connect(stream) の引数妥当性を検証する。
  void _validateConnectStream(LocalMediaStream? stream) {
    final role = config.role;
    if (role == SoraRole.recvonly) {
      if (stream != null) {
        throw StateError('MediaStream must be null for recvonly connection.');
      }
      return;
    }

    final audioExplicit = config.audio;
    final videoExplicit = config.video;
    // 音声・映像ともに明示的にオフ、またはともに未指定のときはローカルメディアなし。
    if ((audioExplicit == false && videoExplicit == false) ||
        (audioExplicit == null && videoExplicit == null)) {
      if (stream != null) {
        throw StateError(
          'MediaStream must be null when audio and video are disabled.',
        );
      }
      return;
    }

    if (stream == null) {
      throw StateError('MediaStream is required when sending audio or video.');
    }

    final audioTracks = stream.getAudioTracks();
    final videoTracks = stream.getVideoTracks();
    if (audioExplicit == true && audioTracks.length != 1) {
      throw StateError(
        'MediaStream must contain exactly one audio track when audio is enabled.',
      );
    }
    if (audioExplicit == false && audioTracks.isNotEmpty) {
      throw StateError('Audio track must be absent when audio is disabled.');
    }
    if (audioExplicit == null && audioTracks.length > 1) {
      throw StateError('MediaStream must contain at most one audio track.');
    }
    if (videoExplicit == true && videoTracks.length != 1) {
      throw StateError(
        'MediaStream must contain exactly one video track when video is enabled.',
      );
    }
    if (videoExplicit == false && videoTracks.isNotEmpty) {
      throw StateError('Video track must be absent when video is disabled.');
    }
    if (videoExplicit == null && videoTracks.length > 1) {
      throw StateError('MediaStream must contain at most one video track.');
    }
  }

  /// replaceAudioTrack() の前提条件を検証する。
  void _validateReplaceAudioTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) {
    if (!_peerConnectionConnected) {
      throw StateError(
        'replaceAudioTrack failed: PeerConnection is not connected.',
      );
    }
    _validateAttachedStream(stream);
    if (track is! LocalAudioTrack) {
      throw StateError('replaceAudioTrack requires an audio track.');
    }
    track.ensureNotDisposed();
    if (config.role == SoraRole.recvonly || config.audio == false) {
      throw StateError('replaceAudioTrack is not available in this mode.');
    }
  }

  /// replaceVideoTrack() の前提条件を検証する。
  void _validateReplaceVideoTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) {
    if (!_peerConnectionConnected) {
      throw StateError(
        'replaceVideoTrack failed: PeerConnection is not connected.',
      );
    }
    _validateAttachedStream(stream);
    if (track is! LocalVideoTrack) {
      throw StateError('replaceVideoTrack requires a video track.');
    }
    track.ensureNotDisposed();
    if (config.role == SoraRole.recvonly || config.video == false) {
      throw StateError('replaceVideoTrack is not available in this mode.');
    }
  }

  /// removeAudioTrack() の前提条件を検証する。
  void _validateRemoveAudioTrack(LocalMediaStream stream) {
    if (!_peerConnectionConnected) {
      throw StateError(
        'removeAudioTrack failed: PeerConnection is not connected.',
      );
    }
    _validateAttachedStream(stream);
    if (config.role == SoraRole.recvonly || config.audio == false) {
      throw StateError('removeAudioTrack is not available in this mode.');
    }
  }

  /// removeVideoTrack() の前提条件を検証する。
  void _validateRemoveVideoTrack(LocalMediaStream stream) {
    if (!_peerConnectionConnected) {
      throw StateError(
        'removeVideoTrack failed: PeerConnection is not connected.',
      );
    }
    _validateAttachedStream(stream);
    if (config.role == SoraRole.recvonly || config.video == false) {
      throw StateError('removeVideoTrack is not available in this mode.');
    }
  }

  /// 現在接続中の local stream と一致しているかを検証する。
  void _validateAttachedStream(LocalMediaStream stream) {
    if (_signalingState.webSocketChannel == null &&
        !_signalingState.signalingSwitched) {
      throw StateError('Connection is not established.');
    }
    if (_localStream == null || !identical(_localStream, stream)) {
      throw StateError(
        'LocalMediaStream is not attached to this SoraConnection.',
      );
    }
    stream.ensureNotDisposed();
  }

  /// LocalVideoTrack の capture 種別に応じて映像入力経路を切り替える。
  Future<void> _applyVideoCaptureBackend(LocalVideoTrack track) async {
    if (track.captureType == VideoTrackCaptureType.external) {
      return;
    }
    // ウィンドウキャプチャエラーの通知先をこの接続のクライアント ID に紐付ける。
    // 接続前 preview で ensure 済みの renderer がある場合も、
    // ネイティブ側は renderer の現在の clientId を参照するため、
    // ここで後付けされた ID 宛にエラーが通知される。
    track.attachClientId(id);
    try {
      final textureId = await track.textureId;
      _emitLocalVideo(SoraLocalVideoHandle(textureId: textureId));
    } catch (e) {
      final code = track.captureType == VideoTrackCaptureType.window
          ? _windowCaptureErrorCodeFromError(e)
          : SoraErrorCode.cameraOpenError;
      _emitConnectionErrorEvent(
        code: code,
        message: 'Failed to apply video capture backend: $e',
        retriable: true,
      );
      throw StateError('Failed to apply video capture backend: $e');
    }
  }

  /// ウィンドウキャプチャ開始失敗の [PlatformException] から原因種別を判別する。
  ///
  /// ネイティブ側は FlutterError の code に原因種別を埋め込むため、
  /// `PlatformException.code` を [SoraErrorCode] の定数値へ変換できる。
  /// 判別できない場合は [SoraErrorCode.windowCaptureError] を返す。
  static String _windowCaptureErrorCodeFromError(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case SoraErrorCode.windowCapturePermissionDenied:
        case SoraErrorCode.windowCaptureWindowNotFound:
        case SoraErrorCode.windowCaptureStartFailed:
        case SoraErrorCode.windowCaptureStartCancelled:
          return error.code;
      }
    }
    return SoraErrorCode.windowCaptureError;
  }

  /// stream が指定 audio track を含んでいるかを返す。
  bool _streamContainsAudioTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) {
    return stream.getAudioTracks().any(
      (candidate) => candidate.nativeTrackAddress == track.nativeTrackAddress,
    );
  }

  /// stream が指定 video track を含んでいるかを返す。
  bool _streamContainsVideoTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) {
    return stream.getVideoTracks().any(
      (candidate) => candidate.nativeTrackAddress == track.nativeTrackAddress,
    );
  }

  // ---------------------------------------------------------------------------
  // イベント処理
  // ---------------------------------------------------------------------------

  /// dart:ffi の WebrtcClient からのイベントを処理する
  Future<void> _handleWebrtcEvent(
    String type,
    Map<String, Object?> data,
  ) async {
    if (_disposed) {
      return;
    }
    // 接続状態の変更イベント
    if (type == 'state_changed') {
      // 旧セッションの遅延 PC イベントは全操作を抑制する
      final eventGeneration = data['session_generation'] as int?;
      if (eventGeneration != null && eventGeneration != _sessionGeneration) {
        _emitDebugMessage(
          'Ignore stale PC event: '
          'event_gen=$eventGeneration current_gen=$_sessionGeneration',
        );
        return;
      }
      final stateName = data['state'] as String? ?? 'error';
      final code = data['reason'] as String?;
      final message = data['message'] as String?;

      if (stateName == 'connecting') {
        _emitConnectionStateEvent(const SoraConnectingState());
      } else if (stateName == 'connected') {
        if (_ongoingDisconnect != null && !_peerConnectionConnected) {
          _emitDebugMessage('Ignore connected state while disconnecting.');
          return;
        }
        // PeerConnection が connected を複数回通知しても
        // SoraConnectedState が 1 回だけ発火するようにする。
        if (_peerConnectionConnected) return;
        _emitConnectionStateEvent(const SoraConnectedState());
        _peerConnectionConnected = true;
        _completeConnectReady();
      } else if (stateName == 'disconnected') {
        if (!_peerConnectionConnected) {
          _failConnectReady(
            StateError('PeerConnection disconnected before connected'),
          );
        }
        // 全 disconnected 経路で PeerConnection 未接続状態を反映する。
        // これにより signaling switch 後に PeerConnection が切断されても、
        // replaceTrack / removeTrack 系 API が適切に拒否される。
        _peerConnectionConnected = false;
        if (!_disconnecting) {
          if (_signalingState.emittedDisconnectedWithCloseInfo) {
            _signalingState.emittedDisconnectedWithCloseInfo = false;
          } else {
            _emitConnectionStateEvent(
              SoraDisconnectedState(
                closeInfo: _signalingState.pendingDisconnectCloseInfo,
              ),
            );
          }
          // server 主導の切断、または native PC observer 由来の切断の場合は
          // cleanup を実行したうえで state をリセットする。
          // disconnect() 経由 (closed) の場合は _disconnectBody() 側で
          // cleanup 済みのためここでは実行しない。
          if (code == _disconnectReasonServerDisconnect ||
              code == _disconnectReasonPeerConnectionClosed) {
            _disconnecting = true;
            await _teardownNativeSession();
            _resetConnectionSessionState();
          }
        }
        _signalingState.pendingDisconnectCloseInfo = null;
      } else if (!_disconnecting) {
        // teardown 中に native 側が disconnected 以外の state
        // (例: peer_connection_failed) を emit することがあるため、
        // _disconnecting 中はエラーイベントを抑制する。
        _failConnectReady(
          StateError('PeerConnection error: code=$code message=$message'),
        );
        _emitConnectionErrorEvent(code: code, message: message);
      }
      _emitTimelineEvent(
        SoraTimelineEvent(
          type: 'onconnectionstatechange',
          logType: SoraTimelineEventLogType.peerconnection,
          data: () {
            final data = <String, Object?>{'state': stateName};
            if (code != null) {
              data['reason'] = code;
            }
            if (message != null) {
              data['message'] = message;
            }
            return data;
          }(),
        ),
      );
      _emitLogEvent('ONCONNECTIONSTATECHANGE CONNECTIONSTATE', stateName);
      return;
    }
    // Timeout イベント
    if (type == 'timeout') {
      _emitLogEvent('DISCONNECT', 'Signaling connection timeout');
      _emitTimelineEvent(
        const SoraTimelineEvent(
          type: 'signaling-connection-timeout',
          logType: SoraTimelineEventLogType.peerconnection,
        ),
      );
      _emitTimeoutEvent();
      return;
    }
    // リモートトラック追加イベント
    if (type == 'remote_track_added') {
      final kind = _requireRemoteTrackKind(data, type: type);
      final trackId = _requireRemoteTrackId(data, type: type);
      if (kind == 'video') {
        return;
      }
      _remoteTrackManager.handleRemoteAudioTrackAdded(trackId);
      return;
    }
    // リモートトラック削除イベント
    if (type == 'remote_track_removed') {
      final kind = _requireRemoteTrackKind(data, type: type);
      final trackId = _requireRemoteTrackId(data, type: type);
      if (kind == 'video') {
        return;
      }
      _remoteTrackManager.handleRemoteAudioTrackRemoved(trackId);
      return;
    }
    // リモート映像トラック追加イベント
    if (type == 'remote_video_track_added') {
      final trackAddress = data['trackAddress'] as int?;
      final trackId = _requireRemoteTrackId(data, type: type);
      if (trackAddress != null && trackAddress != 0) {
        unawaited(
          _remoteTrackManager
              .attachRemoteVideoTrack(trackAddress, trackId: trackId)
              .catchError((Object e, StackTrace st) {
                _emitDebugMessage('remote_track attach failed: $e');
              }),
        );
      }
      return;
    }
    // リモート映像トラック削除イベント
    if (type == 'remote_video_track_removed') {
      final trackAddress = data['trackAddress'] as int?;
      if (trackAddress != null && trackAddress != 0) {
        unawaited(
          _remoteTrackManager.detachRemoteVideoTrack(trackAddress).catchError((
            Object e,
            StackTrace st,
          ) {
            _emitDebugMessage('remote_track detach failed: $e');
          }),
        );
      }
      return;
    }
    // 全リモート映像トラック削除イベント
    // 切断時の発火を想定
    if (type == 'remote_video_all_removed') {
      unawaited(
        _remoteTrackManager.detachAllRemoteVideoTracks().catchError((
          Object e,
          StackTrace st,
        ) {
          _emitDebugMessage('remote_track detach all failed: $e');
        }),
      );
      return;
    }
    // シグナリングメッセージ受信イベント
    // native SdpNegotiationCallbacks.emitSignalingMessage から転送された
    // サーバー宛メッセージを _sendSignalingMessage が現在のチャネル状態に
    // 応じて適切な経路（DataChannel / WebSocket）で送信する。
    if (type == 'signaling_message') {
      if (_disconnecting) {
        _emitDebugMessage('Ignore signaling message while disconnecting');
        return;
      }
      final message = data['message'];
      if (message is Map) {
        final msgMap = Map<String, Object?>.from(
          message.map((key, value) => MapEntry('$key', value)),
        );
        _sendSignalingMessage(msgMap);
      }
      return;
    }
    // DataChannel メッセージ受信イベント
    if (type == 'data_channel_message') {
      final label = data['label'] as String?;
      if (label != null) {
        unawaited(
          _dataChannelController.handleMessage(label, data['data']).catchError((
            Object e,
            StackTrace st,
          ) {
            _emitDebugMessage('data_channel handleMessage failed: $e');
          }),
        );
      }
      return;
    }
    // DataChannel 確立時イベント
    if (type == 'data_channel_open') {
      final label = data['label'] as String?;
      if (label != null) {
        _dataChannelController.emitDataChannelAvailable(label);
      }
      return;
    }
    // デバッグメッセージ発火時イベント
    if (type == 'debug_message') {
      final message = data['message'];
      if (message is String) {
        _emitDebugMessage(message);
      }
    }
  }

  /// プラットフォーム側 (カメラ/レンダリング) からのイベントを処理する
  void _handlePlatformEvent(Object? event) {
    if (_disposed) {
      return;
    }
    if (event is! Map) {
      return;
    }
    final type = event['type'];
    if (type == 'audio_init_failed') {
      final code = event['code'] as String?;
      final message = event['message'] as String?;
      _emitConnectionErrorEvent(code: code, message: message);
      return;
    }
    if (type == 'camera_open_error') {
      final errorCode = event['errorCode'] as int?;
      final attempts = event['attempts'] as int?;
      final platformErrorName = _cameraErrorCodeToName(errorCode);
      _emitConnectionErrorEvent(
        code: SoraErrorCode.cameraOpenError,
        message: 'Camera open failed: errorCode=$errorCode attempts=$attempts',
        retriable: false,
        details: SoraConnectionErrorDetails(
          attempts: attempts,
          platformError: platformErrorName,
        ),
      );
      return;
    }
    if (type == 'window_capture_error') {
      final message = event['message'] as String?;
      _emitConnectionErrorEvent(
        code: SoraErrorCode.windowCaptureError,
        message: message ?? 'Window capture error',
        retriable: true,
      );
      return;
    }
  }

  static const _cameraErrorCodeNames = <int, String>{
    -1: 'ERROR_EXCEPTION',
    0: 'ERROR_NO_CAMERA_DEVICE',
    1: 'ERROR_CAMERA_DEVICE',
    2: 'ERROR_CAMERA_IN_USE',
    3: 'ERROR_MAX_CAMERAS_IN_USE',
    4: 'ERROR_CAMERA_DISABLED',
    5: 'ERROR_CAMERA_FATAL_ERROR',
  };

  String _cameraErrorCodeToName(int? errorCode) =>
      _cameraErrorCodeNames[errorCode] ?? 'ERROR_UNKNOWN';

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  /// JSON デコードを行う。 _jsonDecodeOffloadThreshold より大きい場合は isolate でオフロードする
  Future<Object?> _decodeJsonMaybeOffloaded(String text) async {
    if (text.length < _jsonDecodeOffloadThreshold) {
      return jsonDecode(text);
    }
    _emitDebugMessage('json decode offloaded: length=${text.length}');
    return Isolate.run<Object?>(() => _decodeJsonInIsolate(text));
  }

  /// JSON をオフロード付きでデコードし Map 型に変換する。
  Future<Map<String, Object?>?> _decodeJsonMapMaybeOffloaded(
    String text,
  ) async {
    final decoded = await _decodeJsonMaybeOffloaded(text);
    if (decoded is! Map) {
      return null;
    }
    return Map<String, Object?>.from(
      decoded.map((Object? key, Object? value) => MapEntry('$key', value)),
    );
  }

  /// remote track イベントの `kind` が `audio` または `video` であることを検証し返す。
  String _requireRemoteTrackKind(
    Map<String, Object?> data, {
    required String type,
  }) {
    final kind = data['kind'] as String?;
    if (kind == 'audio' || kind == 'video') {
      return kind!;
    }
    throw StateError(
      'Remote track kind must be audio or video: type=$type kind=$kind',
    );
  }

  /// remote track 系イベントで必須の `trackId` を取得する。
  ///
  /// `get` ではなく `require` としているのは、値が任意ではなく、
  /// 欠けていた場合はその場で異常として扱う契約を名前で明示するため。
  /// この経路では `trackId` を後続の `connectionId` 導出やイベント通知に使うため、
  /// `null` や空文字を許容すると SDK 内部状態だけが中途半端に壊れる。
  String _requireRemoteTrackId(
    Map<String, Object?> data, {
    required String type,
  }) {
    final trackId = data['trackId'] as String?;
    if (trackId == null || trackId.isEmpty) {
      throw StateError('$type requires non-empty trackId');
    }
    return trackId;
  }

  /// シグナリングメッセージイベントを発火する
  void _emitSignalingEvent(
    String transportType,
    String direction,
    Map<String, Object?>? data,
  ) {
    final event = SoraSignalingEvent(
      transportType: transportType,
      direction: direction,
      data: data,
    );
    _emitEvent(SoraSignalingMessageEvent(event));
    final type = data?['type'];
    _emitTimelineEvent(
      SoraTimelineEvent(
        type: type is String && type.isNotEmpty ? type : 'unknown',
        logType: transportType == 'datachannel'
            ? SoraTimelineEventLogType.datachannel
            : SoraTimelineEventLogType.websocket,
        data: data,
        dataChannelLabel: transportType == 'datachannel' ? 'signaling' : null,
      ),
    );
  }

  /// 接続状態の変更イベントを発火する
  void _emitConnectionStateEvent(SoraConnectionState state) {
    if (!_events.isClosed) {
      _events.add(SoraConnectionStateChangedEvent(state));
    }
  }

  /// 接続エラーイベントを発火する
  void _emitConnectionErrorEvent({
    String? code,
    String? message,
    bool? retriable,
    SoraConnectionErrorDetails? details,
  }) {
    if (!_events.isClosed) {
      _events.add(
        SoraConnectionErrorEvent(
          code: code,
          message: message,
          retriable: retriable,
          details: details,
        ),
      );
    }
  }

  /// 切断コードをパースする
  /// WebSocket 切断は int 型のコード値を想定している
  int? _parseDisconnectCode(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  /// WebSocket の切断コードと理由を `pendingDisconnectCloseInfo` へ保存する。
  ///
  /// `webSocketClosedCompleter` が破棄された後も、`_waitForWebSocketCloseInfo`
  /// や `_emitDisconnectedWithCloseInfo` から closeInfo を参照できるようにするために
  /// `SignalingSessionState` 側へ退避する。
  void _storePendingDisconnectCloseInfo({required int code, String? reason}) {
    _signalingState.pendingDisconnectCloseInfo = SoraDisconnectCloseInfo(
      code: code,
      reason: reason,
    );
  }

  /// WebSocket 切断時の closeInfo を `webSocketClosedCompleter` に完了させ、
  /// `_waitForWebSocketCloseInfo` で待機している呼び出し元へ通知する。
  /// completer が既に破棄済みまたは完了済みの場合は何もしない。
  void _completeWebSocketClosedCompleter(SoraDisconnectCloseInfo? closeInfo) {
    final completer = _signalingState.webSocketClosedCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(closeInfo);
    }
  }

  /// WebSocket 切断情報を待機する。
  ///
  /// `webSocketClosedCompleter` が生きていればその完了を待ち、
  /// 既に破棄されている場合は退避済みの `pendingDisconnectCloseInfo` を返す。
  Future<SoraDisconnectCloseInfo?> _waitForWebSocketCloseInfo() async {
    final completer = _signalingState.webSocketClosedCompleter;
    if (completer == null) {
      return _signalingState.pendingDisconnectCloseInfo;
    }
    return completer.future;
  }

  void _emitDisconnectedWithCloseInfo({required int code, String? reason}) {
    _storePendingDisconnectCloseInfo(code: code, reason: reason);
    _emitConnectionStateEvent(
      SoraDisconnectedState(
        closeInfo: _signalingState.pendingDisconnectCloseInfo,
      ),
    );
    _signalingState.emittedDisconnectedWithCloseInfo = true;
  }

  void _emitNotifyMessage(Map<String, Object?> message) {
    _emitEvent(SoraNotifyEvent(message));
  }

  void _emitPushMessage(Map<String, Object?> message) {
    _emitEvent(SoraPushEvent(message));
  }

  void _emitSwitchedMessage(Map<String, Object?> message) {
    _emitEvent(SoraSwitchedEvent(message));
  }

  void _emitDataChannelOpenEvent(SoraDataChannelEvent event) {
    _emitEvent(SoraDataChannelOpenEvent(event));
  }

  void _emitDataChannelMessageEvent(SoraDataChannelMessage message) {
    _emitEvent(SoraDataChannelMessageEvent(message));
  }

  void _emitTrackEvent(RemoteMediaStreamTrack track) {
    _emitEvent(SoraTrackEvent(track));
  }

  void _emitRemoveTrackEvent(RemoteMediaStreamTrack track) {
    _emitEvent(SoraRemoveTrackEvent(track));
  }

  void _emitTimeoutEvent() {
    _emitEvent(const SoraTimeoutEvent());
  }

  void _emitLogEvent(String title, [Object? message]) {
    if (_debugEvents.isClosed) {
      return;
    }
    _emitDebugEvent(
      SoraLogDebugEvent(SoraLogEvent(title: title, message: message)),
    );
  }

  void _emitTimelineEvent(SoraTimelineEvent event) {
    if (_debugEvents.isClosed) {
      return;
    }
    _emitDebugEvent(SoraTimelineDebugEvent(event));
  }

  void _emitEvent(SoraConnectionEvent event) {
    if (!_events.isClosed) {
      _events.add(event);
    }
  }

  void _emitDebugEvent(SoraDebugEvent event) {
    if (!_debugEvents.isClosed) {
      _debugEvents.add(event);
    }
  }

  void _emitLocalVideo(SoraLocalVideoHandle handle) {
    if (!_localVideo.isClosed) {
      _localVideo.add(handle);
    }
  }

  void _emitDebugMessage(String message) {
    if (!_debugMessages.isClosed) {
      _debugMessages.add(message);
    }
  }

  /// Dispose 済みであれば StateError をスローする
  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('SoraConnection disposed');
    }
  }
}
