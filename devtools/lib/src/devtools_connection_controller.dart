/// DevTools 画面の接続生成と local media 準備を提供するモジュール。
///
/// `SoraConnection` の生成、購読 controller との結合、Android の audio
/// output routing、`MediaDevices` を使った local stream 準備をここに集約する。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_connection_subscription_controller.dart';
import 'devtools_media_devices_support.dart';
import 'devtools_models.dart';
import 'devtools_beep_audio_track.dart';

class DevToolsConnectRequest {
  // 接続生成と local media 準備に必要な入力値をまとめる。
  const DevToolsConnectRequest({
    required this.signalingUrls,
    required this.channelId,
    required this.role,
    required this.configuredAudio,
    required this.configuredVideo,
    required this.beepAudioEnabled,
    required this.selectedVideoCodecType,
    required this.selectedVideoBitRate,
    required this.simulcastEnabled,
    required this.selectedSimulcastRid,
    required this.spotlightEnabled,
    required this.selectedSpotlightFocusRid,
    required this.selectedSpotlightUnfocusRid,
    required this.usesSimulcastRequestRid,
    required this.usesSpotlightRid,
    required this.selectedAudioOutputDeviceId,
    required this.selectedAudioInputDeviceId,
    required this.selectedVideoInputDeviceId,
    required this.selectedResolution,
    required this.selectedFrameRate,
    required this.existingLocalStream,
    required this.dataChannelSignaling,
    required this.ignoreDisconnectWebSocket,
    this.useExternalVideoTrack = false,
    this.dataChannels = const <Map<String, Object?>>[],
  });

  final List<String> signalingUrls;
  final String channelId;
  final SoraRole role;
  final bool configuredAudio;
  final bool configuredVideo;
  final bool beepAudioEnabled;
  final String? selectedVideoCodecType;
  final int? selectedVideoBitRate;
  final bool simulcastEnabled;
  final String? selectedSimulcastRid;
  final bool spotlightEnabled;
  final String? selectedSpotlightFocusRid;
  final String? selectedSpotlightUnfocusRid;
  final bool usesSimulcastRequestRid;
  final bool usesSpotlightRid;
  final String? selectedAudioOutputDeviceId;
  final String? selectedAudioInputDeviceId;
  final String? selectedVideoInputDeviceId;
  final DevToolsVideoInputResolutionOption? selectedResolution;
  final int? selectedFrameRate;
  final LocalMediaStream? existingLocalStream;
  // DataChannel signaling を利用するかどうか。
  final bool dataChannelSignaling;
  // WebSocket 切断通知を無視するかどうか。
  final bool ignoreDisconnectWebSocket;
  final bool useExternalVideoTrack;
  final List<Map<String, Object?>> dataChannels;
}

// DevTools の接続要求を SDK の接続設定へ変換する。
// DataChannel、dataChannels、DataChannel signaling 設定を別々に保持する。
SoraConnectionConfig buildSoraConnectionConfig(DevToolsConnectRequest request) {
  return SoraConnectionConfig(
    signalingUrls: request.signalingUrls,
    channelId: request.channelId,
    role: request.role,
    audio: request.configuredAudio,
    video: request.configuredVideo,
    useAudioDevice: !request.beepAudioEnabled,
    videoCodecType: VideoCodecType.fromValue(request.selectedVideoCodecType),
    videoBitRate: request.selectedVideoBitRate,
    simulcast: request.simulcastEnabled ? true : null,
    simulcastRequestRid: request.usesSimulcastRequestRid
        ? SimulcastRequestRid.fromValue(request.selectedSimulcastRid)
        : null,
    spotlight: request.spotlightEnabled ? true : null,
    spotlightFocusRid: request.usesSpotlightRid
        ? SpotlightRid.fromValue(request.selectedSpotlightFocusRid)
        : null,
    spotlightUnfocusRid: request.usesSpotlightRid
        ? SpotlightRid.fromValue(request.selectedSpotlightUnfocusRid)
        : null,
    timeoutOptions: const SoraTimeoutOptions(
      connectionTimeout: Duration(seconds: 30),
      disconnectWaitTimeout: Duration(seconds: 10),
      signalingCandidateTimeout: Duration(seconds: 5),
    ),
    dataChannels: request.dataChannels,
    dataChannelSignaling: request.dataChannelSignaling,
    ignoreDisconnectWebSocket: request.ignoreDisconnectWebSocket,
  );
}

