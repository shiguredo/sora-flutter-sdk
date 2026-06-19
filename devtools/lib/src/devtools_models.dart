/// DevTools 画面で共有する軽量なモデルと notifier を定義するモジュール。
///
/// UI セクション間で受け渡す値オブジェクトや、画面更新通知に使う
/// 補助型をここに集約する。
library;

import 'package:flutter/material.dart';
import 'package:sora_sdk/sora_sdk.dart';

class DevToolsVideoInputResolutionOption {
  // デバイス列挙結果から得た映像入力解像度を表す。
  const DevToolsVideoInputResolutionOption({
    required this.width,
    required this.height,
  });

  final int width;
  final int height;

  @override
  // ドロップダウン表示用に `WIDTHxHEIGHT` 形式へ変換する。
  String toString() => '${width}x$height';

  @override
  // 幅と高さが一致する解像度を同一値として扱う。
  bool operator ==(Object other) {
    return other is DevToolsVideoInputResolutionOption &&
        other.width == width &&
        other.height == height;
  }

  @override
  // 幅と高さに基づく hash 値を返す。
  int get hashCode => Object.hash(width, height);
}

class DevToolsVideoResolutionOption {
  // 既定解像度候補に使う固定解像度を表す。
  const DevToolsVideoResolutionOption(this.width, this.height);

  final int width;
  final int height;

  static const DevToolsVideoResolutionOption qqvgaLandscape =
      DevToolsVideoResolutionOption(160, 120);
  static const DevToolsVideoResolutionOption qcifLandscape =
      DevToolsVideoResolutionOption(176, 144);
  static const DevToolsVideoResolutionOption hqvgaLandscape =
      DevToolsVideoResolutionOption(240, 160);
  static const DevToolsVideoResolutionOption qvgaLandscape =
      DevToolsVideoResolutionOption(320, 240);
  static const DevToolsVideoResolutionOption vgaLandscape =
      DevToolsVideoResolutionOption(640, 480);
  static const DevToolsVideoResolutionOption qhdLandscape =
      DevToolsVideoResolutionOption(960, 540);
  static const DevToolsVideoResolutionOption hdLandscape =
      DevToolsVideoResolutionOption(1280, 720);
  static const DevToolsVideoResolutionOption fhdLandscape =
      DevToolsVideoResolutionOption(1920, 1080);

  static const List<DevToolsVideoResolutionOption> presets =
      <DevToolsVideoResolutionOption>[
        qqvgaLandscape,
        qcifLandscape,
        hqvgaLandscape,
        qvgaLandscape,
        vgaLandscape,
        qhdLandscape,
        hdLandscape,
        fhdLandscape,
      ];
  static const int defaultLandscapeIndex = 4;
}

class DevToolsRemoteClientInfo {
  // Remote client の接続情報を保持する。
  const DevToolsRemoteClientInfo({required this.connectionId, this.clientId});

  final String connectionId;
  final String? clientId;
}

enum DevToolsLogTab { app, event, timeline, stats }

class DevToolsMessageEntry {
  const DevToolsMessageEntry({
    required this.timestamp,
    required this.label,
    required this.text,
    required this.isSent,
  });

  final DateTime timestamp;
  final String label;
  final String text;
  final bool isSent;
}

