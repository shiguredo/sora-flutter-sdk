// macOS の実カメラを使い、接続中の removeVideoTrack / replaceVideoTrack と
// disconnect / dispose を繰り返すローカル専用 E2E。
//
// SoraCameraCapturer.stop() が main thread から呼ばれるタイミングで
// capture delegate が走っていても、delegate 側が sessionQueue を待たずに
// 完了できることを、操作 timeout と複数回反復で確認する。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

const _cameraOptions = GetUserMediaOptions(
  audio: false,
  video: true,
  videoWidth: 320,
  videoHeight: 180,
  videoFrameRate: 30,
);

const _cameraOperationTimeout = Duration(seconds: 15);
const _mediaWarmup = Duration(seconds: 2);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'macos_camera_runtime_stress: 実カメラの停止と再開を繰り返してデッドロックしないことを検証する',
    (WidgetTester tester) async {
      final rounds = _stressRoundsFromEnvironment();
      logE2eMessage(
        'stage=camera_stress_config platform=${Platform.operatingSystem} '
        'rounds=$rounds',
      );

      expect(
        Platform.isMacOS,
        isTrue,
        reason: 'このテストは macOS の実カメラ capturer を検証するため macOS 専用です。',
      );

      final devices = await MediaDevices.enumerateVideoInputDevices();
      expect(
        devices,
        isNotEmpty,
        reason: 'macOS のカメラ入力デバイスが 1 件以上必要です。',
      );
      logE2eMessage(
        'stage=camera_devices_ready count=${devices.length}',
      );

      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-macos-camera-stress',
      );

      final receiverConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        useAudioDevice: false,
        metadata: env.metadata,
      );
      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        audio: false,
        video: true,
        useAudioDevice: false,
        metadata: env.metadata,
      );

      final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);

      ObservedConnection? receiver;
      Object? bodyError;

      try {
        receiver = await ObservedConnection.create(
          name: 'receiver',
          config: receiverConfig,
        );
        logE2eMessage(
          'stage=receiver_connect_start channelId=$channelId',
        );
        await receiver.connect();
        await receiver.waitUntilConnected(receiverConnectTimeout);
        receiver.throwIfHasErrors();
        logE2eMessage(
          'stage=receiver_connected channelId=$channelId '
          'receiverConnectionId=${receiver.connectionId}',
        );

        for (var round = 1; round <= rounds; round++) {
          await _runCameraStressRound(
            tester,
            round: round,
            rounds: rounds,
            channelId: channelId,
            senderConfig: senderConfig,
            senderConnectTimeout: senderConnectTimeout,
            senderDisconnectTimeout: senderDisconnectTimeout,
            receiver: receiver,
          );
        }

        receiver.throwIfHasErrors();
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        if (receiver != null) {
          logE2eMessage(
            'stage=cleanup_start receiver=${receiver.debugSummary()}',
          );
        }
        await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver!.waitUntilDisconnected(receiverDisconnectTimeout);
          }
        });
        await runCleanupStep(
          cleanupErrors,
          'receiver.dispose',
          () async => await receiver?.dispose(),
        );

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
        receiver.errors,
        isEmpty,
        reason: 'receiver で接続エラーイベントが発生しないこと。',
      );
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

