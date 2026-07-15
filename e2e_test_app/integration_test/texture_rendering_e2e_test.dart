// native renderer が払い出す Texture ID を Flutter Widget へ渡し、
// remote renderer の生成・描画・破棄と local camera preview を検証する E2E。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';
import 'helpers/video_source.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'texture_rendering_remote: remote Texture の生成・Widget 描画・破棄を検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-texture-remote',
      );
      final receiverConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        audio: false,
        video: true,
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
      final receiverTimeout = connectionStageTimeout(receiverConfig);
      final senderTimeout = connectionStageTimeout(senderConfig);
      const remoteTrackTimeout = Duration(seconds: 30);

      ObservedConnection? receiver;
      ObservedConnection? sender;
      StreamSubscription<String>? debugSubscription;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      ColorBarVideoSource? videoSource;
      final debugMessages = <String>[];
      final textureBoundaryKey = GlobalKey();
      var senderDisconnected = false;
      Object? bodyError;

      try {
        receiver = await ObservedConnection.create(
          name: 'texture-receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'texture-sender',
          config: senderConfig,
        );
        debugSubscription = receiver.connection.debugMessages.listen(
          debugMessages.add,
        );

        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createExternalVideoTrack();
        stream.addTrack(videoTrack);
        videoSource = ColorBarVideoSource(
          width: 320,
          height: 180,
          frameRate: 30,
        );

        await receiver.connect();
        await receiver.waitUntilConnected(receiverTimeout);
        await sender.connect(stream);
        await sender.waitUntilConnected(senderTimeout);
        videoSource.start(videoTrack);

        final senderConnectionId = sender.connectionId;
        expect(senderConnectionId, isNotNull);
        await receiver.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: senderConnectionId!,
          timeout: remoteTrackTimeout,
        );

        final remoteTrack = receiver
            .connection.remoteMediaStreams[senderConnectionId]?.videoTrack;
        expect(
          remoteTrack,
          isNotNull,
          reason: 'SoraTrackEvent 発火時に remote video track が保持されていること。',
        );
        expect(
          remoteTrack!.textureId,
          isNotNull,
          reason: 'native remote renderer が Texture ID を払い出すこと。',
        );
        expect(
          remoteTrack.textureId,
          greaterThanOrEqualTo(0),
          reason: 'Texture ID は 0 以上であること。',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: textureBoundaryKey,
                  child: SizedBox(
                    width: 320,
                    height: 180,
                    child: SoraRemoteVideoWidget(
                      track: remoteTrack,
                      fit: BoxFit.fill,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        final texture = tester.widget<Texture>(find.byType(Texture));
        expect(
          texture.textureId,
          remoteTrack.textureId,
          reason: 'SoraRemoteVideoWidget が native renderer の Texture ID を使うこと。',
        );

        // Texture ID の配線だけでなく、native renderer が受け取ったカラーバーを
        // Flutter の描画結果まで反映していることを実ピクセルで確認する。
        final renderedFrame = await _waitForRenderedColorBars(
          tester,
          textureBoundaryKey,
        );
        expect(
          renderedFrame.distinctColorCount,
          greaterThanOrEqualTo(4),
          reason: '描画結果にカラーバー由来の複数色が含まれること。',
        );
        expect(
          renderedFrame.brightSampleRatio,
          greaterThan(0.25),
          reason: '描画結果が未描画の黒い Texture ではないこと。',
        );

        final receivedStats = await waitForVideoInboundStats(
          tester,
          receiver.connection,
        );
        expect(
          receivedStats.bytesReceived,
          greaterThan(0),
          reason: 'Texture へ接続した remote track が映像を受信していること。',
        );

        final textureId = remoteTrack.textureId!;
        await sender.disconnect();
        await sender.waitUntilDisconnected(senderTimeout);
        senderDisconnected = true;
        await receiver.waitForRemoteMediaStreamRemoved(
          tester,
          connectionId: senderConnectionId,
          timeout: remoteTrackTimeout,
        );

        expect(
          debugMessages.any(
            (message) =>
                message.contains('remote_track_detached:') &&
                message.contains('textureId=$textureId'),
          ),
          isTrue,
          reason: 'remote track 削除時に対応する native renderer が破棄されること。',
        );

        // 破棄済み Texture を Widget ツリーから外し、placeholder へ安全に遷移する。
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SoraRemoteVideoWidget(
                track: const RemoteMediaStreamTrack(
                  trackId: 'removed',
                  kind: 'video',
                  connectionId: 'removed',
                ),
                placeholder: const Text('映像なし'),
              ),
            ),
          ),
        );
        expect(find.byType(Texture), findsNothing);
        expect(find.text('映像なし'), findsOneWidget);
        receiver.throwIfHasErrors();
        sender.throwIfHasErrors();
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        videoSource?.stop();
        if (!senderDisconnected) {
          await runCleanupStep(cleanupErrors, 'sender.disconnect', () async {
            if (sender != null) {
              await sender.disconnect();
              await sender.waitUntilDisconnected(senderTimeout);
            }
          });
        }
        await runCleanupStep(cleanupErrors, 'receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver.waitUntilDisconnected(receiverTimeout);
          }
        });
        await runCleanupStep(
          cleanupErrors,
          'debugSubscription.cancel',
          () async => debugSubscription?.cancel(),
        );
        await runCleanupStep(
          cleanupErrors,
          'sender.dispose',
          () async => sender?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'receiver.dispose',
          () async => receiver?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'stream.dispose',
          () async => stream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'videoTrack.dispose',
          () async => videoTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty && bodyError == null) {
          throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
        }
      }
    },
  );

  final runLocalCameraTest =
      Platform.environment['TEST_ENABLE_CAMERA_TEXTURE_E2E'] == 'true';
  testWidgets(
    'texture_rendering_local: localVideo の Texture ID を Widget で描画する',
    (WidgetTester tester) async {
      final devices = await MediaDevices.enumerateVideoInputDevices();
      expect(
        devices,
        isNotEmpty,
        reason: 'local Texture E2E にはカメラ入力デバイスが必要です。',
      );

      final env = loadE2eEnvironment();
      final config = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: buildChannelId(
          env.channelPrefix,
          suffix: '-texture-local',
        ),
        role: SoraRole.sendonly,
        audio: false,
        video: true,
        useAudioDevice: false,
        metadata: env.metadata,
      );
      final timeout = connectionStageTimeout(config);

      SoraConnection? connection;
      StreamSubscription<SoraConnectionEvent>? eventSubscription;
      StreamSubscription<SoraLocalVideoHandle>? localVideoSubscription;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      final localTextureId = Completer<int>();
      final errors = <SoraConnectionErrorEvent>[];
      Object? bodyError;

      try {
        stream = await MediaDevices.getUserMedia(
          GetUserMediaOptions(
            audio: false,
            video: true,
            videoDeviceId: devices.first.deviceId,
            videoWidth: 320,
            videoHeight: 180,
            videoFrameRate: 30,
          ),
        );
        videoTrack = stream.currentVideoTrackOrNull;
        expect(videoTrack, isNotNull);

        connection = await Sora.createConnection(config);
        eventSubscription = connection.events.listen((event) {
          if (event is SoraConnectionErrorEvent) {
            errors.add(event);
          }
        });
        localVideoSubscription = connection.localVideo.listen((handle) {
          if (!localTextureId.isCompleted) {
            localTextureId.complete(handle.textureId);
          }
        });

        await connection.connect(stream);
        final textureId = await localTextureId.future.timeout(timeout);
        expect(textureId, greaterThanOrEqualTo(0));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SoraLocalVideoWidget(textureId: textureId, mirror: true),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        final texture = tester.widget<Texture>(find.byType(Texture));
        expect(texture.textureId, textureId);
        expect(find.byType(Transform), findsOneWidget);

        final outboundStats = await waitForVideoOutboundStats(
          tester,
          connection,
        );
        expect(outboundStats.bytesSent, greaterThan(0));
        expect(errors, isEmpty);
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];
        await runCleanupStep(
          cleanupErrors,
          'connection.disconnect',
          () async => connection?.disconnect(),
        );
        await runCleanupStep(
          cleanupErrors,
          'eventSubscription.cancel',
          () async => eventSubscription?.cancel(),
        );
        await runCleanupStep(
          cleanupErrors,
          'localVideoSubscription.cancel',
          () async => localVideoSubscription?.cancel(),
        );
        await runCleanupStep(
          cleanupErrors,
          'connection.dispose',
          () async => connection?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'stream.dispose',
          () async => stream?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'videoTrack.dispose',
          () async => videoTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty && bodyError == null) {
          throw StateError('Cleanup failed: ${cleanupErrors.join(" | ")}');
        }
      }
    },
    skip: !runLocalCameraTest,
  );
}

