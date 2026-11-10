/// DevTools 画面のログ整形とログ保持補助を提供するモジュール。
///
/// Sora SDK の各種イベントを表示用文字列へ変換する補助関数と、
/// アプリ内ログ配列へ追記するための共通処理をここに集約する。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_models.dart';

class DevToolsLoggingSupport {
  /// ログ行に timestamp を付与して保存先へ追記する。
  ///
  /// 画面が mount 済みであれば `mutateView` 経由で更新し、
  /// unmount 済みであれば `addWhenUnmounted` だけを実行する。
  static void appendEntry({
    required List<String> target,
    required String line,
    required bool mounted,
    required VoidCallback addWhenUnmounted,
    required void Function(VoidCallback update) mutateView,
  }) {
    final entry = '[${DateTime.now().toIso8601String()}] $line';
    if (!mounted) {
      addWhenUnmounted();
      return;
    }
    mutateView(() {
      target.add(entry);
      if (target.length > 200) {
        target.removeRange(0, target.length - 200);
      }
    });
  }

  /// `notify` イベントの payload から remote client 一覧を抽出する。
  static List<DevToolsRemoteClientInfo> extractRemoteClients(
    Map<String, Object?> message,
  ) {
    final data = message['data'];
    if (data is! List) {
      return const <DevToolsRemoteClientInfo>[];
    }
    final clients = <DevToolsRemoteClientInfo?>[];
    for (final item in data) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, Object?>.from(item);
      final connectionId = map['connection_id'] as String?;
      if (connectionId == null || connectionId.isEmpty) {
        continue;
      }
      clients.add(
        DevToolsRemoteClientInfo(
          connectionId: connectionId,
          clientId: map['client_id'] as String?,
        ),
      );
    }
    return clients.whereType<DevToolsRemoteClientInfo>().toList(
      growable: false,
    );
  }

  /// 自分自身を除外しつつ、connection ID 単位で remote client を正規化する。
  static List<DevToolsRemoteClientInfo> filterRemoteClients({
    required List<DevToolsRemoteClientInfo?> clients,
    required String? selfConnectionId,
  }) {
    final filtered = <DevToolsRemoteClientInfo>[];
    for (final client in clients) {
      if (client == null) {
        continue;
      }
      if (client.connectionId == selfConnectionId) {
        continue;
      }
      final index = filtered.indexWhere(
        (candidate) => candidate.connectionId == client.connectionId,
      );
      if (index == -1) {
        filtered.add(client);
        continue;
      }
      filtered[index] = client;
    }
    return filtered;
  }

  /// 接続状態イベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatStateEventLog(SoraConnectionState state) {
    switch (state) {
      case SoraConnectingState():
        return 'event: state=connecting';
      case SoraConnectedState():
        return 'event: state=connected';
      case SoraDisconnectedState(:final closeInfo):
        if (closeInfo == null) {
          return 'event: state=disconnected';
        }
        if (closeInfo.reason case final reason?) {
          return 'event: state=disconnected code=${closeInfo.code} reason=$reason';
        }
        return 'event: state=disconnected code=${closeInfo.code}';
    }
  }

  /// 接続エラーイベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatConnectionErrorEventLog(String? code, String? message) {
    if (code == null && message == null) {
      return 'event: connection_error';
    }
    if (code != null && message != null) {
      return 'event: connection_error code=$code message=$message';
    }
    if (code != null) {
      return 'event: connection_error code=$code';
    }
    return 'event: connection_error message=$message';
  }

  /// `notify` イベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatNotifyLog(Map<String, Object?> message) {
    final eventType = message['event_type'] ?? 'unknown';
    final connectionId = message['connection_id'];
    if (connectionId is String && connectionId.isNotEmpty) {
      return 'notify: event_type=$eventType connection_id=$connectionId';
    }
    return 'notify: event_type=$eventType';
  }

  /// `push` イベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatPushLog(Map<String, Object?> message) {
    final value = message['type'] ?? 'unknown';
    return 'push: type=$value';
  }

  /// `switched` イベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatSwitchedLog(Map<String, Object?> message) {
    final ignoreDisconnect = message['ignore_disconnect_websocket'] == true
        ? 'true'
        : 'false';
    return 'switched: ignore_disconnect_websocket=$ignoreDisconnect';
  }

  /// シグナリングイベントをコールバックログ向けの 1 行文字列へ整形する。
  static String formatSignalingLog(SoraSignalingEvent event) {
    final type = event.data?['type'] ?? 'unknown';
    final data = event.data != null ? jsonEncode(event.data) : 'null';
    return 'signaling: transport=${event.transportType} direction=${event.direction} type=$type data=$data';
  }

  /// DataChannel の open / close などのイベントを 1 行文字列へ整形する。
  static String formatDataChannelEventLog(SoraDataChannelEvent event) {
    return 'datachannel: label=${event.label} direction=${event.direction ?? 'unknown'} compress=${event.compress}';
  }

  /// DataChannel の受信メッセージ情報を 1 行文字列へ整形する。
  static String formatDataChannelMessageLog(SoraDataChannelMessage message) {
    return 'message: label=${message.label} bytes=${message.data.length}';
  }

  /// Remote track の概要をアプリログ向けの 1 行文字列へ整形する。
  static String formatTrackLog(String name, RemoteMediaStreamTrack track) {
    final base =
        '$name: kind=${track.kind} trackId=${track.trackId} connectionId=${track.connectionId}';
    if (track.textureId case final textureId?) {
      return '$base textureId=$textureId';
    }
    return base;
  }

  /// SDK ログイベントをアプリログ向けの 1 行文字列へ整形する。
  static String formatSdkLog(SoraLogEvent event) {
    final message = event.message;
    if (message == null) {
      return 'log: title=${event.title}';
    }
    return 'log: title=${event.title} message=${jsonEncode(message)}';
  }

  /// Timeline イベントをタイムラインログ向けの 1 行文字列へ整形する。
  static String formatTimelineLog(SoraTimelineEvent event) {
    final buffer = StringBuffer(
      'timeline: type=${event.type} logType=${event.logType.value}',
    );
    if (event.dataChannelId case final id?) {
      buffer.write(' dataChannelId=$id');
    }
    if (event.dataChannelLabel case final label?) {
      buffer.write(' dataChannelLabel=$label');
    }
    if (event.data != null) {
      buffer.write(' data=${jsonEncode(event.data)}');
    }
    return buffer.toString();
  }
}
