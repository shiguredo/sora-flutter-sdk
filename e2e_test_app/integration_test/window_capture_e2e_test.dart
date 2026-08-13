// ダミーウィンドウを ScreenCaptureKit でキャプチャし、受信側の stats で
// 映像が届くことを検証する E2E。
//
// macOS ローカル専用。SCStream の開始には画面収録権限が必要なため、
// CI では実行できない。ローカルでシステム設定から画面収録権限を
// 付与してから実行する。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show FlutterError, FlutterErrorDetails;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'helpers/connection_helpers.dart';
import 'helpers/stats_helpers.dart';
import 'helpers/test_helpers.dart';

/// ダミーウィンドウの表示・破棄を制御する MethodChannel。
const _dummyWindowChannel = MethodChannel('e2e_test_app/dummy_window');

/// ダミーウィンドウのタイトル。AppDelegate 側のタイトルと一致させる。
const _dummyWindowTitle = 'Sora E2E Dummy Window';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'window-capture: ダミーウィンドウの映像が receiver に届くことを検証する',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-windowcapture',
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
        video: true,
        audio: false,
        useAudioDevice: false,
        metadata: env.metadata,
      );

      final receiverConnectTimeout = connectionStageTimeout(receiverConfig);
      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final receiverDisconnectTimeout = connectionStageTimeout(receiverConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);
      const receiverTrackTimeout = Duration(seconds: 30);

      ObservedConnection? sender;
      ObservedConnection? receiver;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      VideoOutboundStats? firstOutbound;
      VideoOutboundStats? secondOutbound;
      VideoInboundStats? firstInbound;
      VideoInboundStats? secondInbound;
      Object? bodyError;

      try {
        // ダミーウィンドウを表示し、SCShareableContent に反映されるまで待つ
        await _dummyWindowChannel.invokeMethod<void>('show');
        final source = await _waitForDummyWindowSource(tester);
        logE2eMessage(
          'stage=dummy_window_ready channelId=$channelId '
          'sourceId=${source.id} title=${source.title}',
        );

        receiver = await ObservedConnection.create(
          name: 'receiver',
          config: receiverConfig,
        );
        sender = await ObservedConnection.create(
          name: 'sender',
          config: senderConfig,
        );

        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createWindowVideoTrack(source);
        expect(
          videoTrack.captureType,
          VideoTrackCaptureType.window,
          reason:
              'createWindowVideoTrack で作成したトラックの captureType が window であること。',
        );
        stream.addTrack(videoTrack);

        logE2eMessage(
          'stage=receiver_connect_start channelId=$channelId '
          'bundleId=${receiver.connection.bundleId}',
        );
        await receiver.connect();
        await receiver.waitUntilConnected(receiverConnectTimeout);
        receiver.throwIfHasErrors();
        logE2eMessage(
          'stage=receiver_connected channelId=$channelId '
          'receiverConnectionId=${receiver.connectionId}',
        );

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId '
          'bundleId=${sender.connection.bundleId}',
        );
        await sender.connect(stream);
        await sender.waitUntilConnected(senderConnectTimeout);
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_connected channelId=$channelId '
          'senderConnectionId=${sender.connectionId}',
        );

        final senderConnectionId = sender.connectionId;
        expect(
          senderConnectionId,
          isNotNull,
          reason: 'sender connected 後に connectionId が確定していること。',
        );

        final remoteTrack = await receiver.waitForRemoteVideoTrackFrom(
          tester,
          remoteConnectionId: senderConnectionId!,
          timeout: receiverTrackTimeout,
        );
        logE2eMessage(
          'stage=receiver_track_ready channelId=$channelId '
          'trackId=${remoteTrack.trackId} remoteConnectionId=${remoteTrack.connectionId}',
        );

        firstOutbound =
            await waitForVideoOutboundStats(tester, sender.connection);
        secondOutbound = await waitForVideoOutboundStats(
          tester,
          sender.connection,
          previous: firstOutbound,
        );
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_outbound_ready channelId=$channelId '
          'first=$firstOutbound second=$secondOutbound',
        );

        firstInbound =
            await waitForVideoInboundStats(tester, receiver.connection);
        secondInbound = await waitForVideoInboundStats(
          tester,
          receiver.connection,
          previous: firstInbound,
        );
        receiver.throwIfHasErrors();
        logE2eMessage(
          'stage=receiver_inbound_ready channelId=$channelId '
          'first=$firstInbound second=$secondInbound',
        );

        expect(
          secondOutbound.bytesSent,
          greaterThan(firstOutbound.bytesSent),
          reason: 'sender 2 回目取得時に video outbound-rtp の bytesSent が増えていること。',
        );
        expect(
          secondOutbound.packetsSent,
          greaterThan(firstOutbound.packetsSent),
          reason: 'sender 2 回目取得時に video outbound-rtp の packetsSent が増えていること。',
        );
        expect(
          secondInbound.bytesReceived,
          greaterThan(firstInbound.bytesReceived),
          reason:
              'receiver 2 回目取得時に video inbound-rtp の bytesReceived が増えていること。',
        );
        expect(
          secondInbound.packetsReceived,
          greaterThan(firstInbound.packetsReceived),
          reason:
              'receiver 2 回目取得時に video inbound-rtp の packetsReceived が増えていること。',
        );

        final framesDecoded = secondInbound.framesDecoded;
        if (framesDecoded != null) {
          expect(
            framesDecoded,
            greaterThan(0),
            reason: 'framesDecoded が存在する場合は 0 より大きいこと。',
          );
        }

        final framesReceived = secondInbound.framesReceived;
        if (framesReceived != null) {
          expect(
            framesReceived,
            greaterThan(0),
            reason: 'framesReceived が存在する場合は 0 より大きいこと。',
          );
        }

        expect(
          remoteTrack.kind,
          'video',
          reason: 'receiver で sender 由来の video track が 1 回到達すること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        if (sender != null || receiver != null) {
          logE2eMessage(
            'stage=cleanup_start '
            'sender=${sender?.debugSummary()} '
            'receiver=${receiver?.debugSummary()} '
            'senderOutboundLast=$secondOutbound '
            'receiverInboundLast=$secondInbound',
          );
        }

        final cleanupErrors = <String>[];

        Future<void> runCleanupStep(
          String name,
          Future<void> Function() action,
        ) async {
          try {
            await action();
          } catch (e) {
            cleanupErrors.add('$name: $e');
            logE2eMessage('stage=cleanup_error step=$name error=$e');
          }
        }

        await runCleanupStep('sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender.waitUntilDisconnected(senderDisconnectTimeout);
          }
        });
        await runCleanupStep('receiver.disconnect', () async {
          if (receiver != null) {
            await receiver.disconnect();
            await receiver.waitUntilDisconnected(receiverDisconnectTimeout);
          }
        });
        await runCleanupStep(
            'sender.dispose', () async => await sender?.dispose());
        await runCleanupStep(
          'receiver.dispose',
          () async => await receiver?.dispose(),
        );
        await runCleanupStep(
            'stream.dispose', () async => await stream?.dispose());
        await runCleanupStep(
          'videoTrack.dispose',
          () async => await videoTrack?.dispose(),
        );
        // dummyWindow.hide は videoTrack.dispose (SCStream 停止) の後に実行する。
        // キャプチャ中のウィンドウ消失は didStopWithError 経由で
        // window_capture_error が通知されるため、正常系テストでは
        // 先にキャプチャを停止してからウィンドウを閉じる。
        // エラー通知の検証は window-capture-error テストが担当する。
        await runCleanupStep('dummyWindow.hide', () async {
          await _dummyWindowChannel.invokeMethod<void>('hide');
        });

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed errors=${cleanupErrors.join(" | ")}',
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
        sender.errors,
        isEmpty,
        reason: 'sender で接続エラーイベントが発生しないこと。',
      );
      expect(
        receiver.errors,
        isEmpty,
        reason: 'receiver で接続エラーイベントが発生しないこと。',
      );
    },
  );
  testWidgets(
    'window-capture-error: キャプチャ中のウィンドウが閉じられると '
    'window_capture_error が通知される',
    (WidgetTester tester) async {
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-windowcapture-error',
      );

      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        video: true,
        audio: false,
        useAudioDevice: false,
        metadata: env.metadata,
      );

      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);

      ObservedConnection? sender;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      Object? bodyError;

      try {
        // ダミーウィンドウを表示し、SCShareableContent に反映されるまで待つ
        await _dummyWindowChannel.invokeMethod<void>('show');
        final source = await _waitForDummyWindowSource(tester);
        logE2eMessage(
          'stage=dummy_window_ready channelId=$channelId sourceId=${source.id}',
        );

        sender = await ObservedConnection.create(
          name: 'sender',
          config: senderConfig,
        );
        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createWindowVideoTrack(source);
        stream.addTrack(videoTrack);

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId '
          'bundleId=${sender.connection.bundleId}',
        );
        await sender.connect(stream);
        await sender.waitUntilConnected(senderConnectTimeout);
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_connected channelId=$channelId '
          'senderConnectionId=${sender.connectionId}',
        );

        // ウィンドウキャプチャが動いていることを outbound stats で確認する
        await waitForVideoOutboundStats(tester, sender.connection);
        logE2eMessage('stage=sender_outbound_ready channelId=$channelId');

        // キャプチャ中のウィンドウを閉じて、SCStream をエラーにさせる
        await _dummyWindowChannel.invokeMethod<void>('hide');
        logE2eMessage('stage=dummy_window_hidden channelId=$channelId');

        // window_capture_error イベントが通知されるまで待つ
        final errorEvent = await _waitForWindowCaptureError(
          sender,
          timeout: const Duration(seconds: 30),
        );
        logE2eMessage(
          'stage=window_capture_error_received channelId=$channelId '
          'code=${errorEvent.code} message=${errorEvent.message}',
        );

        expect(
          errorEvent.code,
          SoraErrorCode.windowCaptureError,
          reason: 'キャプチャ中のウィンドウ消失が window_capture_error として通知されること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];

        Future<void> runCleanupStep(
          String name,
          Future<void> Function() action,
        ) async {
          try {
            await action();
          } catch (e) {
            cleanupErrors.add('$name: $e');
            logE2eMessage('stage=cleanup_error step=$name error=$e');
          }
        }

        await runCleanupStep('dummyWindow.hide', () async {
          await _dummyWindowChannel.invokeMethod<void>('hide');
        });
        await runCleanupStep('sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender.waitUntilDisconnected(senderDisconnectTimeout);
          }
        });
        await runCleanupStep(
            'sender.dispose', () async => await sender?.dispose());
        await runCleanupStep(
            'stream.dispose', () async => await stream?.dispose());
        await runCleanupStep(
            'videoTrack.dispose', () async => await videoTrack?.dispose());

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
    },
  );
  testWidgets(
    'window-capture-reconnect: ウィンドウ消失後の同じ track での再接続は映像ゼロのまま成功しない',
    (WidgetTester tester) async {
      // ウィンドウ消失 (didStopWithError) 後に同じ track で再接続する。
      // 停止済み renderer がキャッシュされて再利用されると、
      // ensureLocalVideoTrackTexture の early-return が死んだ textureId を
      // 返し、SCStream が再起動されず映像ゼロのまま「成功」してしまう。
      // 修正後は停止済み renderer が破棄されて作り直され、新しい
      // SCStream の開始はウィンドウ不在 (破棄されたウィンドウの ID は
      // 新しいウィンドウで再利用されない) で失敗し、再接続は
      // windowCaptureError 通知付きで失敗する。
      // 「映像ゼロのまま成功しない」ことを検証する (回帰テスト)。
      final env = loadE2eEnvironment();
      final channelId = buildChannelId(
        env.channelPrefix,
        suffix: '-windowcapture-reconnect',
      );

      final senderConfig = SoraConnectionConfig(
        signalingUrls: env.signalingUrls,
        channelId: channelId,
        role: SoraRole.sendonly,
        video: true,
        audio: false,
        useAudioDevice: false,
        metadata: env.metadata,
      );

      final senderConnectTimeout = connectionStageTimeout(senderConfig);
      final senderDisconnectTimeout = connectionStageTimeout(senderConfig);

      ObservedConnection? sender;
      LocalMediaStream? stream;
      LocalVideoTrack? videoTrack;
      VideoOutboundStats? firstOutbound;
      VideoOutboundStats? secondOutbound;
      Object? bodyError;

      try {
        // ダミーウィンドウを表示し、SCShareableContent に反映されるまで待つ
        await _dummyWindowChannel.invokeMethod<void>('show');
        final source = await _waitForDummyWindowSource(tester);
        logE2eMessage(
          'stage=dummy_window_ready channelId=$channelId sourceId=${source.id}',
        );

        sender = await ObservedConnection.create(
          name: 'sender',
          config: senderConfig,
        );

        stream = MediaDevices.createMediaStream();
        videoTrack = MediaDevices.createWindowVideoTrack(source);
        stream.addTrack(videoTrack);

        logE2eMessage(
          'stage=sender_connect_start channelId=$channelId',
        );
        await sender.connect(stream);
        await sender.waitUntilConnected(senderConnectTimeout);
        sender.throwIfHasErrors();
        logE2eMessage('stage=sender_connected channelId=$channelId');

        // 1 回目の接続で映像が流れていることを確認する
        firstOutbound =
            await waitForVideoOutboundStats(tester, sender.connection);
        secondOutbound = await waitForVideoOutboundStats(
          tester,
          sender.connection,
          previous: firstOutbound,
        );
        sender.throwIfHasErrors();
        logE2eMessage(
          'stage=sender_outbound_ready channelId=$channelId '
          'first=$firstOutbound second=$secondOutbound',
        );

        // キャプチャ中のウィンドウを閉じて SCStream をエラーにする
        await _dummyWindowChannel.invokeMethod<void>('hide');
        logE2eMessage('stage=dummy_window_hidden channelId=$channelId');

        // window_capture_error イベントが通知されるまで待つ
        await _waitForWindowCaptureError(
          sender,
          timeout: const Duration(seconds: 30),
        );
        logE2eMessage(
          'stage=window_capture_error_received channelId=$channelId',
        );

        // ウィンドウを表示し直す。閉じられたウィンドウは破棄されているため、
        // 新しい CGWindowID が割り当てられる。
        await _dummyWindowChannel.invokeMethod<void>('show');
        logE2eMessage('stage=dummy_window_reshown channelId=$channelId');

        // 一旦切断して、同じ track で再接続する
        await sender.disconnect();
        await sender.waitUntilDisconnected(senderDisconnectTimeout);
        logE2eMessage('stage=sender_disconnected channelId=$channelId');

        // 再接続前のエラーイベント件数を記録しておく
        final errorsBeforeReconnect = sender.errors.length;
        final reconnectTarget = sender;

        // 停止済み renderer が再利用されると connect は「成功」してしまう。
        // 修正後は新しい renderer の SCStream 開始がウィンドウ不在で失敗し、
        // connect が失敗するため、「映像ゼロのまま成功しない」ことを検証する。
        // connect() の失敗時に SDK 内部の _connectReadyCompleter が
        // エラー完了し、await されない future の unhandled async error として
        // zone へ届く。該当エラーは connect() の戻り値側で検証済みのため
        // ここでは無視し、それ以外は通常どおり報告する。
        final reconnectError = await runZonedGuarded(
          () async {
            try {
              await reconnectTarget.connect(stream);
              return null;
            } catch (e) {
              return e;
            }
          },
          (error, stackTrace) {
            final message = error.toString();
            if (error is StateError &&
                message.contains('Failed to apply video capture backend')) {
              logE2eMessage('stage=swallowed_unhandled_error message=$message');
              return;
            }
            FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stackTrace),
            );
          },
        );
        expect(
          reconnectError,
          isA<StateError>(),
          reason: '再接続は映像ゼロのまま成功せず、失敗すること。',
        );
        logE2eMessage('stage=sender_reconnect_failed channelId=$channelId');

        // エラーイベントの配信は非同期のため、件数が増えるまで待つ
        final errorEventDeadline =
            DateTime.now().add(const Duration(seconds: 10));
        while (sender.errors.length <= errorsBeforeReconnect &&
            DateTime.now().isBefore(errorEventDeadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        // windowCaptureError のエラーイベントが通知されていること
        expect(
          sender.errors.length,
          greaterThan(errorsBeforeReconnect),
          reason: '再接続の失敗がエラーイベントとして通知されること。',
        );
        expect(
          sender.errors.last.code,
          SoraErrorCode.windowCaptureError,
          reason: '再接続の失敗が window_capture_error として通知されること。',
        );
      } catch (e) {
        bodyError = e;
        rethrow;
      } finally {
        final cleanupErrors = <String>[];

        Future<void> runCleanupStep(
          String name,
          Future<void> Function() action,
        ) async {
          try {
            await action();
          } catch (e) {
            cleanupErrors.add('$name: $e');
            logE2eMessage('stage=cleanup_error step=$name error=$e');
          }
        }

        await runCleanupStep('dummyWindow.hide', () async {
          await _dummyWindowChannel.invokeMethod<void>('hide');
        });
        await runCleanupStep('sender.disconnect', () async {
          if (sender != null) {
            await sender.disconnect();
            await sender.waitUntilDisconnected(senderDisconnectTimeout);
          }
        });
        await runCleanupStep(
            'sender.dispose', () async => await sender?.dispose());
        await runCleanupStep(
            'stream.dispose', () async => await stream?.dispose());
        await runCleanupStep(
          'videoTrack.dispose',
          () async => await videoTrack?.dispose(),
        );

        if (cleanupErrors.isNotEmpty) {
          logE2eMessage(
            'stage=cleanup_finished status=failed errors=${cleanupErrors.join(" | ")}',
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
    },
  );
  testWidgets(
    'window-capture-preview-uaf-stress: プレビューの開始と停止を繰り返して '
    'UAF クラッシュしないことを検証する',
    (WidgetTester tester) async {
      // Sora 接続を伴わないプレビューだけのパターンで、キャプチャ動作中に
      // track を dispose する。track は stream にも PeerConnection にも
      // 追加されないため、dispose で video source の参照が確実に 0 になる。
      // ネイティブ側が stopCapture 完了を待たずに MethodChannel へ応答すると、
      // frameQueue 上の in-flight フレームが解放済み source を参照して
      // use-after-free クラッシュを引き起こすため、反復実行でクラッシュ
      // しないことを検証する (UAF レースの回帰テスト)。
      // macOS ローカル専用。SCStream の開始には画面収録権限が必要なため、
      // CI では実行できない。
      final rounds = _windowCaptureStressRoundsFromEnvironment();
      logE2eMessage(
        'stage=preview_uaf_stress_config '
        'platform=${Platform.operatingSystem} rounds=$rounds',
      );

      expect(
        Platform.isMacOS,
        isTrue,
        reason: 'このテストは macOS のウィンドウキャプチャを検証するため macOS 専用です。',
      );

      // ダミーウィンドウを表示し、SCShareableContent に反映されるまで待つ
      await _dummyWindowChannel.invokeMethod<void>('show');
      final source = await _waitForDummyWindowSource(tester);
      logE2eMessage(
        'stage=dummy_window_ready sourceId=${source.id}',
      );

      for (var round = 1; round <= rounds; round++) {
        logE2eMessage('stage=preview_round_start round=$round/$rounds');
        final track = MediaDevices.createWindowVideoTrack(source);
        // textureId の取得でネイティブ側のキャプチャを開始する
        await track.textureId;
        // フレームが frameQueue に流れている状態を作る
        await tester.pump(const Duration(milliseconds: 300));
        // キャプチャ動作中に dispose する。disposeLocalVideoTrackTexture は
        // stopCapture 完了 (frameQueue のフレーム処理完了を含む) を待ってから
        // 応答する必要がある。応答を待たずに video source を解放すると、
        // in-flight フレームが解放済み source を参照して UAF クラッシュを
        // 引き起こすため、クラッシュしないことを検証する。
        await track.dispose();
        logE2eMessage('stage=preview_round_finished round=$round/$rounds');
      }

      // ダミーウィンドウを閉じる
      await _dummyWindowChannel.invokeMethod<void>('hide');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

/// ストレスラウンド数を環境変数から取得する。
///
/// 未指定の場合は 10 回実行する。UAF レースはタイミング依存のため、
/// 強めに確認する場合は 50 回以上を指定する。
int _windowCaptureStressRoundsFromEnvironment() {
  final raw = Platform.environment['TEST_WINDOW_CAPTURE_STRESS_ROUNDS']?.trim();
  if (raw == null || raw.isEmpty) {
    return 10;
  }
  final parsed = int.tryParse(raw);
  expect(
    parsed,
    isNotNull,
    reason: 'TEST_WINDOW_CAPTURE_STRESS_ROUNDS は整数で指定してください。',
  );
  expect(
    parsed!,
    greaterThan(0),
    reason: 'TEST_WINDOW_CAPTURE_STRESS_ROUNDS は 1 以上で指定してください。',
  );
  return parsed;
}

/// window_capture_error エラーイベントが通知されるまで待つ。
///
/// 通知されない場合は 30 秒でタイムアウトする。
Future<SoraConnectionErrorEvent> _waitForWindowCaptureError(
  ObservedConnection connection, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final error in connection.errors) {
      if (error.code == SoraErrorCode.windowCaptureError) {
        return error;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError(
    'window_capture_error イベントが通知されませんでした。'
    'キャプチャ中のウィンドウ消失が Dart 側へ通知されること。',
  );
}

Future<WindowCaptureSource> _waitForDummyWindowSource(
  WidgetTester tester,
) async {
  const maxAttempts = 30;
  const interval = Duration(milliseconds: 500);

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    final sources = await MediaDevices.enumerateWindowCaptureSources();
    for (final source in sources) {
      if (source.title == _dummyWindowTitle) {
        return source;
      }
    }
    logE2eMessage(
      'stage=enumerate_window_sources attempt=${attempt + 1} '
      'found=${sources.length}',
    );
    await tester.pump(interval);
  }

  throw StateError(
    'ダミーウィンドウを列挙できませんでした。'
    '画面収録権限が付与されていることを確認してください。',
  );
}