/// remote Texture にカラーバーが描画されるまで待つ。
Future<_RenderedFrameObservation> _waitForRenderedColorBars(
  WidgetTester tester,
  GlobalKey boundaryKey,
) async {
  const maxAttempts = 30;
  const interval = Duration(milliseconds: 500);
  _RenderedFrameObservation? lastObservation;

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    await tester.pump(interval);
    final renderObject = boundaryKey.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      continue;
    }

    final observation = await _observeRenderedFrame(renderObject);
    lastObservation = observation;
    if (observation.distinctColorCount >= 4 &&
        observation.brightSampleRatio > 0.25) {
      return observation;
    }
  }

  throw StateError(
    'remote Texture にカラーバーが描画されませんでした: $lastObservation',
  );
}

/// [boundary] の RGBA 画素を標本化し、色数と明るい画素の割合を返す。
Future<_RenderedFrameObservation> _observeRenderedFrame(
  RenderRepaintBoundary boundary,
) async {
  final image = await boundary.toImage();
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) {
      throw StateError('Texture の RGBA 画素を取得できませんでした。');
    }

    final pixels = byteData.buffer.asUint8List();
    final colors = <int>{};
    var sampledPixels = 0;
    var brightPixels = 0;

    // 圧縮ノイズの影響を抑えるため RGB を 3 bit ずつに量子化し、
    // 4 pixel 間隔でカラーバーの色分布を確認する。
    for (var y = 0; y < image.height; y += 4) {
      for (var x = 0; x < image.width; x += 4) {
        final offset = (y * image.width + x) * 4;
        final alpha = pixels[offset + 3];
        if (alpha < 128) {
          continue;
        }
        final red = pixels[offset];
        final green = pixels[offset + 1];
        final blue = pixels[offset + 2];
        colors.add(((red >> 5) << 6) | ((green >> 5) << 3) | (blue >> 5));
        sampledPixels++;
        if (red + green + blue >= 96) {
          brightPixels++;
        }
      }
    }

    final brightSampleRatio =
        sampledPixels == 0 ? 0.0 : brightPixels / sampledPixels;
    return _RenderedFrameObservation(
      width: image.width,
      height: image.height,
      distinctColorCount: colors.length,
      brightSampleRatio: brightSampleRatio,
    );
  } finally {
    image.dispose();
  }
}

/// Texture の実描画結果を要約する。
final class _RenderedFrameObservation {
  const _RenderedFrameObservation({
    required this.width,
    required this.height,
    required this.distinctColorCount,
    required this.brightSampleRatio,
  });

  final int width;
  final int height;
  final int distinctColorCount;
  final double brightSampleRatio;

  @override
  String toString() {
    return '_RenderedFrameObservation('
        'width=$width, '
        'height=$height, '
        'distinctColorCount=$distinctColorCount, '
        'brightSampleRatio=$brightSampleRatio)';
  }
}
