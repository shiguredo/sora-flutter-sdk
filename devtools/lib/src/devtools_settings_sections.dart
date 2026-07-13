/// DevTools 画面の設定 / 操作系セクション UI をまとめるモジュール。
///
/// 各 Widget は状態を保持せず、`main.dart` 側から受け取った値と
/// callback を用いて表示と操作イベント通知だけを担当する。
///
/// セクション間で共有する簡単な装飾 Widget もこのモジュールに含める。
library;

import 'package:flutter/material.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_models.dart';

class DevToolsActionSection extends StatelessWidget {
  const DevToolsActionSection({
    super.key,
    required this.busy,
    required this.isConnecting,
    required this.isConnected,
    required this.onConnectionButtonPressed,
    this.audioEnabled = false,
    this.videoEnabled = false,
    this.canToggleAudioEnabled = false,
    this.canToggleVideoEnabled = false,
    this.onToggleAudioEnabled,
    this.onToggleVideoEnabled,
  });

  static const double _compactMaxWidth = 520;

  // 非同期処理中かどうか
  final bool busy;

  // 接続処理中かどうか
  final bool isConnecting;

  // 現在接続済みかどうか
  final bool isConnected;

  // 現在の音声トラック有効状態
  final bool audioEnabled;

  // 現在の映像トラック有効状態
  final bool videoEnabled;

  // 音声トラックの有効 / 無効を切り替え可能かどうか
  final bool canToggleAudioEnabled;

  // 映像トラックの有効 / 無効を切り替え可能かどうか
  final bool canToggleVideoEnabled;

  // 接続 / 切断ボタン押下時の処理
  final VoidCallback onConnectionButtonPressed;

  // 音声トラック有効状態の切り替え処理
  final VoidCallback? onToggleAudioEnabled;

  // 映像トラック有効状態の切り替え処理
  final VoidCallback? onToggleVideoEnabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackToggles = onToggleAudioEnabled != null
            ? _buildTrackToggles()
            : null;
        if (constraints.maxWidth < _compactMaxWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildConnectionButton(),
              if (trackToggles != null) ...[
                const SizedBox(height: 12),
                trackToggles,
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildConnectionButton(),
            if (trackToggles != null) ...[
              const SizedBox(width: 16),
              Expanded(child: trackToggles),
            ],
          ],
        );
      },
    );
  }

  Widget _buildConnectionButton() {
    return FilledButton(
      onPressed: busy || isConnecting ? null : onConnectionButtonPressed,
      child: Text(isConnected ? 'Disconnect' : 'Connect'),
    );
  }

  Widget _buildTrackToggles() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _DevToolsTrackSwitch(
          label: 'Audio Track',
          value: audioEnabled,
          onChanged: canToggleAudioEnabled && onToggleAudioEnabled != null
              ? (_) => onToggleAudioEnabled!()
              : null,
        ),
        _DevToolsTrackSwitch(
          label: 'Video Track',
          value: videoEnabled,
          onChanged: canToggleVideoEnabled && onToggleVideoEnabled != null
              ? (_) => onToggleVideoEnabled!()
              : null,
        ),
      ],
    );
  }
}

class _DevToolsTrackSwitch extends StatelessWidget {
  const _DevToolsTrackSwitch({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.constrainWidth(220),
          child: Row(
            children: [
              Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
        );
      },
    );
  }
}

class DevToolsConnectionStatusSection extends StatelessWidget {
  const DevToolsConnectionStatusSection({
    super.key,
    required this.connectionStateLabel,
    required this.peerConnectionStateLabel,
    required this.iceStateLabel,
    required this.dtlsStateLabel,
    required this.sessionId,
    required this.connectionId,
    required this.clientId,
    required this.disconnectCloseInfo,
    required this.connectionErrorCode,
    required this.connectionErrorMessage,
  });

  // 接続状態表示ラベル
  final String connectionStateLabel;

  // PeerConnection 状態表示ラベル
  final String peerConnectionStateLabel;

