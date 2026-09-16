import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/callback_handlers.dart'
    show SdpNegotiationCallbacks, SdpNegotiationTestHooks;
import 'package:sora_sdk/src/ffi/library_loader.dart';

import 'support/ffi_test_environment.dart';

class _Spy {
  final List<Map<String, Object?>> signalings = [];
  final List<String> states = [];
  int addLocalTracksCount = 0;
  int applyEncodingsCount = 0;

  void emitState(String state, String? reason, String? message) {
    states.add(state);
  }

  void emitDebug(String message) {}

  void emitSignalingMessage(Map<String, Object?> message) {
    signalings.add(message);
  }

  void addLocalTracks() {
    addLocalTracksCount++;
  }

  void applyEncodings() {
    applyEncodingsCount++;
  }
}

class _CallbackHarness {
  _CallbackHarness(
    this.lib,
    this.dylib, {
    _Spy? spy,
    void Function()? applyEncodings,
    bool isReOffer = false,
  }) : spy = spy ?? _Spy() {
    callbacks = SdpNegotiationCallbacks(
      lib: lib,
      consts: WebrtcConstants(dylib),
      emitState: this.spy.emitState,
      emitDebug: this.spy.emitDebug,
      emitSignalingMessage: this.spy.emitSignalingMessage,
      addLocalTracks: this.spy.addLocalTracks,
      applyEncodings: applyEncodings ?? this.spy.applyEncodings,
      testHooks: SdpNegotiationTestHooks(
        // native へ渡さず、_createAnswer hook で止めるため dereference されない。
        initialPeerConnectionRef:
            Pointer<WebrtcPeerConnectionInterfaceRefcounted>.fromAddress(1),
        initialAnswerType: isReOffer ? 're-answer' : 'answer',
        initialIsReOffer: isReOffer,
        createAnswer: _createAnswer,
        setLocalDescription: _setLocalDescription,
      ),
    );
  }

  final LibWebrtcC lib;
  final DynamicLibrary dylib;
  final _Spy spy;
  late final SdpNegotiationCallbacks callbacks;
  String? _answerSdp;

  void completeSetRemoteDescriptionWithAnswer(String sdp) {
    _answerSdp = sdp;
    try {
      callbacks.onSetRemoteDescriptionComplete(nullptr);
    } finally {
      _answerSdp = null;
    }
  }

  void completeSetRemoteDescriptionWithoutAnswer() {
    callbacks.onSetRemoteDescriptionComplete(nullptr);
  }

  void _createAnswer() {
    final sdp = _answerSdp;
    if (sdp == null) {
      return;
    }
    callbacks.onCreateAnswerSuccess(_createAnswerDescription(lib, dylib, sdp));
  }

  void _setLocalDescription(
    Pointer<WebrtcSessionDescriptionInterfaceUnique> desc,
  ) {
    lib.sessionDescriptionUniqueDelete(desc);
    callbacks.onSetLocalDescriptionComplete(nullptr);
  }
}

SdpNegotiationCallbacks _createBareCallback(
  LibWebrtcC lib,
  DynamicLibrary dylib, {
  _Spy? spy,
}) {
  final s = spy ?? _Spy();
  return SdpNegotiationCallbacks(
    lib: lib,
    consts: WebrtcConstants(dylib),
    emitState: s.emitState,
    emitDebug: s.emitDebug,
    emitSignalingMessage: s.emitSignalingMessage,
    addLocalTracks: s.addLocalTracks,
    applyEncodings: s.applyEncodings,
  );
}

Pointer<WebrtcSessionDescriptionInterfaceUnique> _createAnswerDescription(
  LibWebrtcC lib,
  DynamicLibrary dylib,
  String sdp,
) {
  final sdpUtf8 = sdp.toNativeUtf8();
  try {
    final desc = lib.createSessionDescription(
      WebrtcConstants(dylib).sdpTypeAnswer,
      sdpUtf8.cast<Char>(),
      sdpUtf8.length,
    );
    expect(desc, isNot(nullptr));
    return desc;
  } finally {
    calloc.free(sdpUtf8);
  }
}

// libwebrtc-c の SDP パーサに拒否されない最小構成の SDP。
// v/o/s/t の必須ラインのみで media を持たない。
// libwebrtc の SdpSerialize は o= 行の session_id / session_version を parsed 値
// のまま返し、他の要素は kSessionOriginUsername / kSessionOriginNettype /
// kSessionOriginAddrtype / kSessionOriginAddress / kSessionName / kTimeDescription
// の各定数を用いて組み立て直す。この SDP は上記 6 定数の値と一致するように
// 選んであり、parse → serialize の round-trip が identity になる。上記 6 定数が
// 将来変わると完全一致 assertion が破れる点は明示的な負債として了解する。
const String _validMinimalSdp =
    'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';

