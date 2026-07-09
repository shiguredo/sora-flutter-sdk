// ignore_for_file: public_member_api_docs
// dart:ffi で libwebrtc-c の C API を直接呼び出して
// WebRTC のコアロジック (PeerConnectionFactory, PeerConnection,
// SDP ネゴシエーション, ICE, DataChannel, Stats) を管理する。

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import '../sora_error_code.dart';
import 'bindings.dart';
import 'callback_handlers.dart' show SdpNegotiationCallbacks;
import 'library_loader.dart';
import 'memory.dart';
import 'simulcast_video_encoder_factory.dart';

/// WebRTC クライアントのイベントコールバック型
typedef WebrtcClientEventCallback =
    void Function(String type, Map<String, Object?> data);

/// DataChannel のリソースを束ねる内部クラス。
class _DataChannelResources {
  /// DataChannel のポインタ
  Pointer<WebrtcDataChannelInterface>? dc;

  /// sora_observer_bridge_setup_dc の戻り値
  Pointer<Void>? ctx;

  /// DataChannel に登録した NativeCallable 群
  final List<NativeCallable<dynamic>> callables = [];
}

/// WebRTC クライアント (dart:ffi 実装)
class WebrtcClient {
  final LibWebrtcC _lib;
  final WebrtcConstants _consts;
  final Map<String, Object?> _config;
  final WebrtcClientEventCallback _onEvent;
  bool _disposed = false;
  int? _sessionGeneration;

  // PeerConnectionFactory / PeerConnection
  Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted>? _factoryRef;
  Pointer<WebrtcPeerConnectionInterfaceRefcounted>? _pcRef;

  // 進行中の getStats() を後始末するための追跡フィールド
  Completer<String?>? _pendingStatsCompleter;
  Pointer<RTCStatsCollectorCallbackCbs>? _pendingStatsCbsPtr;
  NativeCallable<Function>? _pendingStatsNativeCallable;
  Timer? _pendingStatsTimer;

  // C コールバックブリッジ (PeerConnectionObserver + リモートビデオ管理)
  Pointer<SoraObserverBridge>? _observerBridge;
  // NativeCallable を保持する (C ブリッジのライフタイムに合わせる)
  final List<NativeCallable<dynamic>> _nativeCallables = [];

  // SDP ネゴシエーション
  SdpNegotiationCallbacks? _sdpCallbacks;

  // connect(stream) で受け取った local track を offer 応答まで保持する。
  Pointer<WebrtcAudioTrackInterfaceRefcounted>? _pendingLocalAudioTrackRef;
  Pointer<WebrtcVideoTrackInterfaceRefcounted>? _pendingLocalVideoTrackRef;
  String? _pendingLocalStreamId;

  // Audio / Video RtpSender
  Pointer<WebrtcRtpSenderInterface>? _audioRtpSender;

  // ビデオ RtpSender (simulcast encodings 設定用)
  Pointer<WebrtcRtpSenderInterface>? _videoRtpSender;

  // offer から受け取った encodings (simulcast 用)
  List<Map<String, Object?>>? _pendingEncodings;

  // DataChannel (notify)
  final _notifyDc = _DataChannelResources();
  // DataChannel (push)
  final _pushDc = _DataChannelResources();
  // DataChannel (rpc)
  final _rpcDc = _DataChannelResources();
  // DataChannel (stats)
  final _statsDc = _DataChannelResources();
  // DataChannel (signaling)
  final _signalingDc = _DataChannelResources();
  // DataChannel (カスタムラベル)
  final Map<String, _DataChannelResources> _customDataChannels = {};

  WebrtcClient._({
    required LibWebrtcC lib,
    required WebrtcConstants consts,
    required Map<String, Object?> config,
    required WebrtcClientEventCallback onEvent,
  }) : _lib = lib,
       _consts = consts,
       _config = config,
       _onEvent = onEvent;

  static LibWebrtcC? _sharedLib;
  static WebrtcConstants? _sharedConsts;
  static DynamicLibrary? _sharedDynLib;
  static Pointer<WebrtcThreadUnique>? _sharedNetworkThread;
  static Pointer<WebrtcThreadUnique>? _sharedWorkerThread;
  static Pointer<WebrtcThreadUnique>? _sharedSignalingThread;
  static Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted>?
  _sharedFactoryRef;
  // macOS / Windows / Linux で明示生成した AudioDeviceModule の参照を保持する。
  // Dart 側で SetRecordingDevice を呼ぶために PCF に渡した後も release せず持ち続ける。
  static Pointer<WebrtcAudioDeviceModuleRefcounted>? _sharedAdmRef;
  static SimulcastVideoEncoderFactory? _sharedSimulcastVideoEncoderFactory;
  // 音声デバイスを利用するかどうか。最初の create() 呼び出し時に設定される。
  // false の場合は kDummyAudio が選択される。
  static bool _useAudioDevice = true;

  // `LibWebrtcC` の共有インスタンスを返す。
  //
  // 初回アクセス時だけ共有ライブラリをロードし、以降は全クライアントで同じ
  // FFI バインディングと定数キャッシュを使い回す。
  static LibWebrtcC get sharedLib {
    if (_sharedLib == null) {
      _sharedDynLib = loadLibWebrtcC();
      _sharedLib = LibWebrtcC(_sharedDynLib!);
      _sharedConsts = WebrtcConstants(_sharedDynLib!);
    }
    return _sharedLib!;
  }

  // 共有ライブラリから読み取ったランタイム定数群を返す。
  //
  // `sharedLib` の初期化に依存するため、必要なら先にそちらを起動する。
  static WebrtcConstants get sharedConsts {
    if (_sharedConsts == null) {
      // sharedLib のアクセスで初期化される
      sharedLib;
    }
    return _sharedConsts!;
  }

  // `MediaStream` / Track 生成にも使う共有 `PeerConnectionFactory` を返す。
  //
  // `PeerConnectionFactoryInterfaceRefcounted` を raw pointer 化して返すが、
  // 寿命自体は静的共有フィールドで管理する。
  static Pointer<WebrtcPeerConnectionFactoryInterface> get sharedFactory {
    _ensureSharedFactory();
    return sharedLib.pcFactoryRefcountedGet(_sharedFactoryRef!);
  }

  // macOS / Windows / Linux で保持している `AudioDeviceModule` の raw pointer を返す。
  //
  // 録音デバイスの切り替え API で再利用するため、PCF に渡した後も
  // `_sharedAdmRef` を握り続けている。未生成プラットフォームでは `nullptr`。
  static Pointer<WebrtcAudioDeviceModule> get sharedAudioDeviceModule {
    _ensureSharedFactory();
    final ref = _sharedAdmRef;
    if (ref == null) {
      return nullptr;
    }
    return sharedLib.audioDeviceModuleRefcountedGet(ref);
  }

  // `deviceId` と一致する録音デバイスへ `AudioDeviceModule` を切り替える。
  //
  // macOS の ADM は guid が空になるケースがあるため、必要に応じて
  // `labelHint` や `default (label)` もフォールバック候補として探す。
  static void setRecordingDeviceByGuid(
    String deviceId, {
    String? labelHint,
    bool preferDefaultDevice = false,
  }) {
    final adm = sharedAudioDeviceModule;
    if (adm == nullptr) {
      throw StateError('AudioDeviceModule is not initialized.');
    }
    final count = sharedLib.audioDeviceModuleRecordingDevices(adm);
    if (count <= 0) {
      throw StateError('No audio input devices available.');
    }
    final nameBuf = calloc.allocate<Char>(128);
    final guidBuf = calloc.allocate<Char>(128);
    try {
      int? targetIndex;
      int? labelMatchIndex;
      int? defaultLabelMatchIndex;
      for (var i = 0; i < count; i++) {
        final rc = sharedLib.audioDeviceModuleRecordingDeviceName(
          adm,
          i,
          nameBuf,
          guidBuf,
        );
        if (rc != 0) {
          continue;
        }
        final guidStr = guidBuf.cast<Utf8>().toDartString();
        final nameStr = nameBuf.cast<Utf8>().toDartString();
        if (guidStr == deviceId || nameStr == deviceId) {
          targetIndex = i;
          break;
        }
        if (labelHint != null && nameStr == labelHint) {
          labelMatchIndex ??= i;
        }
        if (preferDefaultDevice &&
            labelHint != null &&
            nameStr == 'default ($labelHint)') {
          defaultLabelMatchIndex ??= i;
        }
      }
      if (targetIndex == null && preferDefaultDevice) {
        targetIndex = defaultLabelMatchIndex;
      }
      targetIndex ??= labelMatchIndex;
      if (targetIndex == null) {
        throw StateError('Audio input device not found: $deviceId');
      }
      final rc = sharedLib.audioDeviceModuleSetRecordingDevice(
        adm,
        targetIndex,
      );
      if (rc != 0) {
        throw StateError(
          'SetRecordingDevice failed: deviceId=$deviceId rc=$rc',
        );
      }
    } finally {
      calloc.free(nameBuf);
      calloc.free(guidBuf);
    }
  }