class DevToolsConnectResult {
  // 接続生成と local media 準備の結果をまとめる。
  const DevToolsConnectResult({
    required this.connection,
    required this.localStream,
  });

  final SoraConnection connection;
  final LocalMediaStream? localStream;
}

class DevToolsPreviewRequest {
  // 接続前 preview 生成に必要な入力値をまとめる。
  const DevToolsPreviewRequest({
    required this.selectedVideoInputDeviceId,
    required this.selectedResolution,
    required this.selectedFrameRate,
  });

  final String? selectedVideoInputDeviceId;
  final DevToolsVideoInputResolutionOption? selectedResolution;
  final int? selectedFrameRate;
}

class DevToolsPreviewResult {
  // 接続前 preview 生成の結果をまとめる。
  const DevToolsPreviewResult({
    required this.previewStream,
    required this.textureId,
  });

  final LocalMediaStream previewStream;
  final int textureId;
}

class DevToolsPermissionRequest {
  // media permission 確認に必要な入力値をまとめる。
  const DevToolsPermissionRequest({
    required this.needsCamera,
    required this.needsMicrophone,
  });

  final bool needsCamera;
  final bool needsMicrophone;
}

class DevToolsSwitchCameraRequest {
  // カメラ切り替えに必要な入力値をまとめる。
  const DevToolsSwitchCameraRequest({
    required this.connection,
    required this.localStream,
    required this.videoInputDevices,
    required this.selectedVideoInputDevice,
    required this.selectedResolution,
    required this.selectedFrameRate,
  });

  final SoraConnection connection;
  final LocalMediaStream localStream;
  final List<VideoInputDevice> videoInputDevices;
  final VideoInputDevice? selectedVideoInputDevice;
  final DevToolsVideoInputResolutionOption? selectedResolution;
  final int? selectedFrameRate;
}

class DevToolsSwitchCameraResult {
  // カメラ切り替え後の選択状態をまとめる。
  const DevToolsSwitchCameraResult({
    required this.selectedVideoInputDevice,
    required this.resolutions,
    required this.selectedResolution,
  });

  final VideoInputDevice selectedVideoInputDevice;
  final List<DevToolsVideoInputResolutionOption> resolutions;
  final DevToolsVideoInputResolutionOption? selectedResolution;
}

class DevToolsRpcRequest {
  // RPC 送信に必要な入力値をまとめる。
  const DevToolsRpcRequest({
    required this.connection,
    required this.method,
    required this.paramsText,
    required this.timeoutText,
    required this.notification,
  });

  final SoraConnection connection;
  final String method;
  final String paramsText;
  final String timeoutText;
  final bool notification;
}

class DevToolsRpcTemplateRequest {
  // RPC テンプレート生成に必要な入力値をまとめる。
  const DevToolsRpcTemplateRequest({
    required this.connectionId,
    required this.channelId,
    required this.selectedSimulcastRid,
    required this.selectedSpotlightFocusRid,
    required this.selectedSpotlightUnfocusRid,
  });

  final String connectionId;
  final String channelId;
  final String? selectedSimulcastRid;
  final String? selectedSpotlightFocusRid;
  final String? selectedSpotlightUnfocusRid;
}

class DevToolsSetTrackEnabledRequest {
  // audio / video の enabled 状態反映に必要な入力値をまとめる。
  const DevToolsSetTrackEnabledRequest({
    required this.connection,
    required this.enabled,
    required this.isAudio,
  });

  final SoraConnection connection;
  final bool enabled;
  final bool isAudio;
}

