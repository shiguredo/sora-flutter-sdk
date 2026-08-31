// ignore_for_file: public_member_api_docs
/// local メディアストリームと track の型定義を提供するモジュールです。
///
/// `LocalMediaStream` による audio / video track の管理と
/// native `MediaStreamInterface` のラップを担当します。
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart';

import 'ffi/bindings.dart';
import 'ffi/memory.dart';
import 'ffi/webrtc_client.dart';
import 'media/sora_media_device_platform.dart' as media_device_platform;
import 'sora_media_stream_track_base.dart';

/// local の `MediaStream` を表すラッパーです。
///
/// native 側の `MediaStreamInterface` を保持し、audio / video track の
/// 列挙や集合更新を行います。
class LocalMediaStream implements MediaStream {
  @internal
  LocalMediaStream.fromNative(this._streamRef);

  final Pointer<WebrtcMediaStreamInterfaceRefcounted> _streamRef;

  bool _disposed = false;
  LocalAudioTrack? _audioTrackCache;
  LocalVideoTrack? _videoTrackCache;
  _LocalVideoTrackMetadata? _videoTrackMetadata;

  Pointer<WebrtcMediaStreamInterface> get _nativeStream =>
      WebrtcClient.sharedLib.mediaStreamRefcountedGet(_streamRef);

  /// MediaStream の ID を返す。
  @override
  String get id {
    ensureNotDisposed();
    return stdStringToDart(
      WebrtcClient.sharedLib,
      WebrtcClient.sharedLib.mediaStreamId(_nativeStream),
    );
  }

  /// 現在の全 track を audio -> video の順で返す。
  ///
  // W3C Media Capture and Streams の `MediaStream.getTracks()` と
  // 名前をそろえるため、`get` をあえて残している。
  @override
  List<LocalMediaStreamTrack> getTracks() {
    ensureNotDisposed();
    return <LocalMediaStreamTrack>[...getAudioTracks(), ...getVideoTracks()];
  }

  /// 現在の audio track 一覧を snapshot として返す。
  ///
  // W3C Media Capture and Streams の `MediaStream.getAudioTracks()` と
  // 名前をそろえるため、`get` をあえて残している。
  List<LocalAudioTrack> getAudioTracks() {
    ensureNotDisposed();
    final lib = WebrtcClient.sharedLib;
    final vector = lib.mediaStreamGetAudioTracks(_nativeStream);
    try {
      final size = lib.audioTrackRefcountedVectorSize(vector);
      if (size > 1) {
        throw StateError('Multiple audio tracks are not supported.');
      }
      if (size == 0) {
        _audioTrackCache = null;
        return const <LocalAudioTrack>[];
      }

      // vectorGet は新規 owned ref を返すため、cast とは別に確実に release する。
      final vectorTrackRef = lib.audioTrackRefcountedVectorGet(vector, 0);
      final ownedMediaTrackRef = lib.audioTrackCastToMediaStreamTrack(
        vectorTrackRef,
      );
      // vectorGet の owned ref を release する。
      // cast が返す新規 owned ref とは別の参照であり、両方の解放を漏らさない。
      lib.audioTrackRelease(lib.audioTrackRefcountedGet(vectorTrackRef));
      return <LocalAudioTrack>[_reuseOrCreateAudioTrack(ownedMediaTrackRef)];
    } finally {
      lib.audioTrackRefcountedVectorDelete(vector);
    }
  }

  /// 現在の video track 一覧を snapshot として返す。
  ///
  // W3C Media Capture and Streams の `MediaStream.getVideoTracks()` と
  // 名前をそろえるため、`get` をあえて残している。
  List<LocalVideoTrack> getVideoTracks() {
    ensureNotDisposed();
    final lib = WebrtcClient.sharedLib;
    final vector = lib.mediaStreamGetVideoTracks(_nativeStream);
    try {
      final size = lib.videoTrackRefcountedVectorSize(vector);
      if (size > 1) {
        throw StateError('Multiple video tracks are not supported.');
      }
      if (size == 0) {
        _videoTrackCache = null;
        _videoTrackMetadata = null;
        return const <LocalVideoTrack>[];
      }

      // vectorGet は新規 owned ref を返すため、cast とは別に確実に release する。
      final vectorTrackRef = lib.videoTrackRefcountedVectorGet(vector, 0);
      final ownedMediaTrackRef = lib.videoTrackCastToMediaStreamTrack(
        vectorTrackRef,
      );
      // vectorGet の owned ref を release する。
      // cast が返す新規 owned ref とは別の参照であり、両方の解放を漏らさない。
      lib.videoTrackRelease(lib.videoTrackRefcountedGet(vectorTrackRef));
      return <LocalVideoTrack>[_reuseOrCreateVideoTrack(ownedMediaTrackRef)];
    } finally {
      lib.videoTrackRefcountedVectorDelete(vector);
    }
  }

