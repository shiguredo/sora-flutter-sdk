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
      dataChannelOpenEvents.add(event.event);
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
  }) async {
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      for (final observation in observations) {
        if (observation.kind == 'video' &&
            observation.connectionId == remoteConnectionId) {
          return observation;
        }
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for $label remote video track on $name. '
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
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      for (final event in dataChannelOpenEvents) {
        if (event.label == label) {
          return event;
        }
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for DataChannel open on $name. '
      'label=$label '
      'dataChannelOpenEvents=${dataChannelOpenEvents.map((e) => e.label).toList()} '
      'milestones=$milestones',
    );
  }

  String debugSummary() {
    return 'name=$name '
        'connectionId=$connectionId '
        'milestones=$milestones '
        'trackEvents=$trackEvents '
        'removeTrackEvents=$removeTrackEvents '
        'dataChannelOpenEvents=${dataChannelOpenEvents.map((e) => e.label).toList()} '
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
