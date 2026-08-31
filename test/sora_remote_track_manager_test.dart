import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/sora_method_channels.dart';
import 'package:sora_sdk/src/sora_remote_track_manager.dart';

void main() {
  // MethodChannel の mock ハンドラ登録に ServicesBinding が必要になるため
  // 先に binding を初期化する。attach / detach の FFI 呼び出しは
  // `releaseTrackRefForTest` / `attachSinkToTrackForTest` /
  // `removeSinkFromTrackForTest` の 3 フックですべて差し替えるため、
  // 本テストは `libsora_sdk.so` の初期化 (FFI 依存) を必要としない。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteTrackManager の refcount 収支', () {
    // 各テストで release / sink attach / sink remove の呼び出し記録と、
    // MethodChannel の renderer id を返すカウンタを共有する。
    late List<int> releasedAddresses;
    late List<(int, int)> attachedSinks;
    late List<(int, int)> removedSinks;
    late List<MethodCall> methodCalls;
    late int nextRendererId;

    setUp(() {
      releasedAddresses = <int>[];
      attachedSinks = <(int, int)>[];
      removedSinks = <(int, int)>[];
      methodCalls = <MethodCall>[];
      nextRendererId = 100;
      // sora_sdk/method の createRemoteVideoRenderer / disposeRemoteVideoRenderer
      // をテスト側で応答する。実プラットフォーム実装を使わないため、テスト
      // 環境に依存せず経路検証だけを行える。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) async {
            methodCalls.add(call);
            switch (call.method) {
              case 'createRemoteVideoRenderer':
                final id = nextRendererId++;
                return <String, Object?>{
                  'rendererId': id,
                  'renderingSinkPtr': 0,
                  // videoSinkPtr は attach 時のフック引数として観測するため、
                  // rendererId ごとにユニークにしておく。
                  'videoSinkPtr': id + 500,
                  'textureId': id + 1000,
                };
              case 'disposeRemoteVideoRenderer':
                return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, null);
    });

    RemoteTrackManager createManager() {
      final manager = RemoteTrackManager(
        clientId: 1,
        soraMethodChannel: soraMethodChannel,
        onDebugMessage: (_) {},
        onTrackEvent: (_) {},
        onRemoveTrackEvent: (_) {},
      );
      // FFI 呼び出しをテスト側で観測・差し替える。ダミーの trackAddress に
      // 対して real な `videoTrackRelease` / `videoTrackAddOrUpdateSink` /
      // `videoTrackRemoveSink` を呼ぶと SEGV するため、必ず 3 フックすべてを
      // 差し替えてから attach/detach を実行する。
      manager.releaseTrackRefForTest = releasedAddresses.add;
      manager.attachSinkToTrackForTest = (trackAddress, videoSinkPtr) {
        attachedSinks.add((trackAddress, videoSinkPtr));
      };
      manager.removeSinkFromTrackForTest = (trackAddress, videoSinkPtr) {
        removedSinks.add((trackAddress, videoSinkPtr));
      };
      return manager;
    }

    int countReleases(int trackAddress) =>
        releasedAddresses.where((addr) => addr == trackAddress).length;

    int countMethodCalls(String method) =>
        methodCalls.where((call) => call.method == method).length;

    test('正常な add → remove サイクルで release が add 分 + remove 分 = 2 回', () async {
      final manager = createManager();
      const trackAddress = 0x1001;
      // renderer 作成の response では renderingSinkPtr / videoSinkPtr / textureId
      // が返り、attach happy path が完走する。
      await manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connA-video',
      );
      // attach が entry を保持している段階では、add 分は release されず、
      // detach 時にまとめて返却されることを期待する。
      expect(
        releasedAddresses,
        isEmpty,
        reason: 'attach happy path では add 分の即時 release は発生しない',
      );
      // attach happy path で sink が 1 回登録されていること。
      expect(attachedSinks, hasLength(1));

      await manager.detachRemoteVideoTrack(trackAddress);
      // detachRemoteVideoTrack 入口で remove 分、内部の
      // _detachRemoteVideoTrackUnsafe happy path で add 分が返却される。
      expect(releasedAddresses, <int>[
        trackAddress,
        trackAddress,
      ], reason: '入口で remove 分・内部で add 分を 1 回ずつ返却する');
      expect(removedSinks, hasLength(1));
    });

    test('attach 済み trackAddress の重複通知で追加 add 分が 1 回 release される', () async {
      final manager = createManager();
      const trackAddress = 0x1002;
      await manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connB-video',
      );
      expect(releasedAddresses, isEmpty);

      // 同一 trackAddress の再通知。この時点では既に entry がある
      // (`_remoteTracks.containsKey(trackAddress) == true`) ため、追加された
      // add 分だけを即時返却して early return する。
      await manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connB-video',
      );
      expect(releasedAddresses, <int>[
        trackAddress,
      ], reason: '重複通知の add 分だけを 1 回返却する');
    });

    test('_ongoingDetachAll 中の attach で add 分が 1 回だけ release される', () async {
      final manager = createManager();
      const attachedAddress = 0x1003;
      // 先に 1 件 attach しておき、detachAllRemoteVideoTracks が実 track を
      // 処理する形にする。
      await manager.attachRemoteVideoTrack(
        attachedAddress,
        trackId: 'connC-video',
      );
      releasedAddresses.clear();

      final detachAllFuture = manager.detachAllRemoteVideoTracks();

      // detachAll 実行中の attach を送り込む。attach 冒頭の
      // `_ongoingDetachAll != null` early return 経路で add 分を返却する。
      const newAddress = 0x1004;
      await manager.attachRemoteVideoTrack(
        newAddress,
        trackId: 'connC-video-new',
      );

      await detachAllFuture;

      // 2 重 release バグを検出するため、newAddress の release 回数を
      // 厳密に 1 回で検証する。
      expect(
        countReleases(newAddress),
        1,
        reason: 'detachAll 中の attach でも add 分が 1 回だけ返却されること',
      );
    });

    test(
      '_ongoingDetachAll 中の detach でも remove 分が 1 回だけ release される',
      () async {
        final manager = createManager();
        const attachedAddress = 0x1005;
        await manager.attachRemoteVideoTrack(
          attachedAddress,
          trackId: 'connD-video',
        );
        releasedAddresses.clear();

        final detachAllFuture = manager.detachAllRemoteVideoTracks();

        // detachAll 実行中に別 trackAddress の detach を送り込む。入口で
        // remove 分だけを返却し、内部は _ongoingDetachAll != null で早期
        // return する経路を検証する。
        const removeOnlyAddress = 0x1006;
        await manager.detachRemoteVideoTrack(removeOnlyAddress);

        await detachAllFuture;

        // remove_only 側は entry が無いため detachAll では扱わず、
        // detachRemoteVideoTrack 入口の 1 回だけ返却される。
        expect(
          countReleases(removeOnlyAddress),
          1,
          reason: 'detachAll 中の detach でも remove 分は 1 回だけ返却されること',
        );
      },
    );

    test('response == null の防御パスで add 分が 1 回 release される', () async {
      // createRemoteVideoRenderer が null を返す状況を再現する。
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) async {
            methodCalls.add(call);
            return null;
          });

      final manager = createManager();
      const trackAddress = 0x1007;
      await manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connE-video',
      );

      expect(releasedAddresses, <int>[
        trackAddress,
      ], reason: 'response == null 経路で add 分だけを 1 回返却する');
      // sink attach は response == null 経路では起動しないことを検証する。
      expect(attachedSinks, isEmpty);
    });

    test('entry == null の遅延 remove で remove 分だけが 1 回 release される', () async {
      final manager = createManager();
      // attach を一切通していない trackAddress に対して detach が到達する
      // ケース。_detachRemoteVideoTrackUnsafe の `entry == null` early return
      // 経路で add 分は返却対象がなく、入口の remove 分だけ返却される。
      const trackAddress = 0x1008;
      await manager.detachRemoteVideoTrack(trackAddress);

      expect(releasedAddresses, <int>[
        trackAddress,
      ], reason: 'entry がなくても remove 分は入口で 1 回返却される');
      // 経路識別性の担保: attach 経路を通っていない (sink attach なし) こと、
      // detach 内部の happy path (sink remove) にも到達していないこと。
      expect(attachedSinks, isEmpty);
      expect(removedSinks, isEmpty);
      // renderer dispose も呼ばれていないことを method call で確認する。
      expect(countMethodCalls('disposeRemoteVideoRenderer'), 0);
    });

    test('attach 途中の detach で remove 分・add 分ともに 1 回ずつ release される', () async {
      // renderer 応答を保留させて attach を進行中にしておく。
      final rendererCompleter = Completer<Map<String, Object?>?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) async {
            methodCalls.add(call);
            switch (call.method) {
              case 'createRemoteVideoRenderer':
                return rendererCompleter.future;
              case 'disposeRemoteVideoRenderer':
                return null;
            }
            return null;
          });

      final manager = createManager();
      const trackAddress = 0x1009;
      // attach を投入して pendingAttach に登録される状態にする。
      final attachFuture = manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connF-video',
      );
      // pending 状態で detach を投入。入口の remove 分と、
      // _pendingAttach.contains 経由の `_removedBeforeAttach` 登録が起きる。
      final detachFuture = manager.detachRemoteVideoTrack(trackAddress);

      // renderer 応答を返し、attach 側の `_removedBeforeAttach` 判定に到達させる。
      rendererCompleter.complete(<String, Object?>{
        'rendererId': 900,
        'renderingSinkPtr': 0,
        'videoSinkPtr': 1400,
        'textureId': 1900,
      });

      await attachFuture;
      await detachFuture;

      // 期待: 入口の remove 分 1 回 + attach の `_removedBeforeAttach` 経路の
      // add 分 1 回 = 合計 2 回。
      expect(
        countReleases(trackAddress),
        2,
        reason: 'attach 途中 detach で remove 分・add 分がそれぞれ 1 回返却される',
      );
      // `_removedBeforeAttach` 経路では renderer dispose が呼ばれる
      // (renderer は既に response で作成されているため)。
      expect(countMethodCalls('disposeRemoteVideoRenderer'), 1);
    });

    test('世代変化した attach で add 分が 1 回 release される', () async {
      // renderer 応答を保留させて attach を進行中にしておき、その間に
      // invalidateGeneration() を呼ぶと、attach は世代変化 early return に落ちる。
      final rendererCompleter = Completer<Map<String, Object?>?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) async {
            methodCalls.add(call);
            switch (call.method) {
              case 'createRemoteVideoRenderer':
                return rendererCompleter.future;
              case 'disposeRemoteVideoRenderer':
                return null;
            }
            return null;
          });

      final manager = createManager();
      const trackAddress = 0x100A;
      final attachFuture = manager.attachRemoteVideoTrack(
        trackAddress,
        trackId: 'connG-video',
      );

      // 世代を進めてから renderer 応答を返す。attach は世代変化を検出して
      // early return し、renderer dispose と add 分 release を行う。
      manager.invalidateGeneration();
      rendererCompleter.complete(<String, Object?>{
        'rendererId': 700,
        'renderingSinkPtr': 0,
        'videoSinkPtr': 1200,
        'textureId': 1700,
      });

      await attachFuture;

      expect(releasedAddresses, <int>[
        trackAddress,
      ], reason: '世代変化 early return で add 分が 1 回だけ返却される');
      expect(countMethodCalls('disposeRemoteVideoRenderer'), 1);
      expect(attachedSinks, isEmpty);
    });

    test(
      'attach 途中の MethodChannel 例外を catch 節が拾い add 分が 1 回 release される',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(soraMethodChannel, (call) async {
              methodCalls.add(call);
              if (call.method == 'createRemoteVideoRenderer') {
                throw PlatformException(code: 'test-error');
              }
              return null;
            });

        final manager = createManager();
        const trackAddress = 0x100B;

        // rethrow するため await は throw する。catch 節が add 分を release
        // した後に例外を伝播することを確認する。
        await expectLater(
          manager.attachRemoteVideoTrack(trackAddress, trackId: 'connH-video'),
          throwsA(isA<PlatformException>()),
        );

        expect(releasedAddresses, <int>[
          trackAddress,
        ], reason: 'catch 節で add 分が 1 回だけ返却される');
        expect(attachedSinks, isEmpty);
      },
    );

    test(
      'detachAll が pending attach を打ち消し、renderer 応答後に add 分が 1 回 release される',
      () async {
        // renderer 応答を保留させた状態で attach を投入し、pendingAttach に
        // 積まれたところで detachAll を起動する。detachAll は _pendingAttach を
        // _removedBeforeAttach.addAll() で全件打ち消しに登録し、
        // pendingAttachWaiters の完了を await する。renderer 応答を返せば
        // attach 側が _removedBeforeAttach を消化して _cancelPendingAttach 経由で
        // add 分を返却し、pendingAttachWaiter を完了させて detachAll が終わる。
        final rendererCompleter = Completer<Map<String, Object?>?>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(soraMethodChannel, (call) async {
              methodCalls.add(call);
              switch (call.method) {
                case 'createRemoteVideoRenderer':
                  return rendererCompleter.future;
                case 'disposeRemoteVideoRenderer':
                  return null;
              }
              return null;
            });

        final manager = createManager();
        const trackAddress = 0x100C;
        final attachFuture = manager.attachRemoteVideoTrack(
          trackAddress,
          trackId: 'connI-video',
        );

        // pending attach が積まれていることを確認するため、微小に yield する。
        await Future<void>.delayed(Duration.zero);

        final detachAllFuture = manager.detachAllRemoteVideoTracks();

        // renderer 応答を返して attach 側の _removedBeforeAttach 打ち消し経路に
        // 到達させる。
        rendererCompleter.complete(<String, Object?>{
          'rendererId': 800,
          'renderingSinkPtr': 0,
          'videoSinkPtr': 1300,
          'textureId': 1800,
        });

        await attachFuture;
        await detachAllFuture;

        // 期待: attach 側の _removedBeforeAttach 打ち消し経路で add 分が 1 回
        // 返却される。detachAll は _pendingAttach 経由で個別 detach を発火
        // しないため remove 分は無い (detachRemoteVideoTrack が呼ばれていない)。
        expect(
          countReleases(trackAddress),
          1,
          reason: 'detachAll 経由の pending attach 打ち消しで add 分が 1 回だけ返却される',
        );
        // renderer は attach 側が dispose する。
        expect(countMethodCalls('disposeRemoteVideoRenderer'), 1);
        // sink attach は _removedBeforeAttach 経路では起動しない。
        expect(attachedSinks, isEmpty);
      },
    );
  });

  group('RemoteTrackManager の crash / 例外', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, (call) async {
            switch (call.method) {
              case 'createRemoteVideoRenderer':
                return <String, Object?>{
                  'rendererId': 1,
                  'renderingSinkPtr': 0,
                  'videoSinkPtr': 2,
                  'textureId': 3,
                };
              case 'disposeRemoteVideoRenderer':
                return null;
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(soraMethodChannel, null);
    });

    test('全経路で crash / 例外が発生せず、収支が期待通りになる (smoke)', () async {
      final released = <int>[];
      final manager = RemoteTrackManager(
        clientId: 1,
        soraMethodChannel: soraMethodChannel,
        onDebugMessage: (_) {},
        onTrackEvent: (_) {},
        onRemoveTrackEvent: (_) {},
      );
      manager.releaseTrackRefForTest = released.add;
      manager.attachSinkToTrackForTest = (_, _) {};
      manager.removeSinkFromTrackForTest = (_, _) {};

      // シナリオ 1: attach x2 (重複通知) → detach = release 3 回
      //   1 回目 attach: entry 保持、release 0
      //   2 回目 attach: 重複 early return、release 1 (add 分)
      //   detach: 入口 remove 分 + happy path add 分、release 2
      await manager.attachRemoteVideoTrack(0x2001, trackId: 'connS-video');
      await manager.attachRemoteVideoTrack(0x2001, trackId: 'connS-video');
      await manager.detachRemoteVideoTrack(0x2001);
      // シナリオ 2: attach なしの detach → 入口 remove 分のみ、release 1
      await manager.detachRemoteVideoTrack(0x2999);
      // シナリオ 3: attach → detachAll → happy path add 分、release 1
      await manager.attachRemoteVideoTrack(0x2002, trackId: 'connT-video');
      await manager.detachAllRemoteVideoTracks();

      // 総 release 回数 = 3 (シナリオ 1) + 1 (シナリオ 2) + 1 (シナリオ 3) = 5
      expect(
        released.length,
        5,
        reason: 'smoke シナリオ全体で expected な release 収支が守られること',
      );
    });
  });
}