class DevToolsStatsRequest {
  // 統計情報取得に必要な入力値をまとめる。
  const DevToolsStatsRequest({required this.connection});

  final SoraConnection connection;
}

class DevToolsConnectionController {
  DevToolsConnectionController({
    required DevToolsPageNotifier pageNotifier,
    required MethodChannel sdkMethodChannel,
    required MethodChannel permissionChannel,
    required DevToolsConnectionSubscriptionController subscriptionController,
    required void Function(String line) appendLog,
    required void Function(String line) appendEventLog,
    required Future<void> Function(LocalMediaStream stream) disposeLocalStream,
  }) : _pageNotifier = pageNotifier,
       _sdkMethodChannel = sdkMethodChannel,
       _permissionChannel = permissionChannel,
       _subscriptionController = subscriptionController,
       _appendLog = appendLog,
       _appendEventLog = appendEventLog,
       _disposeLocalStream = disposeLocalStream;

  // 画面状態の RPC 関連フラグと結果表示を更新する。
  final DevToolsPageNotifier _pageNotifier;
  // SDK の MethodChannel 呼び出しを行う。
  final MethodChannel _sdkMethodChannel;
  // 権限確認と iOS 補助に使う MethodChannel。
  final MethodChannel _permissionChannel;
  // `SoraConnection` の購読開始 / 解除を管理する。
  final DevToolsConnectionSubscriptionController _subscriptionController;
  // アプリログ追記 callback。
  final void Function(String line) _appendLog;
  // イベントログ追記 callback。
  final void Function(String line) _appendEventLog;
  // local stream 破棄 callback。
  final Future<void> Function(LocalMediaStream stream) _disposeLocalStream;
  // beep 音声送信時に保持する BeepAudioTrack。
  DevToolsBeepAudioTrack? _beepAudioTrack;

  // beep 音声トラックを取得する。
  // 接続中かつ beep 音声送信が有効な場合に non-null を返す。
  DevToolsBeepAudioTrack? get beepAudioTrack => _beepAudioTrack;

  // 接続生成から local media 準備、購読開始、connect 送信までをまとめて行う。
  Future<DevToolsConnectResult> createAndConnect({
    required DevToolsConnectRequest request,
    required void Function(int textureId) onLocalTextureReady,
  }) async {
    SoraConnection? connection;
    LocalMediaStream? localStream;
    var mediaPreparationStarted = false;
    try {
      connection = await Sora.createConnection(
        buildSoraConnectionConfig(request),
      );
      await _subscriptionController.bind(connection);
      await applySelectedAudioOutputDevice(request.selectedAudioOutputDeviceId);
      mediaPreparationStarted = true;
      localStream = await _prepareLocalStream(
        request: request,
        onLocalTextureReady: onLocalTextureReady,
      );
      await connection.connect(localStream);
      return DevToolsConnectResult(
        connection: connection,
        localStream: localStream,
      );
    } catch (error, stackTrace) {
      // connect() 失敗時に SDK が発行する connection_error / disconnected を
      // 購読側が受け取ってから資源を解放する。
      await Future<void>.delayed(Duration.zero);
      // transaction 内で確保した資源は、呼び出し元へ渡す前に必ず解放する。
      try {
        await disposeConnectionResources(
          connection: connection,
          localStream: mediaPreparationStarted
              ? localStream
              : request.existingLocalStream,
        );
      } catch (cleanupError) {
        _appendLog(
          'connection cleanup: transaction failed error=$cleanupError',
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  // Android で選択中の audio output routing を native 側へ適用する。
  Future<void> applySelectedAudioOutputDevice(String? deviceId) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _sdkMethodChannel.invokeMethod<void>(
        'setAudioOutputDevice',
        <String, Object?>{'deviceId': deviceId},
      );
      _appendLog('audio output routing: applied deviceId=$deviceId');
    } on PlatformException catch (error) {
      _appendLog(
        'audio output routing: failed code=${error.code} message=${error.message}',
      );
    } catch (error) {
      _appendLog('audio output routing: failed error=$error');
    }
  }

  // Android の audio output routing を既定状態へ戻す。
  Future<void> clearAudioOutputRouting() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _sdkMethodChannel.invokeMethod<void>(
        'setAudioOutputDevice',
        <String, Object?>{'deviceId': null},
      );
      _appendLog('audio output routing: cleared');
    } on PlatformException catch (error) {
      _appendLog(
        'audio output routing: clear failed code=${error.code} message=${error.message}',
      );
    } catch (error) {
      _appendLog('audio output routing: clear failed error=$error');
    }
  }