void main() {
  final ffiTestEnvironment = prepareFfiTestEnvironment();

  group('SdpNegotiationCallbacks race 再現', () {
    late DynamicLibrary dylib;
    late LibWebrtcC lib;

    setUpAll(() {
      dylib = loadLibWebrtcC();
      lib = LibWebrtcC(dylib);
    });

    test('offer -> offer: old emits nothing, new emits answer', () {
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _CallbackHarness(lib, dylib, spy: spyA);
      a.callbacks.cancel();
      final b = _CallbackHarness(lib, dylib, spy: spyB);

      a.completeSetRemoteDescriptionWithAnswer('sdp-a');

      expect(spyA.states, isEmpty);
      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);
      expect(spyA.applyEncodingsCount, 0);

      b.completeSetRemoteDescriptionWithAnswer(_validMinimalSdp);

      expect(b.callbacks.isCancelled, false);
      expect(spyB.signalings.single['type'], 'answer');
      expect(spyB.signalings.single['sdp'], _validMinimalSdp);
      expect(spyB.addLocalTracksCount, 1);
    });

    test(
      're-offer -> re-offer: old re-answer suppressed, new emits re-answer',
      () {
        final spyA = _Spy();
        final spyB = _Spy();

        final a = _CallbackHarness(lib, dylib, spy: spyA, isReOffer: true);
        a.callbacks.cancel();
        final b = _CallbackHarness(lib, dylib, spy: spyB, isReOffer: true);

        a.completeSetRemoteDescriptionWithAnswer('sdp-a');

        expect(spyA.states, isEmpty);
        expect(spyA.signalings, isEmpty);
        expect(spyA.addLocalTracksCount, 0);

        b.completeSetRemoteDescriptionWithAnswer(_validMinimalSdp);

        expect(b.callbacks.isCancelled, false);
        expect(spyB.signalings.single['type'], 're-answer');
        expect(spyB.signalings.single['sdp'], _validMinimalSdp);
        expect(
          spyB.addLocalTracksCount,
          0,
        ); // isReOffer のため addLocalTracks スキップ
      },
    );

    test('offer -> re-offer: late answer from offer suppressed', () {
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _CallbackHarness(lib, dylib, spy: spyA);
      a.callbacks.cancel();
      final b = _CallbackHarness(lib, dylib, spy: spyB, isReOffer: true);

      a.completeSetRemoteDescriptionWithAnswer('sdp-offer');

      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);

      b.completeSetRemoteDescriptionWithAnswer(_validMinimalSdp);

      expect(b.callbacks.isCancelled, false);
      // B は re-offer なので re-answer を emit する
      expect(spyB.signalings.single['type'], 're-answer');
      expect(spyB.signalings.single['sdp'], _validMinimalSdp);
      expect(spyB.addLocalTracksCount, 0);
    });

    test('re-offer -> offer: late re-answer from re-offer suppressed', () {
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _CallbackHarness(lib, dylib, spy: spyA, isReOffer: true);
      a.callbacks.cancel();
      final b = _CallbackHarness(lib, dylib, spy: spyB);

      a.completeSetRemoteDescriptionWithAnswer('sdp-reoffer');

      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);

      b.completeSetRemoteDescriptionWithAnswer(_validMinimalSdp);

      expect(b.callbacks.isCancelled, false);
      // B は offer なので answer を emit する
      expect(spyB.signalings.single['type'], 'answer');
      expect(spyB.signalings.single['sdp'], _validMinimalSdp);
      expect(spyB.addLocalTracksCount, 1);
    });

    test('CreateAnswer failure from old instance does not emit error', () {
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _CallbackHarness(lib, dylib, spy: spyA);
      a.callbacks.cancel();
      final b = _CallbackHarness(lib, dylib, spy: spyB);

      a.completeSetRemoteDescriptionWithoutAnswer();
      a.callbacks.onCreateAnswerFailure(nullptr);

      expect(spyA.states, isEmpty);
      expect(spyA.signalings, isEmpty);

      b.callbacks.onCreateAnswerFailure(nullptr);
      expect(spyB.states, ['error']);
    });

    test(
      'encodings closure: old never called, new called with correct data',
      () {
        var encCalledA = false;
        var encCalledB = false;
        final capturedByB = <String?>[];

        final a = _CallbackHarness(
          lib,
          dylib,
          applyEncodings: () {
            encCalledA = true;
          },
        );
        a.callbacks.cancel();
        final b = _CallbackHarness(
          lib,
          dylib,
          applyEncodings: () {
            encCalledB = true;
            capturedByB.add('r2');
          },
        );

        a.completeSetRemoteDescriptionWithoutAnswer();
        expect(encCalledA, false);

        b.completeSetRemoteDescriptionWithoutAnswer();
        expect(encCalledB, true);
        expect(capturedByB, ['r2']);
      },
    );

    test('cancel 後の onCreateAnswerSuccess は signaling を送出しない', () {
      final spy = _Spy();
      final cbs = _createBareCallback(lib, dylib, spy: spy);
      cbs.cancel();

      final desc = _createAnswerDescription(lib, dylib, _validMinimalSdp);

      cbs.onCreateAnswerSuccess(desc);

      expect(spy.states, isEmpty);
      expect(spy.signalings, isEmpty);
    });

    test('_pcRef が null の onCreateAnswerSuccess は安全に終了する', () {
      final spy = _Spy();
      final cbs = _createBareCallback(lib, dylib, spy: spy);

      final desc = _createAnswerDescription(lib, dylib, _validMinimalSdp);

      cbs.onCreateAnswerSuccess(desc);

      expect(spy.states, isEmpty);
      expect(spy.signalings, isEmpty);
    });
  }, skip: ffiTestEnvironment.skipReason);
}
