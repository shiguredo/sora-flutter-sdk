import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sora_sdk/sora_sdk.dart';
import 'configs/environment.dart';
import 'src/devtools_connection_controller.dart';
import 'src/devtools_connection_subscription_controller.dart';
import 'src/devtools_constants.dart';
import 'src/devtools_external_camera_manager.dart';
import 'src/devtools_event_handler.dart';
import 'src/devtools_local_preview_policy.dart';
import 'src/devtools_log_panel.dart';
import 'src/devtools_logging_support.dart';
import 'src/devtools_media_devices_support.dart';
import 'src/devtools_message_panel.dart';
import 'src/devtools_models.dart';
import 'src/devtools_settings_sections.dart';
import 'src/devtools_track_state.dart';
import 'src/devtools_video_panel.dart';

/// Sora SDK DevTools アプリのエントリポイント。
///
/// 接続設定、media device 選択、RPC 実行、ログ表示を 1 画面で扱う

/// 開発用 UI を起動する。
void main() {
  runApp(const DevToolsApp());
}

/// DevTools アプリ全体の theme と home 画面を定義する。
class DevToolsApp extends StatelessWidget {
  const DevToolsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sora SDK DevTools',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: const DevToolsPage(),
    );
  }
}

/// DevTools の単一画面を表す root widget。
class DevToolsPage extends StatefulWidget {
  const DevToolsPage({super.key});

  @override
  State<DevToolsPage> createState() => _DevToolsPageState();
}