  /// track を MediaStream の集合へ追加する。
  ///
  /// native の `MediaStreamInterface` に track を追加するのみで、
  /// `PeerConnection` への `RtpSender` 作成は行わない。
  /// `RtpSender` の管理は `SoraConnection` 側の責務。
  void addTrack(LocalMediaStreamTrack track) {
    ensureNotDisposed();
    track.ensureNotDisposed();

    final lib = WebrtcClient.sharedLib;
    if (track is LocalAudioTrack) {
      // 音声トラック
      final currentTracks = getAudioTracks();
      if (currentTracks.isNotEmpty) {
        if (currentTracks.first.nativeTrackAddress ==
            track.nativeTrackAddress) {
          return;
        }
        throw StateError('Multiple audio tracks are not supported.');
      }
      final result = track.withNativeTrackRefcounted((
        Pointer<WebrtcAudioTrackInterfaceRefcounted> trackRef,
      ) {
        return lib.mediaStreamAddTrackWithAudioTrack(_nativeStream, trackRef);
      });
      if (result == 0) {
        throw StateError('Failed to add audio track to MediaStream.');
      }
      _audioTrackCache = track;
      return;
    }

    if (track is LocalVideoTrack) {
      // 映像トラック
      final currentTracks = getVideoTracks();
      if (currentTracks.isNotEmpty) {
        if (currentTracks.first.nativeTrackAddress ==
            track.nativeTrackAddress) {
          return;
        }
        throw StateError('Multiple video tracks are not supported.');
      }
      final result = track.withNativeTrackRefcounted((
        Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef,
      ) {
        return lib.mediaStreamAddTrackWithVideoTrack(_nativeStream, trackRef);
      });
      if (result == 0) {
        throw StateError('Failed to add video track to MediaStream.');
      }
      _videoTrackCache = track;
      _videoTrackMetadata = _LocalVideoTrackMetadata.fromTrack(track);
      return;
    }

    // 規定されていないトラック種別のため原則来ない
    throw StateError('Unsupported LocalMediaStreamTrack kind.');
  }

  /// track を MediaStream の集合から削除する。
  ///
  /// native の `MediaStreamInterface` から track を削除するのみで、
  /// `PeerConnection` の `RtpSender` 破棄は行わない。
  /// `RtpSender` の管理は `SoraConnection` 側の責務。
  void removeTrack(LocalMediaStreamTrack track) {
    ensureNotDisposed();
    track.ensureNotDisposed();

    final lib = WebrtcClient.sharedLib;
    if (track is LocalAudioTrack) {
      // 音声トラック
      final result = track.withNativeTrackRefcounted((
        Pointer<WebrtcAudioTrackInterfaceRefcounted> trackRef,
      ) {
        return lib.mediaStreamRemoveTrackWithAudioTrack(
          _nativeStream,
          trackRef,
        );
      });
      if (result == 0) {
        throw StateError('Failed to remove audio track from MediaStream.');
      }
      if (_audioTrackCache?.nativeTrackAddress == track.nativeTrackAddress) {
        _audioTrackCache = null;
      }
      return;
    }

    if (track is LocalVideoTrack) {
      // 映像トラック
      final result = track.withNativeTrackRefcounted((
        Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef,
      ) {
        return lib.mediaStreamRemoveTrackWithVideoTrack(
          _nativeStream,
          trackRef,
        );
      });
      if (result == 0) {
        throw StateError('Failed to remove video track from MediaStream.');
      }
      if (_videoTrackCache?.nativeTrackAddress == track.nativeTrackAddress) {
        _videoTrackCache = null;
        _videoTrackMetadata = null;
      }
      return;
    }

    // 規定されていないトラック種別のため原則来ない
    throw StateError('Unsupported LocalMediaStreamTrack kind.');
  }

