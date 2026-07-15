import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

/// receiver 側で観測した remote track の要約。
final class RemoteTrackObservation {
  const RemoteTrackObservation({
    required this.trackId,
    required this.kind,
    required this.connectionId,
  });

  final String trackId;
  final String kind;
  final String connectionId;

  @override
  String toString() {
    return 'RemoteTrackObservation('
        'trackId=$trackId, '
        'kind=$kind, '
        'connectionId=$connectionId)';
  }
}

/// 接続イベントの監視と待ち合わせをまとめる。
final class ObservedConnection {
  ObservedConnection._({
    required this.name,
    required this.connection,
  }) {
    _subscription = connection.events.listen(_handleEvent);
  }

  static Future<ObservedConnection> create({
    required String name,
    required SoraConnectionConfig config,
  }) async {
    final connection = await Sora.createConnection(config);
    return ObservedConnection._(name: name, connection: connection);
  }

  final String name;
  final SoraConnection connection;
  final List<SoraConnectionErrorEvent> errors = <SoraConnectionErrorEvent>[];
  final List<String> milestones = <String>[];
  final List<RemoteTrackObservation> trackEvents = <RemoteTrackObservation>[];
  final List<RemoteTrackObservation> removeTrackEvents =
      <RemoteTrackObservation>[];
  final List<SoraDataChannelEvent> dataChannelOpenEvents =
      <SoraDataChannelEvent>[];
  final List<SoraDataChannelMessage> dataChannelMessages =
      <SoraDataChannelMessage>[];
  final List<Map<String, Object?>> switchedEvents = <Map<String, Object?>>[];
  final List<Map<String, Object?>> notifyEvents = <Map<String, Object?>>[];
  final List<Map<String, Object?>> pushEvents = <Map<String, Object?>>[];

  final Completer<void> _connected = Completer<void>();
  final Completer<void> _disconnected = Completer<void>();
  StreamSubscription<SoraConnectionEvent>? _subscription;

  String? get connectionId => connection.connectionId;

  void _handleEvent(SoraConnectionEvent event) {
    if (event is SoraConnectionStateChangedEvent) {
      final stateName = event.state.runtimeType.toString();
      milestones.add(stateName);
      if (event.state is SoraConnectedState && !_connected.isCompleted) {
        _connected.complete();
      }
      if (event.state is SoraDisconnectedState && !_disconnected.isCompleted) {
        _disconnected.complete();
      }
      return;
    }

    if (event is SoraConnectionErrorEvent) {
      errors.add(event);
      if (!_connected.isCompleted) {
        _connected.completeError(
          StateError(_buildErrorMessage(event, phase: 'connect')),
        );
      }
      if (!_disconnected.isCompleted) {
        _disconnected.completeError(
          StateError(_buildErrorMessage(event, phase: 'disconnect')),
        );
      }
      return;
    }

    if (event is SoraTrackEvent) {
      trackEvents.add(
        RemoteTrackObservation(
          trackId: event.track.trackId,
          kind: event.track.kind,
          connectionId: event.track.connectionId,
        ),
      );
      return;
    }

    if (event is SoraRemoveTrackEvent) {
      removeTrackEvents.add(
        RemoteTrackObservation(
          trackId: event.track.trackId,
          kind: event.track.kind,
          connectionId: event.track.connectionId,
        ),
      );
      return;
    }

    if (event is SoraDataChannelOpenEvent) {
      final dcEvent = event.event;
      dataChannelOpenEvents.add(dcEvent);
      return;
    }

    if (event is SoraDataChannelMessageEvent) {
      dataChannelMessages.add(event.message);
      return;
    }

    if (event is SoraSwitchedEvent) {
      switchedEvents.add(event.message);
      return;
    }

    if (event is SoraNotifyEvent) {
      notifyEvents.add(event.message);
      return;
    }

    if (event is SoraPushEvent) {
      pushEvents.add(event.message);
      return;
    }
  }

  String _buildErrorMessage(
    SoraConnectionErrorEvent event, {
    required String phase,
  }) {
    return 'Connection error on $name during $phase: '
        'code=${event.code} message=${event.message}';
  }

  Future<void> connect([LocalMediaStream? stream]) {
    return connection.connect(stream);
  }

  Future<void> disconnect() {
    return connection.disconnect();
  }

  Future<void> waitUntilConnected(Duration timeout) async {
    await _connected.future.timeout(
      timeout,
      onTimeout: () => throw StateError(
        'Timed out while waiting for $name to connect. '
        'milestones=$milestones errors=${errorSummaries()}',
      ),
    );
  }