// DevTools 画面の状態と接続制御を保持する。
//
// UI 部品自体は `src/` 配下へ分割し、この state では接続ライフサイクル、
// media device 選択、ログ蓄積、各 section への値受け渡しを担当する。
class _DevToolsPageState extends State<DevToolsPage>
    with TickerProviderStateMixin {
  // SDK 内部呼び出し用の MethodChannel。
  static const MethodChannel _sdkMethodChannel = MethodChannel(
    'sora_sdk/method',
  );
  // 権限要求用の MethodChannel。
  static const MethodChannel _permissionChannel = MethodChannel(
    'devtools/permissions',
  );
  // signaling URL 入力欄の TextEditingController。
  late final TextEditingController _signalingUrlController;
  // channel ID 入力欄の TextEditingController。
  late final TextEditingController _channelIdController;
  // RPC params 入力欄の TextEditingController。
  late final TextEditingController _rpcParamsController;
  // RPC timeout 入力欄の TextEditingController。
  late final TextEditingController _rpcTimeoutController;
  // ログ検索欄の TextEditingController。
  late final TextEditingController _logSearchController;
  // 画面状態の SSOT (ChangeNotifier)。
  late final DevToolsPageNotifier _pageNotifier;
  // 接続イベント購読の bind / unbind を管理する。
  late final DevToolsConnectionSubscriptionController
  _connectionSubscriptionController;
  // 接続生成・切断・RPC・preview 等の SDK 呼び出しを担当する。
  late final DevToolsConnectionController _connectionController;
  // 接続イベント・debug イベントを画面状態とログへ反映する。
  late final DevToolsEventHandler _eventHandler;

  // 現在の SoraConnection。接続中のみ非 null。
  SoraConnection? _connection;
  // 現在の LocalMediaStream。接続中または preview 表示中のみ非 null。
  LocalMediaStream? _localStream;
  // タブ切り替え用の TabController。
  late final TabController _tabController;

  // external video track モード用の状態
  bool _useExternalVideoTrack = false;
  // external camera のライフサイクル管理。
  late final DevToolsExternalCameraManager _cameraManager;

  // DataChannel messaging 用の設定
  bool _dataChannelEnabled = false;
  // DataChannel label 入力欄の TextEditingController。
  late final TextEditingController _dataChannelLabelController;
  // DataChannel の送受信方向 (sendrecv / sendonly / recvonly)。
  String _dataChannelDirection = 'sendrecv';
  // 順序保証の有無。
  bool _dataChannelOrdered = true;
  // メッセージ圧縮の有無。
  bool _dataChannelCompress = false;
  // max_packet_life_time (ms)。順序保証なしの場合のみ使用。
  int _dataChannelMaxPacketLifeTime = 10;
  // max_packet_life_time 入力欄の TextEditingController。
  late final TextEditingController _dataChannelMaxPacketLifeTimeController;

  // SoraConnection の状態を表す。接続状態、remote track 一覧、local preview の
  // texture ID などの画面状態は notifier 側へ保持する。
  SoraConnectionState get _state => _pageNotifier.state;
  set _state(SoraConnectionState value) => _pageNotifier.state = value;

  // 切断時に受け取った close code / reason を保持する。
  SoraDisconnectCloseInfo? get _disconnectCloseInfo =>
      _pageNotifier.disconnectCloseInfo;
  set _disconnectCloseInfo(SoraDisconnectCloseInfo? value) =>
      _pageNotifier.disconnectCloseInfo = value;

  // 接続エラーコードを保持する。
  String? get _connectionErrorCode => _pageNotifier.connectionErrorCode;

  // 接続エラーメッセージを保持する。
  String? get _connectionErrorMessage => _pageNotifier.connectionErrorMessage;

  // 受信中のリモート映像トラック一覧を保持する。
  List<RemoteMediaStreamTrack> get _remoteVideos => _pageNotifier.remoteVideos;
  // 受信中のリモート音声トラック一覧を保持する。
  List<RemoteMediaStreamTrack> get _remoteAudios => _pageNotifier.remoteAudios;
  // リモート接続先の補助情報を保持する。
  List<DevToolsRemoteClientInfo> get _remoteClients =>
      _pageNotifier.remoteClients;

  // ローカルプレビューに使う texture ID を保持する。
  int? get _localTextureId => _pageNotifier.localTextureId;
  set _localTextureId(int? value) => _pageNotifier.localTextureId = value;

  // 接続・切断・切り替えなどの進行中フラグを保持する。
  bool get _busy => _pageNotifier.busy;
  set _busy(bool value) => _pageNotifier.busy = value;

  // アプリログを保持する。
  List<String> get _logs => _pageNotifier.logs;
  // イベントログを保持する。
  List<String> get _eventLogs => _pageNotifier.eventLogs;
  // timeline ログを保持する。
  List<String> get _timelineLogs => _pageNotifier.timelineLogs;
  // stats ログを保持する。
  List<String> get _statsLogs => _pageNotifier.statsLogs;

  // PeerConnection state の表示文字列を保持する。
  String get _peerConnectionStateLabel =>
      _pageNotifier.peerConnectionStateLabel;
  set _peerConnectionStateLabel(String value) =>
      _pageNotifier.peerConnectionStateLabel = value;

  // ICE state の表示文字列を保持する。
  String get _iceStateLabel => _pageNotifier.iceStateLabel;
  set _iceStateLabel(String value) => _pageNotifier.iceStateLabel = value;

  // DTLS state の表示文字列を保持する。
  String get _dtlsStateLabel => _pageNotifier.dtlsStateLabel;
  set _dtlsStateLabel(String value) => _pageNotifier.dtlsStateLabel = value;

  // ログ画面で選択中のタブを保持する。
  DevToolsLogTab get _selectedLogTab => _pageNotifier.selectedLogTab;
  set _selectedLogTab(DevToolsLogTab value) =>
      _pageNotifier.selectedLogTab = value;

  // ローカルプレビューの水平反転設定。
  bool get _localPreviewMirror => _pageNotifier.localPreviewMirror;
  set _localPreviewMirror(bool value) =>
      _pageNotifier.localPreviewMirror = value;

  // 接続中 audio track の enabled 状態を保持する。
  bool get _audioEnabled => _pageNotifier.audioEnabled;
  set _audioEnabled(bool value) => _pageNotifier.audioEnabled = value;

  // 接続中 video track の enabled 状態を保持する。
  bool get _videoEnabled => _pageNotifier.videoEnabled;
  set _videoEnabled(bool value) => _pageNotifier.videoEnabled = value;

  // connect 時に audio を送るかどうかを保持する。
  bool get _connectAudio => _pageNotifier.connectAudio;

  // connect 時に video を送るかどうかを保持する。
  bool get _connectVideo => _pageNotifier.connectVideo;

  // beep 音声送信が有効かどうかを保持する。
  bool get _beepAudioEnabled => _pageNotifier.beepAudioEnabled;
  set _beepAudioEnabled(bool value) => _pageNotifier.beepAudioEnabled = value;

  // 現在選択中の role を保持する。
  SoraRole get _selectedRole => _pageNotifier.selectedRole;
  set _selectedRole(SoraRole value) => _pageNotifier.selectedRole = value;

  // 列挙した映像入力デバイス一覧を保持する。
  List<VideoInputDevice> get _videoInputDevices =>
      _pageNotifier.videoInputDevices;
  set _videoInputDevices(List<VideoInputDevice> value) =>
      _pageNotifier.videoInputDevices = value;

  // 現在選択中の映像入力デバイスを保持する。
  VideoInputDevice? get _selectedVideoInputDevice =>
      _pageNotifier.selectedVideoInputDevice;
  set _selectedVideoInputDevice(VideoInputDevice? value) =>
      _pageNotifier.selectedVideoInputDevice = value;

  // 列挙した音声入力デバイス一覧を保持する。
  List<AudioInputDevice> get _audioInputDevices =>
      _pageNotifier.audioInputDevices;
  set _audioInputDevices(List<AudioInputDevice> value) =>
      _pageNotifier.audioInputDevices = value;

  // 現在選択中の音声入力デバイスを保持する。
  AudioInputDevice? get _selectedAudioInputDevice =>
      _pageNotifier.selectedAudioInputDevice;
  set _selectedAudioInputDevice(AudioInputDevice? value) =>
      _pageNotifier.selectedAudioInputDevice = value;

  // 列挙した音声出力デバイス一覧を保持する。
  List<AudioOutputDevice> get _audioOutputDevices =>
      _pageNotifier.audioOutputDevices;
  set _audioOutputDevices(List<AudioOutputDevice> value) =>
      _pageNotifier.audioOutputDevices = value;

  // 現在選択中の音声出力デバイスを保持する。
  AudioOutputDevice? get _selectedAudioOutputDevice =>
      _pageNotifier.selectedAudioOutputDevice;
  set _selectedAudioOutputDevice(AudioOutputDevice? value) =>
      _pageNotifier.selectedAudioOutputDevice = value;

  // 選択可能な映像入力解像度一覧を保持する。
  List<DevToolsVideoInputResolutionOption> get _videoInputResolutions =>
      _pageNotifier.videoInputResolutions;
  set _videoInputResolutions(List<DevToolsVideoInputResolutionOption> value) =>
      _pageNotifier.videoInputResolutions = value;

  // 現在選択中の映像入力解像度を保持する。
  DevToolsVideoInputResolutionOption? get _selectedResolution =>
      _pageNotifier.selectedResolution;
  set _selectedResolution(DevToolsVideoInputResolutionOption? value) =>
      _pageNotifier.selectedResolution = value;

  // 現在選択中のフレームレートを保持する。
  int? get _selectedFrameRate => _pageNotifier.selectedFrameRate;
  set _selectedFrameRate(int? value) => _pageNotifier.selectedFrameRate = value;

  // 現在選択中の映像コーデックを保持する。
  String? get _selectedVideoCodecType => _pageNotifier.selectedVideoCodecType;
  set _selectedVideoCodecType(String? value) =>
      _pageNotifier.selectedVideoCodecType = value;

  // 現在選択中の映像ビットレートを保持する。
  int? get _selectedVideoBitRate => _pageNotifier.selectedVideoBitRate;
  set _selectedVideoBitRate(int? value) =>
      _pageNotifier.selectedVideoBitRate = value;

  // simulcast の有効状態を保持する。
  bool get _simulcastEnabled => _pageNotifier.simulcastEnabled;
  set _simulcastEnabled(bool value) => _pageNotifier.simulcastEnabled = value;

  // 現在選択中の simulcast request RID を保持する。
  String? get _selectedSimulcastRid => _pageNotifier.selectedSimulcastRid;
  set _selectedSimulcastRid(String? value) =>
      _pageNotifier.selectedSimulcastRid = value;

  // spotlight の有効状態を保持する。
  bool get _spotlightEnabled => _pageNotifier.spotlightEnabled;
  set _spotlightEnabled(bool value) => _pageNotifier.spotlightEnabled = value;

  // 現在選択中の spotlight focus RID を保持する。
  String? get _selectedSpotlightFocusRid =>
      _pageNotifier.selectedSpotlightFocusRid;
  set _selectedSpotlightFocusRid(String? value) =>
      _pageNotifier.selectedSpotlightFocusRid = value;

  // 現在選択中の spotlight unfocus RID を保持する。
  String? get _selectedSpotlightUnfocusRid =>
      _pageNotifier.selectedSpotlightUnfocusRid;
  set _selectedSpotlightUnfocusRid(String? value) =>
      _pageNotifier.selectedSpotlightUnfocusRid = value;

  // 現在選択中の RPC method を保持する。
  String? get _selectedRpcMethod => _pageNotifier.selectedRpcMethod;
  set _selectedRpcMethod(String? value) =>
      _pageNotifier.selectedRpcMethod = value;

  // RPC を notification として送るかどうかを保持する。
  bool get _rpcNotification => _pageNotifier.rpcNotification;
  set _rpcNotification(bool value) => _pageNotifier.rpcNotification = value;

  // signaling URL 入力欄の現在値を返す。
  String get _signalingUrl => _signalingUrlController.text.trim();

  // channel ID 入力欄の現在値を返す。
  String get _channelId => _channelIdController.text.trim();

  // RPC params 入力欄の現在値を返す。
  String get _rpcParamsText => _rpcParamsController.text;

  // RPC timeout 入力欄の現在値を返す。
  String get _rpcTimeoutText => _rpcTimeoutController.text;

  // データチャネルメッセージング関連。
  List<DevToolsMessageEntry> get _messages => _pageNotifier.messages;

  // DataChannel メッセージ送信が可能かどうかを返す。
  bool get _canSendMessage =>
      _isConnected &&
      _dataChannelEnabled &&
      _dataChannelLabelController.text.trim().isNotEmpty &&
      _connection != null;

  // DataChannel 設定が有効な場合、接続用の Map リストを生成する。
  List<Map<String, Object?>> _buildDataChannelConfigs() {
    if (!_dataChannelEnabled) {
      return const <Map<String, Object?>>[];
    }
    final label = _dataChannelLabelController.text.trim();
    if (label.isEmpty) {
      return const <Map<String, Object?>>[];
    }
    return <Map<String, Object?>>[
      <String, Object?>{
        'label': label,
        'direction': _dataChannelDirection,
        'ordered': _dataChannelOrdered,
        if (!_dataChannelOrdered)
          'max_packet_life_time':
              int.tryParse(_dataChannelMaxPacketLifeTimeController.text) ??
              _dataChannelMaxPacketLifeTime,
        'compress': _dataChannelCompress,
      },
    ];
  }

  @override
  void initState() {
    super.initState();
    // タブ切り替えのアニメーション制御。
    _tabController = TabController(length: _tabs.length, vsync: this);
    // 画面状態の ChangeNotifier。全 UI はこれを listen する。
    _pageNotifier = DevToolsPageNotifier();
    // 接続イベント購読の bind / unbind を管理する。
    // callback は _eventHandler.handleEvent / handleDebugEvent へ転送する。
    _connectionSubscriptionController =
        DevToolsConnectionSubscriptionController(
          isMounted: () => mounted,
          onEvent: (event) => _eventHandler.handleEvent(event),
          onDebugEvent: (event) => _eventHandler.handleDebugEvent(event),
          onLocalVideo: (video) {
            _appendEventLog('local_video_ready: textureId=${video.textureId}');
            _mutateView(() {
              _localTextureId = video.textureId;
            });
          },
          onDebugMessage: (message) {
            _consumeDebugState(message);
            _appendLog(message);
          },
        );
    // 接続生成・切断・RPC・preview 等の SDK 呼び出しを担当する。
    _connectionController = DevToolsConnectionController(
      pageNotifier: _pageNotifier,
      sdkMethodChannel: _sdkMethodChannel,
      permissionChannel: _permissionChannel,
      subscriptionController: _connectionSubscriptionController,
      appendLog: _appendLog,
      appendEventLog: _appendEventLog,
      disposeLocalStream: _disposeLocalStream,
    );
    // SDK イベントを画面状態とログへ反映する。
    _eventHandler = DevToolsEventHandler(
      pageNotifier: _pageNotifier,
      mutateView: _mutateView,
      appendEventLog: _appendEventLog,
      appendTimelineLog: _appendTimelineLog,
      updateRemoteClients: _updateRemoteClients,
      connectionController: _connectionController,
      buildRpcTemplateRequest: _buildRpcTemplateRequest,
      setRpcParamsText: (text) {
        _rpcParamsController.text = text;
      },
      onDataChannelMessage: (entry) {
        _mutateView(() {
          _pageNotifier.addMessage(entry);
        });
      },
    );
    // external video track 用のカメラ管理。
    _cameraManager = DevToolsExternalCameraManager(onLog: _appendLog);
    // Windows では External Video Track の動作が未検証のため無効化する
    if (Platform.isWindows) {
      _useExternalVideoTrack = false;
    }
    // シグナリング URL 入力欄の TextEditingController。
    _signalingUrlController = TextEditingController(
      text: Environment.urls.isNotEmpty ? Environment.urls.first : '',
    );
    // チャネル ID 入力欄の TextEditingController。
    _channelIdController = TextEditingController(text: Environment.channelId);
    // RPC リクエストパラメータ入力欄の TextEditingController。
    _rpcParamsController = TextEditingController(text: '{}');
    // RPC リクエスト時のタイムアウト入力欄の TextEditingController。
    _rpcTimeoutController = TextEditingController(text: '5000');
    _logSearchController = TextEditingController();
    // DataChannel リアルタイムメッセージングのラベル入力欄の TextEditingController。
    _dataChannelLabelController = TextEditingController(text: '#chat');
    // DataChannel リアルタイムメッセージングの max_packet_life_time 入力欄の TextEditingController。
    _dataChannelMaxPacketLifeTimeController = TextEditingController(text: '10');
    // デバイス一覧を読み込む。
    _loadVideoInputDevices();
    _loadAudioDevices();
  }

  @override
  void dispose() {
    unawaited(_connectionSubscriptionController.dispose());
    _signalingUrlController.dispose();
    _channelIdController.dispose();
    _rpcParamsController.dispose();
    _rpcTimeoutController.dispose();
    _logSearchController.dispose();
    _dataChannelLabelController.dispose();
    _dataChannelMaxPacketLifeTimeController.dispose();
    _tabController.dispose();
    final conn = _connection;
    _connection = null;
    final localStream = _localStream;
    _localStream = null;
    if (conn != null) {
      unawaited(conn.dispose());
    }
    if (localStream != null) {
      unawaited(_disposeLocalStream(localStream));
    }
    _pageNotifier.dispose();
    unawaited(_cameraManager.dispose());
    super.dispose();
  }

  // sendonly | sendrecv ロールを送信用ロールとする
  bool get _isSendingRole =>
      _selectedRole == SoraRole.sendonly || _selectedRole == SoraRole.sendrecv;

  // connect 時に指定された audio 設定。
  bool get _configuredAudio => _connectAudio;

  // connect 時に指定された video 設定。
  bool get _configuredVideo => _connectVideo;

  // 映像を送信するか（送信ロールかつ video 有効）。
  bool get _publishesVideo => _isSendingRole && _connectVideo;

  // カメラが必要か（映像送信時）。
  bool get _needsCamera => _publishesVideo;

  // リモート映像を表示するか（受信ロール）。
  bool get _showsRemoteVideo =>
      _selectedRole == SoraRole.recvonly || _selectedRole == SoraRole.sendrecv;

  // ローカルプレビューが表示可能な状態か。
  bool get _showsLocalPreview => _needsCamera && _localTextureId != null;

  // ローカルプレビューの取得操作が可能か。
  bool get _canShowLocalPreview =>
      !_busy &&
      _selectedRole != SoraRole.recvonly &&
      _configuredVideo &&
      !_isConnected &&
      !_isConnecting &&
      !_useExternalVideoTrack;

  // カメラ切り替え操作が可能か（モバイルかつ複数カメラが存在する場合）。
  bool get _canSwitchCamera =>
      (Platform.isIOS || Platform.isAndroid) &&
      _videoInputDevices.length >= 2 &&
      _needsCamera &&
      _isConnected &&
      _connection != null &&
      _localStream != null &&
      !_useExternalVideoTrack;

  // simulcast request RID の選択が必要か。
  bool get _usesSimulcastRequestRid =>
      _simulcastEnabled && _selectedRole != SoraRole.sendonly;

  // spotlight RID の選択が必要か。
  bool get _usesSpotlightRid =>
      _spotlightEnabled &&
      _simulcastEnabled &&
      _selectedRole != SoraRole.sendonly;

  // simulcast request RID を編集可能か。
  bool get _canEditSimulcastRequestRid => _simulcastEnabled;

  // spotlight RID を編集可能か。
  bool get _canEditSpotlightRid => _spotlightEnabled;

  // RPC 送信が可能か（接続済みかつ method 選択済み）。
  bool get _canSendRpc =>
      !_pageNotifier.rpcBusy &&
      _isConnected &&
      _connection != null &&
      _selectedRpcMethod != null;

  // stats 取得が可能か。
  bool get _canFetchStats => !_busy && _isConnected && _connection != null;

  // `ChangeNotifier` 経由で画面状態を更新する。
  void _mutateView(VoidCallback update) {
    if (!mounted) {
      update();
      return;
    }
    _pageNotifier.mutate(update);
  }

  // RPC テンプレート生成に必要な入力値をまとめる。
  DevToolsRpcTemplateRequest _buildRpcTemplateRequest() {
    return DevToolsRpcTemplateRequest(
      connectionId: _connection?.connectionId ?? '',
      channelId: _channelId,
      selectedSimulcastRid: _selectedSimulcastRid,
      selectedSpotlightFocusRid: _selectedSpotlightFocusRid,
      selectedSpotlightUnfocusRid: _selectedSpotlightUnfocusRid,
    );
  }

  // 接続前は次回 connect 時の audio/video 設定として扱い、接続中は送信中 track の
  // enabled 切り替えとして扱うため、非同期処理中でなければ操作を許可する。
  bool get _canToggleAudioEnabled => !_busy;

  bool get _canToggleVideoEnabled => !_busy;

  bool get _isConnecting => _state is SoraConnectingState;

  bool get _isConnected => _state is SoraConnectedState;

  String get _connectionStateLabel {
    final state = _state;
    return switch (state) {
      SoraConnectingState() => 'connecting',
      SoraConnectedState() => 'connected',
      SoraDisconnectedState() => 'disconnected',
    };
  }

  // 利用可能な video input device を読み込み、既定選択を反映する。
  Future<void> _loadVideoInputDevices() async {
    final snapshot =
        await DevToolsMediaDevicesSupport.loadInitialVideoDevices();
    if (!mounted) {
      return;
    }
    _mutateView(() {
      _videoInputDevices = snapshot.devices;
      _selectedVideoInputDevice = snapshot.selectedDevice;
      _videoInputResolutions = snapshot.resolutions;
      _selectedResolution = snapshot.selectedResolution;
    });
  }

  // 選択中 video input device の対応解像度一覧を読み込む。
  Future<void> _loadVideoInputFormats(VideoInputDevice device) async {
    final resolutions = await DevToolsMediaDevicesSupport.loadVideoInputFormats(
      device,
    );
    if (!mounted) {
      return;
    }
    _mutateView(() {
      _videoInputResolutions = resolutions;
      _selectedResolution = DevToolsMediaDevicesSupport.findDefaultResolution(
        _videoInputResolutions,
      );
    });
  }

  // Audio input / output device 一覧を読み込み、選択状態を同期する。
  Future<void> _loadAudioDevices() async {
    final snapshot = await DevToolsMediaDevicesSupport.loadAudioDevices(
      isAndroid: Platform.isAndroid,
      selectedAudioInputDeviceId: _selectedAudioInputDevice?.deviceId,
      selectedAudioOutputDeviceId: _selectedAudioOutputDevice?.deviceId,
    );
    if (!mounted) {
      return;
    }
    _mutateView(() {
      _audioInputDevices = snapshot.inputDevices;
      _selectedAudioInputDevice = snapshot.selectedInputDevice;
      _audioOutputDevices = snapshot.outputDevices;
      _selectedAudioOutputDevice = snapshot.selectedOutputDevice;
    });
  }

  // 権限付与後に platform 依存の audio device 一覧を再同期する。
  Future<void> _refreshAudioDevicesAfterPermission() async {
    final snapshot = await _connectionController
        .reloadAudioDevicesAfterPermission(
          selectedAudioInputDeviceId: _selectedAudioInputDevice?.deviceId,
          selectedAudioOutputDeviceId: _selectedAudioOutputDevice?.deviceId,
        );
    if (snapshot == null || !mounted) {
      return;
    }
    _mutateView(() {
      _audioInputDevices = snapshot.inputDevices;
      _selectedAudioInputDevice = snapshot.selectedInputDevice;
      _audioOutputDevices = snapshot.outputDevices;
      _selectedAudioOutputDevice = snapshot.selectedOutputDevice;
    });
  }

  // Device Id を指定して映像入力デバイスを選択する。
  // 見つからなかった場合は _videoInputDevices の先頭を返すフォールバックを行う。
  Future<void> _selectVideoInputDevice(String deviceId) async {
    final device = _videoInputDevices.firstWhere(
      (d) => d.deviceId == deviceId,
      orElse: () => _videoInputDevices.first,
    );
    _mutateView(() {
      _selectedVideoInputDevice = device;
    });
    await _clearLocalPreview();
    await _loadVideoInputFormats(device);
  }

  // DataChannel 経由でメッセージを送信する。
  // 送信先 label は Connect タブの DataChannel 設定で指定したものを常に使う。
  void _handleSendMessage(String text) {
    final conn = _connection;
    final label = _dataChannelLabelController.text.trim();
    if (conn == null || label.isEmpty || !_isConnected) {
      return;
    }
    conn.sendDataChannelMessage(label, Uint8List.fromList(utf8.encode(text)));
    _mutateView(() {
      _pageNotifier.addMessage(
        DevToolsMessageEntry(
          timestamp: DateTime.now(),
          label: label,
          text: text,
          isSent: true,
        ),
      );
    });
    _appendLog('message: sent label=$label text=$text');
  }

  // 入力欄の値を検証し、接続中の peer へ RPC を送信する。
  Future<void> _sendRpcRequest() async {
    final conn = _connection;
    final method = _selectedRpcMethod;
    if (conn == null || method == null || !_isConnected) {
      return;
    }

    final message = await _connectionController.sendRpc(
      DevToolsRpcRequest(
        connection: conn,
        method: method,
        paramsText: _rpcParamsText,
        timeoutText: _rpcTimeoutText,
        notification: _rpcNotification,
      ),
    );
    if (message != null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  // 現在の接続設定を確認するダイアログを表示して接続可否を決める。
  Future<void> _handleConnectPressed() async {
    if (_busy) {
      return;
    }
    final shouldConnect = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Connect Settings'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('signaling_url: $_signalingUrl'),
                Text('channel_id: $_channelId'),
                Text('role: ${_selectedRole.value}'),
                Text(
                  'simulcast: ${_simulcastEnabled ? 'Enabled' : 'Disabled'}',
                ),
                Text(
                  'simulcast_request_rid: ${_selectedSimulcastRid ?? '未指定'}',
                ),
                Text(
                  'spotlight: ${_spotlightEnabled ? 'Enabled' : 'Disabled'}',
                ),
                Text(
                  'spotlight_focus_rid: ${_selectedSpotlightFocusRid ?? '未指定'}',
                ),
                Text(
                  'spotlight_unfocus_rid: ${_selectedSpotlightUnfocusRid ?? '未指定'}',
                ),
                Text(
                  'data_channels: ${_dataChannelEnabled ? 'Enabled' : 'Disabled'}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
    if (shouldConnect != true) {
      return;
    }
    await _connect();
  }

  // 現在の UI 設定から `SoraConnection` を生成して接続を開始する。
  Future<void> _connect() async {
    if (_busy) {
      return;
    }
    _mutateView(() {
      _pageNotifier.prepareForConnect(
        audioEnabledValue: _configuredAudio,
        videoEnabledValue: _configuredVideo,
      );
    });
    try {
      await _disposeClient(preserveLocalStream: true);
      final granted = await _ensureMediaPermissions();
      if (!granted) {
        _appendLog('connect: required media permissions are not granted');
        if (!mounted) {
          return;
        }
        _mutateView(() {
          _busy = false;
        });
        return;
      }
      await _refreshAudioDevicesAfterPermission();
      if (!mounted) {
        return;
      }
      if (_useExternalVideoTrack) {
        await _cameraManager.initialize();
      }
      _appendLog('connect: start role=${_selectedRole.value}');
      final result = await _connectionController.createAndConnect(
        request: _buildConnectRequest(),
        onLocalTextureReady: (textureId) {
          if (!mounted) {
            return;
          }
          _mutateView(() {
            _localTextureId = textureId;
          });
        },
      );
      final conn = result.connection;
      final localStream = result.localStream;
      _connection = conn;
      _localStream = localStream;
      if (_useExternalVideoTrack && localStream != null) {
        final videoTracks = localStream.getVideoTracks();
        if (videoTracks.isNotEmpty &&
            videoTracks.first.captureType == VideoTrackCaptureType.external) {
          await _cameraManager.start(videoTracks.first);
        }
      }
      if (!mounted) {
        return;
      }
      _mutateView(() {
        _audioEnabled = currentAudioTrackEnabled(
          localStream,
          fallback: _configuredAudio,
        );
        _videoEnabled = currentVideoTrackEnabled(
          localStream,
          fallback: _configuredVideo,
        );
      });
      _appendLog('connect: request sent');
      _tabController.animateTo(1);
    } catch (error) {
      _appendLog('connect: exception=$error');
      // connect() 失敗直前に流れる connection_error / disconnected を
      // event log へ取り込めるよう、購読解除を 1 tick 遅らせる。
      await Future<void>.delayed(Duration.zero);
      await _disposeClient(preserveLocalStream: true);
      if (mounted) {
        _mutateView(() {
          _state = const SoraDisconnectedState();
          _disconnectCloseInfo = null;
          _peerConnectionStateLabel = 'disconnected';
          _iceStateLabel = 'unknown';
          _dtlsStateLabel = 'unknown';
        });
      } else {
        _state = const SoraDisconnectedState();
        _disconnectCloseInfo = null;
        _peerConnectionStateLabel = 'disconnected';
        _iceStateLabel = 'unknown';
        _dtlsStateLabel = 'unknown';
      }
    } finally {
      if (mounted) {
        _mutateView(() {
          _busy = false;
        });
      }
    }
  }

  // 現在の UI 設定から接続要求を組み立てる。
  DevToolsConnectRequest _buildConnectRequest() {
    return DevToolsConnectRequest(
      signalingUrls: _signalingUrl.isEmpty
          ? Environment.urls
          : <String>[_signalingUrl],
      channelId: _channelId,
      role: _selectedRole,
      configuredAudio: _configuredAudio,
      configuredVideo: _configuredVideo,
      beepAudioEnabled: _beepAudioEnabled,
      selectedVideoCodecType: _selectedVideoCodecType,
      selectedVideoBitRate: _selectedVideoBitRate,
      simulcastEnabled: _simulcastEnabled,
      selectedSimulcastRid: _selectedSimulcastRid,
      spotlightEnabled: _spotlightEnabled,
      selectedSpotlightFocusRid: _selectedSpotlightFocusRid,
      selectedSpotlightUnfocusRid: _selectedSpotlightUnfocusRid,
      usesSimulcastRequestRid: _usesSimulcastRequestRid,
      usesSpotlightRid: _usesSpotlightRid,
      selectedAudioOutputDeviceId: _selectedAudioOutputDevice?.deviceId,
      selectedAudioInputDeviceId: _selectedAudioInputDevice?.deviceId,
      selectedVideoInputDeviceId: _selectedVideoInputDevice?.deviceId,
      selectedResolution: _selectedResolution,
      selectedFrameRate: _selectedFrameRate,
      existingLocalStream: _localStream,
      useExternalVideoTrack: _useExternalVideoTrack,
      dataChannels: _buildDataChannelConfigs(),
    );
  }

  // 接続前でも確認できる local video preview を取得して表示する。
  Future<void> _showLocalPreview() async {
    if (!_canShowLocalPreview) {
      return;
    }
    _mutateView(() {
      _busy = true;
    });
    try {
      if (Platform.isIOS || Platform.isAndroid) {
        final granted =
            await _permissionChannel.invokeMethod<bool>(
              'ensureMediaPermissions',
              <String, Object?>{'camera': true, 'microphone': false},
            ) ??
            false;
        if (!granted) {
          _appendLog('preview: required camera permission is not granted');
          return;
        }
      }
      await _refreshAudioDevicesAfterPermission();
      await _clearLocalPreview();
      final result = await _connectionController.createLocalPreview(
        DevToolsPreviewRequest(
          selectedVideoInputDeviceId: _selectedVideoInputDevice?.deviceId,
          selectedResolution: _selectedResolution,
          selectedFrameRate: _selectedFrameRate,
        ),
      );
      if (!mounted) {
        await _disposeLocalStream(result.previewStream);
        return;
      }
      _mutateView(() {
        _localStream = result.previewStream;
        _localTextureId = result.textureId;
      });
      _appendLog('preview: local texture ready textureId=${result.textureId}');
    } catch (error) {
      _appendLog('preview: exception=$error');
    } finally {
      if (mounted) {
        _mutateView(() {
          _busy = false;
        });
      }
    }
  }

  // 現在の role と publish 設定に必要な media 権限を確認する。
  Future<bool> _ensureMediaPermissions() async {
    return _connectionController.ensureMediaPermissions(
      DevToolsPermissionRequest(
        needsCamera: _needsCamera,
        needsMicrophone: _isSendingRole && _configuredAudio,
      ),
    );
  }

  // 接続中 peer を切断し、表示状態を初期値へ戻す。
  Future<void> _disconnect() async {
    if (_busy) {
      return;
    }
    _mutateView(() {
      _busy = true;
    });
    try {
      _appendLog('disconnect: start');
      final conn = _connection;
      if (conn != null) {
        await _connectionController.disconnect(conn);
      }
      await _connectionController.disposeBeepAudioTrack();
      _pageNotifier.resetAfterDisconnect(
        audioEnabledValue: _configuredAudio,
        videoEnabledValue: _configuredVideo,
        notify: mounted,
      );
      _appendLog('disconnect: done');
    } finally {
      if (mounted) {
        _mutateView(() {
          _busy = false;
        });
      }
    }
  }

  // 接続状態に応じて connect / disconnect のどちらかを実行する。
  Future<void> _handleConnectionButtonPressed() async {
    switch (_state) {
      case SoraDisconnectedState():
        await _handleConnectPressed();
      case SoraConnectedState():
        await _disconnect();
      case SoraConnectingState():
        // connecting 状態ではボタンは無効化されるため処理不要
        break;
    }
  }

  // 送信中の video track を別カメラへ差し替える。
  Future<void> _switchCamera() async {
    if (_busy || !_canSwitchCamera) {
      return;
    }
    final conn = _connection;
    final localStream = _localStream;
    if (conn == null || localStream == null) {
      return;
    }
    _mutateView(() {
      _busy = true;
    });
    try {
      _appendLog('switch_camera: start');
      final result = await _connectionController.switchCamera(
        DevToolsSwitchCameraRequest(
          connection: conn,
          localStream: localStream,
          videoInputDevices: _videoInputDevices,
          selectedVideoInputDevice: _selectedVideoInputDevice,
          selectedResolution: _selectedResolution,
          selectedFrameRate: _selectedFrameRate,
        ),
      );
      if (!mounted) {
        return;
      }
      _mutateView(() {
        _selectedVideoInputDevice = result.selectedVideoInputDevice;
        _videoInputResolutions = result.resolutions;
        _selectedResolution = result.selectedResolution;
      });
      _appendLog(
        'switch_camera: deviceId=${result.selectedVideoInputDevice.deviceId} label=${result.selectedVideoInputDevice.label}',
      );
    } catch (error) {
      _appendLog('switch_camera: exception=$error');
    } finally {
      if (mounted) {
        _mutateView(() {
          _busy = false;
        });
      }
    }
  }

  // 接続購読と保持中 client をまとめて破棄し、状態を初期化する。
  Future<void> _disposeClient({bool preserveLocalStream = false}) async {
    await _connectionSubscriptionController.unbind();
    _pageNotifier.resetDisposedClientState(
      audioEnabledValue: _configuredAudio,
      videoEnabledValue: _configuredVideo,
    );
    final conn = _connection;
    _connection = null;
    final localStream = preserveLocalStream ? null : _localStream;
    if (!preserveLocalStream) {
      _localStream = null;
    }
    // クリーンアップ順序:
    // 1. frame source 停止（track が生きているうちに stopImageStream する）
    // 2. connection 破棄（track の native リソースが解放される）
    // 3. preserveLocalStream=false の場合のみカメラも破棄
    await _cameraManager.stop();
    if (conn != null) {
      await conn.dispose();
    }
    if (!preserveLocalStream) {
      await _cameraManager.dispose();
    }
    await _connectionController.disposeLocalStream(localStream);
  }

  // 画面内だけで保持している local preview を破棄する。
  Future<void> _clearLocalPreview() async {
    final stream = _localStream;
    _localStream = null;
    if (mounted) {
      _mutateView(() {
        _localTextureId = null;
      });
    } else {
      _localTextureId = null;
    }
    if (stream != null) {
      await _disposeLocalStream(stream);
    }
  }

  // devtools が保持している local stream と track をまとめて破棄する。
  Future<void> _disposeLocalStream(LocalMediaStream stream) async {
    final tracks = stream.getTracks();
    for (final track in tracks) {
      await track.dispose();
    }
    await stream.dispose();
  }

  // 送信 audio の有効 / 無効を切り替えてログへ反映する。
  void _toggleAudioEnabled() {
    if (!_canToggleAudioEnabled) {
      return;
    }
    final enabled = !_audioEnabled;
    final conn = _connection;
    if (conn != null) {
      final actualEnabled = _setTrackEnabledOrNull(
        connection: conn,
        enabled: enabled,
        isAudio: true,
      );
      if (actualEnabled != enabled) {
        _appendLog(
          'audio_enabled: sync failed requested=$enabled actual=$actualEnabled',
        );
        return;
      }
    }
    _mutateView(() {
      _pageNotifier.applyToggleAudio(enabled, isConnected: conn != null);
    });
    if (mounted) {
      if (conn == null && !enabled && !_connectVideo) {
        unawaited(_clearLocalPreview());
      }
      _appendLog('audio_enabled: enabled=${_audioEnabled ? 'true' : 'false'}');
    }
  }

  // 送信 video の有効 / 無効を切り替えてログへ反映する。
  void _toggleVideoEnabled() {
    if (!_canToggleVideoEnabled) {
      return;
    }
    final enabled = !_videoEnabled;
    final conn = _connection;
    if (conn != null) {
      final actualEnabled = _setTrackEnabledOrNull(
        connection: conn,
        enabled: enabled,
        isAudio: false,
      );
      if (actualEnabled != enabled) {
        _appendLog(
          'video_enabled: sync failed requested=$enabled actual=$actualEnabled',
        );
        return;
      }
    }
    _mutateView(() {
      _pageNotifier.applyToggleVideo(enabled, isConnected: conn != null);
    });
    if (mounted) {
      if (conn == null) {
        unawaited(_clearLocalPreview());
      }
      _appendLog('video_enabled: enabled=${_videoEnabled ? 'true' : 'false'}');
    }
  }

  // beep 音声トラックにビープ音の再生を指示する。
  void _handleTriggerBeep() {
    final beepTrack = _connectionController.beepAudioTrack;
    if (beepTrack == null) {
      _appendLog('beep: no active BeepAudioTrack');
      return;
    }
    beepTrack.triggerBeep();
    _appendLog('beep: triggered');
  }

  // トラックの有効・無効を設定する
  bool? _setTrackEnabledOrNull({
    required SoraConnection connection,
    required bool enabled,
    required bool isAudio,
  }) {
    try {
      return _connectionController.setTrackEnabled(
        DevToolsSetTrackEnabledRequest(
          connection: connection,
          enabled: enabled,
          isAudio: isAudio,
        ),
      );
    } on StateError catch (error) {
      _appendLog('track_enabled: failed error=$error');
      return null;
    }
  }

  // 接続前の audio 設定と表示状態を同期する。
  void _changeConnectAudio(bool value) {
    _mutateView(() {
      _pageNotifier.setConnectAudio(value);
    });
    if (shouldClearLocalPreviewForConnectAudioChange(
      hasRetainedConnection: _connection != null,
      nextConnectAudio: value,
      connectVideo: _connectVideo,
    )) {
      unawaited(_clearLocalPreview());
    }
  }

  // 接続前の video 設定と表示状態を同期する。
  void _changeConnectVideo(bool value) {
    _mutateView(() {
      _pageNotifier.setConnectVideo(value);
    });
    if (shouldClearLocalPreviewForConnectVideoChange(
      hasRetainedConnection: _connection != null,
    )) {
      unawaited(_clearLocalPreview());
    }
  }

  // 接続中 peer から統計情報を取得して stats ログへ追記する。
  Future<void> _fetchStats() async {
    final conn = _connection;
    if (conn == null || !_canFetchStats) {
      return;
    }
    _mutateView(() {
      _busy = true;
    });
    try {
      _appendStatsLog('get_stats: start');
      final formatted = await _connectionController.fetchStats(
        DevToolsStatsRequest(connection: conn),
      );
      if (formatted == null) {
        _appendStatsLog('get_stats: empty');
        return;
      }
      _appendStatsLog('get_stats: success\n$formatted');
    } catch (error) {
      _appendStatsLog('get_stats: error=$error');
    } finally {
      if (mounted) {
        _mutateView(() {
          _busy = false;
        });
      }
    }
  }

  // 操作ログ・デバッグログを出力
  void _appendLog(String line) {
    _appendEntry(_logs, line);
  }

  // イベントログを出力
  void _appendEventLog(String line) {
    _appendEntry(_eventLogs, line);
  }

  // タイムラインログを出力
  void _appendTimelineLog(String line) {
    _appendEntry(_timelineLogs, line);
  }

  // 統計情報を出力
  void _appendStatsLog(String line) {
    _appendEntry(_statsLogs, line);
  }

  // 指定ログ配列へ timestamp 付き 1 行を追記する。
  void _appendEntry(List<String> target, String line) {
    DevToolsLoggingSupport.appendEntry(
      target: target,
      line: line,
      mounted: mounted,
      addWhenUnmounted: () {
        final entry = '[${DateTime.now().toIso8601String()}] $line';
        if (identical(target, _logs)) {
          _pageNotifier.addLog(entry);
          return;
        }
        if (identical(target, _eventLogs)) {
          _pageNotifier.addEventLog(entry);
          return;
        }
        if (identical(target, _timelineLogs)) {
          _pageNotifier.addTimelineLog(entry);
          return;
        }
        if (identical(target, _statsLogs)) {
          _pageNotifier.addStatsLog(entry);
          return;
        }
        target.add(entry);
      },
      mutateView: _mutateView,
    );
  }

  // notify event 由来の remote client 一覧を画面状態へ同期する。
  void _updateRemoteClients(Map<String, Object?> message) {
    final eventType = message['event_type'] as String?;
    final connectionId = message['connection_id'] as String?;
    final clientId = message['client_id'] as String?;
    final nestedClients = DevToolsLoggingSupport.extractRemoteClients(message);
    if (eventType == null) {
      return;
    }
    List<DevToolsRemoteClientInfo> buildCandidates() {
      return nestedClients.isNotEmpty
          ? DevToolsLoggingSupport.filterRemoteClients(
              clients: nestedClients,
              selfConnectionId: _connection?.connectionId,
            )
          : DevToolsLoggingSupport.filterRemoteClients(
              clients: <DevToolsRemoteClientInfo?>[
                if (connectionId != null && connectionId.isNotEmpty)
                  DevToolsRemoteClientInfo(
                    connectionId: connectionId,
                    clientId: clientId,
                  ),
              ],
              selfConnectionId: _connection?.connectionId,
            );
    }

    if (eventType == 'connection.created') {
      final candidates = buildCandidates();
      if (candidates.isEmpty) {
        return;
      }
      _mutateView(() {
        _pageNotifier.upsertRemoteClients(candidates);
      });
      return;
    }
    if (eventType == 'connection.destroyed') {
      final candidates = buildCandidates();
      if (candidates.isEmpty) {
        return;
      }
      final candidateIds = candidates
          .map((client) => client.connectionId)
          .toSet();
      _mutateView(() {
        _pageNotifier.removeRemoteClientsByConnectionIds(candidateIds);
      });
    }
  }

  // 自分の Sora ClientId を取得
  String? get _selfClientId {
    final clientId = _connection?.serverClientId;
    if (clientId == null || clientId.isEmpty) {
      return null;
    }
    return clientId;
  }

  // 現在表示中のログをクリップボードへコピーする。
  Future<void> _copyLogs() async {
    await DevToolsLogPanel.copyLogs(_selectedLogs);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied logs')));
  }

  // 表示選択中のログ種類
  List<String> get _selectedLogs => _pageNotifier.filteredSelectedLogs;

  // ログ画面の検索語句。
  set _logSearchQuery(String value) => _pageNotifier.logSearchQuery = value;

  String get _selectedLogDescription => switch (_selectedLogTab) {
    DevToolsLogTab.app => '操作ログ / デバッグログ',
    DevToolsLogTab.event => 'イベントログ',
    DevToolsLogTab.timeline => 'タイムラインログ',
    DevToolsLogTab.stats => '統計情報',
  };

  // ログパネルへ現在の選択状態と操作 callback を束ねて渡す。
  Widget _buildLogPanel({VoidCallback? onClose, bool plain = false}) {
    return DevToolsLogPanel(
      selectedLogTab: _selectedLogTab,
      selectedLogDescription: _selectedLogDescription,
      selectedLogs: _selectedLogs,
      logSearchController: _logSearchController,
      onLogTabChanged: (value) {
        _mutateView(() {
          _selectedLogTab = value;
        });
      },
      onLogSearchQueryChanged: (value) {
        _mutateView(() {
          _logSearchQuery = value;
        });
      },
      onClose: onClose,
      onCopyLogs: _copyLogs,
      canFetchStats: _canFetchStats,
      onFetchStats: _fetchStats,
      plain: plain,
    );
  }

  // RPC セクションへ現在の入力状態と操作 callback を束ねて渡す。
  Widget _buildRpcRequestSection({bool initiallyExpanded = false}) {
    return DevToolsRpcRequestSection(
      selectedRpcMethod: _selectedRpcMethod,
      availableRpcMethods: _pageNotifier.availableRpcMethods,
      rpcNotification: _rpcNotification,
      rpcBusy: _pageNotifier.rpcBusy,
      canSendRpc: _canSendRpc,
      rpcResult: _pageNotifier.rpcResult,
      rpcTimeoutController: _rpcTimeoutController,
      rpcParamsController: _rpcParamsController,
      initiallyExpanded: initiallyExpanded,
      onRpcMethodChanged: (value) {
        _mutateView(() {
          _selectedRpcMethod = value;
        });
        _rpcParamsController.text = _connectionController
            .buildRpcParamsTemplateJson(value, _buildRpcTemplateRequest());
      },
      onRpcNotificationChanged: (value) {
        _mutateView(() {
          _rpcNotification = value;
        });
      },
      onApplyTemplate: () {
        final template = _connectionController.buildRpcParamsTemplateJson(
          _selectedRpcMethod!,
          _buildRpcTemplateRequest(),
        );
        _rpcParamsController.text = template;
      },
      onSendRpc: _sendRpcRequest,
    );
  }

  // Video パネルへ現在の track 状態を束ねて渡す。
  Widget _buildVideoPanel() {
    return DevToolsVideoPanel(
      showsRemoteVideo: _showsRemoteVideo,
      showsLocalPreview: _showsLocalPreview,
      needsCamera: _needsCamera,
      localTextureId: _localTextureId,
      localPreviewMirror: _localPreviewMirror,
      remoteVideos: _remoteVideos,
      remoteAudios: _remoteAudios,
      remoteClients: _remoteClients,
      selectedResolution: _selectedResolution,
    );
  }

  // DataChannel 設定セクションを返す。
  Widget _buildDataChannelSection() {
    const directionOptions = <String>['sendrecv', 'sendonly', 'recvonly'];
    final disabled = _busy || _isConnected;
    return ExpansionTile(
      title: Row(
        children: [
          const Text('DataChannel'),
          const Spacer(),
          Switch(
            value: _dataChannelEnabled,
            onChanged: disabled
                ? null
                : (value) {
                    _mutateView(() {
                      _dataChannelEnabled = value;
                    });
                  },
          ),
        ],
      ),
      initiallyExpanded: _dataChannelEnabled,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _dataChannelLabelController,
            decoration: const InputDecoration(
              labelText: 'label',
              helperText: '先頭に # をつける（例: #chat）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            enabled: !disabled && _dataChannelEnabled,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('direction'),
              const Spacer(),
              DropdownButton<String>(
                value: _dataChannelDirection,
                underline: const SizedBox(),
                style: Theme.of(context).textTheme.bodyMedium,
                items: directionOptions
                    .map(
                      (dir) => DropdownMenuItem(value: dir, child: Text(dir)),
                    )
                    .toList(growable: false),
                onChanged: (!disabled && _dataChannelEnabled)
                    ? (value) {
                        _mutateView(() {
                          _dataChannelDirection = value!;
                        });
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('ordered'),
              const Spacer(),
              Switch(
                value: _dataChannelOrdered,
                onChanged: (!disabled && _dataChannelEnabled)
                    ? (value) {
                        _mutateView(() {
                          _dataChannelOrdered = value;
                        });
                      }
                    : null,
              ),
            ],
          ),
        ),
        if (!_dataChannelOrdered)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _dataChannelMaxPacketLifeTimeController,
              decoration: const InputDecoration(
                labelText: 'max_packet_life_time (ms)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              enabled: !disabled && _dataChannelEnabled,
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  _dataChannelMaxPacketLifeTime = parsed;
                }
              },
            ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('compress'),
              const Spacer(),
              Switch(
                value: _dataChannelCompress,
                onChanged: (!disabled && _dataChannelEnabled)
                    ? (value) {
                        _mutateView(() {
                          _dataChannelCompress = value;
                        });
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // 接続タブへ接続設定、主要操作、状態 summary をまとめて表示する。
  Widget _buildConnectionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildConnectionSettingsSection(),
          const SizedBox(height: 8),
          _buildMediaDeviceSection(),
          const SizedBox(height: 8),
          _buildDataChannelSection(),
          const SizedBox(height: 8),
          ExpansionTile(
            title: const Text('Developer Option'),
            initiallyExpanded: _useExternalVideoTrack,
            children: [
              SwitchListTile(
                title: const Text('External Video Track'),
                subtitle: const Text(
                  'pub.dev の camera package 利用で映像を配信する検証用機能です',
                ),
                value: _useExternalVideoTrack,
                onChanged: _busy || _isConnected || Platform.isWindows
                    ? null
                    : (value) {
                        _mutateView(() {
                          _useExternalVideoTrack = value;
                        });
                      },
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 8),
          DevToolsActionSection(
            busy: _busy,
            isConnecting: _isConnecting,
            isConnected: _isConnected,
            onConnectionButtonPressed: _handleConnectionButtonPressed,
          ),
          if (_isConnected && _beepAudioEnabled) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _handleTriggerBeep,
              icon: const Icon(Icons.volume_up),
              label: const Text('Trigger Beep'),
            ),
          ],
          const SizedBox(height: 12),
          DevToolsConnectionStatusSection(
            connectionStateLabel: _connectionStateLabel,
            peerConnectionStateLabel: _peerConnectionStateLabel,
            iceStateLabel: _iceStateLabel,
            dtlsStateLabel: _dtlsStateLabel,
            sessionId: _connection?.sessionId,
            connectionId: _connection?.connectionId,
            clientId: _selfClientId,
            disconnectCloseInfo: _disconnectCloseInfo,
            connectionErrorCode: _connectionErrorCode,
            connectionErrorMessage: _connectionErrorMessage,
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  // 映像タブへ preview 操作と映像表示パネルをまとめて表示する。
  Widget _buildVideoTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Audio Track',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Switch(
                          value: _audioEnabled,
                          onChanged: _canToggleAudioEnabled
                              ? (_) => _toggleAudioEnabled()
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'Video Track',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Switch(
                          value: _videoEnabled,
                          onChanged: _canToggleVideoEnabled
                              ? (_) => _toggleVideoEnabled()
                              : null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Flexible(
                          child: Text(
                            'Mirror Preview',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Switch(
                          value: _localPreviewMirror,
                          onChanged: (value) {
                            _mutateView(() {
                              _localPreviewMirror = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (_isConnected)
                FilledButton(
                  onPressed: _busy ? null : _disconnect,
                  child: const Text('Disconnect'),
                ),
              OutlinedButton(
                onPressed: _canShowLocalPreview ? _showLocalPreview : null,
                child: const Text('Show Local Preview'),
              ),
              OutlinedButton(
                onPressed: _busy || !_canSwitchCamera ? null : _switchCamera,
                child: const Text('Switch Camera'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildVideoPanel()),
        ],
      ),
    );
  }

  // RPC タブへ RPC 実行 UI を表示する。
  Widget _buildRpcTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: _buildRpcRequestSection(initiallyExpanded: true),
    );
  }

  // 診断タブへ stats 取得操作とログパネルを表示する。
  Widget _buildDiagnosticsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [Expanded(child: _buildLogPanel(plain: true))]),
    );
  }

  // 接続設定セクションへ現在の設定値と操作 callback を束ねて渡す。
  Widget _buildConnectionSettingsSection() {
    return DevToolsConnectionSettingsSection(
      signalingUrlController: _signalingUrlController,
      channelIdController: _channelIdController,
      selectedRole: _selectedRole,
      simulcastEnabled: _simulcastEnabled,
      selectedSimulcastRid: _selectedSimulcastRid,
      spotlightEnabled: _spotlightEnabled,
      selectedSpotlightFocusRid: _selectedSpotlightFocusRid,
      selectedSpotlightUnfocusRid: _selectedSpotlightUnfocusRid,
      connectAudio: _connectAudio,
      connectVideo: _connectVideo,
      beepAudioEnabled: _beepAudioEnabled,
      needsCamera: _needsCamera,
      canEditSimulcastRequestRid: _canEditSimulcastRequestRid,
      canEditSpotlightRid: _canEditSpotlightRid,
      selectedVideoCodecType: _selectedVideoCodecType,
      selectedVideoBitRate: _selectedVideoBitRate,
      selectedResolutionIndex: _selectedResolution != null
          ? _videoInputResolutions.indexOf(_selectedResolution!)
          : null,
      selectedFrameRate: _selectedFrameRate,
      simulcastRidOptions: DevToolsConstants.simulcastRidOptions,
      videoCodecTypeOptions: DevToolsConstants.videoCodecTypeOptions,
      videoBitRateOptions: DevToolsConstants.videoBitRateOptions,
      frameRateOptions: DevToolsConstants.frameRateOptions,
      resolutionLabels: _videoInputResolutions
          .map((resolution) => resolution.toString())
          .toList(growable: false),
      onRoleChanged: (value) {
        _mutateView(() {
          _selectedRole = value;
          if (!_usesSimulcastRequestRid) {
            _selectedSimulcastRid = null;
          }
          if (!_usesSpotlightRid) {
            _selectedSpotlightFocusRid = null;
            _selectedSpotlightUnfocusRid = null;
          }
          if (!_needsCamera) {
            _localTextureId = null;
          }
        });
        unawaited(_clearLocalPreview());
      },
      onSimulcastEnabledChanged: (value) {
        _mutateView(() {
          _simulcastEnabled = value;
          if (!_usesSimulcastRequestRid) {
            _selectedSimulcastRid = null;
          }
          if (!_usesSpotlightRid) {
            _selectedSpotlightFocusRid = null;
            _selectedSpotlightUnfocusRid = null;
          }
        });
      },
      onSimulcastRidChanged: (value) {
        _mutateView(() {
          _selectedSimulcastRid = value;
        });
      },
      onSpotlightEnabledChanged: (value) {
        _mutateView(() {
          _spotlightEnabled = value;
          if (!_usesSpotlightRid) {
            _selectedSpotlightFocusRid = null;
            _selectedSpotlightUnfocusRid = null;
          }
        });
      },
      onSpotlightFocusRidChanged: (value) {
        _mutateView(() {
          _selectedSpotlightFocusRid = value;
        });
      },
      onSpotlightUnfocusRidChanged: (value) {
        _mutateView(() {
          _selectedSpotlightUnfocusRid = value;
        });
      },
      onConnectAudioChanged: (value) {
        _changeConnectAudio(value);
      },
      onConnectVideoChanged: (value) {
        _changeConnectVideo(value);
      },
      onBeepAudioEnabledChanged: (value) {
        _mutateView(() {
          _beepAudioEnabled = value;
        });
      },
      onVideoCodecTypeChanged: (value) {
        _mutateView(() {
          _selectedVideoCodecType = value;
        });
      },
      onVideoBitRateChanged: (value) {
        _mutateView(() {
          _selectedVideoBitRate = value;
        });
      },
      onResolutionChanged: (index) {
        _mutateView(() {
          _selectedResolution = _videoInputResolutions[index];
        });
        unawaited(_clearLocalPreview());
      },
      onFrameRateChanged: (value) {
        _mutateView(() {
          _selectedFrameRate = value;
        });
        unawaited(_clearLocalPreview());
      },
    );
  }

  // Media device セクションへ現在の選択状態と操作 callback を束ねて渡す。
  Widget _buildMediaDeviceSection() {
    return DevToolsMediaDeviceSection(
      isAndroid: Platform.isAndroid,
      needsCamera: _needsCamera,
      cameraSubtitle: _needsCamera
          ? (_selectedVideoInputDevice?.label ?? '')
          : 'Camera is not used in current role',
      selectedAudioInputLabel: _selectedAudioInputDevice == null
          ? 'Unavailable'
          : DevToolsMediaDevicesSupport.formatAudioInputDeviceLabel(
              _selectedAudioInputDevice!,
            ),
      selectedAudioInputDeviceId: _selectedAudioInputDevice?.deviceId,
      selectedAudioOutputDeviceId: _selectedAudioOutputDevice?.deviceId,
      selectedVideoInputDeviceId: _selectedVideoInputDevice?.deviceId,
      audioInputOptions: _audioInputDevices
          .map(
            (device) => DevToolsSelectionOption(
              value: device.deviceId,
              label: DevToolsMediaDevicesSupport.formatAudioInputDeviceLabel(
                device,
              ),
            ),
          )
          .toList(growable: false),
      audioOutputOptions: _audioOutputDevices
          .map(
            (device) => DevToolsSelectionOption(
              value: device.deviceId,
              label: DevToolsMediaDevicesSupport.formatAudioOutputDeviceLabel(
                device,
              ),
            ),
          )
          .toList(growable: false),
      videoInputOptions: _videoInputDevices
          .map(
            (device) => DevToolsSelectionOption(
              value: device.deviceId,
              label: device.label,
            ),
          )
          .toList(growable: false),
      onExpanded: () {
        unawaited(_loadAudioDevices());
      },
      onAudioInputChanged: (deviceId) {
        _mutateView(() {
          _selectedAudioInputDevice = _audioInputDevices.firstWhere(
            (device) => device.deviceId == deviceId,
            orElse: () => _audioInputDevices.first,
          );
        });
      },
      onAudioOutputChanged: (deviceId) {
        if (Platform.isAndroid) {
          final outputDevice = _audioOutputDevices.firstWhere(
            (device) => device.deviceId == deviceId,
            orElse: () => _audioOutputDevices.first,
          );
          final inputDevice =
              DevToolsMediaDevicesSupport.deriveAndroidAudioInputDevice(
                outputDevice: outputDevice,
                inputDevices: _audioInputDevices,
              );
          _mutateView(() {
            _selectedAudioOutputDevice = outputDevice;
            _selectedAudioInputDevice =
                inputDevice ?? _selectedAudioInputDevice;
          });
        } else {
          _mutateView(() {
            _selectedAudioOutputDevice = _audioOutputDevices.firstWhere(
              (device) => device.deviceId == deviceId,
              orElse: () => _audioOutputDevices.first,
            );
          });
        }
        if (_connection != null) {
          unawaited(
            _connectionController.applySelectedAudioOutputDevice(
              _selectedAudioOutputDevice?.deviceId,
            ),
          );
        }
      },
      onVideoInputChanged: (deviceId) {
        unawaited(_selectVideoInputDevice(deviceId));
      },
    );
  }

  // native 側 debug message から接続状態ラベルだけを抽出して反映する。
  void _consumeDebugState(String message) {
    if (!mounted) {
      return;
    }
    _mutateView(() {
      _pageNotifier.applyDebugStateMessage(message);
    });
  }

  // タブリスト
  static const List<Tab> _tabs = <Tab>[
    Tab(icon: Icon(Icons.settings_ethernet), text: 'Connect'),
    Tab(icon: Icon(Icons.videocam), text: 'Video'),
    Tab(icon: Icon(Icons.hub), text: 'RPC'),
    Tab(icon: Icon(Icons.message), text: 'Messages'),
    Tab(icon: Icon(Icons.article), text: 'Diagnostics'),
  ];

  // メッセージタブへ DataChannel メッセージングの送受信 UI を表示する。
  Widget _buildMessageTab() {
    final label = _dataChannelEnabled && _isConnected
        ? _dataChannelLabelController.text.trim()
        : null;
    return DevToolsMessagePanel(
      label: label,
      messages: _messages,
      sendEnabled: _canSendMessage,
      onSend: _handleSendMessage,
    );
  }

  /// 接続、映像、RPC、メッセージング、診断を横断できるタブ構造で画面を構築する。
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pageNotifier,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('sora_sdk DevTools'),
            bottom: TabBar(controller: _tabController, tabs: _tabs),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildConnectionTab(),
              _buildVideoTab(),
              _buildRpcTab(),
              _buildMessageTab(),
              _buildDiagnosticsTab(),
            ],
          ),
        );
      },
    );
  }
}
