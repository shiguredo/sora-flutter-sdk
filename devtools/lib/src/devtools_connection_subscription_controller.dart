/// DevTools 画面の `SoraConnection` 購読開始 / 解除を管理するモジュール。
///
/// connection event、debug event、local video、debug message の 4 系統を
/// 一括で bind / unbind し、画面側の購読配線を簡潔に保つ。
library;

import 'dart:async';

import 'package:sora_sdk/sora_sdk.dart';

class DevToolsConnectionSubscriptionController {
  DevToolsConnectionSubscriptionController({
    required bool Function() isMounted,
    required void Function(SoraConnectionEvent event) onEvent,
    required void Function(SoraDebugEvent event) onDebugEvent,
    required void Function(SoraLocalVideoHandle handle) onLocalVideo,
    required void Function(String message) onDebugMessage,
  }) : _isMounted = isMounted,
       _onEvent = onEvent,
       _onDebugEvent = onDebugEvent,
       _onLocalVideo = onLocalVideo,
       _onDebugMessage = onDebugMessage;

  // 画面がまだ更新可能かどうかを判定する。
  final bool Function() _isMounted;
  // 接続イベント受信時の callback。
  final void Function(SoraConnectionEvent event) _onEvent;
  // debug event 受信時の callback。
  final void Function(SoraDebugEvent event) _onDebugEvent;
  // ローカルビデオ ready 受信時の callback。
  final void Function(SoraLocalVideoHandle handle) _onLocalVideo;
  // debug message 受信時の callback。
  final void Function(String message) _onDebugMessage;

  // 接続イベント購読。
  StreamSubscription<SoraConnectionEvent>? _eventSubscription;
  // debug event 購読。
  StreamSubscription<SoraDebugEvent>? _debugEventSubscription;
  // ローカルビデオハンドル購読。
  StreamSubscription<SoraLocalVideoHandle>? _localVideoSubscription;
  // debugMessages の文字列ログ購読。
  StreamSubscription<String>? _debugMessageSubscription;
  // 現在購読中の接続。別接続の cleanup が新しい購読を解除しないために保持する。
  SoraConnection? _connection;
  // bind / unbind の競合を無効化する世代番号。
  int _generation = 0;
  // dispose 後の再購読を防ぐ。
  bool _disposed = false;

  // 指定接続への購読を開始する。
  Future<void> bind(SoraConnection connection) async {
    if (_disposed) {
      return;
    }
    final generation = ++_generation;
    await _cancelSubscriptions();
    if (_disposed || generation != _generation) {
      return;
    }
    _connection = connection;
    _eventSubscription = connection.events.listen((event) {
      if (!_isActive(connection, generation)) {
        return;
      }
      _onEvent(event);
    });
    _debugEventSubscription = connection.debugEvents.listen((event) {
      if (!_isActive(connection, generation)) {
        return;
      }
      _onDebugEvent(event);
    });
    _localVideoSubscription = connection.localVideo.listen((handle) {
      if (!_isActive(connection, generation)) {
        return;
      }
      _onLocalVideo(handle);
    });
    _debugMessageSubscription = connection.debugMessages.listen((message) {
      if (!_isActive(connection, generation)) {
        return;
      }
      _onDebugMessage(message);
    });
  }

  // 現在の購読をすべて解除する。
  // [connection] が指定された場合は、その接続を購読しているときだけ解除する。
  Future<void> unbind({SoraConnection? connection}) async {
    if (connection != null && !identical(_connection, connection)) {
      return;
    }
    ++_generation;
    _connection = null;
    await _cancelSubscriptions();
  }

  // controller を破棄する。
  Future<void> dispose() async {
    _disposed = true;
    await unbind();
  }

  // 指定された接続が現在の世代で有効かを確認する。
  bool _isActive(SoraConnection connection, int generation) {
    return !_disposed &&
        generation == _generation &&
        identical(_connection, connection) &&
        _isMounted();
  }

  // 購読実体を取り外してから cancel を待つ。
  // 先にフィールドを null にすることで、並行する bind が古い購読を再利用しない。
  Future<void> _cancelSubscriptions() async {
    final eventSubscription = _eventSubscription;
    final debugEventSubscription = _debugEventSubscription;
    final localVideoSubscription = _localVideoSubscription;
    final debugMessageSubscription = _debugMessageSubscription;
    _eventSubscription = null;
    _debugEventSubscription = null;
    _localVideoSubscription = null;
    _debugMessageSubscription = null;
    await eventSubscription?.cancel();
    await debugEventSubscription?.cancel();
    await localVideoSubscription?.cancel();
    await debugMessageSubscription?.cancel();
  }
}
