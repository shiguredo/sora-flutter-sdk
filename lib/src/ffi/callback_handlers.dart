// ignore_for_file: public_member_api_docs
// NativeCallable.listener によるコールバック受信
//
// WebRTC の内部スレッドから呼ばれるコールバックを
// Dart イベントループに安全にディスパッチする。

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.dart';
import 'memory.dart';

// ---------------------------------------------------------------------------
// SDP ネゴシエーションコールバック
// ---------------------------------------------------------------------------

// SDP ネゴシエーションの非同期コールバック連鎖を管理する。
//
// `SetRemoteDescription -> CreateAnswer -> SetLocalDescription` の順に
// observer を作り直しながら進め、途中で失敗した場合は Dart 側イベントへ
// エラーを返す。
class SdpNegotiationCallbacks {
  final LibWebrtcC _lib;
  final WebrtcConstants _consts;
  final void Function(String state, String? reason, String? message) emitState;
  final void Function(String message) emitDebug;
  final void Function(Map<String, Object?> message) emitSignalingMessage;
  final void Function() addLocalTracks;
  final void Function()? applyEncodings;

  Pointer<WebrtcPeerConnectionInterfaceRefcounted>? _pcRef;
  String? _pendingAnswerSdp;
  // re-offer の場合は re-answer を返し、ローカルトラック追加をスキップする
  String _answerType = 'answer';
  bool _isReOffer = false;
  // 後続の offer / re-offer により旧インスタンスが無効化されたかどうか
  bool _cancelled = false;

  // ネゴシエーション中に必要な lib / constants / イベント出力先を束ねる。
  //
  // 実際の処理開始は `setRemoteDescription()` からで、このコンストラクタでは
  // 依存注入のみを行う。
  SdpNegotiationCallbacks({
    required LibWebrtcC lib,
    required WebrtcConstants consts,
    required this.emitState,
    required this.emitDebug,
    required this.emitSignalingMessage,
    required this.addLocalTracks,
    this.applyEncodings,
  }) : _lib = lib,
       _consts = consts;

  // このインスタンスを無効化する。
  //
  // 後続の offer / re-offer により新しい `SdpNegotiationCallbacks` が
  // 生成される前に呼び出す。cancel 後は全コールバックが早期 return し、
  // イベント送出や状態変更を行わない。
  void cancel() {
    _cancelled = true;
  }

  /// テスト用に cancel 状態を公開する。
  @visibleForTesting
  bool get isCancelled => _cancelled;

  /// [SetRemoteDescription 成功時の処理を模擬する。
  ///
  /// cancel ガード、addLocalTracks、applyEncodings の抑制を
  /// FFI なしで検証するために使う。
  @visibleForTesting
  void simulateSetRemoteDescriptionSuccessForTest() {
    if (_cancelled) return;
    if (!_isReOffer) {
      addLocalTracks();
    }
    applyEncodings?.call();
  }

  /// CreateAnswer 成功時の SDP 退避を模擬する。
  ///
  /// `_pendingAnswerSdp` への代入と cancel ガードを検証する。
  @visibleForTesting
  void simulateCreateAnswerSuccessForTest(String sdp) {
    if (_cancelled) return;
    _pendingAnswerSdp = sdp;
  }

  /// CreateAnswer 失敗時の error emit を模擬する。
  @visibleForTesting
  void simulateCreateAnswerFailureForTest(String message) {
    if (_cancelled) return;
    emitState('error', 'create_answer_failed', message);
  }

  /// SetLocalDescription 成功時の signaling emit を模擬する。
  ///
  /// cancel ガード、`_answerType` / `_pendingAnswerSdp` の送出を検証する。
  @visibleForTesting
  void simulateSetLocalDescriptionSuccessForTest() {
    if (_cancelled) return;
    if (_pendingAnswerSdp != null) {
      emitSignalingMessage({'type': _answerType, 'sdp': _pendingAnswerSdp});
      _pendingAnswerSdp = null;
    }
  }

  /// re-offer 用の状態を模擬する。
  ///
  /// `_answerType = 're-answer'`、`_isReOffer = true` に設定し、
  /// cancel 後の re-answer 取り違え防止を検証できるようにする。
  @visibleForTesting
  void simulateReOfferStateForTest() {
    _answerType = 're-answer';
    _isReOffer = true;
  }