Future<void> _runCameraStressRound(
  WidgetTester tester, {
  required int round,
  required int rounds,
  required String channelId,
  required SoraConnectionConfig senderConfig,
  required Duration senderConnectTimeout,
  required Duration senderDisconnectTimeout,
  required ObservedConnection receiver,
}) async {
  ObservedConnection? sender;
  LocalMediaStream? stream;
  LocalVideoTrack? currentVideoTrack;
  LocalVideoTrack? pendingReplacementTrack;
  Object? bodyError;

  try {
    logE2eMessage(
      'stage=round_start round=$round/$rounds channelId=$channelId',
    );
    sender = await ObservedConnection.create(
      name: 'sender-$round',
      config: senderConfig,
    );
    stream = await _createCameraStreamWithTimeout(round);
    currentVideoTrack = _requireVideoTrack(stream, round: round);

    await _withStepTimeout(
      round: round,
      step: 'sender_connect',
      timeout: senderConnectTimeout,
      action: () async {
        await sender!.connect(stream);
        await sender!.waitUntilConnected(senderConnectTimeout);
      },
    );
    sender.throwIfHasErrors();

    final senderConnectionId = sender.connectionId;
    expect(
      senderConnectionId,
      isNotNull,
      reason: 'sender connected 後に connectionId が確定していること。',
    );
    await receiver.waitForRemoteVideoTrackFrom(
      tester,
      remoteConnectionId: senderConnectionId!,
      timeout: const Duration(seconds: 30),
    );
    await tester.pump(_mediaWarmup);

    final outboundBeforeRemove = await waitForVideoOutboundStats(
      tester,
      sender.connection,
    );
    logE2eMessage(
      'stage=round_media_ready round=$round outbound=$outboundBeforeRemove',
    );

    await _withStepTimeout(
      round: round,
      step: 'remove_video_track',
      action: () => sender!.connection.removeVideoTrack(stream!),
    );

    final removedTrack = currentVideoTrack;
    await _withStepTimeout(
      round: round,
      step: 'dispose_removed_camera_track',
      action: () => removedTrack.dispose(),
    );
    currentVideoTrack = null;
    await tester.pump(const Duration(milliseconds: 500));

    final outboundAfterRemove = await _readVideoOutboundStatsOrNull(
      sender.connection,
    );
    final replaceBaseline = outboundAfterRemove ?? outboundBeforeRemove;
    logE2eMessage(
      'stage=round_removed round=$round '
      'baseline=$replaceBaseline outboundAfterRemove=$outboundAfterRemove',
    );

    pendingReplacementTrack = MediaDevices.createCameraVideoTrack(
      videoWidth: _cameraOptions.videoWidth,
      videoHeight: _cameraOptions.videoHeight,
      videoFrameRate: _cameraOptions.videoFrameRate,
    );
    await _withStepTimeout(
      round: round,
      step: 'replace_video_track',
      action: () => sender!.connection.replaceVideoTrack(
        stream!,
        pendingReplacementTrack!,
      ),
    );
    currentVideoTrack = pendingReplacementTrack;
    pendingReplacementTrack = null;
    await tester.pump(_mediaWarmup);

    final outboundAfterReplace = await waitForVideoOutboundStats(
      tester,
      sender.connection,
      previous: replaceBaseline,
    );
    logE2eMessage(
      'stage=round_replace_ready round=$round outbound=$outboundAfterReplace',
    );

    await _withStepTimeout(
      round: round,
      step: 'sender_disconnect',
      timeout: senderDisconnectTimeout,
      action: () async {
        await sender!.disconnect();
        await sender!.waitUntilDisconnected(senderDisconnectTimeout);
      },
    );

    final activeTrack = currentVideoTrack;
    await _withStepTimeout(
      round: round,
      step: 'dispose_active_camera_track',
      action: () => activeTrack.dispose(),
    );
    currentVideoTrack = null;

    sender.throwIfHasErrors();
    receiver.throwIfHasErrors();
    logE2eMessage(
      'stage=round_finished round=$round/$rounds '
      'sender=${sender.debugSummary()}',
    );
  } catch (e) {
    bodyError = e;
    rethrow;
  } finally {
    final cleanupErrors = <String>[];
    await runCleanupStep(cleanupErrors, 'sender.disconnect.$round', () async {
      if (sender != null) {
        await sender.disconnect();
        await sender!.waitUntilDisconnected(senderDisconnectTimeout);
      }
    });
    await runCleanupStep(
      cleanupErrors,
      'pendingReplacementTrack.dispose.$round',
      () async => await pendingReplacementTrack?.dispose(),
    );
    await runCleanupStep(
      cleanupErrors,
      'currentVideoTrack.dispose.$round',
      () async => await currentVideoTrack?.dispose(),
    );
    await runCleanupStep(
      cleanupErrors,
      'sender.dispose.$round',
      () async => await sender?.dispose(),
    );
    await runCleanupStep(
      cleanupErrors,
      'stream.dispose.$round',
      () async => await stream?.dispose(),
    );

    if (cleanupErrors.isNotEmpty) {
      logE2eMessage(
        'stage=round_cleanup_finished status=failed round=$round '
        'errors=${cleanupErrors.join(" | ")}',
      );
      if (bodyError == null) {
        throw StateError(
          'Round $round cleanup failed: ${cleanupErrors.join(" | ")}',
        );
      }
    }
  }
}

Future<LocalMediaStream> _createCameraStreamWithTimeout(int round) async {
  return _withStepTimeout(
    round: round,
    step: 'get_user_media',
    action: () => MediaDevices.getUserMedia(_cameraOptions),
  );
}

Future<VideoOutboundStats?> _readVideoOutboundStatsOrNull(
  SoraConnection connection,
) async {
  final raw = await connection.getStats();
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return extractVideoOutboundStats(raw);
}

LocalVideoTrack _requireVideoTrack(
  LocalMediaStream stream, {
  required int round,
}) {
  final track = stream.currentVideoTrackOrNull;
  expect(
    track,
    isNotNull,
    reason: 'round=$round の getUserMedia 結果に video track が含まれること。',
  );
  return track!;
}

int _stressRoundsFromEnvironment() {
  final raw = Platform.environment['TEST_MACOS_CAMERA_STRESS_ROUNDS']?.trim();
  if (raw == null || raw.isEmpty) {
    return 10;
  }
  final parsed = int.tryParse(raw);
  expect(
    parsed,
    isNotNull,
    reason: 'TEST_MACOS_CAMERA_STRESS_ROUNDS は整数で指定してください。',
  );
  expect(
    parsed!,
    greaterThan(0),
    reason: 'TEST_MACOS_CAMERA_STRESS_ROUNDS は 1 以上で指定してください。',
  );
  return parsed;
}

Future<T> _withStepTimeout<T>({
  required int round,
  required String step,
  required Future<T> Function() action,
  Duration timeout = _cameraOperationTimeout,
}) async {
  logE2eMessage(
      'stage=${step}_start round=$round timeout=${timeout.inSeconds}s');
  try {
    final result = await action().timeout(
      timeout,
      onTimeout: () => throw TimeoutException(
        '$step timed out at round $round after ${timeout.inSeconds}s',
        timeout,
      ),
    );
    logE2eMessage('stage=${step}_finished round=$round status=ok');
    return result;
  } catch (e) {
    logE2eMessage('stage=${step}_finished round=$round status=failed error=$e');
    rethrow;
  }
}