  /// 共有 `PeerConnectionFactory` と関連スレッド群を必要時に 1 回だけ生成する。
  ///
  /// network / worker / signaling thread、ADM、encoder/decoder factory、
  /// audio processing をまとめて依存オブジェクトへ積み、最後に modular
  /// factory を構築する。
  static void _ensureSharedFactory() {
    if (_sharedFactoryRef != null) {
      return;
    }

    _sharedNetworkThread = sharedLib.threadCreateWithSocketServer();
    _sharedWorkerThread = sharedLib.threadCreate();
    _sharedSignalingThread = sharedLib.threadCreate();
    sharedLib.threadStart(sharedLib.threadUniqueGet(_sharedNetworkThread!));
    sharedLib.threadStart(sharedLib.threadUniqueGet(_sharedWorkerThread!));
    sharedLib.threadStart(sharedLib.threadUniqueGet(_sharedSignalingThread!));

    final deps = sharedLib.pcFactoryDependenciesNew();
    sharedLib.pcFactoryDependenciesSetNetworkThread(
      deps,
      sharedLib.threadUniqueGet(_sharedNetworkThread!),
    );
    sharedLib.pcFactoryDependenciesSetWorkerThread(
      deps,
      sharedLib.threadUniqueGet(_sharedWorkerThread!),
    );
    sharedLib.pcFactoryDependenciesSetSignalingThread(
      deps,
      sharedLib.threadUniqueGet(_sharedSignalingThread!),
    );

    if (Platform.isAndroid) {
      final env = sharedLib.createEnvironment();
      final adm = sharedLib.createAndroidAudioDeviceModule(env);
      sharedLib.environmentDelete(env);
      if (adm != nullptr) {
        sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
        sharedLib.audioDeviceModuleRelease(
          sharedLib.audioDeviceModuleRefcountedGet(adm),
        );
      }
    } else if (Platform.isMacOS) {
      if (_useAudioDevice) {
        final env = sharedLib.createEnvironment();
        final adm = sharedLib.createAudioDeviceModule(
          env,
          sharedConsts.kPlatformDefaultAudio,
        );
        sharedLib.environmentDelete(env);
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          // Dart から SetRecordingDevice を呼ぶために参照を保持しておく
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcMac = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcMac != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcMac');
          }
        }
      } else {
        final adm = sharedLib.soraCreatePushAudioDevice();
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcMac = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcMac != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcMac');
          }
        }
      }
    } else if (Platform.isWindows) {
      if (_useAudioDevice) {
        // Windows: setjmp/longjmp で abort を捕捉して安全に ADM を作成する
        final env = sharedLib.createEnvironment();
        final adm = sharedLib.soraCreateAudioDeviceModule(
          env,
          sharedConsts.kPlatformDefaultAudio,
        );
        sharedLib.environmentDelete(env);
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcWin = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcWin != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcWin');
          }
        }
      } else {
        final adm = sharedLib.soraCreatePushAudioDevice();
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcWin = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcWin != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcWin');
          }
        }
      }
    } else if (Platform.isLinux) {
      if (_useAudioDevice) {
        final env = sharedLib.createEnvironment();
        final adm = sharedLib.createAudioDeviceModule(
          env,
          sharedConsts.kPlatformDefaultAudio,
        );
        sharedLib.environmentDelete(env);
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcLinux = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcLinux != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcLinux');
          }
        }
      } else {
        final adm = sharedLib.soraCreatePushAudioDevice();
        if (adm != nullptr) {
          sharedLib.pcFactoryDependenciesSetAdm(deps, adm);
          if (_sharedAdmRef != null) {
            sharedLib.audioDeviceModuleRelease(
              sharedLib.audioDeviceModuleRefcountedGet(_sharedAdmRef!),
            );
          }
          _sharedAdmRef = adm;
          final initRcLinux = sharedLib.audioDeviceModuleInit(
            sharedLib.audioDeviceModuleRefcountedGet(adm),
          );
          if (initRcLinux != 0) {
            throw StateError('AudioDeviceModule init failed: rc=$initRcLinux');
          }
        }
      }
    }

    final eventLogFactory = sharedLib.rtcEventLogFactoryCreate();
    sharedLib.pcFactoryDependenciesSetEventLogFactory(deps, eventLogFactory);

    final audioEnc = sharedLib.createBuiltinAudioEncoderFactory();
    final audioDec = sharedLib.createBuiltinAudioDecoderFactory();
    final videoEnc = _createDefaultVideoEncoderFactory();
    _sharedSimulcastVideoEncoderFactory = SimulcastVideoEncoderFactory(
      sharedLib,
      videoEnc,
    );
    final videoDec = _createDefaultVideoDecoderFactory();
    sharedLib.pcFactoryDependenciesSetAudioEncoderFactory(deps, audioEnc);
    sharedLib.pcFactoryDependenciesSetAudioDecoderFactory(deps, audioDec);
    sharedLib.pcFactoryDependenciesSetVideoEncoderFactory(
      deps,
      _sharedSimulcastVideoEncoderFactory!.native(),
    );
    sharedLib.pcFactoryDependenciesSetVideoDecoderFactory(deps, videoDec);
    sharedLib.audioEncoderFactoryRelease(
      sharedLib.audioEncoderFactoryRefcountedGet(audioEnc),
    );
    sharedLib.audioDecoderFactoryRelease(
      sharedLib.audioDecoderFactoryRefcountedGet(audioDec),
    );

    final apBuilder = sharedLib.builtinAudioProcessingBuilderCreate();
    sharedLib.pcFactoryDependenciesSetAudioProcessingBuilder(deps, apBuilder);
    sharedLib.enableMedia(deps);
    _sharedFactoryRef = sharedLib.createModularPeerConnectionFactory(deps);
    sharedLib.pcFactoryDependenciesDelete(deps);

    final options = sharedLib.pcFactoryOptionsNew();
    sharedLib.pcFactoryOptionsSetDisableEncryption(options, 0);
    sharedLib.pcFactoryOptionsSetSslMaxVersion(
      options,
      sharedConsts.sslProtocolDtls12,
    );
    sharedLib.pcFactorySetOptions(sharedFactory, options);
    sharedLib.pcFactoryOptionsDelete(options);
  }

  /// 設定とイベント出力先を束ねた `WebrtcClient` を生成する。
  static WebrtcClient create({
    required Map<String, Object?> config,
    required WebrtcClientEventCallback onEvent,
  }) {
    // 最初の create() 呼び出し時に useAudioDevice を共有設定として記録する。
    // _ensureSharedFactory() は一度だけ実行されるため、後続の create() で
    // 異なる値を渡しても反映されない。
    _useAudioDevice = (config['useAudioDevice'] as bool?) ?? true;
    return WebrtcClient._(
      lib: sharedLib,
      consts: sharedConsts,
      config: config,
      onEvent: onEvent,
    );
  }

  // ---------------------------------------------------------------------------
  // 接続制御
  // ---------------------------------------------------------------------------

  /// 接続開始要求を受け取り、ローカルトラックを一時保持して PC 作成へ進む。
  ///
  /// 実際の `PeerConnection` 生成は offer 受信時まで遅延されるが、
  /// connect 呼び出し時点で state は `connecting` へ遷移させる。
  ///
  /// [sessionGeneration] は `SoraConnection` のセッション世代。
  /// 全 state_changed イベントに付与され、旧セッションの遅延イベント抑制に使われる。
  void connect({
    Pointer<WebrtcAudioTrackInterfaceRefcounted>? localAudioTrackRef,
    Pointer<WebrtcVideoTrackInterfaceRefcounted>? localVideoTrackRef,
    String? localStreamId,
    required int sessionGeneration,
  }) {
    if (_disposed) return;
    _sessionGeneration = sessionGeneration;
    _emitState('connecting', null, null, sessionGeneration: sessionGeneration);
    _pendingLocalAudioTrackRef = localAudioTrackRef;
    _pendingLocalVideoTrackRef = localVideoTrackRef;
    _pendingLocalStreamId = localStreamId;
    _createPeerConnectionFactory();
  }

  /// 現在の `PeerConnection` 一式だけを破棄して切断状態へ戻す。
  ///
  /// shared factory や共有スレッドは残すため、同じプロセス内での再接続は
  /// 軽量に行える。
  void disconnect() {
    if (_disposed) return;
    closePeerConnection();
    _emitState(
      'disconnected',
      'closed',
      null,
      sessionGeneration: _sessionGeneration,
    );
    _sessionGeneration = null;
  }

  /// インスタンス寿命を終了させ、以後の利用を禁止する。
  ///
  /// `disconnect()` 相当の片付けを行ったうえで、
  /// 以降のシグナリング入力や sender 操作を無効化する。
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    closePeerConnection();
    _factoryRef = null;
  }

  // PeerConnection と関連リソースを解放する
  //
  // 解放順序:
  // 1. DataChannel の Observer 解除と解放
  // 2. リモートビデオトラックのシンク解除と参照解放
  // 3. 進行中の getStats の Dart 側追跡解除
  //    (native callback リソースは onStatsDelivered が自己解放)
  // 4. ローカルビデオトラックの解放
  // 5. PeerConnection の解放
  // 6. C コールバックブリッジの破棄
  // 7. NativeCallable の解放
  //
  // リモートビデオトラックは PeerConnection の Release 前に解放する。
  // PeerConnection 破棄後だと VideoTrack のデストラクタが
  // 無効な VideoSource に対して UnregisterObserver を呼んでクラッシュする。
  @visibleForTesting
  void closePeerConnection() {
    // DataChannel をクリーンアップする
    _cleanupNotifyDataChannel();
    _cleanupPushDataChannel();
    _cleanupRpcDataChannel();
    _cleanupStatsDataChannel();
    _cleanupCustomDataChannels();
    _cleanupSignalingDataChannel();

    // 進行中の getStats があればエラー完了させる。
    // native callback リソース (cbsPtr, NativeCallable) は
    // onStatsDelivered コールバックが到着時に自身で解放するため、
    // ここでは Dart 側の追跡 (Completer, Timer) だけを解除する。
    //
    // libwebrtc-c m148 系では、`pcRelease()` 後に pending callback が
    // 必ず到達する契約は確認できない。
    // `pcGetStats` は callback 登録付きの非同期要求だが、`pcRelease` は
    // `Close` の callback 完了待ち契約を持たないため、破棄タイミング次第で
    // stats callback が drop されうる。
    // そのため callback 未到達時は 1 PC あたり最大 1 件の bounded leak が
    // 残りうるが、UAF 回避を優先して意図的に許容する。
    cleanupPendingStatsRequest()?.completeError(
      StateError('PeerConnection closed during getStats.'),
    );

    if (_audioRtpSender != null) {
      _lib.rtpSenderRelease(_audioRtpSender!);
      _audioRtpSender = null;
    }

    // ビデオ RtpSender を解放する
    if (_videoRtpSender != null) {
      _lib.rtpSenderRelease(_videoRtpSender!);
      _videoRtpSender = null;
    }
    _pendingEncodings = null;
    if (_pendingLocalAudioTrackRef != null) {
      _lib.audioTrackRelease(
        _lib.audioTrackRefcountedGet(_pendingLocalAudioTrackRef!),
      );
    }
    if (_pendingLocalVideoTrackRef != null) {
      _lib.videoTrackRelease(
        _lib.videoTrackRefcountedGet(_pendingLocalVideoTrackRef!),
      );
    }
    _pendingLocalAudioTrackRef = null;
    _pendingLocalVideoTrackRef = null;
    _pendingLocalStreamId = null;

    // PeerConnection を解放する
    if (_pcRef != null) {
      _lib.pcRelease(_lib.pcRefcountedGet(_pcRef!));
      _pcRef = null;
    }

    // C コールバックブリッジを破棄する (observer も含む)
    if (_observerBridge != null) {
      _lib.soraObserverBridgeDestroy(_observerBridge!);
      _observerBridge = null;
    }

    // NativeCallable を閉じる
    for (final nc in _nativeCallables) {
      nc.close();
    }
    _nativeCallables.clear();

    // SDP コールバックをクリアする
    _sdpCallbacks?.cancel();
    _sdpCallbacks = null;
  }

  // ---------------------------------------------------------------------------
  // シグナリングメッセージ処理
  // ---------------------------------------------------------------------------

  /// 初回 offer を処理し、必要なら `PeerConnection` を生成して answer へ進む。
  ///
  /// simulcast 用 encodings の退避、offer config の PC 反映、
  /// `SdpNegotiationCallbacks` の初期化までをまとめて行う。
  void handleOffer(Map<String, Object?> message) {
    if (_disposed) return;
    final sdp = message['sdp'] as String?;
    if (sdp == null) {
      _emitState(
        'error',
        'offer_invalid',
        'Offer SDP is null.',
        sessionGeneration: _sessionGeneration,
      );
      return;
    }

    // offer メッセージから encodings を保存する (simulcast 用)
    final encodingsRaw = message['encodings'];
    if (encodingsRaw is List<Object?>) {
      _pendingEncodings = encodingsRaw
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> entry) => Map<String, Object?>.from(
              entry.map(
                (Object? key, Object? value) => MapEntry('$key', value),
              ),
            ),
          )
          .toList();
      _emitDebug(
        'native: offer encodings=${_pendingEncodings!.length} entries',
      );
    }

    final offerConfig = message['config'] as Map<String, Object?>?;
    if (!_ensurePeerConnection(offerConfig)) {
      return;
    }
    if (_pcRef == null) {
      _emitState(
        'error',
        'offer_invalid',
        'PeerConnection is not available.',
        sessionGeneration: _sessionGeneration,
      );
      return;
    }

    _sdpCallbacks?.cancel();
    final capturedEncodings = _pendingEncodings;
    _sdpCallbacks = SdpNegotiationCallbacks(
      lib: _lib,
      consts: _consts,
      emitState: _emitState,
      emitDebug: _emitDebug,
      emitSignalingMessage: _emitSignalingMessage,
      addLocalTracks: _addLocalTracks,
      applyEncodings: capturedEncodings != null && capturedEncodings.isNotEmpty
          ? () => _applySimulcastEncodings(capturedEncodings)
          : null,
    );
    _sdpCallbacks!.setRemoteDescription(_pcRef!, sdp);
  }

  /// 再ネゴシエーション用 re-offer を処理する。
  ///
  /// 既存 `PeerConnection` を使い回し、ローカルトラック追加はスキップしたまま
  /// `re-answer` を返す。
  void handleReOffer(Map<String, Object?> message) {
    if (_disposed) return;
    final sdp = message['sdp'] as String?;
    if (sdp == null) {
      _emitState(
        'error',
        'reoffer_invalid',
        'Re-offer SDP is null.',
        sessionGeneration: _sessionGeneration,
      );
      return;
    }
    if (_pcRef == null) {
      _emitState(
        'error',
        'reoffer_invalid',
        'PeerConnection is not available.',
        sessionGeneration: _sessionGeneration,
      );
      return;
    }

    _sdpCallbacks?.cancel();
    _sdpCallbacks = SdpNegotiationCallbacks(
      lib: _lib,
      consts: _consts,
      emitState: _emitState,
      emitDebug: _emitDebug,
      emitSignalingMessage: _emitSignalingMessage,
      addLocalTracks: _addLocalTracks,
      applyEncodings: null,
    );
    _sdpCallbacks!.setRemoteDescription(
      _pcRef!,
      sdp,
      answerType: 're-answer',
      isReOffer: true,
    );
  }

  /// リモートから受け取った ICE candidate を parse・追加する。
  ///
  /// parse 失敗時は `SdpParseError` から説明文字列を取り出し、接続エラーとして
  /// Dart 側へ返す。
  void handleCandidate(Map<String, Object?> message) {
    if (_disposed || _pcRef == null) return;
    final candidateStr = message['candidate'] as String?;
    if (candidateStr == null) return;
    final sdpMid = message['sdpMid'] as String? ?? '';
    final sdpMLineIndex = (message['sdpMLineIndex'] as num?)?.toInt() ?? 0;

    _emitDebug('native: remote_candidate mid=$sdpMid text=$candidateStr');

    final midUtf8 = sdpMid.toNativeUtf8();
    final midNative = midUtf8.cast<Char>();
    final candUtf8 = candidateStr.toNativeUtf8();
    final candidateNative = candUtf8.cast<Char>();
    final parseErrorPtr = calloc<Pointer<WebrtcSdpParseErrorUnique>>();

    final ice = _lib.createIceCandidate(
      midNative,
      midUtf8.length,
      sdpMLineIndex,
      candidateNative,
      candUtf8.length,
      parseErrorPtr,
    );

    if (ice != nullptr) {
      _lib.pcAddIceCandidate(_lib.pcRefcountedGet(_pcRef!), ice);
      _lib.iceCandidateDelete(ice);
    } else if (parseErrorPtr.value != nullptr) {
      final descPtr = calloc<Pointer<Char>>();
      final lenPtr = calloc<Size>();
      _lib.sdpParseErrorDescription(
        _lib.sdpParseErrorUniqueGet(parseErrorPtr.value),
        descPtr,
        lenPtr,
      );
      final desc = lenPtr.value > 0
          ? descPtr.value.cast<Utf8>().toDartString(length: lenPtr.value)
          : '';
      calloc.free(descPtr);
      calloc.free(lenPtr);
      _lib.sdpParseErrorUniqueDelete(parseErrorPtr.value);
      _emitState(
        'error',
        'candidate_parse_failed',
        'Candidate parse failed: $desc',
        sessionGeneration: _sessionGeneration,
      );
    }

    calloc.free(parseErrorPtr);
    calloc.free(midNative);
    calloc.free(candidateNative);
  }

  // サーバー主導の disconnect メッセージを state イベントへ変換する。
  void handleDisconnect() {
    if (_disposed) return;
    _emitState(
      'disconnected',
      'server_disconnect',
      null,
      sessionGeneration: _sessionGeneration,
    );
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  /// 進行中の getStats の Dart 側追跡 (Completer / Timer) を解除し、
  /// 未完了の Completer を返す。
  ///
  /// NativeCallable と cbsPtr は遅延 callback の到着に備えて保持し続ける。
  /// これらは onStatsDelivered コールバック自身が到着時に解放する。
  /// callback が未到達の場合、同一 PC では最大 1 件の bounded leak となる。
  ///
  /// disconnect() / dispose() 時は Dart 側追跡だけを解除し、
  /// native リソースの解放は onStatsDelivered コールバックへ委譲する。
  ///
  /// タイムアウト後にネイティブリソースを解放すると、
  /// 遅延コールバック到着時に native crash を起こすため解放しない。
  ///
  /// 二重呼び出しへの対策として、2回目以降は null を返すようにしている。
  @visibleForTesting
  Completer<String?>? cleanupPendingStatsRequest() {
    final completer = _pendingStatsCompleter;
    final timer = _pendingStatsTimer;
    _pendingStatsCompleter = null;
    _pendingStatsTimer = null;

    timer?.cancel();
    return completer;
  }

  @visibleForTesting
  void setupPendingStatsForTest(
    Completer<String?>? completer,
    Timer? timer, {
    Pointer<RTCStatsCollectorCallbackCbs>? cbsPtr,
    NativeCallable<Function>? nativeCallable,
  }) {
    _pendingStatsCompleter = completer;
    _pendingStatsTimer = timer;
    _pendingStatsCbsPtr = cbsPtr;
    _pendingStatsNativeCallable = nativeCallable;
  }

  /// WebRTC 統計情報を取得する。
  //
  // 公開 API の `RTCPeerConnection.getStats()` 互換を保つため、
  // `get` をあえて残している。
  Future<String?> getStats() {
    if (_disposed) {
      return Future<String?>.value(null);
    }
    // Future 共有: 進行中の getStats() がある場合、その future を返す
    final pendingCompleter = _pendingStatsCompleter;
    if (pendingCompleter != null) {
      return pendingCompleter.future;
    }
    // null フォールバック: timeout 後など completer が解放済みだが
    // native callback が残っている期間は null を返す
    if (_pendingStatsCbsPtr != null || _pendingStatsNativeCallable != null) {
      return Future<String?>.value(null);
    }
    if (_pcRef == null) {
      return Future<String?>.value(null);
    }

    final completer = Completer<String?>();
    _pendingStatsCompleter = completer;

    final cbsPtr = calloc<RTCStatsCollectorCallbackCbs>();
    _pendingStatsCbsPtr = cbsPtr;
    final onStatsDelivered =
        NativeCallable<
          Void Function(Pointer<WebrtcRTCStatsReportRefcounted>, Pointer<Void>)
        >.listener((
          Pointer<WebrtcRTCStatsReportRefcounted> reportRef,
          Pointer<Void> _,
        ) {
          final compt = cleanupPendingStatsRequest();
          // NativeCallable と cbsPtr の解放は callback 自身が行う。
          // PeerConnection 生存中の timeout による先行完了に備え、ここで確実に解放する。
          _pendingStatsNativeCallable?.close();
          _pendingStatsNativeCallable = null;
          if (_pendingStatsCbsPtr != null) {
            calloc.free(_pendingStatsCbsPtr!);
            _pendingStatsCbsPtr = null;
          }

          // PeerConnection 破棄後に callback が到達した場合、
          // 結果を破棄するが、callback が到達している以上 reportRef は有効である。
          // webrtc-rs 側で callback 呼び出し時に scoped_refptr で 1 ref が移譲されており、
          // reportRef は _pcRef とは独立したライフタイムを持つため Release してよい。
          final pcDisposed = _pcRef == null;
          if (pcDisposed && reportRef != nullptr) {
            final report = _lib.rtcStatsReportRefcountedGet(reportRef);
            _lib.rtcStatsReportRelease(report);
          }
          if (pcDisposed) return;

          if (compt != null && !compt.isCompleted) {
            String? json;
            if (reportRef != nullptr) {
              final report = _lib.rtcStatsReportRefcountedGet(reportRef);
              final stats = _lib.rtcStatsReportToJson(report);
              json = stdStringToDart(_lib, stats);
              _lib.rtcStatsReportRelease(report);
            }
            compt.complete(json);
          } else if (reportRef != nullptr) {
            final report = _lib.rtcStatsReportRefcountedGet(reportRef);
            _lib.rtcStatsReportRelease(report);
          }
        });
    _pendingStatsNativeCallable = onStatsDelivered;

    // タイムアウトは 5　秒とする
    _pendingStatsTimer = Timer(const Duration(seconds: 5), () {
      cleanupPendingStatsRequest()?.completeError(
        TimeoutException('getStats() timed out.', const Duration(seconds: 5)),
      );
    });

    cbsPtr.ref.onStatsDelivered = onStatsDelivered.nativeFunction;
    _lib.pcGetStats(_lib.pcRefcountedGet(_pcRef!), cbsPtr, nullptr);
    return completer.future;
  }

  /// 既存の audio sender に別の audio track を差し替える。
  ///
  /// `AudioTrack -> MediaStreamTrack` への cast を挟み、参照解放は
  /// `finally` で必ず行う。
  void replaceAudioTrack(
    Pointer<WebrtcAudioTrackInterfaceRefcounted> audioTrackRef,
  ) {
    final sender = _audioRtpSender;
    if (sender == null) {
      throw StateError('Audio sender is not available.');
    }

    final trackRef = _lib.audioTrackCastToMediaStreamTrack(audioTrackRef);
    try {
      final result = _lib.rtpSenderSetTrack(
        sender,
        _lib.mediaStreamTrackRefcountedGet(trackRef),
      );
      if (result == 0) {
        throw StateError('Failed to replace audio track on sender.');
      }
    } finally {
      _lib.mediaStreamTrackRelease(
        _lib.mediaStreamTrackRefcountedGet(trackRef),
      );
    }
  }

  /// 既存の video sender に別の video track を差し替える。
  void replaceVideoTrack(
    Pointer<WebrtcVideoTrackInterfaceRefcounted> videoTrackRef,
  ) {
    final sender = _videoRtpSender;
    if (sender == null) {
      throw StateError('Video sender is not available.');
    }

    final trackRef = _lib.videoTrackCastToMediaStreamTrack(videoTrackRef);
    try {
      final result = _lib.rtpSenderSetTrack(
        sender,
        _lib.mediaStreamTrackRefcountedGet(trackRef),
      );
      if (result == 0) {
        throw StateError('Failed to replace video track on sender.');
      }
    } finally {
      _lib.mediaStreamTrackRelease(
        _lib.mediaStreamTrackRefcountedGet(trackRef),
      );
    }
  }

  /// audio sender から track を外し、送信を停止する。
  void removeAudioTrack() {
    final sender = _audioRtpSender;
    if (sender == null) {
      throw StateError('Audio sender is not available.');
    }
    final result = _lib.rtpSenderSetTrack(sender, nullptr);
    if (result == 0) {
      throw StateError('Failed to remove audio track from sender.');
    }
  }

  /// video sender から track を外し、映像送信を停止する。
  void removeVideoTrack() {
    final sender = _videoRtpSender;
    if (sender == null) {
      throw StateError('Video sender is not available.');
    }
    final result = _lib.rtpSenderSetTrack(sender, nullptr);
    if (result == 0) {
      throw StateError('Failed to remove video track from sender.');
    }
  }

  // ---------------------------------------------------------------------------
  // PeerConnectionFactory
  // ---------------------------------------------------------------------------

  // インスタンス側で使う `PeerConnectionFactory` 参照を共有 factory へ向ける。
  //
  // factory 本体は shared 側の寿命に従うため、ここでは参照を保持するだけ。
  void _createPeerConnectionFactory() {
    if (_factoryRef != null) return;
    _ensureSharedFactory();
    _factoryRef = _sharedFactoryRef;
  }

  // ---------------------------------------------------------------------------
  // PeerConnection
  // ---------------------------------------------------------------------------

  // `PeerConnection` 未生成なら構成を反映して新規生成する。
  //
  // RTCConfiguration、ICE サーバー、observer bridge、DataChannel 受信口を
  // まとめて初期化し、生成エラーは Dart 側 event として返す。
  bool _ensurePeerConnection(Map<String, Object?>? offerConfig) {
    if (_pcRef != null) return true;
    _createPeerConnectionFactory();
    // _sessionGeneration をクロージャでキャプチャする。
    // これにより旧 connect() 由来の遅延イベントが新 connect() の世代で
    // タグ付けされるのを防ぐ。
    final sessionGen = _sessionGeneration;

    final rtcConfig = _lib.rtcConfigurationNew();
    _lib.rtcConfigurationSetSdpSemantics(
      rtcConfig,
      _consts.sdpSemanticsUnifiedPlan,
    );
    _lib.rtcConfigurationSetEnableGcmCryptoSuites(rtcConfig, 1);

    // ICE Transport Policy
    final iceTransportPolicy = offerConfig?['iceTransportPolicy'] as String?;
    if (iceTransportPolicy == 'relay') {
      _lib.rtcConfigurationSetType(rtcConfig, _consts.iceTransportsTypeRelay);
      _emitDebug('native: ice_transport_policy=relay');
    }

    // ICE サーバー
    final iceServers = offerConfig?['iceServers'] as List<Object?>?;
    if (iceServers != null && iceServers.isNotEmpty) {
      final servers = _lib.rtcConfigurationGetServers(rtcConfig);
      for (final serverObj in iceServers) {
        if (serverObj is! Map) continue;
        final serverMap = Map<String, Object?>.from(
          serverObj.map((k, v) => MapEntry('$k', v)),
        );
        final server = _lib.iceServerNew();
        // URL
        final urlVector = _lib.iceServerGetUrls(server);
        final urls = serverMap['urls'];
        if (urls is List) {
          for (final u in urls) {
            if (u is String) {
              final urlStr = u.toNativeUtf8().cast<Char>();
              final stdStr = _lib.stdStringNewFromCstr(urlStr);
              _lib.stdStringVectorPushBack(
                urlVector,
                _lib.stdStringUniqueGet(stdStr),
              );
              _lib.stdStringUniqueDelete(stdStr);
              calloc.free(urlStr);
            }
          }
        } else if (urls is String) {
          final urlStr = urls.toNativeUtf8().cast<Char>();
          final stdStr = _lib.stdStringNewFromCstr(urlStr);
          _lib.stdStringVectorPushBack(
            urlVector,
            _lib.stdStringUniqueGet(stdStr),
          );
          _lib.stdStringUniqueDelete(stdStr);
          calloc.free(urlStr);
        }
        // ユーザー名
        final username = serverMap['username'] as String?;
        if (username != null) {
          final usernameNative = username.toNativeUtf8();
          _lib.iceServerSetUsername(
            server,
            usernameNative.cast<Char>(),
            usernameNative.length,
          );
          calloc.free(usernameNative);
        }
        // パスワード
        final credential = serverMap['credential'] as String?;
        if (credential != null) {
          final credNative = credential.toNativeUtf8();
          _lib.iceServerSetPassword(
            server,
            credNative.cast<Char>(),
            credNative.length,
          );
          calloc.free(credNative);
        }
        _lib.iceServerVectorPushBack(servers, server);
        _lib.iceServerDelete(server);
      }
    }

    // C コールバックブリッジ経由で PeerConnectionObserver を作成する
    // NativeCallable.listener には FFI 互換のプリミティブ型（整数・raw pointer）のみ
    // 渡されるため、Dart GC の干渉を受けず安全
    final ncConnectionChange =
        NativeCallable<Void Function(Int32, Pointer<Void>)>.listener(
          (int state, Pointer<Void> _) =>
              _onConnectionChange(state, sessionGeneration: sessionGen),
        );
    final ncIceConnectionChange =
        NativeCallable<Void Function(Int32, Pointer<Void>)>.listener(
          (int state, Pointer<Void> _) =>
              _onStandardizedIceConnectionChange(state),
        );
    final ncIceGatheringChange =
        NativeCallable<Void Function(Int32, Pointer<Void>)>.listener(
          (int state, Pointer<Void> _) => _onIceGatheringChange(state),
        );
    final ncIceCandidate =
        NativeCallable<
          Void Function(Pointer<Char>, Pointer<Char>, Int32, Pointer<Void>)
        >.listener((
          Pointer<Char> sdp,
          Pointer<Char> mid,
          int mlineIndex,
          Pointer<Void> _,
        ) {
          _onIceCandidateExtracted(sdp, mid, mlineIndex);
        });
    final ncOnTrack =
        NativeCallable<
          Void Function(
            Pointer<Void>,
            Pointer<Char>,
            Pointer<Char>,
            Pointer<Void>,
          )
        >.listener((
          Pointer<Void> trackPtr,
          Pointer<Char> kindPtr,
          Pointer<Char> trackIdPtr,
          Pointer<Void> _,
        ) {
          final kind = kindPtr == nullptr
              ? ''
              : kindPtr.cast<Utf8>().toDartString();
          final trackId = trackIdPtr == nullptr
              ? null
              : trackIdPtr.cast<Utf8>().toDartString();
          if (kindPtr != nullptr) {
            malloc.free(kindPtr);
          }
          if (trackIdPtr != nullptr) {
            malloc.free(trackIdPtr);
          }
          _onEvent('remote_track_added', {
            'kind': kind,
            if (trackPtr != nullptr) 'trackAddress': trackPtr.address,
            if (trackId != null && trackId.isNotEmpty) 'trackId': trackId,
          });
          if (kind == 'video') {
            // C 側で AddRef 済みのビデオトラックポインタを受け取る
            if (trackPtr != nullptr) {
              _onEvent('remote_video_track_added', {
                'trackAddress': trackPtr.address,
                if (trackId != null && trackId.isNotEmpty) 'trackId': trackId,
              });
            }
          }
        });
    final ncOnRemoveTrack =
        NativeCallable<
          Void Function(
            Pointer<Void>,
            Pointer<Char>,
            Pointer<Char>,
            Pointer<Void>,
          )
        >.listener((
          Pointer<Void> trackPtr,
          Pointer<Char> kindPtr,
          Pointer<Char> trackIdPtr,
          Pointer<Void> _,
        ) {
          final kind = kindPtr == nullptr
              ? ''
              : kindPtr.cast<Utf8>().toDartString();
          final trackId = trackIdPtr == nullptr
              ? null
              : trackIdPtr.cast<Utf8>().toDartString();
          if (kindPtr != nullptr) {
            malloc.free(kindPtr);
          }
          if (trackIdPtr != nullptr) {
            malloc.free(trackIdPtr);
          }
          _onEvent('remote_track_removed', {
            'kind': kind,
            if (trackPtr != nullptr) 'trackAddress': trackPtr.address,
            if (trackId != null && trackId.isNotEmpty) 'trackId': trackId,
          });
          if (kind == 'video') {
            if (trackPtr != nullptr) {
              _onEvent('remote_video_track_removed', {
                'trackAddress': trackPtr.address,
                if (trackId != null && trackId.isNotEmpty) 'trackId': trackId,
              });
            }
          }
        });
    final ncOnDataChannel =
        NativeCallable<
          Void Function(Pointer<Void>, Pointer<Char>, Pointer<Void>)
        >.listener((
          Pointer<Void> dcPtr,
          Pointer<Char> labelPtr,
          Pointer<Void> _,
        ) {
          final label = labelPtr == nullptr
              ? ''
              : labelPtr.cast<Utf8>().toDartString();
          if (labelPtr != nullptr) malloc.free(labelPtr);
          _onDataChannelFromBridge(dcPtr, label);
        });
    final ncOnDebug =
        NativeCallable<Void Function(Pointer<Char>, Pointer<Void>)>.listener((
          Pointer<Char> msg,
          Pointer<Void> _,
        ) {
          _onDebugFromBridge(msg);
        });

    _nativeCallables.addAll([
      ncConnectionChange,
      ncIceConnectionChange,
      ncIceGatheringChange,
      ncIceCandidate,
      ncOnTrack,
      ncOnRemoveTrack,
      ncOnDataChannel,
      ncOnDebug,
    ]);

    _observerBridge = _lib.soraObserverBridgeCreate(
      ncConnectionChange.nativeFunction,
      ncIceConnectionChange.nativeFunction,
      ncIceGatheringChange.nativeFunction,
      ncIceCandidate.nativeFunction,
      ncOnTrack.nativeFunction,
      ncOnRemoveTrack.nativeFunction,
      ncOnDataChannel.nativeFunction,
      ncOnDebug.nativeFunction,
      nullptr,
    );
    if (_observerBridge == null) {
      _cleanupNativeCallablesFromRegistries([
        ncConnectionChange,
        ncIceConnectionChange,
        ncIceGatheringChange,
        ncIceCandidate,
        ncOnTrack,
        ncOnRemoveTrack,
        ncOnDataChannel,
        ncOnDebug,
      ]);
      _nativeCallables.clear();
      _lib.rtcConfigurationDelete(rtcConfig);
      _emitState(
        'error',
        SoraErrorCode.observerBridgeCreationFailed,
        'Failed to create observer bridge.',
        sessionGeneration: _sessionGeneration,
      );
      return false;
    }
    final pcObserver = _lib.soraObserverBridgeGetObserver(_observerBridge!);
    if (pcObserver == nullptr) {
      _lib.soraObserverBridgeDestroy(_observerBridge!);
      _observerBridge = null;
      _cleanupNativeCallablesFromRegistries([
        ncConnectionChange,
        ncIceConnectionChange,
        ncIceGatheringChange,
        ncIceCandidate,
        ncOnTrack,
        ncOnRemoveTrack,
        ncOnDataChannel,
        ncOnDebug,
      ]);
      _nativeCallables.clear();
      _lib.rtcConfigurationDelete(rtcConfig);
      _emitState(
        'error',
        SoraErrorCode.observerBridgeObserverCreationFailed,
        'Failed to create peer connection observer.',
        sessionGeneration: _sessionGeneration,
      );
      return false;
    }

    final pcDeps = _lib.pcDependenciesNew(pcObserver);
    final pcRefPtr = calloc<Pointer<WebrtcPeerConnectionInterfaceRefcounted>>();
    final errorPtr = calloc<Pointer<WebrtcRTCErrorUnique>>();

    _lib.pcFactoryCreatePeerConnectionOrError(
      _lib.pcFactoryRefcountedGet(_factoryRef!),
      rtcConfig,
      pcDeps,
      pcRefPtr,
      errorPtr,
    );

    _pcRef = pcRefPtr.value == nullptr ? null : pcRefPtr.value;
    final errMsg = rtcErrorMessage(_lib, errorPtr.value);
    if (errMsg != null) {
      _emitState(
        'error',
        'create_peer_connection_failed',
        errMsg,
        sessionGeneration: _sessionGeneration,
      );
    }
    if (errMsg != null || _pcRef == null) {
      if (errMsg == null) {
        _emitState(
          'error',
          'create_peer_connection_failed',
          'PeerConnection creation returned null.',
          sessionGeneration: _sessionGeneration,
        );
      }
      if (_pcRef != null) {
        _lib.pcRelease(_lib.pcRefcountedGet(_pcRef!));
        _pcRef = null;
      }
      if (_observerBridge != null) {
        _lib.soraObserverBridgeDestroy(_observerBridge!);
        _observerBridge = null;
      }
      _cleanupNativeCallablesFromRegistries(
        List<NativeCallable<dynamic>>.from(_nativeCallables),
      );
    }

    calloc.free(pcRefPtr);
    calloc.free(errorPtr);
    _lib.pcDependenciesDelete(pcDeps);
    _lib.rtcConfigurationDelete(rtcConfig);
    return errMsg == null && _pcRef != null;
  }

  // ---------------------------------------------------------------------------
  // ローカルトラック追加
  // ---------------------------------------------------------------------------

  // connect 時に預かったローカルトラックを role / publish 設定に応じて追加する。
  void _addLocalTracks() {
    final role = _config['role'] as String?;
    final isSend = role == 'sendonly' || role == 'sendrecv';
    if (!isSend) return;

    // connect(stream) で渡された track だけを sender に追加する。
    if (_config['audio'] != false && _pendingLocalAudioTrackRef != null) {
      _addExistingLocalAudioTrack(_pendingLocalAudioTrackRef!);
    }
    if (_config['video'] != false && _pendingLocalVideoTrackRef != null) {
      _addExistingLocalVideoTrack(_pendingLocalVideoTrackRef!);
    }
  }

  // connect 時に受け取った audio track を `pcAddTrack` で sender へ紐付ける。
  //
  // `pcAddTrack` 成功時は sender を AddRef して保持し、後続の track 差し替えや
  // remove 操作で再利用する。
  void _addExistingLocalAudioTrack(
    Pointer<WebrtcAudioTrackInterfaceRefcounted> audioTrackRef,
  ) {
    if (_pcRef == null) return;

    final trackRef = _lib.audioTrackCastToMediaStreamTrack(audioTrackRef);
    final streamIds = _createStreamIdVector();
    final senderRefPtr = calloc<Pointer<WebrtcRtpSenderInterfaceRefcounted>>();
    final errorPtr = calloc<Pointer<WebrtcRTCErrorUnique>>();

    _lib.pcAddTrack(
      _lib.pcRefcountedGet(_pcRef!),
      trackRef,
      streamIds,
      senderRefPtr,
      errorPtr,
    );

    final errMsg = rtcErrorMessage(_lib, errorPtr.value);
    if (errMsg != null) {
      _emitState(
        'error',
        'add_audio_track_failed',
        'Failed to add audio track: $errMsg',
        sessionGeneration: _sessionGeneration,
      );
    } else {
      _emitDebug('native: local_audio_track_added');
    }

    if (senderRefPtr.value != nullptr) {
      final sender = _lib.rtpSenderRefcountedGet(senderRefPtr.value);
      _lib.rtpSenderAddRef(sender);
      _audioRtpSender = sender;
      _lib.rtpSenderRelease(_lib.rtpSenderRefcountedGet(senderRefPtr.value));
    } else if (errMsg == null) {
      _emitState(
        'error',
        'add_audio_track_failed',
        'Failed to get audio sender after pcAddTrack.',
        sessionGeneration: _sessionGeneration,
      );
    }
    calloc.free(senderRefPtr);
    calloc.free(errorPtr);
    _lib.stdStringVectorDelete(streamIds);
    _lib.mediaStreamTrackRelease(_lib.mediaStreamTrackRefcountedGet(trackRef));
    _lib.audioTrackRelease(_lib.audioTrackRefcountedGet(audioTrackRef));
    if (_pendingLocalAudioTrackRef == audioTrackRef) {
      _pendingLocalAudioTrackRef = null;
    }
  }

  // connect 時に受け取った video track を sender に追加する。
  //
  // 映像 sender は simulcast parameter 更新で再利用するため、
  // 成功時に `_videoRtpSender` へ保持する。
  void _addExistingLocalVideoTrack(
    Pointer<WebrtcVideoTrackInterfaceRefcounted> videoTrackRef,
  ) {
    if (_pcRef == null) {
      return;
    }

    final trackRef = _lib.videoTrackCastToMediaStreamTrack(videoTrackRef);
    final streamIds = _createStreamIdVector();
    final senderRefPtr = calloc<Pointer<WebrtcRtpSenderInterfaceRefcounted>>();
    final errorPtr = calloc<Pointer<WebrtcRTCErrorUnique>>();

    _lib.pcAddTrack(
      _lib.pcRefcountedGet(_pcRef!),
      trackRef,
      streamIds,
      senderRefPtr,
      errorPtr,
    );

    final errMsg = rtcErrorMessage(_lib, errorPtr.value);
    if (errMsg != null) {
      _emitState(
        'error',
        'add_video_track_failed',
        'Failed to add video track: $errMsg',
        sessionGeneration: _sessionGeneration,
      );
    } else {
      _emitDebug('native: local_video_track_added');
    }

    if (senderRefPtr.value != nullptr) {
      // simulcast encodings 設定用に RtpSender を保持する
      final sender = _lib.rtpSenderRefcountedGet(senderRefPtr.value);
      _lib.rtpSenderAddRef(sender);
      _videoRtpSender = sender;
      _lib.rtpSenderRelease(_lib.rtpSenderRefcountedGet(senderRefPtr.value));
    } else if (errMsg == null) {
      _emitState(
        'error',
        'add_video_track_failed',
        'Failed to get video sender after pcAddTrack.',
        sessionGeneration: _sessionGeneration,
      );
    }
    calloc.free(senderRefPtr);
    calloc.free(errorPtr);
    _lib.stdStringVectorDelete(streamIds);
    _lib.mediaStreamTrackRelease(_lib.mediaStreamTrackRefcountedGet(trackRef));
    _lib.videoTrackRelease(_lib.videoTrackRefcountedGet(videoTrackRef));
    if (_pendingLocalVideoTrackRef == videoTrackRef) {
      _pendingLocalVideoTrackRef = null;
    }
  }

  // `pcAddTrack` 用の stream id vector を構築する。
  //
  // libwebrtc-c 側は `std::string` vector を要求するため、Dart 文字列を
  // 一時的に `std_string_unique` 化して push したあと即座に delete する。
  Pointer<StdStringVector> _createStreamIdVector() {
    final streamIds = _lib.stdStringVectorNew(0);
    final streamId = _pendingLocalStreamId;
    if (streamId == null || streamId.isEmpty) {
      return streamIds;
    }

    final streamIdNative = streamId.toNativeUtf8().cast<Char>();
    final stdString = _lib.stdStringNewFromCstr(streamIdNative);
    _lib.stdStringVectorPushBack(streamIds, _lib.stdStringUniqueGet(stdString));
    _lib.stdStringUniqueDelete(stdString);
    calloc.free(streamIdNative);
    return streamIds;
  }

  // offer の encodings を RtpSender に適用する (simulcast 用)
  //
  // JS SDK と同じく setRemoteDescription の前後で 2 回呼ぶ。
  // active フラグは setRemoteDescription 後でないと反映されないため。
  // 引数で encodings を受け取り、_pendingEncodings への上書き競合を避ける。
  void _applySimulcastEncodings(List<Map<String, Object?>>? encodings) {
    if (encodings == null || encodings.isEmpty) return;
    if (_videoRtpSender == null) return;

    final params = _lib.rtpSenderGetParameters(_videoRtpSender!);
    if (params == nullptr) return;

    final existingEncodings = _lib.rtpParametersGetEncodings(params);
    final existingSize = _lib.rtpEncodingParametersVectorSize(
      existingEncodings,
    );

    // 既存の encodings 数と offer の encodings 数が一致する場合のみ更新する
    // (WebRTC の制約上、encodings の数は変更できない)
    if (existingSize == encodings.length) {
      for (var i = 0; i < encodings.length; i++) {
        final enc = encodings[i];
        final nativeEnc = _lib.rtpEncodingParametersVectorGet(
          existingEncodings,
          i,
        );

        // rid
        final rid = enc['rid'] as String?;
        if (rid != null) {
          final ridNative = rid.toNativeUtf8();
          _lib.rtpEncodingParametersSetRid(
            nativeEnc,
            ridNative.cast<Char>(),
            ridNative.length,
          );
          calloc.free(ridNative);
        }

        // active
        if (enc.containsKey('active')) {
          final active = enc['active'] == true ? 1 : 0;
          _lib.rtpEncodingParametersSetActive(nativeEnc, active);
        }

        // C API の Int32 制約に合わせて maxBitrate をクランプする。
        // 負の値は無効としてスキップ、上限超過は 0x7FFFFFFF (約 2.1 Gbps) に制限する。
        final maxBitrate = enc['maxBitrate'] as num?;
        if (maxBitrate != null) {
          final intValue = maxBitrate.toInt();
          if (intValue >= 0) {
            final value = intValue > 0x7FFFFFFF ? 0x7FFFFFFF : intValue;
            final valuePtr = calloc<Int32>();
            valuePtr.value = value;
            _lib.rtpEncodingParametersSetMaxBitrateBps(nativeEnc, 1, valuePtr);
            calloc.free(valuePtr);
          }
        }

        // minBitrate も同様に Int32 範囲を制限する。
        final minBitrate = enc['minBitrate'] as num?;
        if (minBitrate != null) {
          final intValue = minBitrate.toInt();
          if (intValue >= 0) {
            final value = intValue > 0x7FFFFFFF ? 0x7FFFFFFF : intValue;
            final valuePtr = calloc<Int32>();
            valuePtr.value = value;
            _lib.rtpEncodingParametersSetMinBitrateBps(nativeEnc, 1, valuePtr);
            calloc.free(valuePtr);
          }
        }

        // scaleResolutionDownBy
        final scaleDown = enc['scaleResolutionDownBy'] as num?;
        if (scaleDown != null) {
          final valuePtr = calloc<Double>();
          valuePtr.value = scaleDown.toDouble();
          _lib.rtpEncodingParametersSetScaleResolutionDownBy(
            nativeEnc,
            1,
            valuePtr,
          );
          calloc.free(valuePtr);
        }

        // maxFramerate
        final maxFramerate = enc['maxFramerate'] as num?;
        if (maxFramerate != null) {
          final valuePtr = calloc<Double>();
          valuePtr.value = maxFramerate.toDouble();
          _lib.rtpEncodingParametersSetMaxFramerate(nativeEnc, 1, valuePtr);
          calloc.free(valuePtr);
        }

        // scalabilityMode
        final scalabilityMode = enc['scalabilityMode'] as String?;
        if (scalabilityMode != null) {
          final modeUtf8 = scalabilityMode.toNativeUtf8();
          _lib.rtpEncodingParametersSetScalabilityMode(
            nativeEnc,
            1,
            modeUtf8.cast<Char>(),
            modeUtf8.length,
          );
          calloc.free(modeUtf8);
        }
      }
    } else {
      _emitDebug(
        'native: simulcast encodings count mismatch: existing=$existingSize offer=${encodings.length}',
      );
    }

    final errorUnique = _lib.rtpSenderSetParameters(_videoRtpSender!, params);
    if (errorUnique != nullptr) {
      final error = _lib.rtcErrorUniqueGet(errorUnique);
      if (_lib.rtcErrorOk(error) == 0) {
        final msgPtr = calloc<Pointer<Char>>();
        final lenPtr = calloc<Size>();
        _lib.rtcErrorMessage(error, msgPtr, lenPtr);
        final msg = lenPtr.value > 0
            ? msgPtr.value.cast<Utf8>().toDartString(length: lenPtr.value)
            : 'unknown';
        _emitDebug('native: set_sender_parameters_failed: $msg');
        calloc.free(msgPtr);
        calloc.free(lenPtr);
      }
      _lib.rtcErrorUniqueDelete(errorUnique);
    } else {
      _emitDebug('native: simulcast encodings applied');
    }
    _lib.rtpParametersDelete(params);
  }

  // ---------------------------------------------------------------------------
  // PeerConnection Observer コールバック
  // ---------------------------------------------------------------------------

  /// `PeerConnectionState` 変更を debug / state イベントへ変換する。
  ///
  /// [sessionGeneration] は `_ensurePeerConnection()` でキャプチャされた世代。
  /// 旧セッション由来の遅延イベントが新 `_sessionGeneration` でタグ付けされるのを防ぐ。
  void _onConnectionChange(int newState, {int? sessionGeneration}) {
    final stateName = _pcStateName(newState);
    _emitDebug('native: pc_state=$stateName');

    if (newState == _consts.pcStateConnected) {
      _emitState('connected', null, null, sessionGeneration: sessionGeneration);
    } else if (newState == _consts.pcStateFailed) {
      _emitState(
        'error',
        'peer_connection_failed',
        null,
        sessionGeneration: sessionGeneration,
      );
    } else if (newState == _consts.pcStateClosed) {
      _emitState(
        'disconnected',
        'peer_connection_closed',
        null,
        sessionGeneration: sessionGeneration,
      );
    }
  }

  // ICE connection state を debug ログ向け文字列に変換して流す。
  void _onStandardizedIceConnectionChange(int newState) {
    _emitDebug(
      'native: ice_connection_state=${_iceConnectionStateName(newState)}',
    );
  }

  // ICE gathering state を debug ログ向け文字列に変換して流す。
  void _onIceGatheringChange(int newState) {
    _emitDebug(
      'native: ice_gathering_state=${_iceGatheringStateName(newState)}',
    );
  }

  // C コールバックブリッジから malloc 済み文字列で ICE candidate を受け取る
  void _onIceCandidateExtracted(
    Pointer<Char> sdpPtr,
    Pointer<Char> midPtr,
    int mlineIndex,
  ) {
    final sdp = sdpPtr == nullptr ? '' : sdpPtr.cast<Utf8>().toDartString();
    final mid = midPtr == nullptr ? '' : midPtr.cast<Utf8>().toDartString();
    // C 側で malloc 確保されたメモリを解放する
    if (sdpPtr != nullptr) malloc.free(sdpPtr);
    if (midPtr != nullptr) malloc.free(midPtr);

    _emitDebug('native: local_candidate mid=$mid text=$sdp');
    _emitSignalingMessage({
      'type': 'candidate',
      'candidate': sdp,
      'sdpMid': mid,
      'sdpMLineIndex': mlineIndex,
    });
  }

  // ---------------------------------------------------------------------------
  // DataChannel
  // ---------------------------------------------------------------------------

  // C bridge から渡された `DataChannel` を label ごとの管理スロットへ振り分ける。
  //
  // 不要 label は即 release し、必要 label だけ observer を登録する。
  void _onDataChannelFromBridge(Pointer<Void> dcPtr, String label) {
    if (dcPtr == nullptr) return;
    final dc = Pointer<WebrtcDataChannelInterface>.fromAddress(dcPtr.address);

    if (label == 'notify') {
      _setupNotifyDataChannel(dc);
    } else if (label == 'push') {
      _setupPushDataChannel(dc);
    } else if (label == 'rpc') {
      _setupRpcDataChannel(dc);
    } else if (label == 'stats') {
      _setupStatsDataChannel(dc);
    } else if (label == 'signaling') {
      _setupSignalingDataChannel(dc);
    } else if (label.startsWith('#')) {
      _setupCustomDataChannel(dc, label);
    } else {
      // 不要な DataChannel は解放する
      _lib.dataChannelRelease(dc);
    }
  }

  // DataChannel の observer 登録を行う。
  //
  // 成功時は DcBridgeContext ポインタを返す。
  // 失敗時は dc を release して消費し、追加済み NativeCallable を閉じる。
  Pointer<Void>? _configureDataChannelObserver(
    Pointer<WebrtcDataChannelInterface> dc,
    String label,
    List<NativeCallable<dynamic>> callables,
  ) {
    if (_observerBridge == null) {
      _releaseDataChannelOnSetupFailure(dc);
      return null;
    }
    final ncStateChange = NativeCallable<Void Function(Pointer<Void>)>.listener(
      (Pointer<Void> _) => _handleDataChannelState(dc, label),
    );
    final ncMessage =
        NativeCallable<
          Void Function(Pointer<Uint8>, Int32, Int32, Pointer<Void>)
        >.listener((
          Pointer<Uint8> dataPtr,
          int len,
          int isBinary,
          Pointer<Void> _,
        ) {
          if (dataPtr == nullptr) {
            _onEvent('data_channel_message', {
              'label': label,
              'isBinary': isBinary != 0,
              'data': Uint8List(0),
            });
            return;
          }
          final bytes = len > 0
              ? Uint8List.fromList(dataPtr.asTypedList(len))
              : Uint8List(0);
          if (len > 0) {
            malloc.free(dataPtr);
          }
          _onEvent('data_channel_message', {
            'label': label,
            'isBinary': isBinary != 0,
            'data': bytes,
          });
        });
    final registeredCallables = <NativeCallable<dynamic>>[
      ncStateChange,
      ncMessage,
    ];
    callables.addAll(registeredCallables);

    final ctx = _lib.soraObserverBridgeSetupDc(
      _observerBridge!,
      dc,
      ncStateChange.nativeFunction,
      ncMessage.nativeFunction,
      nullptr,
    );
    if (ctx == nullptr) {
      _cleanupDataChannelSetupCallables(callables, registeredCallables);
      _releaseDataChannelOnSetupFailure(dc);
      return null;
    }
    return ctx;
  }

  /// 単一 DataChannel の unregister / release / NativeCallable 解放。
  void _cleanupSingleDataChannel(_DataChannelResources res) {
    if (res.dc != null && res.ctx != null) {
      _lib.soraObserverBridgeDestroyDc(res.ctx!, res.dc!);
    } else if (res.dc != null) {
      _lib.dataChannelUnregisterObserver(res.dc!);
    }
    if (res.dc != null) {
      _lib.dataChannelRelease(res.dc!);
    }
    for (final nc in res.callables) {
      nc.close();
    }
    res.callables.clear();
    res.dc = null;
    res.ctx = null;
  }

  /// setup 失敗時に追加済み NativeCallable だけを閉じる。
  void _cleanupDataChannelSetupCallables(
    List<NativeCallable<dynamic>> owner,
    List<NativeCallable<dynamic>> registeredCallables,
  ) {
    for (final nc in registeredCallables) {
      owner.remove(nc);
      nc.close();
    }
  }

  /// 登録済み NativeCallable を閉じ、保持リストから取り除く。
  void _cleanupNativeCallablesFromRegistries(
    List<NativeCallable<dynamic>> callables,
  ) {
    for (final nc in callables) {
      nc.close();
      _nativeCallables.remove(nc);
      _notifyDc.callables.remove(nc);
      _pushDc.callables.remove(nc);
      for (final res in _customDataChannels.values) {
        res.callables.remove(nc);
      }
      _rpcDc.callables.remove(nc);
      _statsDc.callables.remove(nc);
      _signalingDc.callables.remove(nc);
    }
  }

  /// 管理スロットへ DataChannel を登録し、setup 失敗時は空に戻す。
  void _setupManagedDataChannel(
    _DataChannelResources res,
    Pointer<WebrtcDataChannelInterface> dc,
    String label,
  ) {
    _cleanupSingleDataChannel(res);
    res.dc = dc;

    final ctx = _configureDataChannelObserver(dc, label, res.callables);
    if (ctx == null) {
      res.dc = null;
      res.ctx = null;
      return;
    }

    res.ctx = ctx;
    _handleDataChannelState(dc, label);
  }

  /// notify DataChannel を observer 登録込みで初期化する。
  void _setupNotifyDataChannel(Pointer<WebrtcDataChannelInterface> dc) {
    _setupManagedDataChannel(_notifyDc, dc, 'notify');
  }

  /// push DataChannel を observer 登録込みで初期化する。
  void _setupPushDataChannel(Pointer<WebrtcDataChannelInterface> dc) {
    _setupManagedDataChannel(_pushDc, dc, 'push');
  }

  /// rpc DataChannel を observer 登録込みで初期化する。
  void _setupRpcDataChannel(Pointer<WebrtcDataChannelInterface> dc) {
    _setupManagedDataChannel(_rpcDc, dc, 'rpc');
  }

  /// stats DataChannel を observer 登録込みで初期化する。
  void _setupStatsDataChannel(Pointer<WebrtcDataChannelInterface> dc) {
    _setupManagedDataChannel(_statsDc, dc, 'stats');
  }

  // カスタム label の DataChannel を map へ登録し observer を設定する。
  void _setupCustomDataChannel(
    Pointer<WebrtcDataChannelInterface> dc,
    String label,
  ) {
    // 既存エントリがあれば先に解放する (固定 label 系と防御方針を揃える)
    final old = _customDataChannels[label];
    if (old != null) {
      _cleanupSingleDataChannel(old);
    }

    final res = _DataChannelResources();
    res.dc = dc;
    _customDataChannels[label] = res;

    final ctx = _configureDataChannelObserver(dc, label, res.callables);
    if (ctx == null) {
      _customDataChannels.remove(label);
      res.dc = null;
      res.ctx = null;
      return;
    }

    res.ctx = ctx;
    _handleDataChannelState(dc, label);
  }

  void _releaseDataChannelOnSetupFailure(
    Pointer<WebrtcDataChannelInterface> dc,
  ) {
    _lib.dataChannelRelease(dc);
  }

  /// signaling DataChannel を observer 登録込みで初期化する。
  void _setupSignalingDataChannel(Pointer<WebrtcDataChannelInterface> dc) {
    _setupManagedDataChannel(_signalingDc, dc, 'signaling');
  }

  // 現在の DataChannel state を読み、open 到達時だけ Dart 側へ通知する。
  void _handleDataChannelState(
    Pointer<WebrtcDataChannelInterface> dc,
    String label,
  ) {
    final state = _lib.dataChannelState(dc);
    if (state == _consts.dcStateOpen) {
      _onEvent('data_channel_open', {'label': label});
    }
  }

  // signaling DataChannel へバイナリメッセージを送信する。
  //
  // `dataChannelSend` は呼び出し時点のメモリ参照しか持たない前提で、
  // Dart 側で一時バッファを確保して送信後すぐ解放する。
  void sendSignalingMessage(Uint8List data) {
    if (_signalingDc.dc == null) return;
    final ptr = malloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    _lib.dataChannelSend(_signalingDc.dc!, ptr, data.length, 1);
    malloc.free(ptr);
  }

  // rpc DataChannel へバイナリメッセージを送信する。
  void sendRpcMessage(Uint8List data) {
    if (_rpcDc.dc == null) return;
    final ptr = malloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    _lib.dataChannelSend(_rpcDc.dc!, ptr, data.length, 1);
    malloc.free(ptr);
  }

  // stats DataChannel へバイナリメッセージを送信する。
  void sendStatsMessage(Uint8List data) {
    if (_statsDc.dc == null) return;
    final ptr = malloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    _lib.dataChannelSend(_statsDc.dc!, ptr, data.length, 1);
    malloc.free(ptr);
  }

  // 任意 label の DataChannel へバイナリメッセージを送信する。
  void sendCustomDataChannelMessage(String label, Uint8List data) {
    final res = _customDataChannels[label];
    final dc = res?.dc;
    if (dc == null) return;
    final ptr = malloc<Uint8>(data.length);
    ptr.asTypedList(data.length).setAll(0, data);
    _lib.dataChannelSend(dc, ptr, data.length, 1);
    malloc.free(ptr);
  }

  // C bridge から受け取った malloc 済みデバッグ文字列を Dart ログへ流す。
  void _onDebugFromBridge(Pointer<Char> msgPtr) {
    if (msgPtr == nullptr) return;
    final msg = msgPtr.cast<Utf8>().toDartString();
    malloc.free(msgPtr);
    _emitDebug(msg);
  }

  /// notify DataChannel とその observer callback をまとめて解放する。
  void _cleanupNotifyDataChannel() {
    _cleanupSingleDataChannel(_notifyDc);
  }

  /// push DataChannel とその observer callback をまとめて解放する。
  void _cleanupPushDataChannel() {
    _cleanupSingleDataChannel(_pushDc);
  }

  /// rpc DataChannel とその observer callback をまとめて解放する。
  void _cleanupRpcDataChannel() {
    _cleanupSingleDataChannel(_rpcDc);
  }

  /// stats DataChannel とその observer callback をまとめて解放する。
  void _cleanupStatsDataChannel() {
    _cleanupSingleDataChannel(_statsDc);
  }

  /// カスタム DataChannel 群をすべて unregister / release する。
  void _cleanupCustomDataChannels() {
    for (final res in _customDataChannels.values) {
      _cleanupSingleDataChannel(res);
    }
    _customDataChannels.clear();
  }

  // signaling DataChannel とその observer callback をまとめて解放する。
  void _cleanupSignalingDataChannel() {
    _cleanupSingleDataChannel(_signalingDc);
  }

  // ---------------------------------------------------------------------------
  // イベント発行
  // ---------------------------------------------------------------------------

  // state 変更イベントを統一フォーマットで Dart 側へ流す。
  void _emitState(
    String state,
    String? reason,
    String? message, {
    int? sessionGeneration,
  }) {
    final event = <String, Object?>{'state': state};
    if (reason != null) {
      event['reason'] = reason;
    }
    if (message != null) {
      event['message'] = message;
    }
    if (sessionGeneration != null) {
      event['session_generation'] = sessionGeneration;
    }
    _onEvent('state_changed', event);
  }

  // デバッグ用の文字列メッセージを Dart 側へ流す。
  void _emitDebug(String message) {
    _onEvent('debug_message', {'message': message});
  }

  // signaling 相当のメッセージ payload を Dart 側へ流す。
  void _emitSignalingMessage(Map<String, Object?> message) {
    _onEvent('signaling_message', {'message': message});
  }

  // ---------------------------------------------------------------------------
  // 状態名変換ヘルパー
  // ---------------------------------------------------------------------------

  // runtime の `PeerConnectionState` 数値を表示用文字列へ変換する。
  String _pcStateName(int state) {
    if (state == _consts.pcStateNew) return 'new';
    if (state == _consts.pcStateConnecting) return 'connecting';
    if (state == _consts.pcStateConnected) return 'connected';
    if (state == _consts.pcStateFailed) return 'failed';
    if (state == _consts.pcStateClosed) return 'closed';
    return 'unknown';
  }

  // ICE connection state の概算名を debug 表示用に返す。
  static String _iceConnectionStateName(int state) {
    // debug 出力用。値はランタイムだが概算で表示する。
    const names = [
      'new',
      'checking',
      'connected',
      'completed',
      'failed',
      'disconnected',
      'closed',
      'max',
    ];
    if (state >= 0 && state < names.length) return names[state];
    return 'unknown';
  }

  // ICE gathering state の概算名を debug 表示用に返す。
  static String _iceGatheringStateName(int state) {
    const names = ['new', 'gathering', 'complete'];
    if (state >= 0 && state < names.length) return names[state];
    return 'unknown';
  }

  // プラットフォーム既定のビデオエンコーダーファクトリを返す
  //
  // iOS / Android ではプラットフォーム既定ファクトリを優先し、
  // 取得できない場合のみ built-in にフォールバックする。
  static Pointer<WebrtcVideoEncoderFactoryUnique>
  _createDefaultVideoEncoderFactory() {
    // Android は Java の既定 factory を native factory へ変換する。
    if (Platform.isAndroid) {
      return _createAndroidDefaultVideoEncoderFactory();
    }

    // iOS は ObjC の既定 factory を native factory へ変換する。
    if (Platform.isIOS) {
      final objcFactory = sharedLib.objcDefaultVideoEncoderFactoryNew();
      if (objcFactory == nullptr) {
        return sharedLib.createBuiltinVideoEncoderFactory();
      }

      final nativeFactory = sharedLib.objcToNativeVideoEncoderFactory(
        objcFactory,
      );
      sharedLib.objcVideoEncoderFactoryRelease(objcFactory);
      if (nativeFactory == nullptr) {
        return sharedLib.createBuiltinVideoEncoderFactory();
      }
      return nativeFactory;
    }

    // それ以外のプラットフォームは built-in factory を使う。
    return sharedLib.createBuiltinVideoEncoderFactory();
  }

  // プラットフォーム既定のビデオデコーダーファクトリを返す
  //
  // iOS / Android ではプラットフォーム既定ファクトリを優先し、
  // 取得できない場合のみ built-in にフォールバックする。
  static Pointer<WebrtcVideoDecoderFactoryUnique>
  _createDefaultVideoDecoderFactory() {
    // Android は Java の既定 factory を native factory へ変換する。
    if (Platform.isAndroid) {
      return _createAndroidDefaultVideoDecoderFactory();
    }

    // iOS は ObjC の既定 factory を native factory へ変換する。
    if (Platform.isIOS) {
      final objcFactory = sharedLib.objcDefaultVideoDecoderFactoryNew();
      if (objcFactory == nullptr) {
        return sharedLib.createBuiltinVideoDecoderFactory();
      }

      final nativeFactory = sharedLib.objcToNativeVideoDecoderFactory(
        objcFactory,
      );
      sharedLib.objcVideoDecoderFactoryRelease(objcFactory);
      if (nativeFactory == nullptr) {
        return sharedLib.createBuiltinVideoDecoderFactory();
      }
      return nativeFactory;
    }

    // それ以外のプラットフォームは built-in factory を使う。
    return sharedLib.createBuiltinVideoDecoderFactory();
  }

  // Android の既定ビデオエンコーダーファクトリを JNI 経由で作る。
  //
  // Java `DefaultVideoEncoderFactory` を生成して native factory へ変換し、
  // どこかで失敗した場合は built-in factory にフォールバックする。
  static Pointer<WebrtcVideoEncoderFactoryUnique>
  _createAndroidDefaultVideoEncoderFactory() {
    final env = sharedLib.jniAttachCurrentThreadIfNeeded();
    if (env == nullptr) {
      return sharedLib.createBuiltinVideoEncoderFactory();
    }

    final className = 'org/webrtc/DefaultVideoEncoderFactory'
        .toNativeUtf8()
        .cast<Char>();
    final clazz = sharedLib.jniGetClass(env, className);
    calloc.free(className);
    if (clazz == nullptr) {
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoEncoderFactory();
    }

    final ctorName = '<init>'.toNativeUtf8().cast<Char>();
    final ctorSig = '(Lorg/webrtc/EglBase\$Context;ZZ)V'
        .toNativeUtf8()
        .cast<Char>();
    final ctor = sharedLib.jniGetMethodId(env, clazz, ctorName, ctorSig);
    calloc.free(ctorName);
    calloc.free(ctorSig);
    if (ctor == nullptr) {
      sharedLib.jniDeleteLocalRef(env, clazz);
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoEncoderFactory();
    }

    final args = calloc<JValue>(3);
    args[0].l = nullptr;
    args[1].z = 1;
    args[2].z = 0;
    final encoderFactory = sharedLib.jniNewObjectA(env, clazz, ctor, args);
    calloc.free(args);
    if (encoderFactory == nullptr) {
      sharedLib.jniDeleteLocalRef(env, clazz);
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoEncoderFactory();
    }

    final nativeFactory = sharedLib.javaToNativeVideoEncoderFactory(
      env,
      encoderFactory,
    );
    sharedLib.jniDeleteLocalRef(env, encoderFactory);
    sharedLib.jniDeleteLocalRef(env, clazz);
    if (sharedLib.jniExceptionCheck(env) != 0) {
      sharedLib.jniExceptionClear(env);
      return sharedLib.createBuiltinVideoEncoderFactory();
    }
    if (nativeFactory == nullptr) {
      return sharedLib.createBuiltinVideoEncoderFactory();
    }
    return nativeFactory;
  }

  // Android の既定ビデオデコーダーファクトリを JNI 経由で作る。
  //
  // Java `DefaultVideoDecoderFactory` を native 側へ橋渡しし、
  // JNI エラー時はすべて built-in factory にフォールバックする。
  static Pointer<WebrtcVideoDecoderFactoryUnique>
  _createAndroidDefaultVideoDecoderFactory() {
    final env = sharedLib.jniAttachCurrentThreadIfNeeded();
    if (env == nullptr) {
      return sharedLib.createBuiltinVideoDecoderFactory();
    }

    final className = 'org/webrtc/DefaultVideoDecoderFactory'
        .toNativeUtf8()
        .cast<Char>();
    final clazz = sharedLib.jniGetClass(env, className);
    calloc.free(className);
    if (clazz == nullptr) {
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoDecoderFactory();
    }

    final ctorName = '<init>'.toNativeUtf8().cast<Char>();
    final ctorSig = '(Lorg/webrtc/EglBase\$Context;)V'
        .toNativeUtf8()
        .cast<Char>();
    final ctor = sharedLib.jniGetMethodId(env, clazz, ctorName, ctorSig);
    calloc.free(ctorName);
    calloc.free(ctorSig);
    if (ctor == nullptr) {
      sharedLib.jniDeleteLocalRef(env, clazz);
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoDecoderFactory();
    }

    final args = calloc<JValue>(1);
    args[0].l = nullptr;
    final decoderFactory = sharedLib.jniNewObjectA(env, clazz, ctor, args);
    calloc.free(args);
    if (decoderFactory == nullptr) {
      sharedLib.jniDeleteLocalRef(env, clazz);
      if (sharedLib.jniExceptionCheck(env) != 0) {
        sharedLib.jniExceptionClear(env);
      }
      return sharedLib.createBuiltinVideoDecoderFactory();
    }

    final nativeFactory = sharedLib.javaToNativeVideoDecoderFactory(
      env,
      decoderFactory,
    );
    sharedLib.jniDeleteLocalRef(env, decoderFactory);
    sharedLib.jniDeleteLocalRef(env, clazz);
    if (sharedLib.jniExceptionCheck(env) != 0) {
      sharedLib.jniExceptionClear(env);
      return sharedLib.createBuiltinVideoDecoderFactory();
    }
    if (nativeFactory == nullptr) {
      return sharedLib.createBuiltinVideoDecoderFactory();
    }
    return nativeFactory;
  }
}