  // `SetRemoteDescription` を開始し、answer 生成チェーンの起点を作る。
  //
  // offer SDP を native 側 `SessionDescription` へ変換し、
  // observer 完了時に `_onSetRemoteDescriptionComplete()` が呼ばれるよう
  // 一時コールバック構造体を組み立てる。
  void setRemoteDescription(
    Pointer<WebrtcPeerConnectionInterfaceRefcounted> pcRef,
    String sdp, {
    String answerType = 'answer',
    bool isReOffer = false,
  }) {
    _answerType = answerType;
    _isReOffer = isReOffer;
    _pcRef = pcRef;
    final sdpUtf8 = sdp.toNativeUtf8();
    try {
      final sdpNative = sdpUtf8.cast<Char>();
      final desc = _lib.createSessionDescription(
        _consts.sdpTypeOffer,
        sdpNative,
        sdpUtf8.length,
      );

      final cbsPtr = calloc<SetRemoteDescriptionObserverCbs>();
      late final NativeCallable<Void Function(Pointer<Void>)> onDestroy;
      final onComplete =
          NativeCallable<
            Void Function(Pointer<WebrtcRTCErrorUnique>, Pointer<Void>)
          >.listener((Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> _) {
            onSetRemoteDescriptionComplete(error);
          });
      onDestroy = NativeCallable<Void Function(Pointer<Void>)>.listener((
        Pointer<Void> _,
      ) {
        onComplete.close();
        onDestroy.close();
        calloc.free(cbsPtr);
      });
      cbsPtr.ref.onSetRemoteDescriptionComplete = onComplete.nativeFunction;
      cbsPtr.ref.onDestroy = onDestroy.nativeFunction;
      // desc と cbsPtr + NativeCallable は pcSetRemoteDescription 成功時に
      // 所有権が移譲される。例外時のみ解放するため registered フラグで二重解放を防ぐ。
      var registered = false;
      try {
        final observer = _lib.setRemoteDescriptionObserverMakeRefCounted(
          cbsPtr,
          nullptr,
        );
        _lib.pcSetRemoteDescription(
          _lib.pcRefcountedGet(_pcRef!),
          desc,
          observer,
        );
        registered = true;
      } finally {
        // pcSetRemoteDescription 登録前に例外が発生した場合、
        // NativeCallable / cbsPtr / desc を C 側で解放する。
        // 登録成功時 (registered == true) は onDestroy / pc が所有権を持つため何もしない。
        if (!registered) {
          onComplete.close();
          onDestroy.close();
          calloc.free(cbsPtr);
          _lib.sessionDescriptionUniqueDelete(desc);
        }
      }
    } finally {
      // sdpUtf8 は常に解放する
      calloc.free(sdpUtf8);
    }
  }

  // `SetRemoteDescription` 完了後の分岐を処理する。
  //
  // 失敗時は即座に error を通知し、成功時は必要ならローカルトラック追加と
  // simulcast parameters 適用を行ってから `CreateAnswer` へ進む。
  @visibleForTesting
  void onSetRemoteDescriptionComplete(Pointer<WebrtcRTCErrorUnique> error) {
    if (_cancelled) return;
    final errMsg = rtcErrorMessage(_lib, error);
    if (errMsg != null) {
      emitState('error', 'set_remote_description_failed', errMsg);
      return;
    }
    emitDebug('native: set_remote_description_succeeded');

    // 初回 offer の場合のみローカルトラックを追加する
    if (!_isReOffer) {
      addLocalTracks();
    }

    // simulcast encodings を適用する (setRemoteDescription 後)
    // JS SDK と同様、active フラグの反映には setRemoteDescription 後の
    // setParameters が必要
    applyEncodings?.call();

    // CreateAnswer を実行する
    _createAnswer();
  }

  // `CreateAnswer` を発行し、成功時に local description 設定へ進める。
  //
  // observer の `onDestroy` で `NativeCallable` と構造体を解放し、
  // WebRTC 側が完了通知を終えたタイミングで寿命を閉じる。
  void _createAnswer() {
    if (_pcRef == null) return;

    final cbsPtr = calloc<CreateSessionDescriptionObserverCbs>();
    late final NativeCallable<Void Function(Pointer<Void>)> onDestroy;
    final onSuccess =
        NativeCallable<
          Void Function(
            Pointer<WebrtcSessionDescriptionInterfaceUnique>,
            Pointer<Void>,
          )
        >.listener((
          Pointer<WebrtcSessionDescriptionInterfaceUnique> desc,
          Pointer<Void> _,
        ) {
          onCreateAnswerSuccess(desc);
        });
    final onFailure =
        NativeCallable<
          Void Function(Pointer<WebrtcRTCErrorUnique>, Pointer<Void>)
        >.listener((Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> _) {
          if (_cancelled) return;
          final errMsg = rtcErrorMessage(_lib, error);
          emitState('error', 'create_answer_failed', errMsg ?? '');
        });
    onDestroy = NativeCallable<Void Function(Pointer<Void>)>.listener((
      Pointer<Void> _,
    ) {
      onSuccess.close();
      onFailure.close();
      onDestroy.close();
      calloc.free(cbsPtr);
    });
    cbsPtr.ref.onSuccess = onSuccess.nativeFunction;
    cbsPtr.ref.onFailure = onFailure.nativeFunction;
    cbsPtr.ref.onDestroy = onDestroy.nativeFunction;
    // cbsPtr + NativeCallable は pcCreateAnswer 成功時に onDestroy へ所有権が移る。
    // 例外時のみ解放するため registered フラグで二重解放を防ぐ。
    // options は常時解放のため内側の finally で rtcOfferAnswerOptionsDelete する。
    var registered = false;
    try {
      final observer = _lib.createSessionDescriptionObserverMakeRefCounted(
        cbsPtr,
        nullptr,
      );
      final options = _lib.rtcOfferAnswerOptionsNew();
      try {
        _lib.pcCreateAnswer(_lib.pcRefcountedGet(_pcRef!), observer, options);
        registered = true;
      } finally {
        _lib.rtcOfferAnswerOptionsDelete(options);
      }
    } finally {
      // pcCreateAnswer 登録前に例外が発生した場合、
      // NativeCallable / cbsPtr を Dart 側で解放する。
      // 登録成功時 (registered == true) は onDestroy が所有権を持つため何もしない。
      if (!registered) {
        onSuccess.close();
        onFailure.close();
        onDestroy.close();
        calloc.free(cbsPtr);
      }
    }
  }