class DevToolsPageNotifier extends ChangeNotifier {
  // 現在の接続状態を保持する。
  SoraConnectionState state = const SoraDisconnectedState();
  // 切断時に受け取った close code / reason を保持する。
  SoraDisconnectCloseInfo? disconnectCloseInfo;
  // 接続エラーコードを保持する。
  String? connectionErrorCode;
  // 接続エラーメッセージを保持する。
  String? connectionErrorMessage;
  // 受信中のリモート映像トラック一覧を保持する。
  final List<RemoteMediaStreamTrack> remoteVideos = <RemoteMediaStreamTrack>[];
  // 受信中のリモート音声トラック一覧を保持する。
  final List<RemoteMediaStreamTrack> remoteAudios = <RemoteMediaStreamTrack>[];
  // リモート接続先の補助情報を保持する。
  final List<DevToolsRemoteClientInfo> remoteClients =
      <DevToolsRemoteClientInfo>[];
  // ローカルプレビューに使う texture ID を保持する。
  int? localTextureId;
  // 接続・切断・切り替えなどの進行中フラグを保持する。
  bool busy = false;
  // アプリログを保持する。
  final List<String> logs = <String>[];
  // イベントログを保持する。
  final List<String> eventLogs = <String>[];
  // timeline ログを保持する。
  final List<String> timelineLogs = <String>[];
  // stats ログを保持する。
  final List<String> statsLogs = <String>[];
  // PeerConnection state の表示文字列を保持する。
  String peerConnectionStateLabel = 'disconnected';
  // ICE state の表示文字列を保持する。
  String iceStateLabel = 'unknown';
  // DTLS state の表示文字列を保持する。
  String dtlsStateLabel = 'unknown';
  // ログ画面で選択中のタブを保持する。
  DevToolsLogTab selectedLogTab = DevToolsLogTab.app;
  // RPC 実行中フラグを保持する。
  bool rpcBusy = false;

  // ローカルプレビューの水平反転を有効にするかどうかを保持する。
  //
  // デフォルト true: 一般的なカメラプレビューと同様に鏡表示にする。
  bool localPreviewMirror = true;
  // 接続中 audio track の enabled 状態を保持する。
  bool audioEnabled = true;
  // 接続中 video track の enabled 状態を保持する。
  bool videoEnabled = true;
  // connect 時に audio を送るかどうかを保持する。
  bool connectAudio = true;
  // connect 時に video を送るかどうかを保持する。
  bool connectVideo = true;
  // 現在選択中の role を保持する。
  SoraRole selectedRole = SoraRole.sendrecv;
  // 列挙した映像入力デバイス一覧を保持する。
  List<VideoInputDevice> videoInputDevices = <VideoInputDevice>[];
  // 現在選択中の映像入力デバイスを保持する。
  VideoInputDevice? selectedVideoInputDevice;
  // 列挙した音声入力デバイス一覧を保持する。
  List<AudioInputDevice> audioInputDevices = <AudioInputDevice>[];
  // 現在選択中の音声入力デバイスを保持する。
  AudioInputDevice? selectedAudioInputDevice;
  // 列挙した音声出力デバイス一覧を保持する。
  List<AudioOutputDevice> audioOutputDevices = <AudioOutputDevice>[];
  // 現在選択中の音声出力デバイスを保持する。
  AudioOutputDevice? selectedAudioOutputDevice;
  // 選択可能な映像入力解像度一覧を保持する。
  List<DevToolsVideoInputResolutionOption> videoInputResolutions =
      <DevToolsVideoInputResolutionOption>[];
  // 現在選択中の映像入力解像度を保持する。
  DevToolsVideoInputResolutionOption? selectedResolution;
  // 現在選択中のフレームレートを保持する。
  int? selectedFrameRate;
  // 現在選択中の映像コーデックを保持する。
  String? selectedVideoCodecType;
  // 現在選択中の映像ビットレートを保持する。
  int? selectedVideoBitRate;
  // simulcast の有効状態を保持する。
  bool simulcastEnabled = false;
  // 現在選択中の simulcast request RID を保持する。
  String? selectedSimulcastRid;
  // spotlight の有効状態を保持する。
  bool spotlightEnabled = false;
  // 現在選択中の spotlight focus RID を保持する。
  String? selectedSpotlightFocusRid;
  // 現在選択中の spotlight unfocus RID を保持する。
  String? selectedSpotlightUnfocusRid;
  // offer から得た RPC method 一覧を保持する。
  List<String> availableRpcMethods = <String>[];
  // 現在選択中の RPC method を保持する。
  String? selectedRpcMethod;
  // RPC を notification として送るかどうかを保持する。
  bool rpcNotification = false;
  // RPC 実行結果の表示文字列を保持する。
  String? rpcResult;

  // DataChannel messaging 用の状態。

  // 送受信メッセージの履歴。
  final List<DevToolsMessageEntry> messages = <DevToolsMessageEntry>[];