  // 現在の role と publish 設定に必要な media 権限を確認する。
  Future<bool> ensureMediaPermissions(DevToolsPermissionRequest request) async {
    if (!Platform.isIOS && !Platform.isAndroid && !Platform.isMacOS) {
      return true;
    }
    final granted =
        await _permissionChannel.invokeMethod<bool>(
          'ensureMediaPermissions',
          <String, Object?>{
            'camera': request.needsCamera,
            'microphone': request.needsMicrophone,
          },
        ) ??
        false;
    return granted;
  }

  // 権限付与後に platform 依存の audio device 一覧を再同期する。
  Future<InitialAudioDevices?> reloadAudioDevicesAfterPermission({
    required String? selectedAudioInputDeviceId,
    required String? selectedAudioOutputDeviceId,
  }) async {
    if (!Platform.isIOS && !Platform.isAndroid && !Platform.isMacOS) {
      return null;
    }
    if (Platform.isIOS) {
      try {
        await DevToolsMediaDevicesSupport.prepareAudioDeviceEnumeration(
          _permissionChannel,
        );
      } on PlatformException catch (error) {
        _appendLog(
          'audio device enumeration prepare: failed code=${error.code} message=${error.message}',
        );
      }
    }
    return DevToolsMediaDevicesSupport.loadAudioDevices(
      isAndroid: Platform.isAndroid,
      selectedAudioInputDeviceId: selectedAudioInputDeviceId,
      selectedAudioOutputDeviceId: selectedAudioOutputDeviceId,
    );
  }

  // 接続前でも確認できる local video preview を生成する。
  Future<DevToolsPreviewResult> createLocalPreview(
    DevToolsPreviewRequest request,
  ) async {
    final previewStream = await MediaDevices.getUserMedia(
      GetUserMediaOptions(
        audio: false,
        video: true,
        videoDeviceId: request.selectedVideoInputDeviceId,
        videoWidth: request.selectedResolution?.width,
        videoHeight: request.selectedResolution?.height,
        videoFrameRate: request.selectedFrameRate,
      ),
    );
    final videoTracks = previewStream.getVideoTracks();
    if (videoTracks.isEmpty) {
      await previewStream.dispose();
      throw StateError('createLocalPreview: no video track available');
    }
    final textureId = await videoTracks.first.textureId;
    return DevToolsPreviewResult(
      previewStream: previewStream,
      textureId: textureId,
    );
  }