  /// MediaStream 自身の参照を解放する。
  ///
  /// 含まれる track は自動で dispose しない。
  /// 通常は `await stream.dispose()` を推奨する。
  /// `State.dispose()` のように await できない文脈では
  /// `unawaited(stream.dispose())` のように明示的に扱う。
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    WebrtcClient.sharedLib.mediaStreamRelease(_nativeStream);
  }

  /// 現在の audio track を 1 本だけ取得する。
  LocalAudioTrack? get currentAudioTrackOrNull {
    ensureNotDisposed();
    final audioTracks = getAudioTracks();
    if (audioTracks.isEmpty) {
      return null;
    }
    return audioTracks.first;
  }

  /// 現在の video track を 1 本だけ取得する。
  LocalVideoTrack? get currentVideoTrackOrNull {
    ensureNotDisposed();
    final videoTracks = getVideoTracks();
    if (videoTracks.isEmpty) {
      return null;
    }
    return videoTracks.first;
  }

  /// 列挙結果から audio track ラッパーを再利用または再生成する。
  LocalAudioTrack _reuseOrCreateAudioTrack(
    Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> ownedMediaTrackRef,
  ) {
    final lib = WebrtcClient.sharedLib;
    final nativeTrack = lib.mediaStreamTrackRefcountedGet(ownedMediaTrackRef);
    final nativeAddress = nativeTrack.address;
    final cachedTrack = _audioTrackCache;
    if (cachedTrack != null &&
        !cachedTrack.isDisposed &&
        cachedTrack.nativeTrackAddress == nativeAddress) {
      // cache-hit のみ release する。ownedMediaTrackRef は cast が新規生成した
      // owned ref であり、再利用する wrapper では不要になるため破棄する。
      lib.mediaStreamTrackRelease(nativeTrack);
      return cachedTrack;
    }

    // cache-miss は owned ref を LocalAudioTrack へ transfer するため
    // release しない。
    final createdTrack = LocalAudioTrack.fromNativeMediaTrack(
      ownedMediaTrackRef,
    );
    _audioTrackCache = createdTrack;
    return createdTrack;
  }

  /// 列挙結果から video track ラッパーを再利用または再生成する。
  LocalVideoTrack _reuseOrCreateVideoTrack(
    Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> ownedMediaTrackRef,
  ) {
    final lib = WebrtcClient.sharedLib;
    final nativeTrack = lib.mediaStreamTrackRefcountedGet(ownedMediaTrackRef);
    final nativeAddress = nativeTrack.address;
    final cachedTrack = _videoTrackCache;
    if (cachedTrack != null &&
        !cachedTrack.isDisposed &&
        cachedTrack.nativeTrackAddress == nativeAddress) {
      // cache-hit のみ release する。ownedMediaTrackRef は cast が新規生成した
      // owned ref であり、再利用する wrapper では不要になるため破棄する。
      lib.mediaStreamTrackRelease(nativeTrack);
      return cachedTrack;
    }

    // cache-miss は owned ref を LocalVideoTrack へ transfer するため
    // release しない。
    final createdTrack = LocalVideoTrack.fromNativeMediaTrack(
      ownedMediaTrackRef,
      captureType:
          _videoTrackMetadata?.captureType ?? VideoTrackCaptureType.external,
      captureSettings: _videoTrackMetadata?.captureSettings,
      videoSourceRef: _videoTrackMetadata?.videoSourceRef,
      clientId: _videoTrackMetadata?.clientId,
    );
    _videoTrackCache = createdTrack;
    return createdTrack;
  }

  /// dispose 済み利用を防ぐ。
  void ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Disposed LocalMediaStream cannot be used.');
    }
  }
}

/// `LocalMediaStream` に属する track の共通基底クラスです。
///
/// ローカルトラックはアプリが生成・操作・破棄する責務を持ちます。
abstract class LocalMediaStreamTrack implements MediaStreamTrack {
  LocalMediaStreamTrack._(this._mediaTrackRef);

  final Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> _mediaTrackRef;

  bool _disposed = false;
  bool _nativeTrackReleased = false;

  Pointer<WebrtcMediaStreamTrackInterface> get _nativeTrack =>
      WebrtcClient.sharedLib.mediaStreamTrackRefcountedGet(_mediaTrackRef);

  int get nativeTrackAddress => _nativeTrack.address;

  /// track の ID を返す。
  @override
  String get trackId {
    ensureNotDisposed();
    return stdStringToDart(
      WebrtcClient.sharedLib,
      WebrtcClient.sharedLib.mediaStreamTrackId(_nativeTrack),
    );
  }

  /// track の kind を返す。
  @override
  String get kind {
    ensureNotDisposed();
    return stdStringToDart(
      WebrtcClient.sharedLib,
      WebrtcClient.sharedLib.mediaStreamTrackKind(_nativeTrack),
    );
  }

  /// track の enabled 状態を返す。
  bool get enabled {
    ensureNotDisposed();
    return WebrtcClient.sharedLib.mediaStreamTrackEnabled(_nativeTrack) != 0;
  }

