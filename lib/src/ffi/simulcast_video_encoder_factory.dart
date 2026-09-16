// ignore_for_file: public_member_api_docs
// ignore_for_file: must_return_void

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'bindings.dart';

final class _UserData extends Struct {
  // C callback から元の factory と必須関数ポインタへ戻るための束。
  //
  // Dart オブジェクトを直接 userData に渡せないため、必要最小限の native
  // 情報だけを POD 構造体へ詰めている。
  external Pointer<WebrtcVideoEncoderFactoryUnique> inner;
  external Pointer<NativeFunction<VideoEncoderFactoryUniqueGetNativeFn>>
  videoEncoderFactoryUniqueGet;
  external Pointer<
    NativeFunction<VideoEncoderFactoryGetSupportedFormatsNativeFn>
  >
  videoEncoderFactoryGetSupportedFormats;
  external Pointer<NativeFunction<SimulcastEncoderAdapterNewNativeFn>>
  simulcastEncoderAdapterNew;
  external Pointer<NativeFunction<SimulcastEncoderAdapterUniqueGetNativeFn>>
  simulcastEncoderAdapterUniqueGet;
  external Pointer<NativeFunction<SimulcastEncoderAdapterUniqueDeleteNativeFn>>
  simulcastEncoderAdapterUniqueDelete;
  external Pointer<
    NativeFunction<SimulcastEncoderAdapterCastToVideoEncoderNativeFn>
  >
  simulcastEncoderAdapterCastToVideoEncoder;
  external Pointer<NativeFunction<VideoEncoderFactoryUniqueDeleteNativeFn>>
  videoEncoderFactoryUniqueDelete;
}

// `SimulcastEncoderAdapter` を返すラッパー `VideoEncoderFactory`。
//
// 既存の encoder factory を包み、`create()` 呼び出し時に WebRTC の
// simulcast adapter を挟んだ encoder を返すよう C callback で差し替える。
class SimulcastVideoEncoderFactory {
  final LibWebrtcC _lib;
  final Pointer<WebrtcVideoEncoderFactoryUnique> _inner;
  Pointer<WebrtcVideoEncoderFactoryUnique> _native = nullptr;
  Pointer<VideoEncoderFactoryCbs> _cbs = nullptr;
  Pointer<_UserData> _userData = nullptr;
  NativeCallable<VideoEncoderFactoryCbsGetSupportedFormatsNativeFn>?
  _getSupportedFormats;
  NativeCallable<VideoEncoderFactoryCbsCreateNativeFn>? _create;
  NativeCallable<VideoEncoderFactoryCbsOnDestroyNativeFn>? _onDestroy;
  bool _cleaned = false;

  // 元の encoder factory を受け取り、C 側 callback factory を構築する。
  //
  // 途中失敗時は `_cleanup()` で確保済みリソースをすべて巻き戻す。
  SimulcastVideoEncoderFactory(
    LibWebrtcC lib,
    Pointer<WebrtcVideoEncoderFactoryUnique> inner,
  ) : _lib = lib,
      _inner = inner {
    _ensureRequiredSymbols();

    try {
      _userData = calloc<_UserData>();
      _userData.ref.inner = _inner;
      _userData.ref.videoEncoderFactoryUniqueGet =
          _lib.videoEncoderFactoryUniqueGetPtr;
      _userData.ref.videoEncoderFactoryGetSupportedFormats =
          _lib.videoEncoderFactoryGetSupportedFormatsPtr;
      _userData.ref.simulcastEncoderAdapterNew =
          _lib.simulcastEncoderAdapterNewPtr;
      _userData.ref.simulcastEncoderAdapterUniqueGet =
          _lib.simulcastEncoderAdapterUniqueGetPtr;
      _userData.ref.simulcastEncoderAdapterUniqueDelete =
          _lib.simulcastEncoderAdapterUniqueDeletePtr;
      _userData.ref.simulcastEncoderAdapterCastToVideoEncoder =
          _lib.simulcastEncoderAdapterCastToVideoEncoderPtr;
      _userData.ref.videoEncoderFactoryUniqueDelete =
          _lib.videoEncoderFactoryUniqueDeletePtr;

      _getSupportedFormats =
          NativeCallable<
            VideoEncoderFactoryCbsGetSupportedFormatsNativeFn
          >.isolateGroupBound(_onGetSupportedFormats);
      _create =
          NativeCallable<
            VideoEncoderFactoryCbsCreateNativeFn
          >.isolateGroupBound(_onCreate);
      _onDestroy =
          NativeCallable<
            VideoEncoderFactoryCbsOnDestroyNativeFn
          >.isolateGroupBound(onNativeDestroy);

      _cbs = calloc<VideoEncoderFactoryCbs>();
      _cbs.ref.getSupportedFormats = _getSupportedFormats!.nativeFunction;
      _cbs.ref.create = _create!.nativeFunction;
      _cbs.ref.onDestroy = _onDestroy!.nativeFunction;

      _native = _lib.videoEncoderFactoryNew(_cbs, _userData.cast<Void>());
      if (_native == nullptr) {
        throw StateError('failed to create SimulcastVideoEncoderFactory');
      }
    } catch (_) {
      _cleanup();
      rethrow;
    }
  }