  Future<void> waitUntilDisconnected(Duration timeout) async {
    await _disconnected.future.timeout(
      timeout,
      onTimeout: () => throw StateError(
        'Timed out while waiting for $name to disconnect. '
        'milestones=$milestones errors=${errorSummaries()}',
      ),
    );
  }

  void throwIfHasErrors() {
    if (errors.isEmpty) {
      return;
    }
    throw StateError(
      'Observed error events on $name: ${errorSummaries().join(", ")}',
    );
  }

  Future<RemoteTrackObservation> waitForRemoteVideoTrackFrom(
    WidgetTester tester, {
    required String remoteConnectionId,
    required Duration timeout,
  }) async {
    return _waitForObservation(
      tester,
      observations: trackEvents,
      remoteConnectionId: remoteConnectionId,
      timeout: timeout,
      label: 'add',
      kind: 'video',
    );
  }

  /// 指定 connectionId の remote audio track が追加されるまで待つ。
  Future<RemoteTrackObservation> waitForRemoteAudioTrackFrom(
    WidgetTester tester, {
    required String remoteConnectionId,
    required Duration timeout,
  }) async {
    return _waitForObservation(
      tester,
      observations: trackEvents,
      remoteConnectionId: remoteConnectionId,
      timeout: timeout,
      label: 'add',
      kind: 'audio',
    );
  }

  Future<RemoteTrackObservation> waitForRemoteVideoTrackRemoved(
    WidgetTester tester, {
    required String remoteConnectionId,
    required Duration timeout,
  }) async {
    return _waitForObservation(
      tester,
      observations: removeTrackEvents,
      remoteConnectionId: remoteConnectionId,
      timeout: timeout,
      label: 'remove',
      kind: 'video',
    );
  }