  /// track の enabled 状態を更新する。
  set enabled(bool value) {
    ensureNotDisposed();
    WebrtcClient.sharedLib.mediaStreamTrackSetEnabled(
      _nativeTrack,
      value ? 1 : 0,
    );
  }

  /// track 自身の参照を解放する。
  ///
  /// 通常は `await track.dispose()` を推奨する。
  /// `State.dispose()` のように await できない文脈では
  /// `unawaited(track.dispose())` のように明示的に扱う。
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _releaseNativeTrack();
  }

  /// dispose 済みかどうかを返します。
  bool get isDisposed => _disposed;

  /// dispose 済み利用を防ぐ。
  void ensureNotDisposed() {
    if (_disposed) {
      throw StateError('Disposed LocalMediaStreamTrack cannot be used.');
    }
  }

  /// native track の参照を一度だけ解放する。
  ///
  /// `LocalVideoTrack.dispose()` は非同期後始末中の利用を防ぐために
  /// 先に `_disposed` を立てるので、基底の `dispose()` とは独立して呼び出せる
  /// release 処理として分離している。
  void _releaseNativeTrack() {
    if (_nativeTrackReleased) {
      return;
    }
    _nativeTrackReleased = true;
    WebrtcClient.sharedLib.mediaStreamTrackRelease(_nativeTrack);
  }
}

/// local の audio track を表すラッパーです。
class LocalAudioTrack extends LocalMediaStreamTrack {
  @internal
  LocalAudioTrack.fromNativeMediaTrack(super.mediaTrackRef) : super._();

  /// AudioTrack の native refcounted を一時的に取得して処理する。
  @internal
  T withNativeTrackRefcounted<T>(
    T Function(Pointer<WebrtcAudioTrackInterfaceRefcounted> trackRef) action,
  ) {
    ensureNotDisposed();
    final lib = WebrtcClient.sharedLib;
    final audioTrackRef = lib.mediaStreamTrackCastToAudioTrack(_mediaTrackRef);
    try {
      return action(audioTrackRef);
    } finally {
      lib.audioTrackRelease(lib.audioTrackRefcountedGet(audioTrackRef));
    }
  }

  /// caller 側で明示解放するための owned refcounted を返す。
  @internal
  Pointer<WebrtcAudioTrackInterfaceRefcounted> retainNativeTrackRefcounted() {
    ensureNotDisposed();
    return WebrtcClient.sharedLib.mediaStreamTrackCastToAudioTrack(
      _mediaTrackRef,
    );
  }
}

/// 映像トラックのキャプチャ種類
///
/// 画面キャプチャは公開 API から撤回されたため、この enum は内部実装専用として
/// `@internal` を付与する。カメラ / 外部入力の判別にも使われるが、外部から
/// 参照する必要はない。
@internal
enum VideoTrackCaptureType {
  /// カメラデバイス
  camera,

  /// iOS の ReplayKit によるアプリ内画面キャプチャ
  screen,

  /// 外部入力(ダミー映像、スクリーンキャスト、外付けカメラ等)
  external,
}

/// external video track へ投入する I420 フレームです。
///
/// `yPlane` / `uPlane` / `vPlane` は各 plane の生データを保持し、
/// stride はそれぞれの 1 行あたりバイト数を表します。
class ExternalVideoFrame {
  const ExternalVideoFrame({
    required this.width,
    required this.height,
    required this.yPlane,
    required this.uPlane,
    required this.vPlane,
    required this.yStride,
    required this.uStride,
    required this.vStride,
    this.rotation = 0,
    this.timestampUs,
  });

  /// 映像の幅 (ピクセル)。
  final int width;

  /// 映像の高さ (ピクセル)。
  final int height;

  /// Y プレーンの生データ。
  final Uint8List yPlane;

  /// U プレーンの生データ。
  final Uint8List uPlane;

  /// V プレーンの生データ。
  final Uint8List vPlane;

  /// Y プレーンの 1 行あたりバイト数。
  final int yStride;

  /// U プレーンの 1 行あたりバイト数。
  final int uStride;

  /// V プレーンの 1 行あたりバイト数。
  final int vStride;

  /// フレームの回転角度 (0, 90, 180, 270)。
  final int rotation;

  /// フレームのタイムスタンプ (マイクロ秒)。null の場合は現在時刻を使用する。
  final int? timestampUs;
}

/// local の video track を表すラッパーです。
class LocalVideoTrack extends LocalMediaStreamTrack {
  @internal
  LocalVideoTrack.fromNativeMediaTrack(
    super.mediaTrackRef, {
    required VideoTrackCaptureType captureType,
    VideoCaptureSettings? captureSettings,
    Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>? videoSourceRef,
    int? clientId,
  }) : _captureType = captureType,
       _captureSettings = captureSettings,
       _videoSourceRef = videoSourceRef,
       _clientId = clientId,
       super._();