  // 送受信メッセージを履歴に追加する。
  // notifyListeners() は呼ばない（呼び出し元の _mutateView → mutate() 経由で発火させる）。
  void addMessage(DevToolsMessageEntry entry) {
    messages.add(entry);
  }

  // RPC 実行を開始する。
  void startRpc() {
    rpcBusy = true;
    rpcResult = null;
    notifyListeners();
  }

  // RPC 実行結果を反映する。
  void finishRpc(String resultText) {
    rpcBusy = false;
    rpcResult = resultText;
    notifyListeners();
  }

  // offer から得た RPC method 一覧と選択状態を同期する。
  String? syncRpcMethods(List<String> methods) {
    final nextSelected = methods.contains(selectedRpcMethod)
        ? selectedRpcMethod
        : (methods.isNotEmpty ? methods.first : null);
    mutate(() {
      availableRpcMethods = methods;
      selectedRpcMethod = nextSelected;
    });
    return nextSelected;
  }

  // 接続開始直前の画面状態へ初期化する。
  void prepareForConnect({
    required bool audioEnabledValue,
    required bool videoEnabledValue,
  }) {
    busy = true;
    disconnectCloseInfo = null;
    connectionErrorCode = null;
    connectionErrorMessage = null;
    remoteAudios.clear();
    remoteVideos.clear();
    remoteClients.clear();
    localTextureId = null;
    eventLogs.clear();
    timelineLogs.clear();
    statsLogs.clear();
    messages.clear();
    audioEnabled = audioEnabledValue;
    videoEnabled = videoEnabledValue;
  }

  // 切断後の画面状態へ戻す。
  // [notify] が true の場合のみ [notifyListeners] を呼ぶ（mounted 判定を呼び出し側から受け取るため）。
  void resetAfterDisconnect({
    required bool audioEnabledValue,
    required bool videoEnabledValue,
    required bool notify,
  }) {
    audioEnabled = audioEnabledValue;
    videoEnabled = videoEnabledValue;
    remoteAudios.clear();
    remoteVideos.clear();
    remoteClients.clear();
    messages.clear();
    if (notify) notifyListeners();
  }

  // 購読や接続を破棄したあとの画面状態を初期化する。
  void resetDisposedClientState({
    required bool audioEnabledValue,
    required bool videoEnabledValue,
  }) {
    availableRpcMethods = <String>[];
    selectedRpcMethod = null;
    rpcResult = null;
    audioEnabled = audioEnabledValue;
    videoEnabled = videoEnabledValue;
    remoteAudios.clear();
    remoteVideos.clear();
    remoteClients.clear();
    messages.clear();
  }

  // 状態変更を伴わずにアプリログへ 1 行追加する。
  void addLog(String line) {
    logs.add(line);
  }

  // 状態変更を伴わずにイベントログへ 1 行追加する。
  void addEventLog(String line) {
    eventLogs.add(line);
  }

  // 状態変更を伴わずに timeline ログへ 1 行追加する。
  void addTimelineLog(String line) {
    timelineLogs.add(line);
  }

  // 状態変更を伴わずに stats ログへ 1 行追加する。
  void addStatsLog(String line) {
    statsLogs.add(line);
  }

  // ログ画面で選択中のログ一覧を返す。
  List<String> get selectedLogs => switch (selectedLogTab) {
    DevToolsLogTab.app => logs,
    DevToolsLogTab.event => eventLogs,
    DevToolsLogTab.timeline => timelineLogs,
    DevToolsLogTab.stats => statsLogs,
  };

  // 接続状態イベントを画面状態へ反映する。
  void applyConnectionState(SoraConnectionState nextState) {
    state = nextState;
    if (nextState case SoraDisconnectedState(:final closeInfo)) {
      disconnectCloseInfo = closeInfo;
      iceStateLabel = 'disconnected';
      dtlsStateLabel = 'unknown';
      remoteVideos.clear();
      remoteAudios.clear();
      remoteClients.clear();
    } else {
      disconnectCloseInfo = null;
    }
    connectionErrorCode = null;
    connectionErrorMessage = null;
    peerConnectionStateLabel = switch (nextState) {
      SoraConnectingState() => 'connecting',
      SoraConnectedState() => 'connected',
      SoraDisconnectedState() => 'disconnected',
    };
  }