  // 送信中の video track を別カメラへ差し替える。
  Future<DevToolsSwitchCameraResult> switchCamera(
    DevToolsSwitchCameraRequest request,
  ) async {
    final previousResolution = request.selectedResolution;
    final currentIndex = request.videoInputDevices.indexWhere(
      (device) => device.deviceId == request.selectedVideoInputDevice?.deviceId,
    );
    final nextIndex = currentIndex < 0
        ? 0
        : (currentIndex + 1) % request.videoInputDevices.length;
    final selectedVideoInputDevice = request.videoInputDevices[nextIndex];
    final temporaryStream = await MediaDevices.getUserMedia(
      GetUserMediaOptions(
        audio: false,
        video: true,
        videoDeviceId: selectedVideoInputDevice.deviceId,
        videoWidth: request.selectedResolution?.width,
        videoHeight: request.selectedResolution?.height,
        videoFrameRate: request.selectedFrameRate,
      ),
    );
    try {
      final videoTracks = temporaryStream.getVideoTracks();
      if (videoTracks.isEmpty) {
        throw StateError('switchCamera: no video track available');
      }
      final newVideoTrack = videoTracks.first;
      final previousVideoTrack = request.localStream.getVideoTracks().isEmpty
          ? null
          : request.localStream.getVideoTracks().first;
      try {
        await request.connection.replaceVideoTrack(
          request.localStream,
          newVideoTrack,
        );
        _appendLog(
          'switchCamera: success deviceId=${selectedVideoInputDevice.deviceId}',
        );
      } catch (error) {
        _appendLog(
          'switchCamera: failed deviceId=${selectedVideoInputDevice.deviceId} error=$error',
        );
        rethrow;
      }
      if (previousVideoTrack != null) {
        await previousVideoTrack.dispose();
      }
      final formats = await selectedVideoInputDevice.supportedFormats();
      final resolutions =
          DevToolsMediaDevicesSupport.extractVideoInputResolutions(formats);
      return DevToolsSwitchCameraResult(
        selectedVideoInputDevice: selectedVideoInputDevice,
        resolutions: resolutions,
        selectedResolution: DevToolsMediaDevicesSupport.findClosestResolution(
          resolutions,
          previousResolution,
        ),
      );
    } finally {
      await temporaryStream.dispose();
    }
  }

  // RPC 入力を検証し、接続中の peer へ送信する。
  Future<String?> sendRpc(DevToolsRpcRequest request) async {
    final timeoutText = request.timeoutText.trim();
    final int? timeout = timeoutText.isEmpty ? null : int.tryParse(timeoutText);
    if (timeoutText.isNotEmpty && timeout == null) {
      _appendLog('rpc: invalid timeout value');
      return 'Timeout must be an integer';
    }

    Object? params;
    final paramsText = request.paramsText.trim();
    if (paramsText.isNotEmpty) {
      try {
        params = jsonDecode(paramsText);
      } catch (error) {
        _appendLog('rpc: invalid params json error=$error');
        return 'Params must be valid JSON';
      }
    }

    _pageNotifier.startRpc();
    try {
      _appendLog(
        'rpc: send method=${request.method} notification=${request.notification ? 'true' : 'false'} timeout=${timeout?.toString() ?? 'none'}',
      );
      final result = await request.connection.rpc(
        request.method,
        params: params,
        options: SoraRpcOptions(
          timeout: timeout,
          notification: request.notification,
        ),
      );
      final resultText = request.notification
          ? 'Notification sent'
          : const JsonEncoder.withIndent('  ').convert(result);
      _appendLog('rpc: success method=${request.method}');
      _pageNotifier.finishRpc(resultText);
      return null;
    } catch (error) {
      _appendLog('rpc: error method=${request.method} error=$error');
      _pageNotifier.finishRpc('Error: $error');
      return null;
    }
  }

  // audio / video の enabled 状態を connection へ反映する。
  bool setTrackEnabled(DevToolsSetTrackEnabledRequest request) {
    if (request.isAudio) {
      request.connection.setAudioEnabled(request.enabled);
      return request.connection.isAudioEnabled;
    }
    request.connection.setVideoEnabled(request.enabled);
    return request.connection.isVideoEnabled;
  }

  // 接続中 peer を切断し、音声出力 routing を既定状態へ戻す。
  Future<void> disconnect(SoraConnection connection) async {
    try {
      await connection.disconnect();
    } finally {
      await clearAudioOutputRouting();
    }
  }

  // 接続、購読、local stream、beep、audio routing を順序付きで解放する。
  // 接続・画面破棄・接続 transaction 失敗のすべてで同じ cleanup 経路を利用する。
  Future<void> disposeConnectionResources({
    required SoraConnection? connection,
    required LocalMediaStream? localStream,
  }) async {
    try {
      await _subscriptionController.unbind(connection: connection);
    } catch (error) {
      _appendLog('connection cleanup: unbind failed error=$error');
    }
    try {
      if (connection != null) {
        await connection.dispose();
      }
    } catch (error) {
      _appendLog('connection cleanup: dispose failed error=$error');
    } finally {
      try {
        await disposeLocalStream(localStream);
      } catch (error) {
        _appendLog(
          'connection cleanup: local stream dispose failed error=$error',
        );
      } finally {
        await clearAudioOutputRouting();
      }
    }
  }

