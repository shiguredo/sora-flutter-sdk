import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sora_sdk/src/ffi/bindings.dart';
import 'package:sora_sdk/src/ffi/callback_handlers.dart'
    show SdpNegotiationCallbacks;
import 'package:sora_sdk/src/ffi/library_loader.dart';

DynamicLibrary? _tryLoadDynLib() {
  try {
    return loadLibWebrtcC();
  } catch (_) {
    return null;
  }
}

bool _ffiAvailable(DynamicLibrary dylib) {
  try {
    final lib = LibWebrtcC(dylib);
    final f = lib.createBuiltinVideoEncoderFactory();
    if (f != nullptr) {
      lib.videoEncoderFactoryUniqueDelete(f);
      return true;
    }
    return false;
  } catch (_) {
    return false;
  }
}

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

SdpNegotiationCallbacks _createCallback(
  LibWebrtcC lib,
  DynamicLibrary dylib, {
  _Spy? spy,
  void Function()? applyEncodings,
  bool isReOffer = false,
}) {
  final s = spy ?? _Spy();
  final cbs = SdpNegotiationCallbacks(
    lib: lib,
    consts: WebrtcConstants(dylib),
    emitState: s.emitState,
    emitDebug: s.emitDebug,
    emitSignalingMessage: s.emitSignalingMessage,
    addLocalTracks: s.addLocalTracks,
    applyEncodings: applyEncodings ?? s.applyEncodings,
  );
  if (isReOffer) {
    cbs.simulateReOfferStateForTest();
  }
  return cbs;
}