  /// remoteMediaStreams に指定 connectionId のエントリが生成されるまで待つ。
  Future<RemoteMediaStream> waitForRemoteMediaStreamEntry(
    WidgetTester tester, {
    required String connectionId,
    required Duration timeout,
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      final entry = connection.remoteMediaStreams[connectionId];
      if (entry != null) {
        return entry;
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for RemoteMediaStream entry on $name. '
      'connectionId=$connectionId '
      'milestones=$milestones',
    );
  }

  /// 指定 connectionId の RemoteMediaStream で audioTrack と videoTrack の
  /// 両方が non-null になるまで待つ。
  Future<RemoteMediaStream> waitForRemoteMediaStreamBothTracks(
    WidgetTester tester, {
    required String connectionId,
    required Duration timeout,
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      final entry = connection.remoteMediaStreams[connectionId];
      if (entry != null &&
          entry.audioTrack != null &&
          entry.videoTrack != null) {
        return entry;
      }

      await tester.pump(interval);
    }

    final entry = connection.remoteMediaStreams[connectionId];
    throw StateError(
      'Timed out while waiting for both audio/video tracks on $name. '
      'connectionId=$connectionId '
      'entryExists=${entry != null} '
      'audioTrack=${entry?.audioTrack != null} '
      'videoTrack=${entry?.videoTrack != null} '
      'milestones=$milestones',
    );
  }

  /// remoteMediaStreams から指定 connectionId のエントリが削除されるまで待つ。
  Future<void> waitForRemoteMediaStreamRemoved(
    WidgetTester tester, {
    required String connectionId,
    required Duration timeout,
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      if (!connection.remoteMediaStreams.containsKey(connectionId)) {
        return;
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for RemoteMediaStream removal on $name. '
      'connectionId=$connectionId '
      'streamCount=${connection.remoteMediaStreams.length} '
      'milestones=$milestones',
    );
  }

  Future<RemoteTrackObservation> _waitForObservation(
    WidgetTester tester, {
    required List<RemoteTrackObservation> observations,
    required String remoteConnectionId,
    required Duration timeout,
    required String label,
    required String kind,
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      for (final observation in observations) {
        if (observation.kind == kind &&
            observation.connectionId == remoteConnectionId) {
          return observation;
        }
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for $label remote $kind track on $name. '
      'remoteConnectionId=$remoteConnectionId '
      'trackEvents=$trackEvents '
      'removeTrackEvents=$removeTrackEvents '
      'milestones=$milestones',
    );
  }

  List<String> errorSummaries() {
    return errors
        .map(
          (SoraConnectionErrorEvent event) =>
              'code=${event.code} message=${event.message}',
        )
        .toList();
  }

  /// #messaging 等の DataChannel が open するまで待つ。
  Future<SoraDataChannelEvent> waitForDataChannelOpen(
    WidgetTester tester, {
    required String label,
    required Duration timeout,
  }) async {
    return _waitForCondition<SoraDataChannelEvent>(
      tester,
      source: dataChannelOpenEvents,
      predicate: (event) => event.label == label,
      timeout: timeout,
      buildTimeoutMessage: () =>
          'Timed out while waiting for DataChannel open on $name. '
          'label=$label '
          'dataChannelOpenEvents=${dataChannelOpenEvents.map((e) => e.label).toList()} '
          'milestones=$milestones',
    );
  }

  /// 指定 label の DataChannel メッセージを受信するまで待つ。
  Future<SoraDataChannelMessage> waitForDataChannelMessage(
    WidgetTester tester, {
    required String label,
    required Duration timeout,
  }) async {
    return _waitForCondition<SoraDataChannelMessage>(
      tester,
      source: dataChannelMessages,
      predicate: (message) => message.label == label,
      timeout: timeout,
      buildTimeoutMessage: () =>
          'Timed out while waiting for DataChannel message on $name. '
          'label=$label '
          'dataChannelMessageLabels=${dataChannelMessages.map((m) => m.label).toList()} '
          'milestones=$milestones',
    );
  }

  /// switched メッセージを受信するまで待つ。
  Future<Map<String, Object?>> waitForSwitched(
    WidgetTester tester, {
    required Duration timeout,
  }) async {
    return _waitForCondition<Map<String, Object?>>(
      tester,
      source: switchedEvents,
      predicate: (_) => true,
      timeout: timeout,
      buildTimeoutMessage: () =>
          'Timed out while waiting for SoraSwitchedEvent on $name. '
          'switchedEvents=${switchedEvents.length} '
          'milestones=$milestones',
    );
  }

  /// event_type が connection.created で、指定 connectionId に一致する
  /// SoraNotifyEvent を待つ。
  ///
  /// connection.created notify の payload には connection_id が常に含まれる
  /// ことを前提とする。
  Future<Map<String, Object?>> waitForNotifyCreatedEvent(
    WidgetTester tester, {
    required String connectionId,
    required Duration timeout,
  }) async {
    return _waitForCondition<Map<String, Object?>>(
      tester,
      source: notifyEvents,
      predicate: (message) =>
          message['event_type'] == 'connection.created' &&
          message['connection_id'] == connectionId,
      timeout: timeout,
      buildTimeoutMessage: () =>
          'Timed out while waiting for connection.created notify on $name. '
          'connectionId=$connectionId '
          'notifyEvents.length=${notifyEvents.length} '
          'milestones=$milestones',
    );
  }

  /// SoraPushEvent を待つ。
  /// predicate が null の場合は最初の push を返す。
  Future<Map<String, Object?>> waitForPushEvent(
    WidgetTester tester, {
    required Duration timeout,
    bool Function(Map<String, Object?> message)? predicate,
  }) async {
    return _waitForCondition<Map<String, Object?>>(
      tester,
      source: pushEvents,
      predicate: predicate ?? (_) => true,
      timeout: timeout,
      buildTimeoutMessage: () =>
          'Timed out while waiting for SoraPushEvent on $name. '
          'pushEvents.length=${pushEvents.length} '
          'milestones=$milestones',
    );
  }

  /// 条件を満たす要素が見つかるまで polling する共通ヘルパー。
  Future<T> _waitForCondition<T>(
    WidgetTester tester, {
    required Iterable<T> source,
    required bool Function(T) predicate,
    required Duration timeout,
    required String Function() buildTimeoutMessage,
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      for (final item in source) {
        if (predicate(item)) {
          return item;
        }
      }

      await tester.pump(interval);
    }

    throw StateError(buildTimeoutMessage());
  }

  String debugSummary() {
    return 'name=$name '
        'connectionId=$connectionId '
        'milestones=$milestones '
        'trackEvents=$trackEvents '
        'removeTrackEvents=$removeTrackEvents '
        'dataChannelOpenEvents=${dataChannelOpenEvents.map((e) => e.label).toList()} '
        'dataChannelMessages=${dataChannelMessages.length} '
        'switchedEvents=${switchedEvents.length} '
        'notifyEvents=${notifyEvents.length} '
        'pushEvents=${pushEvents.length} '
        'errors=${errorSummaries()}';
  }

  Future<void> dispose() async {
    Object? cancelError;
    try {
      await _subscription?.cancel();
    } catch (e) {
      // EventChannel cancel 失敗でも接続本体の解放は継続する。
      cancelError = e;
    } finally {
      _subscription = null;
      await connection.dispose();
    }
    if (cancelError != null) {
      // ignore: avoid_print
      print('[e2e] cleanup warning: failed to cancel $name subscription: '
          '$cancelError');
    }
  }
}