  // 接続エラーイベントを画面状態へ反映する。
  void applyConnectionError({required String? code, required String? message}) {
    connectionErrorCode = code;
    connectionErrorMessage = message;
  }

  // remote client 一覧へ接続情報を追加または更新する。
  void upsertRemoteClients(List<DevToolsRemoteClientInfo> clients) {
    for (final client in clients) {
      final index = remoteClients.indexWhere(
        (candidate) => candidate.connectionId == client.connectionId,
      );
      if (index == -1) {
        remoteClients.add(client);
      } else {
        remoteClients[index] = client;
      }
    }
  }

  // remote client 一覧から指定 connection ID 群を削除する。
  void removeRemoteClientsByConnectionIds(Set<String> connectionIds) {
    remoteClients.removeWhere(
      (remoteClient) => connectionIds.contains(remoteClient.connectionId),
    );
  }

  // remote track を追加または更新する。
  void upsertRemoteTrack(RemoteMediaStreamTrack track) {
    if (track.kind == 'video') {
      remoteVideos.removeWhere(
        (candidate) => candidate.trackId == track.trackId,
      );
      remoteVideos.add(track);
    } else if (track.kind == 'audio') {
      remoteAudios.removeWhere(
        (candidate) => candidate.trackId == track.trackId,
      );
      remoteAudios.add(track);
    }
    if (!remoteClients.any(
      (client) => client.connectionId == track.connectionId,
    )) {
      remoteClients.add(
        DevToolsRemoteClientInfo(connectionId: track.connectionId),
      );
    }
  }

  // remote track を削除する。
  void removeRemoteTrack(RemoteMediaStreamTrack track) {
    if (track.kind == 'video') {
      remoteVideos.removeWhere(
        (candidate) => candidate.trackId == track.trackId,
      );
    } else if (track.kind == 'audio') {
      remoteAudios.removeWhere(
        (candidate) => candidate.trackId == track.trackId,
      );
    }
  }

  // native debug message から接続状態ラベルを反映する。
  void applyDebugStateMessage(String message) {
    const pcPrefix = 'native: pc_state=';
    const icePrefix = 'native: ice_connection_state=';
    const dtlsPrefix = 'native: dtls_state=';
    if (message.startsWith(pcPrefix)) {
      peerConnectionStateLabel = message.substring(pcPrefix.length);
      return;
    }
    if (message.startsWith(icePrefix)) {
      iceStateLabel = message.substring(icePrefix.length);
      return;
    }
    if (message.startsWith(dtlsPrefix)) {
      dtlsStateLabel = message.substring(dtlsPrefix.length);
    }
  }

  // 接続前の audio 設定と表示状態を同期する。
  // notifyListeners() は呼ばない（呼び出し元の _mutateView → mutate() 経由で発火させる）。
  void setConnectAudio(bool value) {
    connectAudio = value;
    audioEnabled = value;
  }

  // 接続前の video 設定と表示状態を同期する。
  // notifyListeners() は呼ばない（呼び出し元の _mutateView → mutate() 経由で発火させる）。
  void setConnectVideo(bool value) {
    connectVideo = value;
    videoEnabled = value;
    if (!value) {
      localTextureId = null;
    }
  }

  // audio enabled の切り替えを notifier 側の状態へ反映する。
  void applyToggleAudio(bool enabled, {bool isConnected = false}) {
    if (!isConnected) {
      connectAudio = enabled;
    }
    audioEnabled = enabled;
  }

  // video enabled の切り替えを notifier 側の状態へ反映する。
  void applyToggleVideo(bool enabled, {bool isConnected = false}) {
    if (!isConnected) {
      connectVideo = enabled;
    }
    videoEnabled = enabled;
  }

  // 状態更新と再描画通知を 1 つの呼び出しにまとめる。
  void mutate(VoidCallback update) {
    update();
    notifyListeners();
  }
}

class DevToolsSelectionOption {
  // `DropdownButton` 系に渡す value と label の組を表す。
  const DevToolsSelectionOption({required this.value, required this.label});

  final String value;
  final String label;
}