  final VideoTrackCaptureType _captureType;
  final VideoCaptureSettings? _captureSettings;
  final Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>? _videoSourceRef;
  final int? _clientId;
  Future<int>? _textureIdFuture;
  Future<void>? _disposeFuture;
  final Set<int> _connectionOwners = <int>{};

  /// トラックのキャプチャ種類。
  ///
  /// 画面キャプチャの公開 API 撤回に伴い、この getter も内部実装専用とした。
  @internal
  VideoTrackCaptureType get captureType => _captureType;

  /// 接続中の sender がこの track を参照していることを記録します。
  @internal
  void attachToConnection(int clientId) {
    ensureNotDisposed();
    _connectionOwners.add(clientId);
  }

  /// 接続中の sender からこの track が外れたことを記録します。
  @internal
  void detachFromConnection(int clientId) {
    _connectionOwners.remove(clientId);
  }

  /// 指定した接続以外にも sender が残っているかを返します。
  @internal
  bool hasOtherConnectionOwner(int clientId) {
    return _connectionOwners.any((owner) => owner != clientId);
  }

  /// ローカルプレビュー用の Flutter Texture ID を返す。
  ///
  /// camera track の場合は初回アクセス時に platform 側で texture を生成し、
  /// キャプチャ開始まで待機する。screen track の場合は texture だけを確保し、
  /// Sora 接続へ設定されるまで ReplayKit を開始しない。
  Future<int> get textureId {
    ensureNotDisposed();
    final existingFuture = _textureIdFuture;
    if (existingFuture != null) {
      return existingFuture;
    }
    final future = _ensureTextureId();
    _textureIdFuture = future;
    return future;
  }

  /// platform 側へ渡す video source のポインタ値を返す。
  int get _videoSourceAddress {
    if (_videoSourceRef == null) {
      return 0;
    }
    return _videoSourceRef.address;
  }

  @internal
  int get videoSourceAddress => _videoSourceAddress;

  /// SDK 管理映像トラック用のプレビューテクスチャを確保し、texture ID を返す。
  ///
  /// プラットフォーム側で video source・デバイス ID・解像度・フレームレートを
  /// 指定してテクスチャを生成する。外部映像トラックの場合はエラー。
  /// 失敗時はキャッシュした Future を破棄し、次回の `textureId` 取得時に再試行させる。
  Future<int> _ensureTextureId() async {
    try {
      if (_captureType != VideoTrackCaptureType.camera &&
          _captureType != VideoTrackCaptureType.screen) {
        throw StateError(
          'textureId is not available for external video track.',
        );
      }
      final textureId = await media_device_platform
          .ensureLocalVideoTrackTexture(
            videoSourcePtr: _videoSourceAddress,
            clientId: _clientId ?? 0,
            captureType: _captureType.name,
            videoDeviceId: _captureSettings?.deviceId,
            videoWidth: _captureSettings?.width,
            videoHeight: _captureSettings?.height,
            videoFrameRate: _captureSettings?.frameRate,
          );
      // iOS では Texture 確保とキャプチャ開始を分離している。
      // カメラの接続前プレビューは既存動作を維持するため、ここで開始する。
      if (Platform.isIOS && _captureType == VideoTrackCaptureType.camera) {
        await media_device_platform.startLocalVideoCapture(
          videoSourcePtr: _videoSourceAddress,
          captureType: _captureType.name,
          clientId: null,
          videoDeviceId: _captureSettings?.deviceId,
          videoWidth: _captureSettings?.width,
          videoHeight: _captureSettings?.height,
          videoFrameRate: _captureSettings?.frameRate,
        );
      }
      return textureId;
    } catch (_) {
      _textureIdFuture = null;
      rethrow;
    }
  }

  /// 接続に紐付けて SDK 管理の映像キャプチャを開始する。
  @internal
  Future<int> startCaptureForConnection(int clientId) async {
    ensureNotDisposed();
    if (_captureType == VideoTrackCaptureType.external) {
      throw StateError('External video track has no capture backend.');
    }
    final resolvedTextureId = await textureId;
    if (Platform.isIOS) {
      await media_device_platform.startLocalVideoCapture(
        videoSourcePtr: _videoSourceAddress,
        captureType: _captureType.name,
        clientId: clientId,
        videoDeviceId: _captureSettings?.deviceId,
        videoWidth: _captureSettings?.width,
        videoHeight: _captureSettings?.height,
        videoFrameRate: _captureSettings?.frameRate,
      );
    }
    return resolvedTextureId;
  }