  // C API へ渡す `VideoEncoderFactoryUnique` を返す。
  //
  /// `PeerConnectionFactoryDependencies` へ渡す所有ポインタ。
  ///
  /// 呼び出しにより `_native` の delete 責務をネイティブ側へ移譲する。
  /// 移譲後は `_native = nullptr` にし、`_cleanup` での二重解放を防ぐ。
  Pointer<WebrtcVideoEncoderFactoryUnique> native() {
    final result = _native;
    _native = nullptr;
    return result;
  }

  // 明示破棄 API。内部的には `_cleanup()` に集約する。
  void dispose() {
    _cleanup();
  }

  // 生成前に必須シンボルがロードできることを確認する。
  //
  // ランタイムで不足している場合は、利用途中ではなく初期化時点で
  // 失敗させて原因を分かりやすくする。
  void _ensureRequiredSymbols() {
    // 必須シンボルを初期化時に解決し、欠落時は即時失敗させる。
    _lib.videoEncoderFactoryNew;
    _lib.videoEncoderFactoryGetSupportedFormats;
    _lib.videoEncoderFactoryUniqueGet;
    _lib.videoEncoderFactoryUniqueDelete;
    _lib.simulcastEncoderAdapterNew;
    _lib.simulcastEncoderAdapterUniqueGet;
    _lib.simulcastEncoderAdapterUniqueDelete;
    _lib.simulcastEncoderAdapterCastToVideoEncoder;
  }

  // C callback からサポート format 一覧を元 factory へ委譲する。
  //
  // `userData` から関数ポインタを取り出し、Dart object を介さず
  // native レベルで完結させる。
  static Pointer<WebrtcSdpVideoFormatVector> _onGetSupportedFormats(
    Pointer<Void> userData,
  ) {
    final ud = userData.cast<_UserData>();
    final inner = ud.ref.inner;
    final uniqueGet = ud.ref.videoEncoderFactoryUniqueGet
        .asFunction<VideoEncoderFactoryUniqueGetDartFn>();
    final getSupportedFormats = ud.ref.videoEncoderFactoryGetSupportedFormats
        .asFunction<VideoEncoderFactoryGetSupportedFormatsDartFn>();

    final innerRaw = uniqueGet(inner);
    if (innerRaw == nullptr) {
      return nullptr;
    }
    return getSupportedFormats(innerRaw);
  }