  // ICE 状態表示ラベル
  final String iceStateLabel;

  // DTLS 状態表示ラベル
  final String dtlsStateLabel;

  // 現在のセッション ID
  final String? sessionId;

  // 現在の connection ID
  final String? connectionId;

  // 現在の client ID
  final String? clientId;

  // 切断時に返された close 情報
  final SoraDisconnectCloseInfo? disconnectCloseInfo;

  // 接続エラーコード
  final String? connectionErrorCode;

  // 接続エラーメッセージ
  final String? connectionErrorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('State: $connectionStateLabel'),
        const SizedBox(height: 4),
        Text('PeerConnection: $peerConnectionStateLabel'),
        Text('ICE: $iceStateLabel'),
        Text('DTLS: $dtlsStateLabel'),
        if (sessionId != null) Text('Session ID: $sessionId'),
        if (connectionId != null) Text('Connection ID: $connectionId'),
        if (clientId != null) Text('Client ID: $clientId'),
        if (disconnectCloseInfo != null) ...[
          const SizedBox(height: 4),
          Text('Close Code: ${disconnectCloseInfo!.code}'),
          if (disconnectCloseInfo!.reason case final reason?)
            Text('Close Reason: $reason'),
        ],
        if (connectionErrorCode != null || connectionErrorMessage != null) ...[
          const SizedBox(height: 4),
          if (connectionErrorCode != null)
            Text('Error Code: $connectionErrorCode'),
          if (connectionErrorMessage != null)
            Text('Error Message: $connectionErrorMessage'),
        ],
      ],
    );
  }
}

class DevToolsRpcRequestSection extends StatelessWidget {
  const DevToolsRpcRequestSection({
    super.key,
    required this.selectedRpcMethod,
    required this.availableRpcMethods,
    required this.rpcNotification,
    required this.rpcBusy,
    required this.canSendRpc,
    required this.rpcResult,
    required this.rpcTimeoutController,
    required this.rpcParamsController,
    this.initiallyExpanded = false,
    required this.onRpcMethodChanged,
    required this.onRpcNotificationChanged,
    required this.onApplyTemplate,
    required this.onSendRpc,
  });

  // 現在選択中の RPC メソッド
  final String? selectedRpcMethod;

  // 選択可能な RPC メソッド一覧
  final List<String> availableRpcMethods;

  // notification モードで送信するかどうか
  final bool rpcNotification;

  // RPC 送信処理中かどうか
  final bool rpcBusy;

  // RPC を送信できる状態かどうか
  final bool canSendRpc;

  // RPC 実行結果表示文字列
  final String? rpcResult;

  // RPC タイムアウト入力欄の controller
  final TextEditingController rpcTimeoutController;

  // RPC パラメータ入力欄の controller
  final TextEditingController rpcParamsController;

  // 初期表示時にセクションを展開するかどうか
  final bool initiallyExpanded;

  // RPC メソッド変更時の処理
  final ValueChanged<String> onRpcMethodChanged;

  // notification 設定変更時の処理
  final ValueChanged<bool> onRpcNotificationChanged;

  // テンプレート適用時の処理
  final VoidCallback onApplyTemplate;