  /// 接続に紐付いた SDK 管理の映像キャプチャを停止する。
  @internal
  Future<void> stopCaptureForConnection(int clientId) async {
    if (_captureType == VideoTrackCaptureType.external || !Platform.isIOS) {
      return;
    }
    await media_device_platform.stopLocalVideoCapture(
      videoSourcePtr: _videoSourceAddress,
      captureType: _captureType.name,
      clientId: clientId,
    );
  }

  /// VideoTrack の native refcounted を一時的に取得して処理する。
  @internal
  T withNativeTrackRefcounted<T>(
    T Function(Pointer<WebrtcVideoTrackInterfaceRefcounted> trackRef) action,
  ) {
    ensureNotDisposed();
    final lib = WebrtcClient.sharedLib;
    final videoTrackRef = lib.mediaStreamTrackCastToVideoTrack(_mediaTrackRef);
    try {
      return action(videoTrackRef);
    } finally {
      lib.videoTrackRelease(lib.videoTrackRefcountedGet(videoTrackRef));
    }
  }

  /// caller 側で明示解放するための owned refcounted を返す。
  @internal
  Pointer<WebrtcVideoTrackInterfaceRefcounted> retainNativeTrackRefcounted() {
    ensureNotDisposed();
    return WebrtcClient.sharedLib.mediaStreamTrackCastToVideoTrack(
      _mediaTrackRef,
    );
  }

  /// external video track へ I420 フレームを投入する。
  void writeFrame(ExternalVideoFrame frame) {
    ensureNotDisposed();
    if (_captureType != VideoTrackCaptureType.external) {
      throw StateError(
        'writeFrame is available only for external video track.',
      );
    }
    final sourceRef = _videoSourceRef;
    if (sourceRef == null) {
      throw StateError('External video source is not available.');
    }

    validateExternalVideoFrame(frame);

    final lib = WebrtcClient.sharedLib;
    final source = lib.adaptedVideoTrackSourceRefcountedGet(sourceRef);
    final adaptedWidthPtr = calloc<Int32>();
    final adaptedHeightPtr = calloc<Int32>();
    final cropWidthPtr = calloc<Int32>();
    final cropHeightPtr = calloc<Int32>();
    final cropXPtr = calloc<Int32>();
    final cropYPtr = calloc<Int32>();

    Pointer<WebrtcI420BufferRefcounted>? sourceBufferRef;
    Pointer<WebrtcI420Buffer>? sourceBuffer;
    Pointer<WebrtcI420BufferRefcounted>? adaptedBufferRef;
    Pointer<WebrtcI420Buffer>? adaptedBuffer;
    Pointer<SoraVideoFrameUnique>? videoFrame;

    try {
      final timestampUs =
          frame.timestampUs ?? DateTime.now().microsecondsSinceEpoch;
      // AdaptFrame で適合後の解像度と切り抜き領域を計算する。
      // 0 が返った場合はドロップ（後続フレームが処理中など）。
      final adapted = lib.adaptedVideoTrackSourceAdaptFrame(
        source,
        frame.width,
        frame.height,
        timestampUs,
        adaptedWidthPtr,
        adaptedHeightPtr,
        cropWidthPtr,
        cropHeightPtr,
        cropXPtr,
        cropYPtr,
      );
      if (adapted == 0) {
        return;
      }

      // 入力フレームから I420 バッファを生成し、Y / U / V プレーンをコピーする。
      sourceBufferRef = lib.i420BufferCreate(frame.width, frame.height);
      if (sourceBufferRef == nullptr) {
        throw StateError('Failed to create source I420 buffer.');
      }
      sourceBuffer = lib.i420BufferRefcountedGet(sourceBufferRef);
      _copyPlane(
        source: frame.yPlane,
        requiredWidth: frame.width,
        requiredHeight: frame.height,
        sourceStride: frame.yStride,
        destination: lib.i420BufferMutableDataY(sourceBuffer),
        destinationStride: lib.i420BufferStrideY(sourceBuffer),
      );
      final chromaWidth = (frame.width + 1) ~/ 2;
      final chromaHeight = (frame.height + 1) ~/ 2;
      _copyPlane(
        source: frame.uPlane,
        requiredWidth: chromaWidth,
        requiredHeight: chromaHeight,
        sourceStride: frame.uStride,
        destination: lib.i420BufferMutableDataU(sourceBuffer),
        destinationStride: lib.i420BufferStrideU(sourceBuffer),
      );
      _copyPlane(
        source: frame.vPlane,
        requiredWidth: chromaWidth,
        requiredHeight: chromaHeight,
        sourceStride: frame.vStride,
        destination: lib.i420BufferMutableDataV(sourceBuffer),
        destinationStride: lib.i420BufferStrideV(sourceBuffer),
      );

      // AdaptFrame の結果と入力サイズが異なる場合は、スケーリングした
      // バッファを別途生成する。一致する場合は入力バッファをそのまま使う。
      final adaptedWidth = adaptedWidthPtr.value;
      final adaptedHeight = adaptedHeightPtr.value;
      adaptedBufferRef = sourceBufferRef;
      adaptedBuffer = sourceBuffer;
      if (adaptedWidth != frame.width || adaptedHeight != frame.height) {
        adaptedBufferRef = lib.i420BufferCreate(adaptedWidth, adaptedHeight);
        if (adaptedBufferRef == nullptr) {
          throw StateError('Failed to create adapted I420 buffer.');
        }
        adaptedBuffer = lib.i420BufferRefcountedGet(adaptedBufferRef);
        lib.i420BufferScaleFrom(adaptedBuffer, sourceBuffer);
      }

      // 適合済みバッファから SoraVideoFrame を構築し、VideoSource へ配送する。
      // `soraVideoFrameCreate()` は I420 バッファの所有権を move しない。
      // `VideoFrame` 構築後も呼び出し側が `i420BufferRelease()` で解放する責務を持つ。
      videoFrame = lib.soraVideoFrameCreate(
        adaptedBufferRef,
        frame.rotation,
        timestampUs,
        0,
      );
      if (videoFrame == nullptr) {
        throw StateError('Failed to create video frame.');
      }

      lib.adaptedVideoTrackSourceOnFrame(
        source,
        lib.soraVideoFrameUniqueGet(videoFrame),
      );
    } finally {
      if (videoFrame != null && videoFrame != nullptr) {
        lib.soraVideoFrameUniqueDelete(videoFrame);
      }
      if (adaptedBuffer != null && adaptedBuffer != nullptr) {
        lib.i420BufferRelease(adaptedBuffer);
      }
      if (sourceBuffer != null &&
          sourceBuffer != nullptr &&
          sourceBuffer.address != adaptedBuffer?.address) {
        lib.i420BufferRelease(sourceBuffer);
      }
      calloc.free(adaptedWidthPtr);
      calloc.free(adaptedHeightPtr);
      calloc.free(cropWidthPtr);
      calloc.free(cropHeightPtr);
      calloc.free(cropXPtr);
      calloc.free(cropYPtr);
    }
  }

