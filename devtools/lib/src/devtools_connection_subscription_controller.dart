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

  // 指定接続への購読を開始する。
  Future<void> bind(SoraConnection connection) async {
    await unbind();
    _eventSubscription = connection.events.listen((event) {
      if (!_isMounted()) {
        return;
      }
      _onEvent(event);
    });
    _debugEventSubscription = connection.debugEvents.listen((event) {
      if (!_isMounted()) {
        return;
      }
      _onDebugEvent(event);
    });
    _localVideoSubscription = connection.localVideo.listen((handle) {
      if (!_isMounted()) {
        return;
      }
      _onLocalVideo(handle);
    });
    _debugMessageSubscription = connection.debugMessages.listen((message) {
      if (!_isMounted()) {
        return;
      }
      _onDebugMessage(message);
    });
  }

  // 現在の購読をすべて解除する。
  Future<void> unbind() async {
    await _eventSubscription?.cancel();
    await _debugEventSubscription?.cancel();
    await _localVideoSubscription?.cancel();
    await _debugMessageSubscription?.cancel();
    _eventSubscription = null;
    _debugEventSubscription = null;
    _localVideoSubscription = null;
    _debugMessageSubscription = null;
  }

  // controller を破棄する。
  Future<void> dispose() async {
    await unbind();
  }
}
