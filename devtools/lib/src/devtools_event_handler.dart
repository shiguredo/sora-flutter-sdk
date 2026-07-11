/// SoraConnection のイベントを画面状態とログへ反映するハンドラ。
///
/// [DevToolsConnectionSubscriptionController] から受け取った
/// [SoraConnectionEvent] / [SoraDebugEvent] を解釈し、
/// [DevToolsPageNotifier] の更新と各ログカテゴリへの追記を行う。
///
/// RPC method 同期や remote client 一覧更新もここで扱う。
library;

import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_connection_controller.dart';
import 'devtools_logging_support.dart';
import 'devtools_models.dart';

class DevToolsEventHandler {
  DevToolsEventHandler({
    required DevToolsPageNotifier pageNotifier,
    required void Function(void Function()) mutateView,
    required void Function(String) appendEventLog,
    required void Function(String) appendTimelineLog,
    required void Function(Map<String, Object?>) updateRemoteClients,
    required DevToolsConnectionController connectionController,
    required DevToolsRpcTemplateRequest Function() buildRpcTemplateRequest,
    required void Function(String text) setRpcParamsText,
    required void Function(String label) onDataChannelOpen,
    required void Function(DevToolsMessageEntry entry) onDataChannelMessage,
  }) : _pageNotifier = pageNotifier,
       _mutateView = mutateView,
       _appendEventLog = appendEventLog,
       _appendTimelineLog = appendTimelineLog,
       _updateRemoteClients = updateRemoteClients,
       _connectionController = connectionController,
       _buildRpcTemplateRequest = buildRpcTemplateRequest,
       _setRpcParamsText = setRpcParamsText,
       _onDataChannelOpen = onDataChannelOpen,
       _onDataChannelMessage = onDataChannelMessage;

  final DevToolsPageNotifier _pageNotifier;
  final void Function(void Function()) _mutateView;
  final void Function(String) _appendEventLog;
  final void Function(String) _appendTimelineLog;
  final void Function(Map<String, Object?>) _updateRemoteClients;
  final DevToolsConnectionController _connectionController;
  final DevToolsRpcTemplateRequest Function() _buildRpcTemplateRequest;
  final void Function(String) _setRpcParamsText;
  final void Function(String) _onDataChannelOpen;
  final void Function(DevToolsMessageEntry) _onDataChannelMessage;

  /// SoraConnection の主要イベントを画面状態とログへ反映する。
  void handleEvent(SoraConnectionEvent event) {
    switch (event) {
      case SoraConnectionStateChangedEvent(state: final state):
        _appendEventLog(DevToolsLoggingSupport.formatStateEventLog(state));
        _mutateView(() {
          _pageNotifier.applyConnectionState(state);
        });
      case SoraConnectionErrorEvent(code: final code, message: final message):
        _appendEventLog(
          DevToolsLoggingSupport.formatConnectionErrorEventLog(code, message),
        );
        _mutateView(() {
          _pageNotifier.applyConnectionError(code: code, message: message);
        });
      case SoraNotifyEvent(message: final message):
        _updateRemoteClients(message);
        _appendEventLog(DevToolsLoggingSupport.formatNotifyLog(message));
      case SoraPushEvent(message: final message):
        _appendEventLog(DevToolsLoggingSupport.formatPushLog(message));
      case SoraSwitchedEvent(message: final message):
        _appendEventLog(DevToolsLoggingSupport.formatSwitchedLog(message));
      case SoraSignalingMessageEvent(event: final event):
        _appendEventLog(DevToolsLoggingSupport.formatSignalingLog(event));
        if (event.direction == 'received' && event.data?['type'] == 'offer') {
          final template = _connectionController.syncRpcMethodsFromOffer(
            event.data,
            _buildRpcTemplateRequest(),
          );
          if (template != null) {
            _setRpcParamsText(template);
          }
        }
      case SoraDataChannelOpenEvent(event: final event):
        _appendEventLog(
          DevToolsLoggingSupport.formatDataChannelEventLog(event),
        );
        _onDataChannelOpen(event.label);
      case SoraDataChannelMessageEvent(message: final message):
        _appendEventLog(
          DevToolsLoggingSupport.formatDataChannelMessageLog(message),
        );
        _onDataChannelMessage(
          DevToolsMessageEntry(
            timestamp: DateTime.now(),
            label: message.label,
            text: DevToolsMessageHistory.decodeReceivedMessage(message.data),
            isSent: false,
          ),
        );
      case SoraTrackEvent(track: final track):
        _appendEventLog(DevToolsLoggingSupport.formatTrackLog('track', track));
        _mutateView(() {
          _pageNotifier.upsertRemoteTrack(track);
        });
      case SoraRemoveTrackEvent(track: final track):
        _appendEventLog(
          DevToolsLoggingSupport.formatTrackLog('removetrack', track),
        );
        _mutateView(() {
          _pageNotifier.removeRemoteTrack(track);
        });
      case SoraTimeoutEvent():
        _appendEventLog('timeout');
    }
  }

  /// SDK debug event を event / timeline ログへ振り分ける。
  void handleDebugEvent(SoraDebugEvent event) {
    switch (event) {
      case SoraLogDebugEvent(event: final event):
        _appendEventLog(DevToolsLoggingSupport.formatSdkLog(event));
      case SoraTimelineDebugEvent(event: final event):
        _appendTimelineLog(DevToolsLoggingSupport.formatTimelineLog(event));
    }
  }
}