  // RPC 送信時の処理
  final VoidCallback onSendRpc;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: const Text('RPC Request'),
        subtitle: null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: selectedRpcMethod,
                  decoration: const InputDecoration(
                    labelText: 'RPC Method',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: availableRpcMethods.map((method) {
                    return DropdownMenuItem<String>(
                      value: method,
                      child: Text(method, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: availableRpcMethods.isEmpty
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          onRpcMethodChanged(value);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: rpcTimeoutController,
                  decoration: const InputDecoration(
                    labelText: 'RPC Timeout (ms)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<bool>(
                  initialValue: rpcNotification,
                  decoration: const InputDecoration(
                    labelText: 'Notification',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const <DropdownMenuItem<bool>>[
                    DropdownMenuItem<bool>(
                      value: false,
                      child: Text('Response Required'),
                    ),
                    DropdownMenuItem<bool>(
                      value: true,
                      child: Text('Notification Only'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    onRpcNotificationChanged(value);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: rpcParamsController,
            minLines: 6,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'RPC Params (JSON)',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton(
                onPressed: selectedRpcMethod == null ? null : onApplyTemplate,
                child: const Text('Apply Template'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: canSendRpc ? onSendRpc : null,
                child: Text(rpcBusy ? 'Sending...' : 'Send RPC'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFF7F7F7),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD8D8D8)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                rpcResult ?? 'No RPC result',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DevToolsMediaDeviceSection extends StatelessWidget {
  const DevToolsMediaDeviceSection({
    super.key,
    required this.isAndroid,
    required this.needsCamera,
    required this.canChangeAudioInput,
    required this.canChangeAudioOutput,
    required this.canChangeVideoInput,
    required this.cameraSubtitle,
    required this.selectedAudioInputLabel,
    required this.selectedAudioInputDeviceId,
    required this.selectedAudioOutputDeviceId,
    required this.selectedVideoInputDeviceId,
    required this.audioInputOptions,
    required this.audioOutputOptions,
    required this.videoInputOptions,
    required this.onExpanded,
    required this.onAudioInputChanged,
    required this.onAudioOutputChanged,
    required this.onVideoInputChanged,
  });

  // Android 固有 UI を表示するかどうか
  final bool isAndroid;

  // カメラ入力が必要な状態かどうか
  final bool needsCamera;

  // Audio Input を次回接続用に変更できるかどうか。
  final bool canChangeAudioInput;

  // Audio Route を変更できるかどうか。
  final bool canChangeAudioOutput;

  // Camera を次回接続用に変更できるかどうか。
  final bool canChangeVideoInput;

  // タイル見出し下に表示するカメラ情報
  final String cameraSubtitle;

  // Android で表示する現在の Audio Input ラベル
  final String selectedAudioInputLabel;

  // 現在選択中の Audio Input deviceId
  final String? selectedAudioInputDeviceId;

  // 現在選択中の Audio Output deviceId
  final String? selectedAudioOutputDeviceId;

  // 現在選択中の Camera deviceId
  final String? selectedVideoInputDeviceId;

  // Audio Input 選択肢一覧
  final List<DevToolsSelectionOption> audioInputOptions;

  // Audio Output 選択肢一覧
  final List<DevToolsSelectionOption> audioOutputOptions;

  // Camera 選択肢一覧
  final List<DevToolsSelectionOption> videoInputOptions;

  // 展開時にデバイス一覧を更新する処理
  final VoidCallback onExpanded;

  // Audio Input 選択変更時の処理
  final ValueChanged<String> onAudioInputChanged;

  // Audio Output 選択変更時の処理
  final ValueChanged<String> onAudioOutputChanged;

  // Camera 選択変更時の処理
  final ValueChanged<String> onVideoInputChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (expanded) {
          if (!expanded) {
            return;
          }
          onExpanded();
        },
        title: const Text('Media Device'),
        subtitle: Text(cameraSubtitle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isAndroid) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String?>(selectedAudioOutputDeviceId),
                    initialValue: selectedAudioOutputDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'Audio Route',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText:
                          'Android は communication route が input / output に連動します。',
                    ),
                    items: audioOutputOptions.map((option) {
                      return DropdownMenuItem(
                        value: option.value,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: canChangeAudioOutput
                        ? (deviceId) {
                            if (deviceId == null) {
                              return;
                            }
                            onAudioOutputChanged(deviceId);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Audio Input',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: 'Android は Audio Route から自動選択します。',
                    ),
                    child: Text(
                      selectedAudioInputLabel,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String?>(selectedAudioInputDeviceId),
                    initialValue: selectedAudioInputDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'Audio Input',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: audioInputOptions.map((option) {
                      return DropdownMenuItem(
                        value: option.value,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: canChangeAudioInput
                        ? (deviceId) {
                            if (deviceId == null) {
                              return;
                            }
                            onAudioInputChanged(deviceId);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ],
          if (needsCamera) ...[const SizedBox(height: 8)],
          if (needsCamera) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String?>(selectedVideoInputDeviceId),
                    initialValue: selectedVideoInputDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'Camera',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: videoInputOptions.map((option) {
                      return DropdownMenuItem(
                        value: option.value,
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: canChangeVideoInput
                        ? (deviceId) {
                            if (deviceId == null) {
                              return;
                            }
                            onVideoInputChanged(deviceId);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ] else ...[
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Current role and media settings do not require camera input.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class DevToolsConnectionSettingsSection extends StatelessWidget {
  const DevToolsConnectionSettingsSection({
    super.key,
    required this.signalingUrlController,
    required this.channelIdController,
    required this.clientIdController,
    required this.bundleIdController,
    required this.metadataController,
    required this.signalingNotifyMetadataController,
    required this.audioBitRateController,
    required this.videoVp9ParamsController,
    required this.videoH264ParamsController,
    required this.videoH265ParamsController,
    required this.videoAv1ParamsController,
    required this.forwardingFiltersController,
    required this.connectionTimeoutController,
    required this.disconnectWaitTimeoutController,
    required this.signalingCandidateTimeoutController,
    required this.selectedRole,
    required this.simulcastEnabled,
    required this.selectedSimulcastRid,
    required this.spotlightEnabled,
    required this.selectedSpotlightFocusRid,
    required this.selectedSpotlightUnfocusRid,
    required this.connectAudio,
    required this.connectVideo,
    required this.beepAudioEnabled,
    required this.useAudioDevice,
    required this.useAudioDeviceEditable,
    required this.isAndroid,
    required this.needsCamera,
    required this.connectionParametersEditable,
    required this.canEditSimulcastRequestRid,
    required this.canEditSpotlightRid,
    required this.selectedVideoCodecType,
    required this.selectedVideoBitRate,
    required this.selectedAudioCodecType,
    required this.selectedResolutionIndex,
    required this.selectedFrameRate,
    required this.simulcastRidOptions,
    required this.videoCodecTypeOptions,
    required this.videoBitRateOptions,
    required this.frameRateOptions,
    required this.resolutionLabels,
    required this.onRoleChanged,
    required this.onSimulcastEnabledChanged,
    required this.onSimulcastRidChanged,
    required this.onSpotlightEnabledChanged,
    required this.onSpotlightFocusRidChanged,
    required this.onSpotlightUnfocusRidChanged,
    required this.onConnectAudioChanged,
    required this.onConnectVideoChanged,
    required this.onBeepAudioEnabledChanged,
    required this.onUseAudioDeviceChanged,
    required this.onAudioCodecTypeChanged,
    required this.onVideoCodecTypeChanged,
    required this.onVideoBitRateChanged,
    required this.onResolutionChanged,
    required this.onFrameRateChanged,
    this.signalingUrlValidator,
    this.channelIdValidator,
    this.metadataValidator,
    this.signalingNotifyMetadataValidator,
    this.audioBitRateValidator,
    this.videoCodecParamsValidator,
    this.forwardingFiltersValidator,
    this.timeoutValidator,
  });

  // シグナリング URL 入力欄の controller
  final TextEditingController signalingUrlController;

  // Channel ID 入力欄の controller
  final TextEditingController channelIdController;

  // クライアント識別子入力欄の controller
  final TextEditingController clientIdController;

  // bundle ID 入力欄の controller
  final TextEditingController bundleIdController;

  // connect metadata 入力欄の controller
  final TextEditingController metadataController;

  // signaling notify metadata 入力欄の controller
  final TextEditingController signalingNotifyMetadataController;

  // 音声ビットレート入力欄の controller
  final TextEditingController audioBitRateController;

  // 映像コーデック別追加パラメータ入力欄の controller
  final TextEditingController videoVp9ParamsController;
  final TextEditingController videoH264ParamsController;
  final TextEditingController videoH265ParamsController;
  final TextEditingController videoAv1ParamsController;

  // forwarding filters 入力欄の controller
  final TextEditingController forwardingFiltersController;

  // 接続ライフサイクルのタイムアウト入力欄の controller
  final TextEditingController connectionTimeoutController;
  final TextEditingController disconnectWaitTimeoutController;
  final TextEditingController signalingCandidateTimeoutController;

  // シグナリング URL の入力検証。
  final FormFieldValidator<String>? signalingUrlValidator;

  // Channel ID の入力検証。
  final FormFieldValidator<String>? channelIdValidator;

  // JSON および数値入力の検証。
  final FormFieldValidator<String>? metadataValidator;
  final FormFieldValidator<String>? signalingNotifyMetadataValidator;
  final FormFieldValidator<String>? audioBitRateValidator;
  final FormFieldValidator<String>? videoCodecParamsValidator;
  final FormFieldValidator<String>? forwardingFiltersValidator;
  final FormFieldValidator<String>? timeoutValidator;

  // 現在選択中の role
  final SoraRole selectedRole;

  // simulcast が有効かどうか
  final bool simulcastEnabled;

  // 現在選択中の simulcast_request_rid
  final String? selectedSimulcastRid;

  // spotlight が有効かどうか
  final bool spotlightEnabled;

  // 現在選択中の spotlight_focus_rid
  final String? selectedSpotlightFocusRid;

  // 現在選択中の spotlight_unfocus_rid
  final String? selectedSpotlightUnfocusRid;

  // 音声接続を有効にするかどうか
  final bool connectAudio;

  // 映像接続を有効にするかどうか
  final bool connectVideo;

  // beep 音声送信が有効かどうか
  final bool beepAudioEnabled;

  // 実音声デバイスを利用するかどうか。
  final bool useAudioDevice;

  // 実音声デバイス利用設定を編集できるかどうか。
  final bool useAudioDeviceEditable;

  // Android 上で動作しているかどうか。
  final bool isAndroid;

  // 現在の設定でカメラが必要かどうか
  final bool needsCamera;

  // 接続確立パラメータを編集できるかどうか。
  final bool connectionParametersEditable;

  // simulcast_request_rid を編集可能かどうか
  final bool canEditSimulcastRequestRid;

  // spotlight rid を編集可能かどうか
  final bool canEditSpotlightRid;

  // 現在選択中の Video Codec
  final String? selectedVideoCodecType;

  // 現在選択中の Video Bitrate
  final int? selectedVideoBitRate;

  // 現在選択中の Audio Codec
  final String? selectedAudioCodecType;

  // 現在選択中の Resolution の index
  final int? selectedResolutionIndex;

  // 現在選択中の Framerate
  final int? selectedFrameRate;

  // simulcast rid 選択肢一覧
  final List<String> simulcastRidOptions;

  // video codec 選択肢一覧
  final List<String> videoCodecTypeOptions;

  // video bitrate 選択肢一覧
  final List<int> videoBitRateOptions;

  // frame rate 選択肢一覧
  final List<int> frameRateOptions;

  // resolution 表示ラベル一覧
  final List<String> resolutionLabels;

  // role 変更時の処理
  final ValueChanged<SoraRole> onRoleChanged;

  // simulcast 有効状態変更時の処理
  final ValueChanged<bool> onSimulcastEnabledChanged;

  // simulcast_request_rid 変更時の処理
  final ValueChanged<String?> onSimulcastRidChanged;

  // spotlight 有効状態変更時の処理
  final ValueChanged<bool> onSpotlightEnabledChanged;

  // spotlight_focus_rid 変更時の処理
  final ValueChanged<String?> onSpotlightFocusRidChanged;

  // spotlight_unfocus_rid 変更時の処理
  final ValueChanged<String?> onSpotlightUnfocusRidChanged;

  // 音声接続設定変更時の処理
  final ValueChanged<bool> onConnectAudioChanged;

  // 映像接続設定変更時の処理
  final ValueChanged<bool> onConnectVideoChanged;

  // beep 音声送信設定変更時の処理
  final ValueChanged<bool> onBeepAudioEnabledChanged;

  // 実音声デバイス利用設定変更時の処理
  final ValueChanged<bool> onUseAudioDeviceChanged;

  // Audio Codec 変更時の処理
  final ValueChanged<String?> onAudioCodecTypeChanged;

  // Video Codec 変更時の処理
  final ValueChanged<String?> onVideoCodecTypeChanged;

  // Video Bitrate 変更時の処理
  final ValueChanged<int?> onVideoBitRateChanged;

  // Resolution 変更時の処理
  final ValueChanged<int> onResolutionChanged;

  // Framerate 変更時の処理
  final ValueChanged<int?> onFrameRateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DevToolsSettingsGroup(
          title: 'Signaling',
          initiallyExpanded: true,
          enabled: connectionParametersEditable,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: signalingUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Signaling URL',
                      border: OutlineInputBorder(),
                      helperText: '1 行につき 1 URL。上から順にフェイルオーバーします。',
                    ),
                    validator: signalingUrlValidator,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    minLines: 1,
                    maxLines: 4,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: channelIdController,
                    decoration: const InputDecoration(
                      labelText: 'Channel ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: channelIdValidator,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: clientIdController,
                    decoration: const InputDecoration(
                      labelText: 'Client ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: bundleIdController,
                    decoration: const InputDecoration(
                      labelText: 'Bundle ID',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: metadataController,
              decoration: const InputDecoration(
                labelText: 'Metadata (JSON)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: metadataValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: signalingNotifyMetadataController,
              decoration: const InputDecoration(
                labelText: 'Signaling Notify Metadata (JSON)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: signalingNotifyMetadataValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 5,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SoraRole>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: SoraRole.values.map((role) {
                      return DropdownMenuItem(
                        value: role,
                        child: Text(role.value),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      onRoleChanged(value);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Simulcast',
          subtitle: simulcastEnabled ? 'Enabled' : 'Disabled',
          enabled: connectionParametersEditable,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    initialValue: simulcastEnabled,
                    decoration: const InputDecoration(
                      labelText: 'Simulcast',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: const <DropdownMenuItem<bool>>[
                      DropdownMenuItem<bool>(
                        value: false,
                        child: Text('Disabled'),
                      ),
                      DropdownMenuItem<bool>(
                        value: true,
                        child: Text('Enabled'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      onSimulcastEnabledChanged(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedSimulcastRid,
                    decoration: const InputDecoration(
                      labelText: 'simulcast_request_rid',
                      border: OutlineInputBorder(),
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...simulcastRidOptions.map((rid) {
                        return DropdownMenuItem<String?>(
                          value: rid,
                          child: Text(rid),
                        );
                      }),
                    ],
                    onChanged: canEditSimulcastRequestRid
                        ? onSimulcastRidChanged
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Spotlight',
          subtitle: spotlightEnabled ? 'Enabled' : 'Disabled',
          enabled: connectionParametersEditable,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    initialValue: spotlightEnabled,
                    decoration: const InputDecoration(
                      labelText: 'Spotlight',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: const <DropdownMenuItem<bool>>[
                      DropdownMenuItem<bool>(
                        value: false,
                        child: Text('Disabled'),
                      ),
                      DropdownMenuItem<bool>(
                        value: true,
                        child: Text('Enabled'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      onSpotlightEnabledChanged(value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedSpotlightFocusRid,
                    decoration: const InputDecoration(
                      labelText: 'spotlight_focus_rid',
                      border: OutlineInputBorder(),
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...simulcastRidOptions.map((rid) {
                        return DropdownMenuItem<String?>(
                          value: rid,
                          child: Text(rid),
                        );
                      }),
                    ],
                    onChanged: canEditSpotlightRid
                        ? onSpotlightFocusRidChanged
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedSpotlightUnfocusRid,
                    decoration: const InputDecoration(
                      labelText: 'spotlight_unfocus_rid',
                      border: OutlineInputBorder(),
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...simulcastRidOptions.map((rid) {
                        return DropdownMenuItem<String?>(
                          value: rid,
                          child: Text(rid),
                        );
                      }),
                    ],
                    onChanged: canEditSpotlightRid
                        ? onSpotlightUnfocusRidChanged
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Media',
          initiallyExpanded: true,
          enabled: connectionParametersEditable,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 400) {
                  return Column(
                    children: [
                      DropdownButtonFormField<bool>(
                        initialValue: connectAudio,
                        decoration: const InputDecoration(
                          labelText: 'Connect Audio',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: null,
                        ),
                        items: const <DropdownMenuItem<bool>>[
                          DropdownMenuItem<bool>(
                            value: true,
                            child: Text('Enabled'),
                          ),
                          DropdownMenuItem<bool>(
                            value: false,
                            child: Text('Disabled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onConnectAudioChanged(value);
                        },
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<bool>(
                        initialValue: connectVideo,
                        decoration: const InputDecoration(
                          labelText: 'Connect Video',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: null,
                        ),
                        items: const <DropdownMenuItem<bool>>[
                          DropdownMenuItem<bool>(
                            value: true,
                            child: Text('Enabled'),
                          ),
                          DropdownMenuItem<bool>(
                            value: false,
                            child: Text('Disabled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onConnectVideoChanged(value);
                        },
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: connectAudio,
                        decoration: const InputDecoration(
                          labelText: 'Connect Audio',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: null,
                        ),
                        items: const <DropdownMenuItem<bool>>[
                          DropdownMenuItem<bool>(
                            value: true,
                            child: Text('Enabled'),
                          ),
                          DropdownMenuItem<bool>(
                            value: false,
                            child: Text('Disabled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onConnectAudioChanged(value);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<bool>(
                        initialValue: connectVideo,
                        decoration: const InputDecoration(
                          labelText: 'Connect Video',
                          border: OutlineInputBorder(),
                          isDense: true,
                          helperText: null,
                        ),
                        items: const <DropdownMenuItem<bool>>[
                          DropdownMenuItem<bool>(
                            value: true,
                            child: Text('Enabled'),
                          ),
                          DropdownMenuItem<bool>(
                            value: false,
                            child: Text('Disabled'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          onConnectVideoChanged(value);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Send Beep Audio'),
              subtitle: const Text(
                'Send a 440Hz sine wave beep instead of microphone',
              ),
              value: beepAudioEnabled,
              onChanged: onBeepAudioEnabledChanged,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Use Audio Device'),
              subtitle: Text(
                isAndroid
                    ? 'Android では常に実音声デバイスを利用します。'
                    : useAudioDeviceEditable
                    ? '実マイクなどの音声デバイスを利用します。Beep Audio と独立して指定できます。'
                    : 'プレビューまたは接続の開始後は変更できません。変更するにはアプリを再起動してください。',
              ),
              value: useAudioDevice,
              onChanged: useAudioDeviceEditable
                  ? onUseAudioDeviceChanged
                  : null,
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedAudioCodecType,
                    decoration: const InputDecoration(
                      labelText: 'Audio Codec',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const <DropdownMenuItem<String?>>[
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'OPUS',
                        child: Text('OPUS'),
                      ),
                    ],
                    onChanged: onAudioCodecTypeChanged,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: audioBitRateController,
                    decoration: const InputDecoration(
                      labelText: 'Audio Bitrate (bps)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: audioBitRateValidator,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: selectedVideoCodecType,
                    decoration: const InputDecoration(
                      labelText: 'Video Codec',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...videoCodecTypeOptions.map((codec) {
                        return DropdownMenuItem<String?>(
                          value: codec,
                          child: Text(codec),
                        );
                      }),
                    ],
                    onChanged: needsCamera ? onVideoCodecTypeChanged : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: selectedVideoBitRate,
                    decoration: const InputDecoration(
                      labelText: 'Video Bitrate',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...videoBitRateOptions.map((bitRate) {
                        return DropdownMenuItem<int?>(
                          value: bitRate,
                          child: Text(bitRate.toString()),
                        );
                      }),
                    ],
                    onChanged: needsCamera ? onVideoBitRateChanged : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<int?>(selectedResolutionIndex),
                    initialValue: selectedResolutionIndex ?? 0,
                    decoration: const InputDecoration(
                      labelText: 'Resolution',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: resolutionLabels.asMap().entries.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: needsCamera
                        ? (index) {
                            if (index == null) {
                              return;
                            }
                            onResolutionChanged(index);
                          }
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: selectedFrameRate,
                    decoration: const InputDecoration(
                      labelText: 'Framerate',
                      border: OutlineInputBorder(),
                      isDense: true,
                      helperText: null,
                    ),
                    items: <DropdownMenuItem<int?>>[
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('未指定'),
                      ),
                      ...frameRateOptions.map((frameRate) {
                        return DropdownMenuItem<int?>(
                          value: frameRate,
                          child: Text(frameRate.toString()),
                        );
                      }),
                    ],
                    onChanged: needsCamera ? onFrameRateChanged : null,
                  ),
                ),
              ],
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Video Codec Parameters',
          enabled: connectionParametersEditable,
          children: [
            TextFormField(
              controller: videoVp9ParamsController,
              decoration: const InputDecoration(
                labelText: 'video_vp9_params (JSON object)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: videoCodecParamsValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: videoH264ParamsController,
              decoration: const InputDecoration(
                labelText: 'video_h264_params (JSON object)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: videoCodecParamsValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: videoH265ParamsController,
              decoration: const InputDecoration(
                labelText: 'video_h265_params (JSON object)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: videoCodecParamsValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: videoAv1ParamsController,
              decoration: const InputDecoration(
                labelText: 'video_av1_params (JSON object)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              validator: videoCodecParamsValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 2,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Forwarding Filters',
          enabled: connectionParametersEditable,
          children: [
            TextFormField(
              controller: forwardingFiltersController,
              decoration: const InputDecoration(
                labelText: 'forwarding_filters (JSON object array)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
                helperText:
                    '各要素は Sora の forwarding filter 仕様に従う JSON object です。',
              ),
              validator: forwardingFiltersValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              minLines: 3,
              maxLines: 6,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        _DevToolsSettingsGroup(
          title: 'Timeout',
          enabled: connectionParametersEditable,
          children: [
            TextFormField(
              controller: connectionTimeoutController,
              decoration: const InputDecoration(
                labelText: 'Connection Timeout (seconds)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: timeoutValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: disconnectWaitTimeoutController,
              decoration: const InputDecoration(
                labelText: 'Disconnect Wait Timeout (seconds)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: timeoutValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: signalingCandidateTimeoutController,
              decoration: const InputDecoration(
                labelText: 'Signaling Candidate Timeout (seconds)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              validator: timeoutValidator,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ],
    );
  }
}

class _DevToolsSettingsGroup extends StatelessWidget {
  const _DevToolsSettingsGroup({
    required this.title,
    required this.children,
    this.subtitle,
    this.initiallyExpanded = false,
    this.enabled = true,
  });

  final String title;
  final List<Widget> children;
  final String? subtitle;
  final bool initiallyExpanded;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD8D8D8)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle!),
          childrenPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            ExcludeFocus(
              excluding: !enabled,
              child: IgnorePointer(
                ignoring: !enabled,
                child: Opacity(
                  opacity: enabled ? 1 : 0.55,
                  child: Column(children: children),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