void main() {
  group('SdpNegotiationCallbacks race 再現', () {
    late DynamicLibrary dylib;
    late LibWebrtcC lib;
    late bool ffiAvailable;

    setUpAll(() {
      final loaded = _tryLoadDynLib();
      if (loaded == null) {
        ffiAvailable = false;
        return;
      }
      dylib = loaded;
      lib = LibWebrtcC(dylib);
      ffiAvailable = _ffiAvailable(dylib);
    });

    test('offer -> offer: old emits nothing, new emits answer', () {
      if (!ffiAvailable) return;
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _createCallback(lib, dylib, spy: spyA);
      a.cancel();
      final b = _createCallback(lib, dylib, spy: spyB);

      a.simulateSetRemoteDescriptionSuccessForTest();
      a.simulateCreateAnswerSuccessForTest('sdp-a');
      a.simulateSetLocalDescriptionSuccessForTest();

      expect(spyA.states, isEmpty);
      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);
      expect(spyA.applyEncodingsCount, 0);

      b.simulateSetRemoteDescriptionSuccessForTest();
      b.simulateCreateAnswerSuccessForTest('sdp-b');
      b.simulateSetLocalDescriptionSuccessForTest();

      expect(b.isCancelled, false);
      expect(spyB.signalings.single['type'], 'answer');
      expect(spyB.signalings.single['sdp'], 'sdp-b');
      expect(spyB.addLocalTracksCount, 1);
    });

    test(
      're-offer -> re-offer: old re-answer suppressed, new emits re-answer',
      () {
        if (!ffiAvailable) return;
        final spyA = _Spy();
        final spyB = _Spy();

        final a = _createCallback(lib, dylib, spy: spyA, isReOffer: true);
        a.cancel();
        final b = _createCallback(lib, dylib, spy: spyB, isReOffer: true);

        a.simulateSetRemoteDescriptionSuccessForTest();
        a.simulateCreateAnswerSuccessForTest('sdp-a');
        a.simulateSetLocalDescriptionSuccessForTest();

        expect(spyA.states, isEmpty);
        expect(spyA.signalings, isEmpty);
        expect(spyA.addLocalTracksCount, 0);

        b.simulateSetRemoteDescriptionSuccessForTest();
        b.simulateCreateAnswerSuccessForTest('sdp-b');
        b.simulateSetLocalDescriptionSuccessForTest();

        expect(b.isCancelled, false);
        expect(spyB.signalings.single['type'], 're-answer');
        expect(spyB.signalings.single['sdp'], 'sdp-b');
        expect(
          spyB.addLocalTracksCount,
          0,
        ); // isReOffer のため addLocalTracks スキップ
      },
    );

    test('offer -> re-offer: late answer from offer suppressed', () {
      if (!ffiAvailable) return;
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _createCallback(lib, dylib, spy: spyA);
      a.cancel();
      final b = _createCallback(lib, dylib, spy: spyB, isReOffer: true);

      a.simulateSetRemoteDescriptionSuccessForTest();
      a.simulateCreateAnswerSuccessForTest('sdp-offer');
      a.simulateSetLocalDescriptionSuccessForTest();

      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);

      b.simulateSetRemoteDescriptionSuccessForTest();
      b.simulateCreateAnswerSuccessForTest('sdp-reoffer');
      b.simulateSetLocalDescriptionSuccessForTest();

      expect(b.isCancelled, false);
      // B は re-offer なので re-answer を emit する
      expect(spyB.signalings.single['type'], 're-answer');
      expect(spyB.signalings.single['sdp'], 'sdp-reoffer');
      expect(spyB.addLocalTracksCount, 0);
    });

    test('re-offer -> offer: late re-answer from re-offer suppressed', () {
      if (!ffiAvailable) return;
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _createCallback(lib, dylib, spy: spyA, isReOffer: true);
      a.cancel();
      final b = _createCallback(lib, dylib, spy: spyB);

      a.simulateSetRemoteDescriptionSuccessForTest();
      a.simulateCreateAnswerSuccessForTest('sdp-reoffer');
      a.simulateSetLocalDescriptionSuccessForTest();

      expect(spyA.signalings, isEmpty);
      expect(spyA.addLocalTracksCount, 0);

      b.simulateSetRemoteDescriptionSuccessForTest();
      b.simulateCreateAnswerSuccessForTest('sdp-offer');
      b.simulateSetLocalDescriptionSuccessForTest();

      expect(b.isCancelled, false);
      // B は offer なので answer を emit する
      expect(spyB.signalings.single['type'], 'answer');
      expect(spyB.signalings.single['sdp'], 'sdp-offer');
      expect(spyB.addLocalTracksCount, 1);
    });

    test('CreateAnswer failure from old instance does not emit error', () {
      if (!ffiAvailable) return;
      final spyA = _Spy();
      final spyB = _Spy();

      final a = _createCallback(lib, dylib, spy: spyA);
      a.cancel();
      final b = _createCallback(lib, dylib, spy: spyB);

      a.simulateSetRemoteDescriptionSuccessForTest();
      a.simulateCreateAnswerFailureForTest('something went wrong');

      expect(spyA.states, isEmpty);
      expect(spyA.signalings, isEmpty);

      b.simulateCreateAnswerFailureForTest('real error');
      expect(spyB.states, ['error']);
    });

    test(
      'encodings closure: old never called, new called with correct data',
      () {
        if (!ffiAvailable) return;
        var encCalledA = false;
        var encCalledB = false;
        final capturedByB = <String?>[];

        final a = _createCallback(
          lib,
          dylib,
          applyEncodings: () {
            encCalledA = true;
          },
        );
        a.cancel();
        final b = _createCallback(
          lib,
          dylib,
          applyEncodings: () {
            encCalledB = true;
            capturedByB.add('r2');
          },
        );

        a.simulateSetRemoteDescriptionSuccessForTest();
        expect(encCalledA, false);

        b.simulateSetRemoteDescriptionSuccessForTest();
        expect(encCalledB, true);
        expect(capturedByB, ['r2']);
      },
    );

    test('cancel 後の onCreateAnswerSuccess は signaling を送出しない', () {
      if (!ffiAvailable) return;
      final spy = _Spy();
      final cbs = _createCallback(lib, dylib, spy: spy);
      cbs.cancel();

      final sdp = 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
      final sdpUtf8 = sdp.toNativeUtf8();
      final desc = lib.createSessionDescription(
        WebrtcConstants(dylib).sdpTypeAnswer,
        sdpUtf8.cast<Char>(),
        sdpUtf8.length,
      );
      calloc.free(sdpUtf8);
      expect(desc, isNot(nullptr));

      cbs.onCreateAnswerSuccess(desc);

      expect(spy.states, isEmpty);
      expect(spy.signalings, isEmpty);
    });

    test('_pcRef が null の onCreateAnswerSuccess は安全に終了する', () {
      if (!ffiAvailable) return;
      final spy = _Spy();
      final cbs = _createCallback(lib, dylib, spy: spy);

      final sdp = 'v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
      final sdpUtf8 = sdp.toNativeUtf8();
      final desc = lib.createSessionDescription(
        WebrtcConstants(dylib).sdpTypeAnswer,
        sdpUtf8.cast<Char>(),
        sdpUtf8.length,
      );
      calloc.free(sdpUtf8);
      expect(desc, isNot(nullptr));

      cbs.onCreateAnswerSuccess(desc);

      expect(spy.states, isEmpty);
      expect(spy.signalings, isEmpty);
    });
  });
}