  // C callback から `SimulcastEncoderAdapter` を生成して返す。
  //
  // 元 factory の raw pointer を取り出し、その上に simulcast adapter を
  // 構築して `VideoEncoder` として見えるポインタに変換する。
  static Pointer<WebrtcVideoEncoderUnique> _onCreate(
    Pointer<WebrtcEnvironment> env,
    Pointer<WebrtcSdpVideoFormat> format,
    Pointer<Void> userData,
  ) {
    final ud = userData.cast<_UserData>();
    final inner = ud.ref.inner;
    final uniqueGet = ud.ref.videoEncoderFactoryUniqueGet
        .asFunction<VideoEncoderFactoryUniqueGetDartFn>();
    final simulcastNew = ud.ref.simulcastEncoderAdapterNew
        .asFunction<SimulcastEncoderAdapterNewDartFn>();
    final simulcastUniqueGet = ud.ref.simulcastEncoderAdapterUniqueGet
        .asFunction<SimulcastEncoderAdapterUniqueGetDartFn>();
    final simulcastUniqueDelete = ud.ref.simulcastEncoderAdapterUniqueDelete
        .asFunction<SimulcastEncoderAdapterUniqueDeleteDartFn>();
    final castToVideoEncoder = ud.ref.simulcastEncoderAdapterCastToVideoEncoder
        .asFunction<SimulcastEncoderAdapterCastToVideoEncoderDartFn>();

    final innerRaw = uniqueGet(inner);
    if (innerRaw == nullptr) {
      return nullptr;
    }

    final simulcast = simulcastNew(env, innerRaw, nullptr, format);
    if (simulcast == nullptr) {
      return nullptr;
    }

    final simulcastRaw = simulcastUniqueGet(simulcast);
    if (simulcastRaw == nullptr) {
      simulcastUniqueDelete(simulcast);
      return nullptr;
    }

    final encoderRaw = castToVideoEncoder(simulcastRaw);
    if (encoderRaw == nullptr) {
      simulcastUniqueDelete(simulcast);
      return nullptr;
    }

    // `encoderRaw` は `simulcastRaw` と同じ `SimulcastEncoderAdapter` 本体を
    // `VideoEncoder*` として見せるだけで、この時点では所有権を切り離せない。
    // ここで `simulcastUniqueDelete(simulcast)` を呼ぶと wrapper ごと本体まで
    // 破棄され、返却後の `encoderRaw` がダングリングポインタになる。
    // `libwebrtc-c` に `unique_ptr::release()` 相当 API がない現状では、
    // UAF / 二重解放を避けるため `SimulcastEncoderAdapter` 本体の寿命を優先し、
    // `unique_ptr` ラッパー構造体だけの微小リークを意図的に許容する。
    return encoderRaw.cast<WebrtcVideoEncoderUnique>();
  }

  // native 側 factory 破棄時に呼ばれる空のコールバック。
  //
  // `_cleanup()` が `_inner` / `_userData` の解放責務を一元管理するため、
  // ここでは何も行わない。native 側が `onDestroy` を同期的に呼ぶ場合も
  // 非同期に呼ぶ場合も、`_cleanup()` 完了後に呼ばれても安全。
  @visibleForTesting
  static void onNativeDestroy(Pointer<Void> userData) {}

  // 確保済み callback / 構造体 / factory を安全な順序で解放する。
  //
  // `videoEncoderFactoryUniqueDelete(_native)` の過程で `_onNativeDestroy()` が
  // 呼ばれる可能性があるが、`_onNativeDestroy` は空関数のため安全。
  // 二重解放を避ける目的で `_cleaned` を先に立てる。
  void _cleanup() {
    if (_cleaned) {
      return;
    }
    _cleaned = true;

    // `videoEncoderFactoryUniqueDelete` の過程で native 側が callback を
    // 呼ぶ場合に備え、NativeCallable と _cbs が有効なうちに _native を解放する。
    // native() 呼び出し済み (= 依存へ所有権移譲済み) の場合は _native が nullptr のため
    // ガードによりスキップされ、二重解放を防ぐ。
    if (_native != nullptr) {
      _lib.videoEncoderFactoryUniqueDelete(_native);
    }
    _native = nullptr;

    final onDestroy = _onDestroy;
    _onDestroy = null;
    onDestroy?.close();

    final create = _create;
    _create = null;
    create?.close();

    final getSupportedFormats = _getSupportedFormats;
    _getSupportedFormats = null;
    getSupportedFormats?.close();

    if (_cbs != nullptr) {
      calloc.free(_cbs);
      _cbs = nullptr;
    }

    if (_inner != nullptr) {
      _lib.videoEncoderFactoryUniqueDelete(_inner);
    }

    if (_userData != nullptr) {
      calloc.free(_userData);
    }
    _userData = nullptr;
  }
}
