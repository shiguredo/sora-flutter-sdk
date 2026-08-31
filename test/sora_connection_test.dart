import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/webrtc_client.dart';
import 'package:sora_sdk/src/sora_connection.dart';
import 'package:sora_sdk/src/sora_connection_config.dart';
import 'package:sora_sdk/src/sora_connection_event.dart';
import 'package:sora_sdk/src/sora_connection_state.dart';
import 'package:sora_sdk/src/sora_error_code.dart';
import 'package:sora_sdk/src/sora_local_video_handle.dart';
import 'package:sora_sdk/src/sora_role.dart';
import 'package:sora_sdk/src/sora_timeout_options.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/ffi_test_environment.dart';

void main() {
  // SoraConnection の生成と dispose は MethodChannel / EventChannel を経由するため、
  // ServicesBinding.instance を参照可能な状態にしてから各テストを走らせる必要がある。
  // ここで解消するのは「Binding has not yet been initialized」だけで、handler 未登録
  // による MissingPluginException は disposeConnection ヘルパ側で吸収する。
  TestWidgetsFlutterBinding.ensureInitialized();

  final ffiTestEnvironment = prepareFfiTestEnvironment();

  group('SoraConnection._handleWebrtcEvent の想定外イベント処理', () {
    late WebrtcClient wc;

    setUpAll(() {
      // SoraConnection 生成には FFI の共有 factory が必要なため、
      // 事前に WebrtcClient を生成して初期化する。
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
    });

    tearDownAll(() {
      wc.dispose();
    });

    SoraConnection createConnection() {
      return SoraConnection.createForTest(
        config: const SoraConnectionConfig(
          signalingUrls: <String>['wss://example.com/signaling'],
          channelId: 'test-channel',
          role: SoraRole.recvonly,
        ),
        clientId: 1,
        eventChannelName: 'test-event-channel',
      );
    }

    Future<void> disposeConnection(SoraConnection connection) async {
      // テスト binding では `sora_sdk/method` の handler が登録されていないため、
      // dispose の try/catch まで MissingPluginException が抜けてくる経路は
      // `disposeClient` invokeMethod だけになる（EventChannel 側の listen / cancel
      // 失敗は Flutter services 層の FlutterError.reportError に吸収され、この
      // ヘルパの catch には届かない）。dispose の native 側完了を検証するテスト
      // ではないため、テスト環境固有の期待挙動として吸収する。
      try {
        await connection.dispose();
      } on MissingPluginException catch (_) {
        // handler 未登録による通信失敗のみを想定内として無視する。
      }
    }

    test('kind が空の remote_track_added で error event が発火する', () async {
      final connection = createConnection();
      final errors = <SoraConnectionErrorEvent>[];
      final debugMessages = <String>[];
      final sub = connection.events.listen((event) {
        if (event is SoraConnectionErrorEvent) {
          errors.add(event);
        }
      });
      final debugSub = connection.debugMessages.listen(debugMessages.add);
      try {
        await connection.handleWebrtcEventForTest(
          'remote_track_added',
          <String, Object?>{'kind': '', 'trackId': 'conn1-audio'},
        );
        expect(errors, hasLength(1));
        expect(errors.first.code, SoraErrorCode.unexpectedNativeEvent);
        expect(debugMessages, isNotEmpty);
      } finally {
        await sub.cancel();
        await debugSub.cancel();
        await disposeConnection(connection);
      }
    });

    test('trackId が空の remote_track_removed で error event が発火する', () async {
      final connection = createConnection();
      final errors = <SoraConnectionErrorEvent>[];
      final sub = connection.events.listen((event) {
        if (event is SoraConnectionErrorEvent) {
          errors.add(event);
        }
      });
      try {
        await connection.handleWebrtcEventForTest(
          'remote_track_removed',
          <String, Object?>{'kind': 'audio', 'trackId': ''},
        );
        expect(errors, hasLength(1));
        expect(errors.first.code, SoraErrorCode.unexpectedNativeEvent);
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test('Sora フォーマット外 trackId で error event が発火する', () async {
      final connection = createConnection();
      final errors = <SoraConnectionErrorEvent>[];
      final sub = connection.events.listen((event) {
        if (event is SoraConnectionErrorEvent) {
          errors.add(event);
        }
      });
      try {
        await connection.handleWebrtcEventForTest(
          'remote_track_added',
          <String, Object?>{'kind': 'audio', 'trackId': 'invalid-id'},
        );
        expect(errors, hasLength(1));
        expect(errors.first.code, SoraErrorCode.unexpectedNativeEvent);
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test('正常な remote_track_added では error event が発火しない', () async {
      final connection = createConnection();
      final errors = <SoraConnectionErrorEvent>[];
      final sub = connection.events.listen((event) {
        if (event is SoraConnectionErrorEvent) {
          errors.add(event);
        }
      });
      try {
        await connection.handleWebrtcEventForTest(
          'remote_track_added',
          <String, Object?>{'kind': 'audio', 'trackId': 'conn1-audio'},
        );
        expect(errors, isEmpty);
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test('異常終了の teardown 失敗が zone unhandled error にならない', () async {
      final connection = createConnection();
      final debugMessages = <String>[];
      final debugSub = connection.debugMessages.listen(debugMessages.add);
      try {
        // teardown で即座に例外を投げるテストフックを設定する。
        connection.teardownFailureForTest = StateError('teardown failed');
        // 異常終了処理を fire-and-forget で発火する data_channel_closing を
        // 送る。teardown 例外は .catchError で debug message に変換され、
        // zone unhandled error にならない。
        await connection.handleWebrtcEventForTest(
          'data_channel_closing',
          <String, Object?>{'label': 'signaling'},
        );
        // `_handleAbnormalTermination` は `_closeSignalingTransport` と
        // `_teardownNativeSession` の複数 await を経由してから `.catchError`
        // が debug message を emit するため、単一 microtask では不足する。
        // pumpEventQueue で pending なマイクロタスクとタイマーを最後まで
        // 処理し、debug message の到達を待つ。
        await pumpEventQueue();
        expect(
          debugMessages.any((m) => m.contains('abnormal termination failed')),
          isTrue,
        );
      } finally {
        await debugSub.cancel();
        await disposeConnection(connection);
      }
    });
  }, skip: ffiTestEnvironment.skipReason);

  group(
    'SoraConnection.disconnect の _disconnecting / _abnormalTerminationStarted の finally リセット',
    () {
      late WebrtcClient wc;

      setUpAll(() {
        wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      });

      tearDownAll(() {
        wc.dispose();
      });

      SoraConnection createConnection() {
        return SoraConnection.createForTest(
          config: const SoraConnectionConfig(
            signalingUrls: <String>['wss://example.com/signaling'],
            channelId: 'test-channel',
            role: SoraRole.recvonly,
          ),
          clientId: 1,
          eventChannelName: 'test-event-channel',
        );
      }

      Future<void> disposeConnection(SoraConnection connection) async {
        try {
          await connection.dispose();
        } on MissingPluginException catch (_) {
          // handler 未登録による通信失敗のみを想定内として無視する。
        }
      }

      test(
        '_teardownNativeSession の非 TimeoutException 例外で _disconnecting が false にリセットされる',
        () async {
          final connection = createConnection();
          // teardown で StateError を投げるテストフックを設定する。
          connection.teardownFailureForTest = StateError(
            'injected teardown failure',
          );
          try {
            // disconnect() は catch で completeError + rethrow するため、
            // 呼び出し側は例外を受け取る。
            await expectLater(
              connection.disconnect(),
              throwsA(isA<StateError>()),
            );
            // finally 節で _disconnecting / _abnormalTerminationStarted が
            // 両方リセットされていること。次回 connect() 経路で silent drop
            // されなくなる。
            expect(
              connection.disconnectingForTest,
              isFalse,
              reason:
                  '_disconnecting は例外経由の disconnect() 後も false にリセットされていること',
            );
            expect(
              connection.abnormalTerminationStartedForTest,
              isFalse,
              reason: '_abnormalTerminationStarted も finally でリセットされていること',
            );
          } finally {
            await disposeConnection(connection);
          }
        },
      );

      test('dispose() 経由の間接呼び出しでも _disconnecting がリセットされる', () async {
        final connection = createConnection();
        connection.teardownFailureForTest = StateError(
          'injected teardown failure',
        );
        // dispose() は内部で disconnect() を呼び、disconnect() 由来の例外は
        // 吸収する (他の cleanup 例外は伝播しうる)。dispose() 完了時点で両
        // フラグが finally リセット済みであることをここで検証する。
        try {
          await connection.dispose();
        } on MissingPluginException catch (_) {
          // handler 未登録の副作用は想定内として吸収する。
        }
        expect(
          connection.disconnectingForTest,
          isFalse,
          reason: 'dispose() 経由の disconnect() でもフラグはリセットされていること',
        );
        expect(
          connection.abnormalTerminationStartedForTest,
          isFalse,
          reason: 'dispose() 経由でも _abnormalTerminationStarted はリセットされていること',
        );
      });

      test(
        '通常経路の disconnect() でも _abnormalTerminationStarted がリセットされる',
        () async {
          final connection = createConnection();
          try {
            // teardown 失敗を注入せずに disconnect() を呼ぶ。通常経路では
            // _resetConnectionSessionState() が _disconnecting = false を
            // 実行するが、_abnormalTerminationStarted はそれではリセット
            // されない。disconnect() の finally が両方を確実にリセットする。
            await connection.disconnect();
            expect(connection.disconnectingForTest, isFalse);
            expect(connection.abnormalTerminationStartedForTest, isFalse);
          } finally {
            await disposeConnection(connection);
          }
        },
      );

      test(
        '例外経由 disconnect() 後の state_changed error イベントが silent drop されない',
        () async {
          final connection = createConnection();
          connection.teardownFailureForTest = StateError(
            'injected teardown failure',
          );
          final errors = <SoraConnectionErrorEvent>[];
          final sub = connection.events.listen((event) {
            if (event is SoraConnectionErrorEvent) {
              errors.add(event);
            }
          });
          try {
            // teardown 失敗で disconnect() が rethrow する。
            await expectLater(
              connection.disconnect(),
              throwsA(isA<StateError>()),
            );

            // `state: 'error'` は native 実装が実際には emit しない値だが、
            // `_handleWebrtcEvent` が 'connecting' / 'connected' / 'disconnected'
            // に該当しない state を `else if (!_disconnecting)` の分岐へ落とす
            // 仕様を利用して silent drop 経路をピンポイントで狙う。fix 前
            // (`_disconnecting == true` 残留) では error event が silent drop
            // されて errors が空になり、fix 後 (`_disconnecting == false`) は
            // error event が観測される。
            await connection.handleWebrtcEventForTest(
              'state_changed',
              const <String, Object?>{
                'state': 'error',
                'reason': 'peer_connection_failure',
                'message': 'injected pc failure',
              },
            );
            expect(
              errors,
              hasLength(1),
              reason:
                  '_disconnecting 残留のガードが解消されて次回の state_changed error が emit されること',
            );
            expect(errors.first.code, 'peer_connection_failure');
          } finally {
            await sub.cancel();
            await disposeConnection(connection);
          }
        },
      );

      test(
        '正常経路 disconnect() 後の idle window に遅延 state_changed disconnected が届くと追加 emit する (トレードオフ挙動 pin)',
        () async {
          // フィールド docstring のトレードオフ挙動をピンする。
          //
          // fix で `_disconnecting` / `_abnormalTerminationStarted` を
          // disconnect() finally でリセットするようにしたため、idle window
          // (`_ongoingDisconnect == null` かつ両フラグ false) に届く遅延
          // native 由来の異常イベントは、旧設計の連鎖ガードで抑止されなく
          // なった。`_disconnectBody` の emit は
          // `_signalingState.emittedDisconnectedWithCloseInfo` を true に
          // せず、`_resetConnectionSessionState()` 内の `resetSession()` が
          // false にリセットするため、注入経路は「state 別分岐 (disconnected)」
          // → `!_disconnecting && !_abnormalTerminationStarted` 分岐 →
          // `emittedDisconnectedWithCloseInfo == false` else 節を素通りして
          // 追加 `SoraDisconnectedState` が発火する。
          //
          // 実運用ではこの window は極めて短く、通常のアプリケーションは
          // `disconnect()` 完了後に `dispose()` を呼んで `_disposed` ガードで
          // 遅延イベントを drop する運用のため許容している。将来この挙動を
          // 抑止したくなった際に破壊的変更が加わることを気付けるよう、
          // 現状挙動 (追加 emit が 1 回起きる) をここで pin する。
          final connection = createConnection();
          final disconnectedStates = <SoraDisconnectedState>[];
          final sub = connection.events.listen((event) {
            if (event is SoraConnectionStateChangedEvent) {
              final state = event.state;
              if (state is SoraDisconnectedState) {
                disconnectedStates.add(state);
              }
            }
          });
          try {
            await connection.disconnect();
            // `_disconnectBody` の `_emitConnectionStateEvent` は
            // StreamController.broadcast().add() 経由で listener callback を
            // microtask に schedule する。await disconnect() 直後の同期時点
            // では listener が走っていない可能性があるため、pumpEventQueue で
            // 反映を待ってから beforeCount を確定させる。
            await pumpEventQueue();
            final beforeCount = disconnectedStates.length;

            // idle window で遅延 native 由来の state_changed: disconnected
            // を注入。reason は `peer_connection_closed` を使い、
            // `!_disconnecting && !_abnormalTerminationStarted` 分岐を
            // 通過させる。
            await connection.handleWebrtcEventForTest(
              'state_changed',
              const <String, Object?>{
                'state': 'disconnected',
                'reason': 'peer_connection_closed',
              },
            );
            // マイクロタスク境界をまたぐ emit も含めて拾う。
            await pumpEventQueue();

            expect(
              disconnectedStates.length,
              beforeCount + 1,
              reason:
                  'トレードオフとして、追加 SoraDisconnectedState が 1 回 emit される現状挙動を pin する',
            );
          } finally {
            await sub.cancel();
            await disposeConnection(connection);
          }
        },
      );
    },
    skip: ffiTestEnvironment.skipReason,
  );

  group('SoraConnection._handleRedirectMessage の異常終了処理', () {
    late WebrtcClient wc;
    late HttpServer acceptServer;
    late String acceptUrl;

    setUpAll(() async {
      // SoraConnection 生成には FFI の共有 factory が必要なため、
      // 事前に WebrtcClient を生成して初期化する。
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
      // redirect 起動前の初期 WebSocket として使う実サーバー。
      // WebSocketTransformer で upgrade を受け付けるだけの最小構成にする。
      acceptServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      acceptServer.listen((request) async {
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          await WebSocketTransformer.upgrade(request);
        } else {
          request.response.statusCode = HttpStatus.badRequest;
          await request.response.close();
        }
      });
      acceptUrl = 'ws://${acceptServer.address.host}:${acceptServer.port}';
    });

    tearDownAll(() async {
      await acceptServer.close(force: true);
      wc.dispose();
    });

    SoraConnection createConnection({SoraTimeoutOptions? timeoutOptions}) {
      return SoraConnection.createForTest(
        config: SoraConnectionConfig(
          signalingUrls: <String>[acceptUrl],
          channelId: 'test-channel',
          role: SoraRole.recvonly,
          timeoutOptions: timeoutOptions ?? const SoraTimeoutOptions(),
        ),
        clientId: 1,
        eventChannelName: 'test-event-channel',
      );
    }

    Future<void> disposeConnection(SoraConnection connection) async {
      try {
        await connection.dispose();
      } on MissingPluginException catch (_) {
        // handler 未登録による通信失敗のみを想定内として無視する。
      }
    }

    Future<WebSocketChannel> establishInitialChannel() async {
      final channel = WebSocketChannel.connect(Uri.parse(acceptUrl));
      await channel.ready;
      return channel;
    }

    Future<void> verifyAbnormalTermination({
      required SoraConnection connection,
      required Map<String, Object?> payload,
      required String expectedErrorCode,
    }) async {
      final errors = <SoraConnectionErrorEvent>[];
      final disconnected = Completer<SoraDisconnectedState>();
      final sub = connection.events.listen((event) {
        if (event is SoraConnectionErrorEvent) {
          errors.add(event);
        } else if (event is SoraConnectionStateChangedEvent) {
          final state = event.state;
          if (state is SoraDisconnectedState && !disconnected.isCompleted) {
            disconnected.complete(state);
          }
        }
      });
      try {
        // _handleRedirectMessage は内部で全ての例外を捕捉するため
        // await が throw しない (throw されれば zone unhandled error のバグ再発)。
        await connection.handleRedirectMessageForTest(payload);
        // _handleAbnormalTermination は unawaited で発火するため、
        // SoraDisconnectedState を受け取るまで待機する。
        await disconnected.future.timeout(const Duration(seconds: 10));
        // SoraDisconnectedState 到達直後に別のマイクロタスク由来で発火する
        // 遅延エラーイベント (二重 emit バグ) を取りこぼさないよう、
        // 保留マイクロタスクを最後まで処理してから件数を検証する。
        await pumpEventQueue();
        // 二重通知バグを検出するため、エラーイベントは 1 件だけであることを検証する。
        expect(errors, hasLength(1));
        expect(errors.first.code, expectedErrorCode);
        expect(
          connection.signalingHasActiveTransportForTest,
          isFalse,
          reason: 'シグナリング transport は完全にリセットされていること',
        );
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    }

    test('String でない location で websocket_error 経由の異常終了になる', () async {
      final connection = createConnection();
      final channel = await establishInitialChannel();
      connection.injectSignalingWebSocketForTest(channel);
      // payload['location'] as String? は非 String で TypeError を投げる。
      // 型ガードで統一経路に落ちることを検証する。
      await verifyAbnormalTermination(
        connection: connection,
        payload: <String, Object?>{'location': 42},
        expectedErrorCode: SoraErrorCode.websocketError,
      );
    });

    test('空文字列 location で websocket_error 経由の異常終了になる', () async {
      final connection = createConnection();
      // 実 WebSocket を初期状態として注入し、parseSignalingUrl 拒否経路でも
      // 旧 channel が異常終了の cleanup で確実に解放されることを検証する。
      final channel = await establishInitialChannel();
      connection.injectSignalingWebSocketForTest(channel);
      await verifyAbnormalTermination(
        connection: connection,
        payload: <String, Object?>{'location': ''},
        expectedErrorCode: SoraErrorCode.websocketError,
      );
    });

    test('非 ws/wss スキームの location で websocket_error 経由の異常終了になる', () async {
      final connection = createConnection();
      final channel = await establishInitialChannel();
      connection.injectSignalingWebSocketForTest(channel);
      await verifyAbnormalTermination(
        connection: connection,
        payload: <String, Object?>{'location': 'http://example.com/signaling'},
        expectedErrorCode: SoraErrorCode.websocketError,
      );
    });

    test(
      'Uri.tryParse が拒否する malformed location で websocket_error 経由の異常終了になる',
      () async {
        final connection = createConnection();
        final channel = await establishInitialChannel();
        connection.injectSignalingWebSocketForTest(channel);
        // ':::' は Uri.tryParse が null を返す不正入力であり、
        // parseSignalingUrl 拒否経路を確実に exercise できる。
        await verifyAbnormalTermination(
          connection: connection,
          payload: <String, Object?>{'location': ':::'},
          expectedErrorCode: SoraErrorCode.websocketError,
        );
      },
    );

    test(
      'WebSocket upgrade を拒否するサーバーへの redirect で websocket_error 経由の異常終了になる',
      () async {
        // upgrade 要求に 400 を返すサーバーを立て、newChannel.ready が
        // WebSocketChannelException で失敗する経路 (catch (error)) を検証する。
        // テスト間の副作用を避けるため、このテスト内でサーバーを開閉する。
        final rejectServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        try {
          rejectServer.listen((request) async {
            request.response.statusCode = HttpStatus.badRequest;
            await request.response.close();
          });
          final rejectUrl =
              'ws://${rejectServer.address.host}:${rejectServer.port}';
          // reject サーバーは即座に 400 を返すため、signalingCandidateTimeout
          // に到達する前に catch (error) 経路が発火する想定。default 値
          // (5s) を明示的に使うが、外側の disconnected.future.timeout(10s)
          // より十分短ければよい。
          final connection = createConnection();
          final channel = await establishInitialChannel();
          connection.injectSignalingWebSocketForTest(channel);
          await verifyAbnormalTermination(
            connection: connection,
            payload: <String, Object?>{'location': rejectUrl},
            expectedErrorCode: SoraErrorCode.websocketError,
          );
        } finally {
          await rejectServer.close(force: true);
        }
      },
    );

    test(
      'WebSocket upgrade に応答しないサーバーへの redirect で signaling_candidate_timeout 経由の異常終了になる',
      () async {
        // accept はするが upgrade 応答を返さないサーバーを立て、
        // newChannel.ready が signalingCandidateTimeout で TimeoutException
        // を発火する経路 (on TimeoutException catch) を検証する。
        final hangServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        try {
          hangServer.listen((request) async {
            // upgrade 応答も 400 応答も返さず request をハングさせる。
            // dispose 時に force close で回収する。
          });
          final hangUrl = 'ws://${hangServer.address.host}:${hangServer.port}';
          // 外側の disconnected.future.timeout(10s) 内で timeout 到達
          // させるため、signalingCandidateTimeout を短縮する。500ms は CI
          // 起動直後の loopback で HttpClient warm-up の遅延を吸収しつつ
          // 外側 10s に十分収まる余裕を持たせた値。
          final connection = createConnection(
            timeoutOptions: const SoraTimeoutOptions(
              signalingCandidateTimeout: Duration(milliseconds: 500),
            ),
          );
          final channel = await establishInitialChannel();
          connection.injectSignalingWebSocketForTest(channel);
          await verifyAbnormalTermination(
            connection: connection,
            payload: <String, Object?>{'location': hangUrl},
            expectedErrorCode: SoraErrorCode.signalingCandidateTimeout,
          );
        } finally {
          await hangServer.close(force: true);
        }
      },
    );
  }, skip: ffiTestEnvironment.skipReason);

  group('SoraConnection WebSocket シグナリングメッセージ順序', () {
    late WebrtcClient wc;

    setUpAll(() {
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
    });

    tearDownAll(() {
      wc.dispose();
    });

    SoraConnection createConnection() {
      return SoraConnection.createForTest(
        config: const SoraConnectionConfig(
          signalingUrls: <String>['wss://example.com/signaling'],
          channelId: 'test-channel',
          role: SoraRole.recvonly,
        ),
        clientId: 1,
        eventChannelName: 'test-event-channel',
      );
    }

    Future<void> disposeConnection(SoraConnection connection) async {
      try {
        await connection.dispose();
      } on MissingPluginException catch (_) {
        // handler 未登録による通信失敗のみを想定内として無視する。
      }
    }

    test('大 offer の decode offload 中に届いた小 candidate が受信順で処理される', () async {
      // 32KiB を超える JSON payload は `_decodeJsonMapMaybeOffloaded` が
      // `Isolate.run` へ decode を offload する。fix 前は `listen` が返す
      // Future を discard するため、後続の小 candidate (同期 decode) が
      // 先に handler へ届いて silent drop されるバグがあった。
      // `_enqueueWebSocketMessage` で tail 直列化されているため、
      // enqueue 順が保存されて offer → candidate の順に processing される。
      //
      // なお、silent drop の実効防止 (`WebrtcClient.handleCandidate` の
      // `_disposed || _pcRef == null` 早期 return を避ける) は tail 直列化
      // 自体の帰結として保証される。本テストは順序保証 (処理経路の
      // decode 完了順) までを直接検証する。
      //
      // SDP は Isolate offload の閾値超過だけを目的に、意味を持たない padding
      // 文字列で構成する。`_handleWebSocketMessage` は decode 後に
      // `_webrtcClient.handleOffer(payload)` (FFI) を呼ぶが、libwebrtc の
      // native parser が parse に失敗しても throw ではなく
      // `_emitState('error', 'offer_invalid', ...)` を返す設計、および
      // `_enqueueWebSocketMessage` の try/catch が最後の砦になっているため、
      // テストは安定する。この 2 段の受け皿がテストの成立条件。
      final connection = createConnection();
      final receivedTypes = <String>[];
      final sub = connection.events.listen((event) {
        if (event is SoraSignalingMessageEvent) {
          final signaling = event.event;
          if (signaling.direction == 'received') {
            final type = signaling.data?['type'] as String?;
            if (type != null) {
              receivedTypes.add(type);
            }
          }
        }
      });
      try {
        // 32KiB を大きく上回る 40KB 相当の padding を SDP フィールドに
        // 詰めて Isolate offload 経路を確実に発火させる。
        final largeSdp = 'x' * 40000;
        final offerText = jsonEncode(<String, Object?>{
          'type': 'offer',
          'sdp': largeSdp,
          'connection_id': 'connO',
          'client_id': 'cl',
          'bundle_id': 'bl',
          'session_id': 'se',
        });
        // 同期 decode 経路の小 candidate
        final candidateText = jsonEncode(<String, Object?>{
          'type': 'candidate',
          'candidate': 'candidate:1 1 UDP 2130706431 127.0.0.1 1 typ host',
        });

        // 2 件を enqueue して両方の完了を待つ。fix 前は candidate が offer
        // より先に processing 完了する race が起きうるが、tail 直列化されて
        // いれば enqueue 順で processing される。
        await Future.wait<void>([
          connection.enqueueWebSocketMessageForTest(offerText),
          connection.enqueueWebSocketMessageForTest(candidateText),
        ]);
        // `_emitSignalingEvent` の broadcast StreamController.add() は
        // listener callback をマイクロタスクにスケジュールする。await 直後
        // では最後の event が listener に到達していない可能性があるため、
        // pumpEventQueue で保留マイクロタスクを最後まで処理する。
        await pumpEventQueue();

        expect(receivedTypes, [
          'offer',
          'candidate',
        ], reason: 'tail 直列化により enqueue 順で processing されること');
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test('redirect 相当の old / new channel からのメッセージが同一 tail で直列化される', () async {
      // redirect 経路 (`_handleRedirectMessage`) では、old channel の
      // subscription cancel と new channel の subscription 登録がどちらも
      // 同一 `SignalingSessionState.webSocketMessageTail` に append する
      // 設計になっている。本テストは 2 個の StreamController を
      // `injectSignalingWebSocketForTest` 相当で listen 張って、両者が
      // 同一 tail に append されて enqueue 順が保存されることを
      // dynamic に検証する (redirect 前の old channel からのメッセージが
      // new channel のメッセージと並行処理されないことの証拠となる)。
      //
      // old channel には Isolate offload されるサイズの ping (`sdp` 相当の
      // 40KB padding) を、new channel には同期 decode 経路の小 ping を
      // interleave する。fix 前 (tail 直列化なし) では小 message が
      // 追い抜くが、fix 後は old 側の decode 完了を待って new 側が
      // processing される。
      final connection = createConnection();
      final receivedIds = <String>[];
      final sub = connection.events.listen((event) {
        if (event is SoraSignalingMessageEvent) {
          final signaling = event.event;
          if (signaling.direction == 'received') {
            final id = signaling.data?['id'] as String?;
            if (id != null) {
              receivedIds.add(id);
            }
          }
        }
      });

      // old channel と new channel の 2 個の StreamController を用意し、
      // それぞれの listen を injectSignalingWebSocketForTest 相当
      // (`_enqueueWebSocketMessage` を呼ぶ) で張る。
      final oldChannelCtrl = StreamController<Object?>();
      final newChannelCtrl = StreamController<Object?>();
      final oldSub = oldChannelCtrl.stream.listen(
        connection.enqueueWebSocketMessageForTest,
      );
      final newSub = newChannelCtrl.stream.listen(
        connection.enqueueWebSocketMessageForTest,
      );

      try {
        // old channel に 40KB の Isolate offload 相当を 2 件、
        // new channel に同期 decode 相当を 2 件 interleave して送信する。
        final largePayload = 'x' * 40000;
        oldChannelCtrl.add(
          jsonEncode(<String, Object?>{
            'type': 'ping',
            'id': 'old-0',
            'padding': largePayload,
          }),
        );
        newChannelCtrl.add(
          jsonEncode(<String, Object?>{'type': 'ping', 'id': 'new-0'}),
        );
        oldChannelCtrl.add(
          jsonEncode(<String, Object?>{
            'type': 'ping',
            'id': 'old-1',
            'padding': largePayload,
          }),
        );
        newChannelCtrl.add(
          jsonEncode(<String, Object?>{'type': 'ping', 'id': 'new-1'}),
        );

        // 4 個の stream event が listen callback を経由して tail に
        // リンクを積むまで待機する (handler 完了は次の sentinel await の
        // チェーンで担保する。40KB Isolate offload の handler 完了自体は
        // pumpEventQueue で必ずしも保証できない)。
        await pumpEventQueue();
        // 明示的に tail の完了を待つ (最後に enqueue された message の
        // 処理完了を保証する)。
        await connection.enqueueWebSocketMessageForTest(
          jsonEncode(<String, Object?>{'type': 'ping', 'id': 'sentinel'}),
        );
        // `_emitSignalingEvent` の broadcast StreamController.add() は
        // listener callback をマイクロタスクにスケジュールする。await 直後
        // では最後の event (sentinel) が listener に到達していない可能性が
        // あるため、pumpEventQueue で保留マイクロタスクを最後まで処理する。
        await pumpEventQueue();

        expect(
          receivedIds,
          <String>['old-0', 'new-0', 'old-1', 'new-1', 'sentinel'],
          reason:
              '2 個の channel の listen が同一 tail に append されて enqueue 順で processing されること',
        );
      } finally {
        await oldSub.cancel();
        await newSub.cancel();
        await oldChannelCtrl.close();
        await newChannelCtrl.close();
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test(
      'disconnect() の resetSession() で webSocketMessageTail が null に戻る',
      () async {
        final connection = createConnection();
        try {
          // 何か 1 件 enqueue して tail に代入させる。
          await connection.enqueueWebSocketMessageForTest(
            jsonEncode(<String, Object?>{'type': 'ping'}),
          );
          expect(
            connection.hasWebSocketMessageTailForTest,
            isTrue,
            reason: 'enqueue 後は tail が保持されていること',
          );

          await connection.disconnect();

          expect(
            connection.hasWebSocketMessageTailForTest,
            isFalse,
            reason:
                '`disconnect()` 経路の `_resetConnectionSessionState()` (`resetSession()`) で tail が null 化されること',
          );
        } finally {
          await disposeConnection(connection);
        }
      },
    );

    test('未完了 tail のまま disconnect() を呼んでも tail が null 化される', () async {
      // issue 設計方針: 「次回 `connect()` に前回セッションの未完了 tail
      // チェーンを持ち越さない」ことを検証する。in-flight (=未完了) の
      // メッセージがある状態で disconnect() を呼び、resetSession() が
      // 呼ばれた時点で tail が null 化されることを確認する。
      final connection = createConnection();
      try {
        // Isolate offload される 40KB payload を enqueue した Future を
        // await せずに保持する (in-flight 状態)。
        final inflight = connection.enqueueWebSocketMessageForTest(
          jsonEncode(<String, Object?>{'type': 'ping', 'padding': 'x' * 40000}),
        );
        expect(
          connection.hasWebSocketMessageTailForTest,
          isTrue,
          reason: 'enqueue 直後は tail が保持されていること',
        );

        // in-flight を await せずに disconnect() を呼ぶ。resetSession() が
        // 実行される時点で tail は null 化される。in-flight 自体は
        // detached された Future として cascade 完了するのを別途待つ。
        await connection.disconnect();
        expect(
          connection.hasWebSocketMessageTailForTest,
          isFalse,
          reason: 'in-flight tail があっても resetSession() で null 化されること',
        );

        // in-flight の完了 (成功でも catch 済み失敗でも) を dispose 前に
        // 明示的に await して、後続 test への side-effect が残らないよう
        // にする (現状の `_enqueueWebSocketMessage` は内部 try/catch により
        // 通常 throw しないため実質「completed になるまで待つ」となる)。
        await inflight;
      } finally {
        await disposeConnection(connection);
      }
    });
  }, skip: ffiTestEnvironment.skipReason);

  group('SoraConnection._emitLocalVideo の null スキップ', () {
    late WebrtcClient wc;

    setUpAll(() {
      // SoraConnection 生成には FFI の共有 factory が必要なため、
      // 事前に WebrtcClient を生成して初期化する。
      wc = WebrtcClient.create(config: {}, onEvent: (_, _) {});
    });

    tearDownAll(() {
      wc.dispose();
    });

    SoraConnection createConnection() {
      return SoraConnection.createForTest(
        config: const SoraConnectionConfig(
          signalingUrls: <String>['wss://example.com/signaling'],
          channelId: 'test-channel',
          role: SoraRole.sendonly,
        ),
        clientId: 1,
        eventChannelName: 'test-event-channel',
      );
    }

    Future<void> disposeConnection(SoraConnection connection) async {
      try {
        await connection.dispose();
      } on MissingPluginException catch (_) {
        // handler 未登録による通信失敗のみを想定内として無視する。
      }
    }

    test('null を渡すと localVideo Stream に何も emit されない', () async {
      // external capture のように Flutter Texture ベースのプレビュー経路を
      // 持たない場合、呼び出し元は `_emitLocalVideo(null)` を叩く。
      // 公開 Stream に emit が漏れないことを直接検証する。
      final connection = createConnection();
      final localVideoEvents = <SoraLocalVideoHandle>[];
      final sub = connection.localVideo.listen(localVideoEvents.add);
      try {
        connection.emitLocalVideoForTest(null);
        // broadcast Stream の非同期配信を消化させる。
        await pumpEventQueue();
        expect(localVideoEvents, isEmpty);
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });

    test('0 を渡すと textureId=0 のハンドルが 1 件だけ emit される', () async {
      // Flutter engine の TextureRegistry は 0 を有効な texture id として
      // 発行するため、0 は負値ガードと区別して公開 Stream に流れる。
      final connection = createConnection();
      final localVideoEvents = <SoraLocalVideoHandle>[];
      final sub = connection.localVideo.listen(localVideoEvents.add);
      try {
        connection.emitLocalVideoForTest(0);
        await pumpEventQueue();
        expect(localVideoEvents, hasLength(1));
        expect(localVideoEvents.single.textureId, 0);
      } finally {
        await sub.cancel();
        await disposeConnection(connection);
      }
    });
  }, skip: ffiTestEnvironment.skipReason);
}