  /// VideoTrack に紐づく source 参照も合わせて解放する。
  ///
  /// SDK 管理 track では platform preview texture の解放も含むため非同期。
  /// 通常は `await track.dispose()` を推奨する。
  ///
  /// 接続にアタッチ中の track を dispose すると `StateError` を返す
  /// Future.error として完了する。以前の実装は同期 throw していたが、
  /// 基底 `LocalMediaStreamTrack.dispose()` の非同期契約と揃えるため
  /// Future.error に統一した。sync `try` / `catch` で捕捉していた
  /// コードは `await` または `.catchError` に置き換える必要がある。
  @override
  Future<void> dispose() async {
    final existingFuture = _disposeFuture;
    if (existingFuture != null) {
      return existingFuture;
    }
    if (_disposed) {
      return;
    }
    if (_connectionOwners.isNotEmpty) {
      throw StateError(
        'Cannot dispose a video track while it is attached to a connection.',
      );
    }
    _disposed = true;
    final future = _disposeInternal();
    _disposeFuture = future;
    return future;
  }

  /// platform 側の Texture と映像ソースを解放する。
  Future<void> _disposeInternal() async {
    // ensure 中の textureId Future があれば完了を待つ。
    // 待たずに native release すると、platform 側が ensure 中の
    // videoSourcePtr で解放済み source を参照し UAF になる。
    final textureFuture = _textureIdFuture;
    if (textureFuture != null) {
      try {
        await textureFuture;
      } catch (_) {
        // ensure が失敗した場合も無視して先に進む。
      }
    }
    if (_captureType == VideoTrackCaptureType.camera &&
        _videoSourceAddress != 0) {
      // camera track の preview 解放は従来どおりベストエフォートとし、
      // platform channel の失敗で native track の解放を妨げない。
      try {
        await media_device_platform.disposeLocalVideoTrackTexture(
          videoSourcePtr: _videoSourceAddress,
        );
      } catch (_) {
        // エンジン破棄後などの channel 消失時も native source を解放する。
      }
    } else if (_captureType == VideoTrackCaptureType.screen &&
        _videoSourceAddress != 0) {
      try {
        await media_device_platform.disposeLocalVideoTrackTexture(
          videoSourcePtr: _videoSourceAddress,
        );
      } catch (_) {
        // platform 側が停止できなかった場合は native source を解放せず、
        // 次回の dispose() で停止を再試行できる状態へ戻す。
        _disposed = false;
        _disposeFuture = null;
        rethrow;
      }
    }
    _releaseNativeTrack();
    if (_videoSourceRef != null) {
      WebrtcClient.sharedLib.adaptedVideoTrackSourceRelease(
        WebrtcClient.sharedLib.adaptedVideoTrackSourceRefcountedGet(
          _videoSourceRef,
        ),
      );
    }
  }