  // `CreateAnswer` 成功時に SDP 文字列を退避し、`SetLocalDescription` を開始する。
  @visibleForTesting
  void onCreateAnswerSuccess(
    Pointer<WebrtcSessionDescriptionInterfaceUnique> desc,
  ) {
    if (_cancelled) {
      _lib.sessionDescriptionUniqueDelete(desc);
      return;
    }
    final sdpOutPtr = calloc<Pointer<StdStringUnique>>();
    try {
      _lib.sessionDescriptionToString(
        _lib.sessionDescriptionUniqueGet(desc),
        sdpOutPtr,
      );
      _pendingAnswerSdp = stdStringToDart(_lib, sdpOutPtr.value);
    } finally {
      // sdpOutPtr は常に解放する
      calloc.free(sdpOutPtr);
    }

    // desc は _setLocalDescription 成功時に所有権が移譲される。
    // 例外時のみ解放する。
    try {
      _setLocalDescription(desc);
    } catch (_) {
      _lib.sessionDescriptionUniqueDelete(desc);
      rethrow;
    }
  }

  // `SetLocalDescription` を開始し、answer を最終的にシグナリング送信できる
  // 状態まで進める。
  void _setLocalDescription(
    Pointer<WebrtcSessionDescriptionInterfaceUnique> desc,
  ) {
    if (_pcRef == null) {
      _lib.sessionDescriptionUniqueDelete(desc);
      return;
    }

    final cbsPtr = calloc<SetLocalDescriptionObserverCbs>();
    late final NativeCallable<Void Function(Pointer<Void>)> onDestroy;
    final onComplete =
        NativeCallable<
          Void Function(Pointer<WebrtcRTCErrorUnique>, Pointer<Void>)
        >.listener((Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> _) {
          onSetLocalDescriptionComplete(error);
        });
    onDestroy = NativeCallable<Void Function(Pointer<Void>)>.listener((
      Pointer<Void> _,
    ) {
      onComplete.close();
      onDestroy.close();
      calloc.free(cbsPtr);
    });
    cbsPtr.ref.onSetLocalDescriptionComplete = onComplete.nativeFunction;
    cbsPtr.ref.onDestroy = onDestroy.nativeFunction;
    // desc と cbsPtr + NativeCallable は pcSetLocalDescription 成功時に
    // 所有権が移譲される。例外時のみ解放するため registered フラグで二重解放を防ぐ。
    var registered = false;
    try {
      final observer = _lib.setLocalDescriptionObserverMakeRefCounted(
        cbsPtr,
        nullptr,
      );
      _lib.pcSetLocalDescription(_lib.pcRefcountedGet(_pcRef!), desc, observer);
      registered = true;
    } finally {
      // pcSetLocalDescription 登録前に例外が発生した場合、
      // NativeCallable / cbsPtr / desc を C 側で解放する。
      // 登録成功時 (registered == true) は onDestroy / pc が所有権を持つため何もしない。
      if (!registered) {
        onComplete.close();
        onDestroy.close();
        calloc.free(cbsPtr);
        _lib.sessionDescriptionUniqueDelete(desc);
      }
    }
  }

  // `SetLocalDescription` 完了後に answer SDP を Dart 側へ通知する。
  //
  // `_pendingAnswerSdp` は `CreateAnswer` 成功時にだけ入るため、
  // null でないときだけシグナリングメッセージを emit する。
  @visibleForTesting
  void onSetLocalDescriptionComplete(Pointer<WebrtcRTCErrorUnique> error) {
    if (_cancelled) return;
    final errMsg = rtcErrorMessage(_lib, error);
    if (errMsg != null) {
      emitState('error', 'set_local_description_failed', errMsg);
      return;
    }
    if (_pendingAnswerSdp != null) {
      emitDebug('native: set_local_description_succeeded');
      emitSignalingMessage({'type': _answerType, 'sdp': _pendingAnswerSdp});
      _pendingAnswerSdp = null;
    }
  }
}
