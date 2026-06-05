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
    const interval = Duration(milliseconds: 200);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      throwIfHasErrors();

      for (final observation in trackEvents) {
        if (observation.kind == 'video' &&
            observation.connectionId == remoteConnectionId) {
          return observation;
        }
      }

      await tester.pump(interval);
    }

    throw StateError(
      'Timed out while waiting for remote video track on $name. '
      'remoteConnectionId=$remoteConnectionId '
      'trackEvents=$trackEvents removeTrackEvents=$removeTrackEvents '
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

  String debugSummary() {
    return 'name=$name '
        'connectionId=$connectionId '
        'milestones=$milestones '
        'trackEvents=$trackEvents '
        'removeTrackEvents=$removeTrackEvents '
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
