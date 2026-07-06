// dispose 後の API 呼び出しが StateError で拒否されることを確認する E2E 。
// 接続前と接続後（messaging / video）の 3 系列で検証する。

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'dispose_before_connect: dispose 後に getStats / setAudioEnabled / '
    'setVideoEnabled が StateError になること',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-dispose-before-connect',
      );

      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        metadata: env.metadata,
      );

      SoraConnection? connection;

      try {
        connection = await Sora.createConnection(config);

        // 接続前に dispose する
        await connection.dispose();

        // dispose 後の API 呼び出しがすべて StateError になることを確認する
        final conn = connection;
        expect(
          conn.getStats(),
          throwsA(isA<StateError>()),
          reason: 'dispose 後に getStats が StateError になること。',
        );
        expect(
          () => conn.setAudioEnabled(false),
          throwsA(isA<StateError>()),
          reason: 'dispose 後に setAudioEnabled が StateError になること。',
        );
        expect(
          () => conn.setVideoEnabled(false),
          throwsA(isA<StateError>()),
          reason: 'dispose 後に setVideoEnabled が StateError になること。',
        );
      } finally {
        await connection?.dispose();
      }
    },
  );

  testWidgets(
    'dispose_after_messaging: messaging 接続後に dispose して rpc / '
    'sendDataChannelMessage が StateError になること',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-dispose-after-messaging',
      );

      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: false,
        video: false,
        dataChannelSignaling: true,
        dataChannels: const [
          {'label': '#messaging', 'direction': 'sendrecv', 'compress': true},
        ],
        metadata: env.metadata,
      );

      final connectTimeout = connectionStageTimeout(config);

      ObservedConnection? connection;
      Object? bodyError;

      try {
        connection = await ObservedConnection.create(
          name: 'messaging',
          config: config,
        );

        logE2eMessage(
          'stage=connect_start channelId=$channelId '
          'bundleId=${connection.connection.bundleId}',
        );

        await connection.connect();
        await connection.waitUntilConnected(connectTimeout);
        connection.throwIfHasErrors();

        logE2eMessage(
          'stage=connected channelId=$channelId '
          'connectionId=${connection.connectionId}',
        );

        // 接続後に dispose する
        await connection.dispose();

        // dispose 後の API 呼び出しがすべて StateError になることを確認する
        final conn = connection;
        expect(
          conn.connection.rpc('test.method'),
          throwsA(isA<StateError>()),
          reason: 'dispose 後に rpc が StateError になること。',
        );
        expect(
          () => conn.connection.sendDataChannelMessage(
            '#messaging',
            Uint8List(0),
          ),
          throwsA(isA<StateError>()),
          reason:
              'dispose 後に sendDataChannelMessage が StateError になること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        if (connection != null) {
          logE2eMessage(
            'stage=cleanup_start ${connection.debugSummary()}',
          );
        }

        final cleanupErrors = <String>[];

        await runCleanupStep(cleanupErrors, 'connection.dispose', () async {
          await connection?.dispose();
        });

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed '
            'errors=${cleanupErrors.join(" | ")}',
          );
          if (bodyError == null) {
            throw StateError(
              'Cleanup failed: ${cleanupErrors.join(" | ")}',
            );
          }
        } else {
          logE2eMessage('stage=cleanup_finished status=ok');
        }
      }

      expect(
        connection.errors,
        isEmpty,
        reason: '接続エラーイベントが発生しないこと。',
      );
    },
  );

  testWidgets(
    'dispose_after_video: 映像接続後に dispose して replaceVideoTrack が '
    'StateError になること',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-dispose-after-video',
      );

      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendrecv,
        video: true,
        audio: false,
        metadata: env.metadata,
      );

      final connectTimeout = connectionStageTimeout(config);

      SoraConnection? connection;
      StreamSubscription<SoraConnectionEvent>? sub;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack1;
      LocalVideoTrack? videoTrack2;
      final errors = <SoraConnectionErrorEvent>[];
      final connected = Completer<void>();
      Object? bodyError;

      try {
        stream = MediaDevices.createMediaStream();
        videoTrack1 = MediaDevices.createExternalVideoTrack();
        stream.addTrack(videoTrack1);
        videoTrack2 = MediaDevices.createExternalVideoTrack();

        connection = await Sora.createConnection(config);
        sub = connection.events.listen((SoraConnectionEvent event) {
          if (event is SoraConnectionStateChangedEvent) {
            if (event.state is SoraConnectedState && !connected.isCompleted) {
              connected.complete();
            }
          } else if (event is SoraConnectionErrorEvent) {
            errors.add(event);
            if (!connected.isCompleted) {
              connected.completeError(
                StateError(
                  'Connection error: code=${event.code} '
                  'message=${event.message}',
                ),
              );
            }
          }
        });

        logE2eMessage(
          'stage=connect_start channelId=$channelId '
          'bundleId=${connection.bundleId}',
        );

        await connection.connect(stream);
        await connected.future.timeout(connectTimeout);

        logE2eMessage(
          'stage=connected channelId=$channelId '
          'connectionId=${connection.connectionId}',
        );

        await sub.cancel();
        sub = null;

        // 接続後に dispose する
        await connection.dispose();

        // dispose 後の API 呼び出しが StateError になることを確認する
        expect(
          connection.replaceVideoTrack(stream, videoTrack2),
          throwsA(isA<StateError>()),
          reason: 'dispose 後に replaceVideoTrack が StateError になること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        logE2eMessage('stage=cleanup_start');

        final cleanupErrors = <String>[];

        await runCleanupStep(cleanupErrors, 'sub.cancel', () async {
        await sub?.cancel();
        });
        await runCleanupStep(cleanupErrors, 'connection.dispose', () async {
          await connection?.dispose();
        });
        await runCleanupStep(cleanupErrors, 'stream.dispose', () async {
          await stream?.dispose();
        });
        await runCleanupStep(cleanupErrors, 'videoTrack1.dispose', () async {
          await videoTrack1?.dispose();
        });
        await runCleanupStep(cleanupErrors, 'videoTrack2.dispose', () async {
          await videoTrack2?.dispose();
        });

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed '
            'errors=${cleanupErrors.join(" | ")}',
          );
          if (bodyError == null) {
            throw StateError(
              'Cleanup failed: ${cleanupErrors.join(" | ")}',
            );
          }
        } else {
          logE2eMessage('stage=cleanup_finished status=ok');
        }
      }

      expect(
        errors,
        isEmpty,
        reason: '接続エラーイベントが発生しないこと。',
      );
    },
  );
}
