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
import 'sora_connect_message.dart';
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
import 'sora_video_capture_error.dart';

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
        final existingDisconnect = _ongoingDisconnect;
        if (existingDisconnect != null) {
          await existingDisconnect;
          return;
        }
        final disconnectCompleter = Completer<void>();
        _ongoingDisconnect = disconnectCompleter.future;
        final disconnectSessionGeneration = _sessionGeneration;
        _connectGeneration++;
        _remoteTrackManager.invalidateGeneration();
        _failConnectReady(StateError('signaling close received'));
        _disconnecting = true;
        try {
          if (_sessionGeneration != disconnectSessionGeneration) {
            return;
          }
          final channel = _signalingState.webSocketChannel;
          _signalingState.webSocketChannel = null;
          await channel?.sink.close();
          await _signalingState.webSocketSubscription?.cancel();
          _signalingState.webSocketSubscription = null;
          await _teardownNativeSession();
          _resetConnectionSessionState();
          final closeCode = _parseDisconnectCode(code);
          if (closeCode != null) {
            _emitDisconnectedWithCloseInfo(code: closeCode, reason: reason);
          } else {
            _emitConnectionStateEvent(const SoraDisconnectedState());
          }
        } finally {
          disconnectCompleter.complete();
          _ongoingDisconnect = null;
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

  /// replace / remove の sender と capture backend の更新を直列化する末尾。
  Future<void> _videoMutationLockTail = Future<void>.value();

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

  /// 進行中の映像キャプチャ切り替えを識別する世代。
  ///
  /// `replaceVideoTrack()` が ReplayKit の確認 UI を待っている間に
  /// disconnect / remove / dispose が呼ばれた場合、完了後の古い処理が
  /// sender や `_currentVideoTrack` を復活させないために使う。
  int _videoCaptureOperationGeneration = 0;

  /// 進行中の映像キャプチャ切り替え。
  ///
  /// 無効化後も停止が完了するまで保持し、切断処理から同じ backend を
  /// 停止できるようにする。
  ({int generation, LocalVideoTrack track})? _pendingVideoCaptureOperation;

  /// PeerConnection が connected になったかどうか
  bool _peerConnectionConnected = false;

  /// 初期画面キャプチャの開始完了まで connected 通知を保留するかどうか。
  bool _delayConnectedStateEvent = false;

  /// signaling からの disconnect メッセージ受信による切断
  static const _disconnectReasonServerDisconnect = 'server_disconnect';

  /// native PeerConnection observer 由来の切断 (ICE failure 等)
  static const _disconnectReasonPeerConnectionClosed = 'peer_connection_closed';

  /// native PeerConnection observer 由来の切断 (RTCPeerConnectionState failed)
  static const _disconnectReasonPeerConnectionFailed = 'peer_connection_failed';

  /// `_teardownNativeSession()` 経由で native disconnect を開始したかどうか
  /// `_handleWebrtcEvent` からの重複 disconnected を抑制するために使う
  bool _disconnecting = false;

  /// 異常終了処理を開始したかどうか。
  ///
  /// WebSocket / PeerConnection / DataChannel の異常イベントが連鎖しても
  /// 終了処理と disconnected イベントを重複実行しないためのガード。
  /// `_resetConnectionSessionState()` ではリセットしない。
  ///
  /// リセット箇所:
  /// - `connect()` 開始時 (`_runExclusive` callback 冒頭): 次セッションの
  ///   ために true→false へ戻す。
  /// - `disconnect()` の finally: 途中例外で残留するとフラグが次回
  ///   `connect()` まで抱え込まれ、その間に届く signaling / state_changed が
  ///   silent drop される問題を防ぐ。
  ///
  /// トレードオフ: `disconnect()` 直後の idle window (`_ongoingDisconnect == null`
  /// かつ両フラグ false) に遅延到来する native 由来の異常イベントは連鎖ガードを
  /// 通らず、追加の `SoraDisconnectedState` emit / 追加 teardown を起こしうる。
  /// 実運用ではこの window は極めて短く、通常のアプリケーションは
  /// `disconnect()` 完了後に `dispose()` を呼ぶことで `_disposed` ガード
  /// (`_handleWebrtcEvent` 冒頭) が後続イベントを drop するため許容している。
  /// この挙動 (追加 emit が起きうる現状) は
  /// `SoraConnection.disconnect の _disconnecting / _abnormalTerminationStarted
  /// の finally リセット` group で挙動 pin 用テストとして固定してある。
  bool _abnormalTerminationStarted = false;

  /// ReplayKit stop が deadline を超えた場合に、teardown で同じ Future を
  /// 再度 await しないためのフラグ。
  bool _skipVideoCaptureStopInTeardown = false;

  /// テスト専用に `_teardownNativeSession` の失敗を模擬するためのフック。
  ///
  /// このオブジェクトが設定されている場合、teardown 開始直後に指定された
  /// 例外を throw する。異常終了処理の teardown 失敗経路をユニットテストで
  /// 検証するために使う。
  @visibleForTesting
  Object? teardownFailureForTest;

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
    return _createWithOnEvent(
      config: config,
      clientId: clientId,
      eventChannelName: eventChannelName,
    );
  }

  /// テスト専用に MethodChannel を介さず `SoraConnection` を構築する。
  ///
  /// `internalCreate` はプラットフォーム側の `createClient` を呼ぶため、
  /// イベント処理のユニットテストでは FFI の `WebrtcClient` だけを使い
  /// MethodChannel を迂回する。`onEvent` には `internalCreate` と同じ
  /// `unawaited` + `.catchError` の安全網を設定する。
  @visibleForTesting
  static SoraConnection createForTest({
    required SoraConnectionConfig config,
    required int clientId,
    required String eventChannelName,
  }) {
    return _createWithOnEvent(
      config: config,
      clientId: clientId,
      eventChannelName: eventChannelName,
    );
  }

  /// `WebrtcClient` を生成し、native イベントの安全網を設定して
  /// `SoraConnection` を構築する。
  ///
  /// `_handleWebrtcEvent` の Future は `onEvent` からは await できないため、
  /// 明示的に `unawaited` で扱う。内部の try/catch で捕捉しきれなかった
  /// 例外は、ここで debug message と error event へ落として
  /// zone unhandled error にしない。
  static SoraConnection _createWithOnEvent({
    required SoraConnectionConfig config,
    required int clientId,
    required String eventChannelName,
  }) {
    late final SoraConnection soraConnection;
    WebrtcClient.useAudioDevice = config.useAudioDevice;
    final webrtcClient = WebrtcClient.create(
      config: config.toMap(),
      onEvent: (String type, Map<String, Object?> data) {
        unawaited(
          soraConnection._handleWebrtcEvent(type, data).catchError((
            Object e,
            StackTrace st,
          ) {
            soraConnection._emitDebugMessage(
              'unhandled error in _handleWebrtcEvent: $e',
            );
            soraConnection._emitConnectionErrorEvent(
              code: SoraErrorCode.unexpectedNativeEvent,
              message: 'Unhandled error in native event handling: $e',
            );
          }),
        );
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

  /// ローカル映像の表示に使うハンドルを受け取る Stream。
  ///
  /// external video track を接続に使った場合は Flutter Texture ベースの
  /// プレビュー経路を持たないため何も emit されない。camera / screen 経路の
  /// track に限って [SoraLocalVideoHandle] が emit され、その `textureId` は
  /// 常に非 null である。
  ///
  /// external への切り替え (`replaceVideoTrack`) や `disconnect()` では
  /// 「解除」通知を emit しないため、消費者は前回の `textureId` を保持し
  /// 続けないよう `SoraConnectionState` などの遷移と合わせて破棄すること。
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

  /// 映像 sender の更新を直列化する。
  Future<void> _runVideoMutation(Future<void> Function() body) async {
    final previous = _videoMutationLockTail;
    final current = Completer<void>();
    _videoMutationLockTail = current.future;
    await previous;
    try {
      return await body();
    } finally {
      current.complete();
      if (identical(_videoMutationLockTail, current.future)) {
        _videoMutationLockTail = Future<void>.value();
      }
    }
  }

  /// 進行中の映像キャプチャ切り替えを無効化する。
  void _invalidateVideoCaptureOperation() {
    _videoCaptureOperationGeneration++;
  }

  /// 進行中の映像キャプチャ切り替えを停止する。
  ///
  /// 停止に失敗した場合は pending operation を保持し、切断処理や次の
  /// 操作から再試行できるようにする。
  Future<void> _stopPendingVideoCaptureOperation() async {
    final pending = _pendingVideoCaptureOperation;
    if (pending == null) {
      return;
    }
    await _stopVideoCaptureBackend(pending.track);
    final current = _pendingVideoCaptureOperation;
    if (current?.generation == pending.generation &&
        identical(current?.track, pending.track)) {
      _pendingVideoCaptureOperation = null;
    }
  }

  /// 指定した操作が所有している backend だけを停止する。
  ///
  /// 操作が無効化されたあとに新しい操作が同じトラックを開始することが
  /// あるため、古い操作の完了処理が新しい backend を停止しないようにする。
  Future<void> _stopVideoCaptureBackendIfOwned(
    int generation,
    LocalVideoTrack track,
  ) async {
    final pending = _pendingVideoCaptureOperation;
    if (pending == null ||
        pending.generation != generation ||
        !identical(pending.track, track)) {
      return;
    }
    await _stopVideoCaptureBackend(track);
    final current = _pendingVideoCaptureOperation;
    if (current?.generation == generation && identical(current?.track, track)) {
      _pendingVideoCaptureOperation = null;
    }
  }

  /// 映像キャプチャ切り替えを開始し、操作世代を返す。
  Future<int> _beginVideoCaptureOperation(LocalVideoTrack track) async {
    // 先行する切り替えがあれば、新しい操作を開始する前に停止する。
    _invalidateVideoCaptureOperation();
    await _stopPendingVideoCaptureOperation();
    if (_disposed ||
        !_peerConnectionConnected ||
        _ongoingDisconnect != null ||
        _disconnecting) {
      throw StateError('Video capture operation is no longer available.');
    }
    final generation = ++_videoCaptureOperationGeneration;
    _pendingVideoCaptureOperation = (generation: generation, track: track);
    return generation;
  }

  /// 指定した映像キャプチャ切り替えが現在も有効か確認する。
  bool _isCurrentVideoCaptureOperation({
    required int generation,
    required LocalMediaStream stream,
    required LocalVideoTrack? previousTrack,
    bool requirePending = true,
  }) {
    final pending = _pendingVideoCaptureOperation;
    return !_disposed &&
        _peerConnectionConnected &&
        _ongoingDisconnect == null &&
        !_disconnecting &&
        _videoCaptureOperationGeneration == generation &&
        (!requirePending || pending?.generation == generation) &&
        identical(_localStream, stream) &&
        identical(_currentVideoTrack, previousTrack);
  }

  /// 映像キャプチャ切り替えを正常完了または停止済みとして解放する。
  void _finishVideoCaptureOperation(int generation) {
    final pending = _pendingVideoCaptureOperation;
    if (pending?.generation == generation) {
      _pendingVideoCaptureOperation = null;
    }
  }

  /// MediaStream を使って接続する。
  ///
  /// recvonly、または audio / video がともに `false` の場合は stream を渡せない。
  /// sendonly / sendrecv で audio と video がともに未指定の場合は Sora のデフォルトが適用されるため、
  /// stream を省略することも、config に応じた track を含む stream を渡すこともできる。
  Future<void> connect([LocalMediaStream? stream]) async {
    _ensureNotDisposed();
    // disconnect() は WebSocket の close 待ちと ReplayKit の停止を含む。
    // transport が先に null になるため hasActiveTransport だけでは
    // 切断中を検出できず、旧 teardown が新セッションを破壊する。
    final ongoingDisconnect = _ongoingDisconnect;
    if (ongoingDisconnect != null) {
      await ongoingDisconnect;
    }
    return _runExclusive(() async {
      if (_disposed) {
        throw StateError('SoraConnection disposed');
      }
      final disconnecting = _ongoingDisconnect;
      if (disconnecting != null) {
        await disconnecting;
      }
      // 新しい接続セッションの開始を宣言する。
      // 前セッションの異常終了ガードを解除し、新セッションでは再度
      // 異常終了処理を実行できるようにする。
      _abnormalTerminationStarted = false;
      _validateConnectStream(stream);
      if (_signalingState.hasActiveTransport) {
        await disconnect();
      }
      _localStream = stream;
      _currentAudioTrack = stream?.currentAudioTrackOrNull;
      _currentVideoTrack = stream?.currentVideoTrackOrNull;
      _currentVideoTrack?.attachToConnection(id);
      final initialVideoTrack = _currentVideoTrack;
      final delaysConnectedState =
          initialVideoTrack?.captureType == VideoTrackCaptureType.screen;
      _delayConnectedStateEvent = delaysConnectedState;
      _remoteTrackManager.invalidateGeneration();
      final currentGeneration = ++_connectGeneration;
      final currentSessionGeneration = ++_sessionGeneration;
      _connectReadyCompleter = (
        completer: Completer<void>(),
        generation: currentSessionGeneration,
      );
      try {
        await _connectWithTimeout(currentGeneration);
        if (delaysConnectedState && initialVideoTrack != null) {
          try {
            final textureId = await _applyVideoCaptureBackend(
              initialVideoTrack,
            );
            final isCurrentSession =
                _connectGeneration == currentGeneration &&
                _sessionGeneration == currentSessionGeneration &&
                _peerConnectionConnected &&
                identical(_localStream, stream) &&
                identical(_currentVideoTrack, initialVideoTrack);
            if (!isCurrentSession) {
              await _stopVideoCaptureBackend(initialVideoTrack);
              throw StateError('Connection cancelled during screen capture.');
            }
            _emitLocalVideo(textureId);
            _delayConnectedStateEvent = false;
            _emitConnectionStateEvent(const SoraConnectedState());
          } catch (e, st) {
            final isCurrentSession =
                _connectGeneration == currentGeneration &&
                _sessionGeneration == currentSessionGeneration &&
                _peerConnectionConnected &&
                identical(_localStream, stream) &&
                identical(_currentVideoTrack, initialVideoTrack) &&
                _ongoingDisconnect == null &&
                !_disconnecting;
            if (isCurrentSession) {
              _emitVideoCaptureBackendError(initialVideoTrack, e);
            }
            try {
              await _stopVideoCaptureBackend(initialVideoTrack);
            } catch (_) {
              // 開始失敗後の停止はベストエフォート
            }
            if (_peerConnectionConnected ||
                _signalingState.hasActiveTransport) {
              await disconnect();
            }
            Error.throwWithStackTrace(e, st);
          }
        }
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
      if (_currentVideoTrack != null &&
          _currentVideoTrack!.captureType != VideoTrackCaptureType.screen) {
        final textureId = await _applyVideoCaptureBackend(_currentVideoTrack!);
        _ensureConnectNotCancelled(generation);
        _emitLocalVideo(textureId);
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
      final failedTrack = _currentVideoTrack;
      if (failedTrack != null &&
          failedTrack.captureType != VideoTrackCaptureType.screen &&
          _connectGeneration == generation &&
          _ongoingDisconnect == null &&
          !_disconnecting) {
        _emitVideoCaptureBackendError(failedTrack, e);
      }
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
    // native disconnected イベントが pending stop 待ち中に到着しても、
    // server 主導の cleanup と明示的 disconnect を二重実行しない。
    _disconnecting = true;
    try {
      // ReplayKit の確認 UI 待ち中でも切断を先に反映し、古い
      // replaceVideoTrack() が完了後に状態を復活させないようにする。
      _invalidateVideoCaptureOperation();
      final pendingStop = _stopPendingVideoCaptureOperation();
      try {
        await pendingStop.timeout(config.timeoutOptions.disconnectWaitTimeout);
      } on TimeoutException {
        _skipVideoCaptureStopInTeardown = true;
        // .timeout() は元の native Future を中断しないため、遅延完了は
        // そのまま待機させ、切断本体だけを deadline 内で継続する。
        unawaited(pendingStop.catchError((_) {}));
      } catch (_) {
        // 切断本体でも再度停止を試みるため、切断処理は継続する。
      }
      await _disconnectWithTimeout();
      completer.complete();
    } catch (e, st) {
      // `_ongoingDisconnect` を await している側が居ない場合、
      // `completer.completeError` で生成される error future が zone unhandled
      // error になる (0079 で `_handleAbnormalTermination` に対して行った修正
      // と同型)。`completeError` より先に `.ignore()` を張って rejected future
      // を無害化してから、rethrow で呼び出し元へ例外を伝搬する。
      completer.future.ignore();
      completer.completeError(e, st);
      rethrow;
    } finally {
      // 非 TimeoutException で中断した場合でも、`disconnect()` 完了後に届く
      // signaling / state_changed が `_handleWebrtcEvent` の silent drop
      // ガードで抑止されないよう、両フラグを finally で確実にリセットする
      // (トレードオフはフィールド定義側 docstring 参照)。
      _disconnecting = false;
      _abnormalTerminationStarted = false;
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
      await _closeSignalingTransport();
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

  /// シグナリング transport を後始末する。
  ///
  /// WebSocket 購読の解除と、state 内の channel / completer の破棄を行う。
  /// 通常切断 (`_disconnectBody`) と異常終了処理の両方で共有する。
  Future<void> _closeSignalingTransport() async {
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
  }

  /// 異常終了時の共通処理。
  ///
  /// WebSocket 切断・エラー、PeerConnection の failed、シグナリング用
  /// DataChannel の切断・エラーのいずれかで呼ばれる。複数の異常イベントが
  /// 連鎖しても終了処理と `SoraDisconnectedState` を 1 回だけ実行する。
  ///
  /// [disconnectReason] を指定すると、シグナリング切替後かつ
  /// `ignore_disconnect_websocket` が false の場合のみ、DataChannel 経由で
  /// 理由付きの `disconnect` メッセージを送信してから終了する。
  Future<void> _handleAbnormalTermination({String? disconnectReason}) async {
    // 通常切断中・切断フロー進行中・異常終了処理済みの場合は何もしない。
    if (_abnormalTerminationStarted ||
        _disconnecting ||
        _ongoingDisconnect != null) {
      return;
    }
    _abnormalTerminationStarted = true;
    _connectGeneration++;
    _remoteTrackManager.invalidateGeneration();
    _failConnectReady(StateError('Abnormal connection termination'));
    final completer = Completer<void>();
    _ongoingDisconnect = completer.future;
    _disconnecting = true;
    try {
      if (disconnectReason != null &&
          _signalingState.signalingSwitched &&
          !_signalingState.ignoreDisconnectWebSocket &&
          _peerConnectionConnected) {
        // シグナリング切替後に WebSocket が切断された場合は、DataChannel
        // 経由で理由付きの disconnect メッセージを送信してから終了する。
        // PeerConnection が既に failed している場合は送信しない。
        _sendSignalingMessage({
          'type': 'disconnect',
          'reason': disconnectReason,
        });
      }
      await _closeSignalingTransport();
      await _teardownNativeSession();
      _resetConnectionSessionState();
      _emitConnectionStateEvent(const SoraDisconnectedState());
    } catch (e, st) {
      // teardown 例外は 2 経路へ確実に伝える。
      // (1) `_ongoingDisconnect` awaiter へ `completer.completeError` で
      //     伝搬する。誰も await していないケースで `completer.future` が
      //     unhandled error にならないよう、`completeError` より先に
      //     `.ignore()` を張っておく（unhandled 判定は microtask 境界で
      //     走るが、handler は Future が unresolved のうちに登録しても
      //     問題ないため、順序依存を減らせる）。
      // (2) `_handleAbnormalTermination()` を呼ぶ側は `.catchError` を
      //     chain して debug message へ変換する契約なので、外側 Future に
      //     も rethrow して例外を届ける（await でも fire-and-forget でも
      //     `.catchError` が吸収する）。
      completer.future.ignore();
      completer.completeError(e, st);
      rethrow;
    } finally {
      _ongoingDisconnect = null;
    }
  }

  /// Sora 切断の internal 処理
  Future<void> _disconnectBody() async {
    final disconnectMessage = <String, Object?>{
      'type': 'disconnect',
      'reason': SoraDisconnectReason.noError,
    };
    final text = jsonEncode(disconnectMessage);
    _emitLogEvent('SIGNALING DISCONNECT MESSAGE', disconnectMessage);

    // 切断メッセージ送信中および後続の teardown 処理中に
    // _handleWebrtcEvent への再入を防ぐ。
    _disconnecting = true;
    // teardown 完了後に遅延到達した異常イベントで再度終了処理を
    // 実行しないよう、このセッションの終了処理ガードを立てる。
    _abnormalTerminationStarted = true;

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
    await _closeSignalingTransport();

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
    final failure = teardownFailureForTest;
    if (failure != null) {
      teardownFailureForTest = null;
      throw failure;
    }
    final videoCaptureStopErrors = <Object>[];
    final skipVideoCaptureStop = _skipVideoCaptureStopInTeardown;
    _skipVideoCaptureStopInTeardown = false;
    var videoCaptureStopTimedOut = skipVideoCaptureStop;
    // 明示的な disconnect() 以外の server 主導切断でも、進行中の
    // replaceVideoTrack() を無効化して pending backend を停止する。
    _invalidateVideoCaptureOperation();
    if (!skipVideoCaptureStop) {
      try {
        await _stopPendingVideoCaptureOperation().timeout(
          config.timeoutOptions.disconnectWaitTimeout,
        );
      } on TimeoutException catch (error) {
        // native stop の callback が遅れても PeerConnection teardown を
        // 同じ callback 待ちで止めない。遅延 Future は native 側で回収する。
        videoCaptureStopErrors.add(error);
        videoCaptureStopTimedOut = true;
      } catch (error) {
        // 切断自体は継続するが、画面キャプチャの停止失敗は後で通知する。
        videoCaptureStopErrors.add(error);
      }
    }
    final currentVideoTrack = _currentVideoTrack;
    if (!videoCaptureStopTimedOut &&
        currentVideoTrack?.captureType == VideoTrackCaptureType.screen) {
      try {
        await _stopVideoCaptureBackend(
          currentVideoTrack!,
        ).timeout(config.timeoutOptions.disconnectWaitTimeout);
      } on TimeoutException catch (error) {
        videoCaptureStopErrors.add(error);
        videoCaptureStopTimedOut = true;
      } catch (error) {
        // 切断自体は継続するが、画面キャプチャの停止失敗は後で通知する。
        videoCaptureStopErrors.add(error);
      }
    }
    try {
      await _remoteTrackManager.detachAllRemoteVideoTracks();
    } catch (_) {
      // PeerConnection 切断前のデタッチはベストエフォート
      // (切断処理全体を中断するデメリットの方が大きいため)
    }
    _webrtcClient.disconnect();
    if (videoCaptureStopErrors.isNotEmpty) {
      // 画面キャプチャは現在公開 API として利用できないため、このエラーコードは
      // 内部実装専用の値であり、公開 API (SoraErrorCode) からは参照できない。
      _emitConnectionErrorEvent(
        code: 'screen_capture_error',
        message:
            'Failed to stop screen capture during connection teardown: '
            '${videoCaptureStopErrors.join('; ')}',
        retriable: true,
        details: const SoraConnectionErrorDetails(
          platformError: 'screen_capture_stop_failed',
        ),
      );
    }
  }

  /// 接続セッション固有の状態をリセットする。
  ///
  /// `disconnect()` と server-initiated close の両方で共有する。
  /// transport 切断・disconnect message 送信・native teardown は
  /// 呼び出し側の責務とする。
  void _resetConnectionSessionState() {
    _signalingState.resetSession();
    _peerConnectionConnected = false;
    _delayConnectedStateEvent = false;
    _disconnecting = false;
    _localStream = null;
    _currentAudioTrack = null;
    _currentVideoTrack?.detachFromConnection(id);
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
  ///
  /// external video track を渡した場合、[localVideo] Stream には何も
  /// emit されない。camera からの切り替えで消費者が古い `textureId` を
  /// 保持し続けないよう、切り替え側で明示的に破棄すること。
  Future<void> replaceVideoTrack(
    LocalMediaStream stream,
    LocalMediaStreamTrack track,
  ) {
    return _runVideoMutation(() => _replaceVideoTrackInternal(stream, track));
  }

  /// 接続中の video sender に新しい track を設定する本体。
  Future<void> _replaceVideoTrackInternal(
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

    final operationGeneration = await _beginVideoCaptureOperation(videoTrack);

    try {
      final requiresExclusiveCaptureSwitch =
          Platform.isIOS &&
          (previousTrack?.captureType == VideoTrackCaptureType.screen ||
              videoTrack.captureType == VideoTrackCaptureType.screen);
      if (requiresExclusiveCaptureSwitch && previousTrack != null) {
        await _stopVideoCaptureBackend(previousTrack);
      }

      // 旧 backend の停止待ち中に切断・remove・dispose が進んだ場合は、
      // 新しい sender や ReplayKit を開始せずに中断する。
      if (!_isCurrentVideoCaptureOperation(
        generation: operationGeneration,
        stream: stream,
        previousTrack: previousTrack,
        // 新 backend の停止に成功すると pending は解放されるが、
        // sender / stream / 接続世代が同じならロールバックは必要です。
        requirePending: false,
      )) {
        throw StateError('Video track replacement was cancelled.');
      }

      videoTrack.withNativeTrackRefcounted((
        Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef,
      ) {
        _webrtcClient.replaceVideoTrack(trackRef);
        return 0;
      });

      final applyFuture = _applyVideoCaptureBackend(videoTrack);
      final textureId = videoTrack.captureType == VideoTrackCaptureType.screen
          ? await applyFuture
          : await applyFuture.timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw TimeoutException(
                  '_applyVideoCaptureBackend timed out after 10 seconds',
                  const Duration(seconds: 10),
                );
              },
            );

      if (!_isCurrentVideoCaptureOperation(
        generation: operationGeneration,
        stream: stream,
        previousTrack: previousTrack,
        // 新 backend の停止成功で pending が解放されても、同じ接続・
        // 世代なら sender と旧 backend のロールバックを続行する。
        requirePending: false,
      )) {
        await _stopVideoCaptureBackendIfOwned(operationGeneration, videoTrack);
        throw StateError('Video track replacement was cancelled.');
      }
      // startCaptureForConnection() の完了後に別操作が割り込んだ場合は、
      // 停止済み Texture を localVideo へ通知しない。
      if (!_isCurrentVideoCaptureOperation(
        generation: operationGeneration,
        stream: stream,
        previousTrack: previousTrack,
      )) {
        await _stopVideoCaptureBackendIfOwned(operationGeneration, videoTrack);
        throw StateError('Video track replacement was cancelled.');
      }
      _emitLocalVideo(textureId);
    } catch (e, st) {
      final rollbackErrors = <Object>[];
      try {
        await _stopVideoCaptureBackendIfOwned(operationGeneration, videoTrack);
      } catch (error) {
        rollbackErrors.add(error);
      }

      // 切断や removeVideoTrack() が先に進んでいる場合は、元の sender を
      // 復元すると切断後のセッションへ古い状態を書き戻してしまうため、
      // 新しい backend の停止だけを行って終了する。
      if (!_isCurrentVideoCaptureOperation(
        generation: operationGeneration,
        stream: stream,
        previousTrack: previousTrack,
        requirePending: false,
      )) {
        // 切断・remove・dispose が先行した場合は、元の sender や stream を
        // 復元してはならない。停止に失敗した backend は pending operation
        // として保持し、切断処理または次の操作から再試行できる状態にする。
        if (rollbackErrors.isNotEmpty) {
          throw StateError(
            'Video track replacement was cancelled, but the new capture '
            'backend could not be stopped: ${rollbackErrors.join('; ')} '
            '(original: $e)',
          );
        }
        _finishVideoCaptureOperation(operationGeneration);
        Error.throwWithStackTrace(e, st);
      }

      _emitVideoCaptureBackendError(videoTrack, e);

      // 新 backend を停止できない状態で旧 backend を開始すると、2 つの
      // backend が同時に残るため sender の復元を進めない。pending を保持し、
      // 次の remove / replace / disconnect から停止を再試行できるようにする。
      if (rollbackErrors.isNotEmpty) {
        throw StateError(
          'Failed to stop the new video capture backend: '
          '${rollbackErrors.join('; ')} (original: $e)',
        );
      }

      if (previousTrack != null) {
        if (previousTrack.isDisposed) {
          _finishVideoCaptureOperation(operationGeneration);
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

          if (!_isCurrentVideoCaptureOperation(
            generation: operationGeneration,
            stream: stream,
            previousTrack: previousTrack,
          )) {
            throw StateError('Video track replacement was cancelled.');
          }
          _pendingVideoCaptureOperation = (
            generation: operationGeneration,
            track: previousTrack,
          );
          await _applyVideoCaptureBackend(previousTrack);

          if (!_isCurrentVideoCaptureOperation(
            generation: operationGeneration,
            stream: stream,
            previousTrack: previousTrack,
          )) {
            await _stopVideoCaptureBackendIfOwned(
              operationGeneration,
              previousTrack,
            );
            throw StateError('Video track replacement was cancelled.');
          }
        } catch (error) {
          rollbackErrors.add(error);
          // 旧 backend の開始途中で失敗した場合も、開始済みの backend が
          // 残っていれば停止してから pending を解放する。
          try {
            await _stopVideoCaptureBackendIfOwned(
              operationGeneration,
              previousTrack,
            );
          } catch (stopError) {
            rollbackErrors.add(stopError);
          }
        }
      } else {
        try {
          _webrtcClient.removeVideoTrack();
          // 呼び出し側が replace 前に新しい track を stream へ追加して
          // いた場合も、sender と stream を同じ空の状態へ戻す。
          if (_streamContainsVideoTrack(stream, videoTrack)) {
            stream.removeTrack(videoTrack);
          }
          _currentVideoTrack = null;
        } catch (error) {
          rollbackErrors.add(error);
        }
      }
      if (rollbackErrors.isNotEmpty) {
        // 停止に失敗した backend の pending は解放しない。停止成功時は
        // helper が pending を解放済みなので、ここでの finish は不要です。
        throw StateError(
          'Failed to rollback video track: ${rollbackErrors.join('; ')} '
          '(original: $e)',
        );
      }
      if (e is TimeoutException) {
        _finishVideoCaptureOperation(operationGeneration);
        throw StateError('Failed to apply video capture backend: timeout');
      }
      _finishVideoCaptureOperation(operationGeneration);
      Error.throwWithStackTrace(e, st);
    }

    if (previousTrack != null &&
        _streamContainsVideoTrack(stream, previousTrack)) {
      stream.removeTrack(previousTrack);
    }
    if (!_streamContainsVideoTrack(stream, videoTrack)) {
      stream.addTrack(videoTrack);
    }
    previousTrack?.detachFromConnection(id);
    videoTrack.attachToConnection(id);
    _currentVideoTrack = videoTrack;
    _finishVideoCaptureOperation(operationGeneration);
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
  Future<void> removeVideoTrack(LocalMediaStream stream) {
    _ensureNotDisposed();
    _validateRemoveVideoTrack(stream);
    // remove は進行中の ReplayKit start をキャンセルする意図を持つため、
    // 待ち行列へ入る前に世代だけ無効化する。実際の sender 更新は直列化
    // された本体で行う。
    _invalidateVideoCaptureOperation();
    final pendingStop = _stopPendingVideoCaptureOperation();
    return _runVideoMutation(() async {
      try {
        await pendingStop;
      } catch (_) {
        // 本体でも停止を再試行し、失敗時は pending ownership を保持する。
      }
      return _removeVideoTrackInternal(stream);
    });
  }

  /// 接続中の video sender から track を外す本体。
  Future<void> _removeVideoTrackInternal(LocalMediaStream stream) async {
    _ensureNotDisposed();
    _validateRemoveVideoTrack(stream);

    // 進行中の ReplayKit 開始を無効化し、切断や remove と競合した
    // replaceVideoTrack() が完了後に sender を復活させないようにする。
    final pendingTrack = _pendingVideoCaptureOperation?.track;
    _invalidateVideoCaptureOperation();
    await _stopPendingVideoCaptureOperation();

    final currentTrack = _currentVideoTrack;
    if (currentTrack == null ||
        !_streamContainsVideoTrack(stream, currentTrack)) {
      if (pendingTrack != null) {
        // replaceVideoTrack() が sender を先に置き換えたあとで呼ばれた
        // removeVideoTrack() では、まだ current track が更新されていない。
        // pending track の sender もここで確実に外す。
        _webrtcClient.removeVideoTrack();
        if (_streamContainsVideoTrack(stream, pendingTrack)) {
          // replace 前から stream に追加されていた track を残すと、
          // sender の空状態と stream の内容が不一致になる。
          stream.removeTrack(pendingTrack);
        }
        currentTrack?.detachFromConnection(id);
        pendingTrack.detachFromConnection(id);
        _currentVideoTrack = null;
        return;
      }
      _emitDebugMessage(
        'Video track is not attached to the stream. Skipping removeVideoTrack.',
      );
      return;
    }

    if (currentTrack.captureType == VideoTrackCaptureType.screen) {
      await _stopVideoCaptureBackend(currentTrack);
    }
    _webrtcClient.removeVideoTrack();
    stream.removeTrack(currentTrack);
    if (pendingTrack != null &&
        !identical(pendingTrack, currentTrack) &&
        _streamContainsVideoTrack(stream, pendingTrack)) {
      stream.removeTrack(pendingTrack);
      pendingTrack.detachFromConnection(id);
    }
    currentTrack.detachFromConnection(id);
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
    final mediaDisabled = audioExplicit == false && videoExplicit == false;
    final allowsNullStream =
        mediaDisabled || (audioExplicit == null && videoExplicit == null);

    if (stream == null) {
      // メディアが無効、または未指定で Sora のデフォルトを利用する場合は、
      // ローカル Stream を省略した接続を許可する。
      if (allowsNullStream) {
        return;
      }
      throw StateError('MediaStream is required when sending audio or video.');
    }

    // 音声・映像ともに明示的にオフのときはローカルメディアなし。
    if (mediaDisabled) {
      throw StateError(
        'MediaStream must be null when audio and video are disabled.',
      );
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
  ///
  /// 発生した例外はラップせず元の型でそのまま伝搬させる。呼び出し元での
  /// 通知経路と rollback の扱いは各 caller の `catch` および
  /// `_emitVideoCaptureBackendError` の docstring を参照する。
  ///
  /// external capture では Flutter Texture ベースのプレビュー経路を持たない
  /// ため textureId を返さず null を返す。返り値は [_emitLocalVideo] に
  /// そのまま渡してよく、null の場合は emit がスキップされる。
  Future<int?> _applyVideoCaptureBackend(LocalVideoTrack track) async {
    if (track.captureType == VideoTrackCaptureType.external) {
      return null;
    }
    final textureId = await track.startCaptureForConnection(id);
    if (track.isDisposed) {
      throw StateError('Video track was disposed during capture start.');
    }
    return textureId;
  }

  /// 現在の接続に属するキャプチャ開始失敗だけを通知する。
  ///
  /// screen キャプチャの `SoraConnectionErrorDetails.platformError` 文字列は
  /// `screenCapturePlatformErrorCode` (別ファイル) に委譲する。camera 経路は
  /// 既存設計どおり `details` を null にする (`platformError` を提供しない)。
  void _emitVideoCaptureBackendError(LocalVideoTrack track, Object error) {
    final isScreen = track.captureType == VideoTrackCaptureType.screen;
    // 画面キャプチャは公開 API ではないため、このエラーコードは内部実装専用の
    // 文字列リテラルで表現する (公開定数 SoraErrorCode.screenCaptureError は削除済み)。
    _emitConnectionErrorEvent(
      code: isScreen ? 'screen_capture_error' : SoraErrorCode.cameraOpenError,
      message: 'Failed to apply video capture backend: $error',
      retriable: true,
      details: isScreen
          ? SoraConnectionErrorDetails(
              platformError: screenCapturePlatformErrorCode(error),
            )
          : null,
    );
  }

  /// LocalVideoTrack の capture 種別に応じて映像入力経路を停止する。
  Future<void> _stopVideoCaptureBackend(LocalVideoTrack track) async {
    if (track.captureType == VideoTrackCaptureType.external) {
      return;
    }
    if (track.captureType == VideoTrackCaptureType.camera &&
        track.hasOtherConnectionOwner(id)) {
      // 同じ camera track を別接続も利用している場合、一方の切り替えで
      // process-wide camera capturer を停止すると他接続の映像まで止まる。
      return;
    }
    if (Platform.isIOS) {
      await track.stopCaptureForConnection(id);
      return;
    }
    if (track.captureType == VideoTrackCaptureType.camera) {
      await media_device_platform.stopCameraCapturer(
        videoSourcePtr: track.videoSourceAddress,
      );
    }
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

  /// テスト専用に `_handleWebrtcEvent` を呼び出すラッパー。
  @visibleForTesting
  Future<void> handleWebrtcEventForTest(
    String type,
    Map<String, Object?> data,
  ) {
    return _handleWebrtcEvent(type, data);
  }

  /// テスト専用に `_handleRedirectMessage` を呼び出すラッパー。
  ///
  /// redirect 経路の異常終了処理を、実 WebSocket サーバーに対する
  /// 接続失敗シナリオで検証するために使う。
  @visibleForTesting
  Future<void> handleRedirectMessageForTest(Map<String, Object?> payload) {
    return _handleRedirectMessage(payload);
  }

  /// テスト専用に、redirect 起動前のシグナリング WebSocket 状態を注入する。
  ///
  /// 実 WebSocket サーバー相手に確立した channel を `_signalingState` に
  /// 反映し、`_connectWebSocket` が本番で登録するのと同一形式の subscription
  /// (onData: `_enqueueWebSocketMessage` / onError: `_handleWebSocketError`
  /// / onDone: `_handleWebSocketDone`) を新規に登録する。
  ///
  /// **本番との差分**: `_connectWebSocket` は `connectingWebSocketChannel` に
  /// 一旦セットしてから `channel.ready` 成功後に `webSocketChannel` へ promote
  /// し、その過程で `webSocketClosedCompleter` を設定する。本ヘルパは
  /// `webSocketChannel` を直接セットし、`connectingWebSocketChannel` promotion
  /// と `webSocketClosedCompleter` の設定を省略する。redirect の payload 検証
  /// 失敗経路で旧 subscription が実際に cancel されることを検証するのが
  /// 目的であり、その検証には subscription 登録の再現だけで足りる。
  @visibleForTesting
  void injectSignalingWebSocketForTest(WebSocketChannel channel) {
    _signalingState.webSocketChannel = channel;
    _signalingState.webSocketSubscription = channel.stream.listen(
      (Object? message) => _enqueueWebSocketMessage(message),
      onError: (Object error, StackTrace stackTrace) {
        _handleWebSocketError(error, stackTrace, channel);
      },
      onDone: () {
        _handleWebSocketDone(channel);
      },
    );
  }

  /// テスト専用に `_enqueueWebSocketMessage` を呼び出すラッパー。
  ///
  /// WebSocket メッセージ処理の tail 直列化を、実 WebSocket 経由ではなく
  /// 直接 append 経路で exercise するために使う。テスト側で
  /// `_handleWebSocketMessage` を直接呼ぶと tail を迂回することになるため、
  /// 順序保証を検証するには本ヘルパ経由の enqueue が必須。
  @visibleForTesting
  Future<void> enqueueWebSocketMessageForTest(Object? message) {
    return _enqueueWebSocketMessage(message);
  }

  /// テスト専用に、WebSocket メッセージ tail が保持されているかを返す。
  ///
  /// `_resetConnectionSessionState()` の `resetSession()` で tail が null に
  /// 戻ることを検証するために使う。internal Future を外部に晒さないため、
  /// bool のみを返す (誤って外部から await される事故を防ぐ)。
  @visibleForTesting
  bool get hasWebSocketMessageTailForTest =>
      _signalingState.webSocketMessageTail != null;

  /// テスト専用に、シグナリング transport が残存しているかどうかを返す。
  ///
  /// 異常終了処理後に `_signalingState` が完全にリセットされていることを
  /// 検証するために使う。
  @visibleForTesting
  bool get signalingHasActiveTransportForTest =>
      _signalingState.hasActiveTransport;

  /// テスト専用に、`_disconnecting` フラグの現在値を返す。
  ///
  /// `disconnect()` / `dispose()` が非 TimeoutException の例外で中断した場合に
  /// フラグが true のまま残らないことを検証するために使う。
  @visibleForTesting
  bool get disconnectingForTest => _disconnecting;

  /// テスト専用に、`_abnormalTerminationStarted` フラグの現在値を返す。
  ///
  /// `disconnect()` の finally で併せてリセットされることを検証するために使う。
  /// リセットの根拠と受容トレードオフは `_abnormalTerminationStarted` 側の
  /// フィールド docstring を参照。
  @visibleForTesting
  bool get abnormalTerminationStartedForTest => _abnormalTerminationStarted;

  /// テスト専用に [_emitLocalVideo] を呼び出すラッパー。
  ///
  /// external capture のような Flutter Texture プレビューを持たない経路で
  /// null が渡ると emit がスキップされ、非 null では [localVideo] Stream に
  /// 流れる不変条件を検証するために使う。
  @visibleForTesting
  void emitLocalVideoForTest(int? textureId) {
    _emitLocalVideo(textureId);
  }

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
        _peerConnectionConnected = true;
        _completeConnectReady();
        if (!_delayConnectedStateEvent) {
          _emitConnectionStateEvent(const SoraConnectedState());
        }
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
        if (code == _disconnectReasonPeerConnectionFailed) {
          // RTCPeerConnectionState failed は disconnect メッセージを送信
          // しない異常終了として共通の異常終了処理へ委譲する。
          // teardown 例外は debug message のみに限定して受け止める。
          // エラーイベントは 0075 の外側 catchError が発火するため、
          // ここでは emit しない（二重通知を避ける）。
          await _handleAbnormalTermination().catchError((
            Object e,
            StackTrace st,
          ) {
            _emitDebugMessage('abnormal termination failed: $e');
          });
        } else if (!_disconnecting && !_abnormalTerminationStarted) {
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
            final existingDisconnect = _ongoingDisconnect;
            if (existingDisconnect != null) {
              await existingDisconnect;
            } else {
              // teardown 完了後に遅延到達した異常イベントで再度終了処理を
              // 実行しないよう、このセッションの終了処理ガードを立てる。
              _abnormalTerminationStarted = true;
              final disconnectCompleter = Completer<void>();
              _ongoingDisconnect = disconnectCompleter.future;
              _connectGeneration++;
              _remoteTrackManager.invalidateGeneration();
              _disconnecting = true;
              try {
                await _teardownNativeSession();
                _resetConnectionSessionState();
              } finally {
                disconnectCompleter.complete();
                _ongoingDisconnect = null;
              }
            }
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
    // remote track 系イベントは必須フィールド欠落や Sora フォーマット外の
    // trackId が来ると _require* が StateError を投げるため、silent drop せず
    // デバッグメッセージとエラーイベントへ変換する。
    if (type == 'remote_track_added' ||
        type == 'remote_track_removed' ||
        type == 'remote_video_track_added' ||
        type == 'remote_video_track_removed') {
      try {
        if (type == 'remote_track_added') {
          final kind = _requireRemoteTrackKind(data, type: type);
          final trackId = _requireRemoteTrackId(data, type: type);
          if (kind == 'video') {
            return;
          }
          _remoteTrackManager.handleRemoteAudioTrackAdded(trackId);
          return;
        }
        if (type == 'remote_track_removed') {
          final kind = _requireRemoteTrackKind(data, type: type);
          final trackId = _requireRemoteTrackId(data, type: type);
          if (kind == 'video') {
            return;
          }
          _remoteTrackManager.handleRemoteAudioTrackRemoved(trackId);
          return;
        }
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
        if (type == 'remote_video_track_removed') {
          final trackAddress = data['trackAddress'] as int?;
          if (trackAddress != null && trackAddress != 0) {
            unawaited(
              _remoteTrackManager
                  .detachRemoteVideoTrack(trackAddress)
                  .catchError((Object e, StackTrace st) {
                    _emitDebugMessage('remote_track detach failed: $e');
                  }),
            );
          }
          return;
        }
      } catch (e) {
        _emitDebugMessage('native event handling failed: $e');
        _emitConnectionErrorEvent(
          code: SoraErrorCode.unexpectedNativeEvent,
          message: 'Unexpected native event: $type: $e',
        );
        return;
      }
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
    // DataChannel 切断時イベント
    // シグナリング用 DataChannel の異常切断・エラーを検出した場合は
    // 共通の異常終了処理へ委譲する。通常切断時は _disconnecting ガードで
    // 吸収される。
    if (type == 'data_channel_closing' || type == 'data_channel_closed') {
      final label = data['label'] as String?;
      if (label == 'signaling') {
        unawaited(
          _handleAbnormalTermination().catchError((Object e, StackTrace st) {
            _emitDebugMessage('abnormal termination failed: $e');
          }),
        );
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
    // 画面キャプチャのエラー種別。公開 API の削除に伴い定数を廃止したため、
    // iOS ネイティブ側の送信値と一致させる内部専用の文字列リテラルとして扱う。
    if (type == 'screen_capture_error') {
      final message = event['message'] as String?;
      final platformError = event['platformError'] as String?;
      _emitConnectionErrorEvent(
        code: 'screen_capture_error',
        message: message ?? 'Screen capture failed.',
        retriable: false,
        details: SoraConnectionErrorDetails(platformError: platformError),
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

  /// [textureId] が非 null のときのみ [localVideo] Stream に emit する。
  ///
  /// external capture のように Flutter Texture ベースのプレビュー経路を
  /// 持たない場合は null で呼ばれ、この経路では emit がスキップされる。
  void _emitLocalVideo(int? textureId) {
    if (textureId == null) {
      return;
    }
    if (!_localVideo.isClosed) {
      _localVideo.add(SoraLocalVideoHandle(textureId: textureId));
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