  // 接続中 peer から統計情報を取得して整形する。
  Future<String?> fetchStats(DevToolsStatsRequest request) async {
    final stats = await request.connection.getStats();
    if (stats == null || stats.isEmpty) {
      return null;
    }
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(stats));
  }

  // RPC method に応じた params のテンプレート JSON を生成する。
  String buildRpcParamsTemplateJson(
    String method,
    DevToolsRpcTemplateRequest request,
  ) {
    final template = _buildRpcParamsTemplate(method, request);
    return const JsonEncoder.withIndent('  ').convert(template);
  }

  // RPC method に応じた params のテンプレートを生成する。
  Map<String, Object?> _buildRpcParamsTemplate(
    String method,
    DevToolsRpcTemplateRequest request,
  ) {
    if (method.endsWith('RequestSimulcastRid')) {
      return <String, Object?>{
        'channel_id': request.channelId,
        'receiver_connection_id': request.connectionId,
        'sender_connection_id': '',
        'rid': request.selectedSimulcastRid ?? 'r1',
      };
    }
    if (method.endsWith('RequestSpotlightRid')) {
      return <String, Object?>{
        'channel_id': request.channelId,
        'recv_connection_id': request.connectionId,
        'send_connection_id': '',
        'spotlight_focus_rid': request.selectedSpotlightFocusRid ?? 'r1',
        'spotlight_unfocus_rid': request.selectedSpotlightUnfocusRid ?? 'r0',
      };
    }
    if (method.endsWith('PutSignalingNotifyMetadata')) {
      return <String, Object?>{
        'channel_id': request.channelId,
        'connection_id': request.connectionId,
        'metadata': <String, Object?>{'devtools': 'value'},
      };
    }
    if (method.endsWith('PutSignalingNotifyMetadataItem')) {
      return <String, Object?>{
        'channel_id': request.channelId,
        'connection_id': request.connectionId,
        'key': 'devtools',
        'value': 'value',
      };
    }
    return <String, Object?>{};
  }

  // offer から RPC method 一覧を同期し、選択中 method のテンプレートを返す。
  String? syncRpcMethodsFromOffer(
    Map<String, Object?>? offer,
    DevToolsRpcTemplateRequest request,
  ) {
    final rpcMethodsRaw = offer?['rpc_methods'];
    final methods = rpcMethodsRaw is List
        ? rpcMethodsRaw.whereType<String>().toList(growable: false)
        : <String>[];
    final selected = _pageNotifier.syncRpcMethods(methods);
    if (selected == null) {
      return null;
    }
    return buildRpcParamsTemplateJson(selected, request);
  }

  // connect 前に local media を必要に応じて生成 / 再利用する。
  Future<LocalMediaStream?> _prepareLocalStream({
    required DevToolsConnectRequest request,
    required void Function(int textureId) onLocalTextureReady,
  }) async {
    if (request.role != SoraRole.sendonly &&
        request.role != SoraRole.sendrecv) {
      await disposeLocalStream(request.existingLocalStream);
      return null;
    }
    if (!request.configuredAudio && !request.configuredVideo) {
      await disposeLocalStream(request.existingLocalStream);
      return null;
    }

    LocalMediaStream? localStream = request.existingLocalStream;
    try {
      // 再利用する stream に残った beep track は、先に stream から外して破棄する。
      await disposeBeepAudioTrack(localStream: localStream);
      if (localStream == null) {
        if (request.useExternalVideoTrack) {
          localStream = MediaDevices.createMediaStream();
          localStream.addTrack(MediaDevices.createExternalVideoTrack());
          if (request.configuredAudio) {
            if (request.beepAudioEnabled) {
              final audioTrack = await MediaDevices.createAudioTrack();
              _beepAudioTrack = DevToolsBeepAudioTrack.fromTrack(audioTrack);
              _beepAudioTrack!.start();
              localStream.addTrack(audioTrack);
            } else {
              localStream.addTrack(
                await MediaDevices.createAudioTrack(
                  audioDeviceId: request.selectedAudioInputDeviceId,
                ),
              );
            }
          }
        } else {
          final audioEnabled =
              request.configuredAudio && !request.beepAudioEnabled;
          localStream = await MediaDevices.getUserMedia(
            GetUserMediaOptions(
              audio: audioEnabled,
              audioDeviceId: request.selectedAudioInputDeviceId,
              video: request.configuredVideo,
              videoDeviceId: request.selectedVideoInputDeviceId,
              videoWidth: request.selectedResolution?.width,
              videoHeight: request.selectedResolution?.height,
              videoFrameRate: request.selectedFrameRate,
            ),
          );
          // beep 音声が有効な場合は getUserMedia の後で DevToolsBeepAudioTrack を追加する。
          if (request.configuredAudio && request.beepAudioEnabled) {
            final audioTrack = await MediaDevices.createAudioTrack();
            _beepAudioTrack = DevToolsBeepAudioTrack.fromTrack(audioTrack);
            _beepAudioTrack!.start();
            localStream.addTrack(audioTrack);
          }
        }
      } else {
        if (request.useExternalVideoTrack) {
          // 再接続時は古い video track を破棄して新しい external track を生成する。
          for (final track in localStream.getVideoTracks()) {
            localStream.removeTrack(track);
            await track.dispose();
          }
          localStream.addTrack(MediaDevices.createExternalVideoTrack());
        }
        if (request.configuredAudio) {
          if (localStream.getAudioTracks().isEmpty) {
            if (request.beepAudioEnabled) {
              final audioTrack = await MediaDevices.createAudioTrack();
              _beepAudioTrack = DevToolsBeepAudioTrack.fromTrack(audioTrack);
              _beepAudioTrack!.start();
              localStream.addTrack(audioTrack);
            } else {
              localStream.addTrack(
                await MediaDevices.createAudioTrack(
                  audioDeviceId: request.selectedAudioInputDeviceId,
                ),
              );
            }
          }
        } else {
          for (final track in localStream.getAudioTracks()) {
            localStream.removeTrack(track);
            await track.dispose();
          }
        }
        if (!request.configuredVideo) {
          for (final track in localStream.getVideoTracks()) {
            localStream.removeTrack(track);
            await track.dispose();
          }
        }
      }

      final videoTracks = localStream.getVideoTracks();
      if (request.configuredVideo &&
          videoTracks.isNotEmpty &&
          !request.useExternalVideoTrack) {
        final textureId = await videoTracks.first.textureId;
        onLocalTextureReady(textureId);
        _appendEventLog('local_video_ready: textureId=$textureId');
      }
      return localStream;
    } catch (_) {
      await disposeLocalStream(localStream);
      rethrow;
    }
  }

  // 指定 local stream を破棄する。
  Future<void> disposeLocalStream(LocalMediaStream? stream) async {
    if (stream == null) {
      return;
    }
    await disposeBeepAudioTrack(localStream: stream);
    await _disposeLocalStream(stream);
  }

  // BeepAudioTrack を stream から外して停止・破棄する。
  Future<void> disposeBeepAudioTrack({LocalMediaStream? localStream}) async {
    final beepAudioTrack = _beepAudioTrack;
    if (beepAudioTrack == null) {
      return;
    }
    _beepAudioTrack = null;
    if (localStream != null) {
      final attachedTracks = localStream.getAudioTracks();
      if (attachedTracks.any(
        (track) => identical(track, beepAudioTrack.audioTrack),
      )) {
        localStream.removeTrack(beepAudioTrack.audioTrack);
      }
    }
    await beepAudioTrack.dispose();
  }
}