  /// 1 プレーン (Y / U / V) を Dart 側バッファから native I420 バッファへ行単位でコピーする。
  ///
  /// source stride と destination stride が異なる場合でも、
  /// 各行の `requiredWidth` 分だけを正しく転送する。
  void _copyPlane({
    required Uint8List source,
    required int requiredWidth,
    required int requiredHeight,
    required int sourceStride,
    required Pointer<Uint8> destination,
    required int destinationStride,
  }) {
    final destinationBytes = destination.asTypedList(
      destinationStride * requiredHeight,
    );
    copyI420Plane(
      source: source,
      requiredWidth: requiredWidth,
      requiredHeight: requiredHeight,
      sourceStride: sourceStride,
      destination: destinationBytes,
      destinationStride: destinationStride,
    );
  }
}

/// external video frame の前提整合性を検証する。
///
/// 幅・高さが正であること、各ストライドが最小幅を満たすこと、
/// 各プレーンバッファ長がストライド×高さを満たすことを確認する。
@internal
void validateExternalVideoFrame(ExternalVideoFrame frame) {
  if (frame.width <= 0 || frame.height <= 0) {
    throw StateError('ExternalVideoFrame width and height must be positive.');
  }
  if (frame.yStride < frame.width) {
    throw StateError('ExternalVideoFrame yStride is too small.');
  }
  final chromaWidth = (frame.width + 1) ~/ 2;
  final chromaHeight = (frame.height + 1) ~/ 2;
  if (frame.uStride < chromaWidth || frame.vStride < chromaWidth) {
    throw StateError('ExternalVideoFrame chroma stride is too small.');
  }
  if (frame.yPlane.length < frame.yStride * frame.height) {
    throw StateError('ExternalVideoFrame yPlane is too short.');
  }
  if (frame.uPlane.length < frame.uStride * chromaHeight) {
    throw StateError('ExternalVideoFrame uPlane is too short.');
  }
  if (frame.vPlane.length < frame.vStride * chromaHeight) {
    throw StateError('ExternalVideoFrame vPlane is too short.');
  }
}

/// [Uint8List] の行単位コピー。
///
/// [_copyPlane] から FFI 依存を除いた純粋なコピー処理。
@internal
void copyI420Plane({
  required Uint8List source,
  required int requiredWidth,
  required int requiredHeight,
  required int sourceStride,
  required Uint8List destination,
  required int destinationStride,
}) {
  for (var row = 0; row < requiredHeight; row++) {
    final sourceStart = row * sourceStride;
    final destinationStart = row * destinationStride;
    destination.setRange(
      destinationStart,
      destinationStart + requiredWidth,
      source,
      sourceStart,
    );
  }
}

/// VideoTrack 作成時のキャプチャ条件を保持する内部モデルです。
@immutable
class VideoCaptureSettings {
  const VideoCaptureSettings({
    required this.deviceId,
    required this.width,
    required this.height,
    required this.frameRate,
  });

  final String? deviceId;
  final int? width;
  final int? height;
  final int? frameRate;
}

/// `LocalVideoTrack` のキャプチャ種別・設定・native source 参照をスナップショットとして保持する内部モデル。
///
/// track から切り離した不変データとして扱い、track の状態変化に左右されない参照を提供する。
class _LocalVideoTrackMetadata {
  const _LocalVideoTrackMetadata({
    required this.captureType,
    required this.captureSettings,
    required this.videoSourceRef,
    required this.clientId,
  });

  factory _LocalVideoTrackMetadata.fromTrack(LocalVideoTrack track) {
    return _LocalVideoTrackMetadata(
      captureType: track._captureType,
      captureSettings: track._captureSettings,
      videoSourceRef: track._videoSourceRef,
      clientId: track._clientId,
    );
  }

  final VideoTrackCaptureType captureType;
  final VideoCaptureSettings? captureSettings;
  final Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>? videoSourceRef;
  final int? clientId;
}
