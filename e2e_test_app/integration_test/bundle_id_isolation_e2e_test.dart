// 同一 bundleId 間の受信分離を確認する E2E。
// 3 接続 (A observer recvonly bundle-a、B sender-same sendonly bundle-a、
// C sender-other sendonly bundle-b) で A が B を受信せず C のみを受信することを確認する。
// DataChannel / notify の分離は補助ログのみで pass 条件に含めない。

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
    'bundle_id_isolation: 同一 bundleId の接続から受信しないことを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-bundleid',
      );

      // A = observer: recvonly + bundle-a
      final observerConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.recvonly,
        bundleId: 'bundle-a',
        metadata: env.metadata,
      );

      // B = sender-same: sendonly + bundle-a (A と同じ bundleId)
      final senderSameConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        bundleId: 'bundle-a',
        video: true,
        audio: false,
        metadata: env.metadata,
      );

      // C = sender-other: sendonly + bundle-b (A と異なる bundleId)
      final senderOtherConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        bundleId: 'bundle-b',
        video: true,
        audio: false,
        metadata: env.metadata,
      );

      final observerConnectTimeout = connectionStageTimeout(observerConfig);
      final senderSameConnectTimeout =
          connectionStageTimeout(senderSameConfig);
      final senderOtherConnectTimeout =
          connectionStageTimeout(senderOtherConfig);
      final observerDisconnectTimeout =
          connectionStageTimeout(observerConfig);
      final senderSameDisconnectTimeout =
          connectionStageTimeout(senderSameConfig);
      final senderOtherDisconnectTimeout =
          connectionStageTimeout(senderOtherConfig);
      const observerTrackTimeout = Duration(seconds: 30);

      // B の送信用リソース
      ObservedConnection? senderSame;
      LocalMediaStream? streamB;
      LocalVideoTrack? videoTrackB;
      ColorBarVideoSource? videoSourceB;

      // C の送信用リソース
      ObservedConnection? senderOther;
      LocalMediaStream? streamC;
      LocalVideoTrack? videoTrackC;
      ColorBarVideoSource? videoSourceC;

      // A = observer
      ObservedConnection? observer;

      VideoInboundStats? firstInbound;
      VideoInboundStats? secondInbound;
      Object? bodyError;

      try {
        // ------------------------------------------------------------------
        // B の送信用リソースを準備する
        // ------------------------------------------------------------------
        streamB = MediaDevices.createMediaStream();
        videoTrackB = MediaDevices.createExternalVideoTrack();
        streamB.addTrack(videoTrackB);
        videoSourceB = ColorBarVideoSource(
          width: 320,
          height: 180,
          frameRate: 30,
        );

        // ------------------------------------------------------------------
        // C の送信用リソースを準備する
        // ------------------------------------------------------------------
        streamC = MediaDevices.createMediaStream();
        videoTrackC = MediaDevices.createExternalVideoTrack();
        streamC.addTrack(videoTrackC);
        videoSourceC = ColorBarVideoSource(
          width: 320,
          height: 180,
          frameRate: 30,
        );

        // ------------------------------------------------------------------
        // Step 1: A (observer) を接続する (recvonly, bundleId: bundle-a)
        // ------------------------------------------------------------------
        observer = await ObservedConnection.create(
          name: 'observer',
          config: observerConfig,
        );
        senderSame = await ObservedConnection.create(
          name: 'sender-same',
          config: senderSameConfig,
        );
        senderOther = await ObservedConnection.create(
          name: 'sender-other',
          config: senderOtherConfig,
        );

        logE2eMessage(
          'stage=observer_connect_start channelId=$channelId '
          'bundleId=${observer.connection.bundleId}',
        );
        await observer.connect();
        await observer.waitUntilConnected(observerConnectTimeout);
        observer.throwIfHasErrors();
        logE2eMessage(
          'stage=observer_connected channelId=$channelId '
          'observerConnectionId=${observer.connectionId}',
        );

        // ------------------------------------------------------------------
        // Step 2: B (sender-same) を接続する (sendonly, bundleId: bundle-a)
        //         A と同じ bundleId のため、互いのメディアは届かない
        // ------------------------------------------------------------------
        logE2eMessage(
          'stage=sender_same_connect_start channelId=$channelId '
          'bundleId=${senderSame.connection.bundleId}',
        );
        await senderSame.connect(streamB);
        await senderSame.waitUntilConnected(senderSameConnectTimeout);
        senderSame.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_same_connected channelId=$channelId '
          'senderSameConnectionId=${senderSame.connectionId}',
        );

        final senderSameConnectionId = senderSame.connectionId;
        expect(
          senderSameConnectionId,
          isNotNull,
          reason: 'sender-same connected 後に connectionId が確定していること。',
        );

        // B のフレーム投入を開始し、A に届かないことを settle 時間で確認する
        videoSourceB.start(videoTrackB);
        await tester.pump(const Duration(seconds: 5));

        // A の remoteMediaStreams に B の connectionId が存在しないことを確認する
        expect(
          observer.connection.remoteMediaStreams
              .containsKey(senderSameConnectionId),
          isFalse,
          reason:
              '同一 bundleId の sender-same からの remoteMediaStreams を'
              '受信しないこと。',
        );

        // A の trackEvents に B の connectionId が存在しないことを確認する
        expect(
          observer.trackEvents.where(
            (RemoteTrackObservation o) =>
                o.connectionId == senderSameConnectionId,
          ),
          isEmpty,
          reason:
              '同一 bundleId の sender-same からの SoraTrackEvent を'
              '受信しないこと。',
        );

        logE2eMessage(
          'stage=sender_same_isolation_confirmed channelId=$channelId '
          'senderSameConnectionId=$senderSameConnectionId',
        );

        // ------------------------------------------------------------------
        // Step 3: C (sender-other) を接続する (sendonly, bundleId: bundle-b)
        //         異なる bundleId のため、A が C のメディアを受信する
        // ------------------------------------------------------------------
        logE2eMessage(
          'stage=sender_other_connect_start channelId=$channelId '
          'bundleId=${senderOther.connection.bundleId}',
        );
        await senderOther.connect(streamC);
        await senderOther.waitUntilConnected(senderOtherConnectTimeout);
        senderOther.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_other_connected channelId=$channelId '
          'senderOtherConnectionId=${senderOther.connectionId}',
        );

        final senderOtherConnectionId = senderOther.connectionId;
        expect(
          senderOtherConnectionId,
          isNotNull,
          reason: 'sender-other connected 後に connectionId が確定していること。',
        );

        // C のフレーム投入を開始し、受信待ちに入る
        videoSourceC.start(videoTrackC);
        await tester.pump(const Duration(seconds: 1));

        // A が C 由来の SoraTrackEvent を受信することを確認する
        final remoteTrack = await observer.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: senderOtherConnectionId!,
          timeout: observerTrackTimeout,
        );
        logE2eMessage(
          'stage=observer_track_ready channelId=$channelId '
          'trackId=${remoteTrack.trackId} '
          'remoteConnectionId=${remoteTrack.connectionId}',
        );

        // A の remoteMediaStreams に C のエントリが生成されることを確認する
        final streamEntry = await observer.waitForRemoteMediaStreamEntry(
          tester,
          connectionId: senderOtherConnectionId,
          timeout: observerTrackTimeout,
        );
        logE2eMessage(
          'stage=observer_stream_entry_ready channelId=$channelId '
          'connectionId=${streamEntry.connectionId} '
          'hasVideo=${streamEntry.videoTrack != null}',
        );

        // A の inbound-rtp stats を確認する
        firstInbound =
            await waitForVideoInboundStats(tester, observer.connection);
        secondInbound = await waitForVideoInboundStats(
          tester,
          observer.connection,
          previous: firstInbound,
        );
        observer.throwIfHasErrors();
        logE2eMessage(
          'stage=observer_inbound_ready channelId=$channelId '
          'first=$firstInbound second=$secondInbound',
        );

        expect(
          firstInbound.bytesReceived,
          greaterThan(0),
          reason:
              'observer 初回取得時に video inbound-rtp の bytesReceived が'
              '増えていること。',
        );
        expect(
          firstInbound.packetsReceived,
          greaterThan(0),
          reason:
              'observer 初回取得時に video inbound-rtp の packetsReceived が'
              '増えていること。',
        );
        expect(
          secondInbound.bytesReceived,
          greaterThan(firstInbound.bytesReceived),
          reason:
              'observer 2 回目取得時に video inbound-rtp の bytesReceived が'
              '増えていること。',
        );
        expect(
          secondInbound.packetsReceived,
          greaterThan(firstInbound.packetsReceived),
          reason:
              'observer 2 回目取得時に video inbound-rtp の packetsReceived が'
              '増えていること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        if (observer != null ||
            senderSame != null ||
            senderOther != null) {
          logE2eMessage(
            'stage=cleanup_start '
            'observer=${observer?.debugSummary()} '
            'senderSame=${senderSame?.debugSummary()} '
            'senderOther=${senderOther?.debugSummary()} '
            'observerInboundLast=$secondInbound',
          );
        }

        final cleanupErrors = <String>[];

        try {
          videoSourceB?.stop();
        } catch (e) {
          cleanupErrors.add('videoSourceB.stop: $e');
          logE2eMessage(
            'stage=cleanup_error step=videoSourceB.stop error=$e',
          );
        }
        try {
          videoSourceC?.stop();
        } catch (e) {
          cleanupErrors.add('videoSourceC.stop: $e');
          logE2eMessage(
            'stage=cleanup_error step=videoSourceC.stop error=$e',
          );
        }

        await runCleanupStep(
          cleanupErrors,
          'sender-same.disconnect',
          () async {
            if (senderSame != null) {
              await senderSame.disconnect();
              await senderSame.waitUntilDisconnected(
                senderSameDisconnectTimeout,
              );
            }
          },
        );
        await runCleanupStep(
          cleanupErrors,
          'sender-other.disconnect',
          () async {
            if (senderOther != null) {
              await senderOther.disconnect();
              await senderOther.waitUntilDisconnected(
                senderOtherDisconnectTimeout,
              );
            }
          },
        );
        await runCleanupStep(
          cleanupErrors,
          'observer.disconnect',
          () async {
            if (observer != null) {
              await observer.disconnect();
              await observer.waitUntilDisconnected(
                observerDisconnectTimeout,
              );
            }
          },
        );

        await runCleanupStep(
          cleanupErrors,
          'observer.dispose',
          () async => await observer?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'sender-same.dispose',
          () async => await senderSame?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'sender-other.dispose',
          () async => await senderOther?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'streamB.dispose',
          () async => await streamB?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'videoTrackB.dispose',
          () async => await videoTrackB?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'streamC.dispose',
          () async => await streamC?.dispose(),
        );
        await runCleanupStep(
          cleanupErrors,
          'videoTrackC.dispose',
          () async => await videoTrackC?.dispose(),
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
        observer.errors,
        isEmpty,
        reason: 'observer で接続エラーイベントが発生しないこと。',
      );
      expect(
        senderSame.errors,
        isEmpty,
        reason: 'sender-same で接続エラーイベントが発生しないこと。',
      );
      expect(
        senderOther.errors,
        isEmpty,
        reason: 'sender-other で接続エラーイベントが発生しないこと。',
      );
    },
  );
}
