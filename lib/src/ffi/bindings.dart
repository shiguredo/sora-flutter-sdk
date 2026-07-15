// libwebrtc-c C API の手書き dart:ffi バインディング
//
// jni_onload.c と SoraRtcClient.swift で使用される関数のみを定義する。
// このモジュールでは「薄い関数解決レイヤー」に徹し、所有権・解放順序・
// 高レベルの制御フローは `webrtc_client.dart` など上位レイヤーで扱う。
// ignore_for_file: public_member_api_docs
//
// `webrtc-rs/webrtc` 側の C API に対応する構造体と関数を定義する、
// 低レベル FFI binding 層のため、元の C API 名に合わせて `Cbs` 等の命名を維持している。

import 'dart:ffi';

// ---------------------------------------------------------------------------
// Opaque 型定義
// ---------------------------------------------------------------------------

// `std::string` 本体を指す native 文字列オブジェクト。
final class StdString extends Opaque {}

// `std::unique_ptr<std::string>` 相当の所有ポインタ。
final class StdStringUnique extends Opaque {}

// `std::vector<std::string>` を表すコンテナ。
final class StdStringVector extends Opaque {}

// WebRTC 内部スレッドの raw 実体。
final class WebrtcThread extends Opaque {}

// WebRTC スレッドの unique ownership ハンドル。
final class WebrtcThreadUnique extends Opaque {}

// factory / ADM 生成に使う WebRTC 実行環境オブジェクト。
final class WebrtcEnvironment extends Opaque {}

// `AudioDeviceModule` の refcounted ハンドル。
final class WebrtcAudioDeviceModuleRefcounted extends Opaque {}

// 録音・再生デバイス制御を担う `AudioDeviceModule` 実体。
final class WebrtcAudioDeviceModule extends Opaque {}

// RTC event log factory の unique ownership ハンドル。
final class WebrtcRtcEventLogFactoryUnique extends Opaque {}

// audio encoder factory の refcounted ハンドル。
final class WebrtcAudioEncoderFactoryRefcounted extends Opaque {}

// 音声エンコーダー生成元の raw factory。
final class WebrtcAudioEncoderFactory extends Opaque {}

// audio decoder factory の refcounted ハンドル。
final class WebrtcAudioDecoderFactoryRefcounted extends Opaque {}

// 音声デコーダー生成元の raw factory。
final class WebrtcAudioDecoderFactory extends Opaque {}

// 映像エンコーダー生成元の raw factory。
final class WebrtcVideoEncoderFactory extends Opaque {}

// video encoder factory の unique ownership ハンドル。
final class WebrtcVideoEncoderFactoryUnique extends Opaque {}

// video decoder factory の unique ownership ハンドル。
final class WebrtcVideoDecoderFactoryUnique extends Opaque {}

// 映像デコーダー生成元の raw factory。
final class WebrtcVideoDecoderFactory extends Opaque {}

// 個別の映像エンコーダー実体。
final class WebrtcVideoEncoder extends Opaque {}

// 映像エンコーダーの unique ownership ハンドル。
final class WebrtcVideoEncoderUnique extends Opaque {}

// エンコード対象 codec 情報を持つ `SdpVideoFormat`。
final class WebrtcSdpVideoFormat extends Opaque {}

// `SdpVideoFormat` 一覧を保持する vector。
final class WebrtcSdpVideoFormatVector extends Opaque {}

// simulcast 用に複数 encoder を束ねる adapter 実体。
final class WebrtcSimulcastEncoderAdapter extends Opaque {}

// simulcast encoder adapter の unique ownership ハンドル。
final class WebrtcSimulcastEncoderAdapterUnique extends Opaque {}

// iOS/macOS の ObjC `RTCVideoEncoderFactory` ラッパー。
final class WebrtcObjcRTCVideoEncoderFactory extends Opaque {}

// iOS/macOS の ObjC `RTCVideoDecoderFactory` ラッパー。
final class WebrtcObjcRTCVideoDecoderFactory extends Opaque {}

// JNI の `JNIEnv*`。
final class WebrtcJNIEnv extends Opaque {}

// JNI の `jmethodID`。
final class WebrtcJNIMethodId extends Opaque {}

// audio processing builder の unique ownership ハンドル。
final class WebrtcAudioProcessingBuilderInterfaceUnique extends Opaque {}

// `PeerConnectionFactoryDependencies` の構築途中オブジェクト。
final class WebrtcPeerConnectionFactoryDependencies extends Opaque {}

// `PeerConnectionFactoryInterface` の refcounted ハンドル。
final class WebrtcPeerConnectionFactoryInterfaceRefcounted extends Opaque {}

// `PeerConnectionFactoryInterface` の raw 実体。
final class WebrtcPeerConnectionFactoryInterface extends Opaque {}

// factory 全体へ適用するオプション設定オブジェクト。
final class WebrtcPeerConnectionFactoryInterfaceOptions extends Opaque {}

// `PeerConnection` ごとの `RTCConfiguration`。
final class WebrtcPeerConnectionInterfaceRTCConfiguration extends Opaque {}

// `RTCConfiguration.iceServers` の 1 要素。
final class WebrtcPeerConnectionInterfaceIceServer extends Opaque {}

// ICE server 一覧を保持する vector。
final class WebrtcPeerConnectionInterfaceIceServerVector extends Opaque {}

// observer などを束ねた `PeerConnectionDependencies`。
final class WebrtcPeerConnectionDependencies extends Opaque {}

// `PeerConnectionObserver` の raw 実体。
final class WebrtcPeerConnectionObserver extends Opaque {}

// `PeerConnectionInterface` の refcounted ハンドル。
final class WebrtcPeerConnectionInterfaceRefcounted extends Opaque {}

// `PeerConnectionInterface` の raw 実体。
final class WebrtcPeerConnectionInterface extends Opaque {}

// `CreateOffer` / `CreateAnswer` 用オプション。
final class WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions extends Opaque {}

// WebRTC API が返す `RTCError` 本体。
final class WebrtcRTCError extends Opaque {}

// `RTCError` の unique ownership ハンドル。
final class WebrtcRTCErrorUnique extends Opaque {}

// `SessionDescriptionInterface` の unique ownership ハンドル。
final class WebrtcSessionDescriptionInterfaceUnique extends Opaque {}

// SDP を表す `SessionDescriptionInterface` 本体。
final class WebrtcSessionDescriptionInterface extends Opaque {}

// parse 済み ICE candidate 実体。
final class WebrtcIceCandidate extends Opaque {}

// SDP parse error の unique ownership ハンドル。
final class WebrtcSdpParseErrorUnique extends Opaque {}

// SDP parse failure の詳細を持つ実体。
final class WebrtcSdpParseError extends Opaque {}

// `SetRemoteDescriptionObserverInterface` の refcounted ハンドル。
final class WebrtcSetRemoteDescriptionObserverInterfaceRefcounted
    extends Opaque {}

// `SetLocalDescriptionObserverInterface` の refcounted ハンドル。
final class WebrtcSetLocalDescriptionObserverInterfaceRefcounted
    extends Opaque {}

// `CreateSessionDescriptionObserver` 実体。
final class WebrtcCreateSessionDescriptionObserver extends Opaque {}

// `DataChannelInterface` の refcounted ハンドル。
final class WebrtcDataChannelInterfaceRefcounted extends Opaque {}

// `DataChannelInterface` の raw 実体。
final class WebrtcDataChannelInterface extends Opaque {}

// `DataChannelObserver` の raw 実体。
final class WebrtcDataChannelObserver extends Opaque {}

// `RtpTransceiverInterface` の refcounted ハンドル。
final class WebrtcRtpTransceiverInterfaceRefcounted extends Opaque {}

// `RtpTransceiverInterface` の raw 実体。
final class WebrtcRtpTransceiverInterface extends Opaque {}

// `RtpReceiverInterface` の refcounted ハンドル。
final class WebrtcRtpReceiverInterfaceRefcounted extends Opaque {}

// `RtpReceiverInterface` の raw 実体。
final class WebrtcRtpReceiverInterface extends Opaque {}

// `RtpSenderInterface` の refcounted ハンドル。
final class WebrtcRtpSenderInterfaceRefcounted extends Opaque {}

// `RtpSenderInterface` の raw 実体。
final class WebrtcRtpSenderInterface extends Opaque {}

// `MediaStreamInterface` の refcounted ハンドル。
final class WebrtcMediaStreamInterfaceRefcounted extends Opaque {}

// `MediaStreamInterface` の raw 実体。
final class WebrtcMediaStreamInterface extends Opaque {}

// audio track refcounted ポインタ一覧 vector。
final class WebrtcAudioTrackInterfaceRefcountedVector extends Opaque {}

// video track refcounted ポインタ一覧 vector。
final class WebrtcVideoTrackInterfaceRefcountedVector extends Opaque {}

// `MediaStreamTrackInterface` の refcounted ハンドル。
final class WebrtcMediaStreamTrackInterfaceRefcounted extends Opaque {}

// `MediaStreamTrackInterface` の raw 実体。
final class WebrtcMediaStreamTrackInterface extends Opaque {}

// `VideoTrackInterface` の refcounted ハンドル。
final class WebrtcVideoTrackInterfaceRefcounted extends Opaque {}

// `VideoTrackInterface` の raw 実体。
final class WebrtcVideoTrackInterface extends Opaque {}

// video track source の refcounted ハンドル。
final class WebrtcVideoTrackSourceInterfaceRefcounted extends Opaque {}

// `AudioSourceInterface` の refcounted ハンドル。
final class WebrtcAudioSourceInterfaceRefcounted extends Opaque {}

// `AudioSourceInterface` の raw 実体。
final class WebrtcAudioSourceInterface extends Opaque {}

// `AudioTrackInterface` の refcounted ハンドル。
final class WebrtcAudioTrackInterfaceRefcounted extends Opaque {}

// `AudioTrackInterface` の raw 実体。
final class WebrtcAudioTrackInterface extends Opaque {}

// adapt 済み映像フレーム投入元の refcounted ハンドル。
final class WebrtcAdaptedVideoTrackSourceRefcounted extends Opaque {}

// `AdaptedVideoTrackSource` の raw 実体。
final class WebrtcAdaptedVideoTrackSource extends Opaque {}

// I420 バッファの refcounted ハンドル。
final class WebrtcI420BufferRefcounted extends Opaque {}

// I420 平面データを保持する raw バッファ実体。
final class WebrtcI420Buffer extends Opaque {}

// `VideoFrame` の unique ownership ハンドル。
final class WebrtcVideoFrameUnique extends Opaque {}

// `VideoFrame` の raw 実体。
final class WebrtcVideoFrame extends Opaque {}

// Sora 独自 helper から生成される `VideoFrame` unique ハンドル。
final class SoraVideoFrameUnique extends Opaque {}

// `VideoSinkInterface` の raw 実体。
final class WebrtcVideoSinkInterface extends Opaque {}

// sink 側が要求する解像度・fps 条件を持つ `VideoSinkWants`。
final class WebrtcVideoSinkWants extends Opaque {}

// JNI 呼び出しで使う `jvalue` union。
final class JValue extends Union {
  // object / pointer 系引数スロット。
  external Pointer<Void> l;

  @Uint8()
  // boolean 引数スロット。
  external int z;
}

// RTC stats report の refcounted ハンドル。
final class WebrtcRTCStatsReportRefcounted extends Opaque {}

// `RTCStatsReport` の raw 実体。
final class WebrtcRTCStatsReport extends Opaque {}

// sender / receiver の `RtpParameters`。
final class WebrtcRtpParameters extends Opaque {}

// `RtpParameters.encodings` の 1 要素。
final class WebrtcRtpEncodingParameters extends Opaque {}

// encoding parameters 一覧 vector。
final class WebrtcRtpEncodingParametersVector extends Opaque {}

// C 側で observer と DataChannel callback を橋渡しする Sora 独自 bridge。
final class SoraObserverBridge extends Opaque {}

// ---------------------------------------------------------------------------
// Simulcast 関連関数シグネチャ typedef
// ---------------------------------------------------------------------------

// native callback: サポートする `SdpVideoFormat` 一覧を返す。
typedef VideoEncoderFactoryCbsGetSupportedFormatsNativeFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(Pointer<Void> userData);

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryCbsGetSupportedFormatsDartFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(Pointer<Void> userData);

// native callback: 指定 format 用 encoder を生成する。
typedef VideoEncoderFactoryCbsCreateNativeFn =
    Pointer<WebrtcVideoEncoderUnique> Function(
      Pointer<WebrtcEnvironment> env,
      Pointer<WebrtcSdpVideoFormat> format,
      Pointer<Void> userData,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryCbsCreateDartFn =
    Pointer<WebrtcVideoEncoderUnique> Function(
      Pointer<WebrtcEnvironment> env,
      Pointer<WebrtcSdpVideoFormat> format,
      Pointer<Void> userData,
    );

// native callback: factory 破棄時に userData を片付ける。
typedef VideoEncoderFactoryCbsOnDestroyNativeFn =
    Void Function(Pointer<Void> userData);

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryCbsOnDestroyDartFn =
    void Function(Pointer<Void> userData);

// unique factory から raw factory を取り出す getter。
typedef VideoEncoderFactoryUniqueGetNativeFn =
    Pointer<WebrtcVideoEncoderFactory> Function(
      Pointer<WebrtcVideoEncoderFactoryUnique>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryUniqueGetDartFn =
    Pointer<WebrtcVideoEncoderFactory> Function(
      Pointer<WebrtcVideoEncoderFactoryUnique>,
    );

// unique factory の delete 関数。
typedef VideoEncoderFactoryUniqueDeleteNativeFn =
    Void Function(Pointer<WebrtcVideoEncoderFactoryUnique>);

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryUniqueDeleteDartFn =
    void Function(Pointer<WebrtcVideoEncoderFactoryUnique>);

// callback ベースの custom video encoder factory を生成する。
typedef VideoEncoderFactoryNewNativeFn =
    Pointer<WebrtcVideoEncoderFactoryUnique> Function(
      Pointer<VideoEncoderFactoryCbs>,
      Pointer<Void>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryNewDartFn =
    Pointer<WebrtcVideoEncoderFactoryUnique> Function(
      Pointer<VideoEncoderFactoryCbs>,
      Pointer<Void>,
    );

// raw video encoder factory から対応 format 一覧を取得する。
typedef VideoEncoderFactoryGetSupportedFormatsNativeFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(
      Pointer<WebrtcVideoEncoderFactory>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoEncoderFactoryGetSupportedFormatsDartFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(
      Pointer<WebrtcVideoEncoderFactory>,
    );

// unique video decoder factory から raw factory を取り出す。
typedef VideoDecoderFactoryUniqueGetNativeFn =
    Pointer<WebrtcVideoDecoderFactory> Function(
      Pointer<WebrtcVideoDecoderFactoryUnique>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoDecoderFactoryUniqueGetDartFn =
    Pointer<WebrtcVideoDecoderFactory> Function(
      Pointer<WebrtcVideoDecoderFactoryUnique>,
    );

// unique decoder factory の delete 関数。
typedef VideoDecoderFactoryUniqueDeleteNativeFn =
    Void Function(Pointer<WebrtcVideoDecoderFactoryUnique>);

// Dart 側で同シグネチャを扱うための型。
typedef VideoDecoderFactoryUniqueDeleteDartFn =
    void Function(Pointer<WebrtcVideoDecoderFactoryUnique>);

// raw video decoder factory から対応 format 一覧を取得する。
typedef VideoDecoderFactoryGetSupportedFormatsNativeFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(
      Pointer<WebrtcVideoDecoderFactory>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef VideoDecoderFactoryGetSupportedFormatsDartFn =
    Pointer<WebrtcSdpVideoFormatVector> Function(
      Pointer<WebrtcVideoDecoderFactory>,
    );

// SdpVideoFormat の vector 長を返す。
typedef SdpVideoFormatVectorSizeNativeFn =
    IntPtr Function(Pointer<WebrtcSdpVideoFormatVector>);

// Dart 側で同シグネチャを扱うための型。
typedef SdpVideoFormatVectorSizeDartFn =
    int Function(Pointer<WebrtcSdpVideoFormatVector>);

// SdpVideoFormat vector から index 位置の要素を取得する。
typedef SdpVideoFormatVectorGetNativeFn =
    Pointer<WebrtcSdpVideoFormat> Function(
      Pointer<WebrtcSdpVideoFormatVector>,
      IntPtr,
    );

// Dart 側で同シグネチャを扱うための型。
typedef SdpVideoFormatVectorGetDartFn =
    Pointer<WebrtcSdpVideoFormat> Function(
      Pointer<WebrtcSdpVideoFormatVector>,
      int,
    );

// SdpVideoFormat の name を取得する。
typedef SdpVideoFormatGetNameNativeFn =
    Pointer<Char> Function(Pointer<WebrtcSdpVideoFormat>);

// Dart 側で同シグネチャを扱うための型。
typedef SdpVideoFormatGetNameDartFn =
    Pointer<Char> Function(Pointer<WebrtcSdpVideoFormat>);

// SdpVideoFormat vector を解放する。
typedef SdpVideoFormatVectorDeleteNativeFn =
    Void Function(Pointer<WebrtcSdpVideoFormatVector>);

// Dart 側で同シグネチャを扱うための型。
typedef SdpVideoFormatVectorDeleteDartFn =
    void Function(Pointer<WebrtcSdpVideoFormatVector>);

// simulcast encoder adapter を生成する。
typedef SimulcastEncoderAdapterNewNativeFn =
    Pointer<WebrtcSimulcastEncoderAdapterUnique> Function(
      Pointer<WebrtcEnvironment>,
      Pointer<WebrtcVideoEncoderFactory>,
      Pointer<WebrtcVideoEncoderFactory>,
      Pointer<WebrtcSdpVideoFormat>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef SimulcastEncoderAdapterNewDartFn =
    Pointer<WebrtcSimulcastEncoderAdapterUnique> Function(
      Pointer<WebrtcEnvironment>,
      Pointer<WebrtcVideoEncoderFactory>,
      Pointer<WebrtcVideoEncoderFactory>,
      Pointer<WebrtcSdpVideoFormat>,
    );

// unique adapter から raw adapter を取り出す。
typedef SimulcastEncoderAdapterUniqueGetNativeFn =
    Pointer<WebrtcSimulcastEncoderAdapter> Function(
      Pointer<WebrtcSimulcastEncoderAdapterUnique>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef SimulcastEncoderAdapterUniqueGetDartFn =
    Pointer<WebrtcSimulcastEncoderAdapter> Function(
      Pointer<WebrtcSimulcastEncoderAdapterUnique>,
    );

// unique adapter を破棄する。
typedef SimulcastEncoderAdapterUniqueDeleteNativeFn =
    Void Function(Pointer<WebrtcSimulcastEncoderAdapterUnique>);

// Dart 側で同シグネチャを扱うための型。
typedef SimulcastEncoderAdapterUniqueDeleteDartFn =
    void Function(Pointer<WebrtcSimulcastEncoderAdapterUnique>);

// adapter を `VideoEncoder` として見える型へ cast する。
typedef SimulcastEncoderAdapterCastToVideoEncoderNativeFn =
    Pointer<WebrtcVideoEncoder> Function(
      Pointer<WebrtcSimulcastEncoderAdapter>,
    );

// Dart 側で同シグネチャを扱うための型。
typedef SimulcastEncoderAdapterCastToVideoEncoderDartFn =
    Pointer<WebrtcVideoEncoder> Function(
      Pointer<WebrtcSimulcastEncoderAdapter>,
    );

// ---------------------------------------------------------------------------
// コールバック構造体
// ---------------------------------------------------------------------------

// `webrtc_PeerConnectionObserver_cbs` の Dart 側ミラー。
//
// `PeerConnectionObserver` を C 側で組み立てるための callback テーブルで、
// 接続状態・ICE・track・DataChannel のイベント入口になる。
//
// フィールド順序:
// 1. OnStandardizedIceConnectionChange(int32 new_state, void* user_data)
// 2. OnConnectionChange(int32 new_state, void* user_data)
// 3. OnIceCandidate(const IceCandidate*, void* user_data)
// 4. OnIceCandidateError(address, address_len, port, url, url_len,
//    error_code, error_text, error_text_len, void* user_data)
// 5. OnTrack(RtpTransceiverInterface_refcounted*, void* user_data)
// 6. OnRemoveTrack(RtpReceiverInterface_refcounted*, void* user_data)
// 7. OnDataChannel(DataChannelInterface_refcounted*, void* user_data)
// 8. OnDestroy(void* user_data)
// 9. OnIceGatheringChange(int32 new_state, void* user_data)
final class PeerConnectionObserverCbs extends Struct {
  external Pointer<
    NativeFunction<Void Function(Int32 newState, Pointer<Void> userData)>
  >
  onStandardizedIceConnectionChange;

  external Pointer<
    NativeFunction<Void Function(Int32 newState, Pointer<Void> userData)>
  >
  onConnectionChange;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcIceCandidate> candidate,
        Pointer<Void> userData,
      )
    >
  >
  onIceCandidate;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<Char> address,
        Size addressLen,
        Int32 port,
        Pointer<Char> url,
        Size urlLen,
        Int32 errorCode,
        Pointer<Char> errorText,
        Size errorTextLen,
        Pointer<Void> userData,
      )
    >
  >
  onIceCandidateError;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcRtpTransceiverInterfaceRefcounted> transceiver,
        Pointer<Void> userData,
      )
    >
  >
  onTrack;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcRtpReceiverInterfaceRefcounted> receiver,
        Pointer<Void> userData,
      )
    >
  >
  onRemoveTrack;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcDataChannelInterfaceRefcounted> dataChannel,
        Pointer<Void> userData,
      )
    >
  >
  onDataChannel;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;

  external Pointer<
    NativeFunction<Void Function(Int32 newState, Pointer<Void> userData)>
  >
  onIceGatheringChange;
}

// `webrtc_DataChannelObserver_cbs` の Dart 側ミラー。
//
// DataChannel の state change と message 受信を Dart callback へ渡す。
final class DataChannelObserverCbs extends Struct {
  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onStateChange;

  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<Uint8> data,
        Size len,
        Int32 isBinary,
        Pointer<Void> userData,
      )
    >
  >
  onMessage;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;
}

// `webrtc_VideoSinkInterface_cbs` の Dart 側ミラー。
//
// `VideoTrack` に sink を登録したときの frame 到着通知口を表す。
final class VideoSinkInterfaceCbs extends Struct {
  external Pointer<
    NativeFunction<
      Void Function(Pointer<WebrtcVideoFrame> frame, Pointer<Void> userData)
    >
  >
  onFrame;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDiscardedFrame;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;
}

// `SetRemoteDescription` 完了通知用 callback 構造体。
final class SetRemoteDescriptionObserverCbs extends Struct {
  external Pointer<
    NativeFunction<
      Void Function(Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> userData)
    >
  >
  onSetRemoteDescriptionComplete;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;
}

// `SetLocalDescription` 完了通知用 callback 構造体。
final class SetLocalDescriptionObserverCbs extends Struct {
  external Pointer<
    NativeFunction<
      Void Function(Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> userData)
    >
  >
  onSetLocalDescriptionComplete;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;
}

// `CreateOffer` / `CreateAnswer` の success/failure を受け取る callback 構造体。
final class CreateSessionDescriptionObserverCbs extends Struct {
  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcSessionDescriptionInterfaceUnique> desc,
        Pointer<Void> userData,
      )
    >
  >
  onSuccess;

  external Pointer<
    NativeFunction<
      Void Function(Pointer<WebrtcRTCErrorUnique> error, Pointer<Void> userData)
    >
  >
  onFailure;

  external Pointer<NativeFunction<Void Function(Pointer<Void> userData)>>
  onDestroy;
}

// `GetStats()` 完了時に `RTCStatsReport` を受け取る callback 構造体。
final class RTCStatsCollectorCallbackCbs extends Struct {
  external Pointer<
    NativeFunction<
      Void Function(
        Pointer<WebrtcRTCStatsReportRefcounted> report,
        Pointer<Void> userData,
      )
    >
  >
  onStatsDelivered;
}

// callback ベース custom `VideoEncoderFactory` の vtable。
//
// Dart から native `VideoEncoderFactory` を実装するときの入口になる。
final class VideoEncoderFactoryCbs extends Struct {
  external Pointer<
    NativeFunction<VideoEncoderFactoryCbsGetSupportedFormatsNativeFn>
  >
  getSupportedFormats;

  external Pointer<NativeFunction<VideoEncoderFactoryCbsCreateNativeFn>> create;

  external Pointer<NativeFunction<VideoEncoderFactoryCbsOnDestroyNativeFn>>
  onDestroy;
}

// ---------------------------------------------------------------------------
// LibWebrtcC: DynamicLibrary からの関数解決
// ---------------------------------------------------------------------------

class LibWebrtcC {
  final DynamicLibrary _lib;

  // 共有ライブラリハンドルを保持し、各 C シンボルを lazy lookup する。
  //
  // `late final` を使うことで、未使用シンボルの lookup コストを避けつつ、
  // 必要になった時点で例外付きで解決失敗を表面化させる。
  LibWebrtcC(this._lib);

  // --- std_string ---
  // C++ 文字列を Dart 側へ取り出したり、逆に native API へ渡すための最小 API。

  late final stdStringUniqueGet = _lib
      .lookupFunction<
        Pointer<StdString> Function(Pointer<StdStringUnique>),
        Pointer<StdString> Function(Pointer<StdStringUnique>)
      >('std_string_unique_get');

  late final stdStringUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<StdStringUnique>),
        void Function(Pointer<StdStringUnique>)
      >('std_string_unique_delete');

  late final stdStringCStr = _lib
      .lookupFunction<
        Pointer<Char> Function(Pointer<StdString>),
        Pointer<Char> Function(Pointer<StdString>)
      >('std_string_c_str');

  late final stdStringNewFromCstr = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(Pointer<Char>),
        Pointer<StdStringUnique> Function(Pointer<Char>)
      >('std_string_new_from_cstr');

  // --- std_string_vector ---
  // stream id や ICE server URL のような複数文字列入力を vector で渡す API。

  late final stdStringVectorNew = _lib
      .lookupFunction<
        Pointer<StdStringVector> Function(Int32),
        Pointer<StdStringVector> Function(int)
      >('std_string_vector_new');

  late final stdStringVectorDelete = _lib
      .lookupFunction<
        Void Function(Pointer<StdStringVector>),
        void Function(Pointer<StdStringVector>)
      >('std_string_vector_delete');

  late final stdStringVectorPushBack = _lib
      .lookupFunction<
        Void Function(Pointer<StdStringVector>, Pointer<StdString>),
        void Function(Pointer<StdStringVector>, Pointer<StdString>)
      >('std_string_vector_push_back');

  // --- Thread ---
  // shared PeerConnectionFactory の network / worker / signaling thread を
  // 明示生成・起動・停止する API。

  late final threadCreateWithSocketServer = _lib
      .lookupFunction<
        Pointer<WebrtcThreadUnique> Function(),
        Pointer<WebrtcThreadUnique> Function()
      >('webrtc_Thread_CreateWithSocketServer');

  late final threadCreate = _lib
      .lookupFunction<
        Pointer<WebrtcThreadUnique> Function(),
        Pointer<WebrtcThreadUnique> Function()
      >('webrtc_Thread_Create');

  late final threadUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcThread> Function(Pointer<WebrtcThreadUnique>),
        Pointer<WebrtcThread> Function(Pointer<WebrtcThreadUnique>)
      >('webrtc_Thread_unique_get');

  late final threadStart = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcThread>),
        void Function(Pointer<WebrtcThread>)
      >('webrtc_Thread_Start');

  late final threadStop = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcThread>),
        void Function(Pointer<WebrtcThread>)
      >('webrtc_Thread_Stop');

  late final threadUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcThreadUnique>),
        void Function(Pointer<WebrtcThreadUnique>)
      >('webrtc_Thread_unique_delete');

  // --- Environment ---
  // ADM や custom video factory 生成時に必要な WebRTC 実行環境 API。

  late final createEnvironment = _lib
      .lookupFunction<
        Pointer<WebrtcEnvironment> Function(),
        Pointer<WebrtcEnvironment> Function()
      >('webrtc_CreateEnvironment');

  late final environmentDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcEnvironment>),
        void Function(Pointer<WebrtcEnvironment>)
      >('webrtc_Environment_delete');

  // --- AudioDeviceModule ---
  // 録音デバイス列挙・切り替え・初期化を扱うネイティブ音声入出力 API。

  late final createAudioDeviceModule = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
          Int32,
        ),
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
          int,
        )
      >('webrtc_CreateAudioDeviceModule');

  // abort を setjmp/longjmp で捕捉するラッパー
  late final soraCreateAudioDeviceModule = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
          Int32,
        ),
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
          int,
        )
      >('sora_create_audio_device_module');

  late final createAndroidAudioDeviceModule = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
        ),
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(
          Pointer<WebrtcEnvironment>,
        )
      >('sora_android_create_audio_device_module');

  late final audioDeviceModuleRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDeviceModule> Function(
          Pointer<WebrtcAudioDeviceModuleRefcounted>,
        ),
        Pointer<WebrtcAudioDeviceModule> Function(
          Pointer<WebrtcAudioDeviceModuleRefcounted>,
        )
      >('webrtc_AudioDeviceModule_refcounted_get');

  late final audioDeviceModuleRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioDeviceModule>),
        void Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_Release');

  // ADM を初期化する
  late final audioDeviceModuleInit = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_Init');

  // 再生サブシステムを初期化する
  late final audioDeviceModuleInitPlayout = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_InitPlayout');

  // 録音サブシステムを初期化する
  late final audioDeviceModuleInitRecording = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_InitRecording');

  // 録音が初期化済みかを返す
  late final audioDeviceModuleRecordingIsInitialized = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_RecordingIsInitialized');

  // 録音中かを返す
  late final audioDeviceModuleRecording = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_Recording');

  // 利用可能な録音デバイス数を返す
  late final audioDeviceModuleRecordingDevices = _lib
      .lookupFunction<
        Int16 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_RecordingDevices');

  // 録音デバイスの name と guid を取得する (呼び出し側で 128 バイトのバッファを確保すること)
  late final audioDeviceModuleRecordingDeviceName = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<WebrtcAudioDeviceModule>,
          Uint16,
          Pointer<Char>,
          Pointer<Char>,
        ),
        int Function(
          Pointer<WebrtcAudioDeviceModule>,
          int,
          Pointer<Char>,
          Pointer<Char>,
        )
      >('webrtc_AudioDeviceModule_RecordingDeviceName');

  // 録音デバイスを index で切り替える
  late final audioDeviceModuleSetRecordingDevice = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>, Uint16),
        int Function(Pointer<WebrtcAudioDeviceModule>, int)
      >('webrtc_AudioDeviceModule_SetRecordingDevice');

  // 録音を開始する
  late final audioDeviceModuleStartRecording = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioDeviceModule>),
        int Function(Pointer<WebrtcAudioDeviceModule>)
      >('webrtc_AudioDeviceModule_StartRecording');

  // --- RtcEventLogFactory ---
  // factory dependencies へ event log factory を注入する API。

  late final rtcEventLogFactoryCreate = _lib
      .lookupFunction<
        Pointer<WebrtcRtcEventLogFactoryUnique> Function(),
        Pointer<WebrtcRtcEventLogFactoryUnique> Function()
      >('webrtc_RtcEventLogFactory_Create');

  // --- AudioCodecFactory ---
  // builtin audio codec factory の生成と refcount 管理 API。

  late final createBuiltinAudioEncoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcAudioEncoderFactoryRefcounted> Function(),
        Pointer<WebrtcAudioEncoderFactoryRefcounted> Function()
      >('webrtc_CreateBuiltinAudioEncoderFactory');

  late final createBuiltinAudioDecoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDecoderFactoryRefcounted> Function(),
        Pointer<WebrtcAudioDecoderFactoryRefcounted> Function()
      >('webrtc_CreateBuiltinAudioDecoderFactory');

  late final audioEncoderFactoryRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioEncoderFactory> Function(
          Pointer<WebrtcAudioEncoderFactoryRefcounted>,
        ),
        Pointer<WebrtcAudioEncoderFactory> Function(
          Pointer<WebrtcAudioEncoderFactoryRefcounted>,
        )
      >('webrtc_AudioEncoderFactory_refcounted_get');

  late final audioEncoderFactoryRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioEncoderFactory>),
        void Function(Pointer<WebrtcAudioEncoderFactory>)
      >('webrtc_AudioEncoderFactory_Release');

  late final audioDecoderFactoryRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDecoderFactory> Function(
          Pointer<WebrtcAudioDecoderFactoryRefcounted>,
        ),
        Pointer<WebrtcAudioDecoderFactory> Function(
          Pointer<WebrtcAudioDecoderFactoryRefcounted>,
        )
      >('webrtc_AudioDecoderFactory_refcounted_get');

  late final audioDecoderFactoryRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioDecoderFactory>),
        void Function(Pointer<WebrtcAudioDecoderFactory>)
      >('webrtc_AudioDecoderFactory_Release');

  // --- VideoCodecTypeFactory ---
  // builtin / ObjC / JNI / custom callback ベースを含む video codec factory API。

  late final createBuiltinVideoEncoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoEncoderFactoryUnique> Function(),
        Pointer<WebrtcVideoEncoderFactoryUnique> Function()
      >('webrtc_CreateBuiltinVideoEncoderFactory');

  late final videoEncoderFactoryUniqueGet = _lib
      .lookupFunction<
        VideoEncoderFactoryUniqueGetNativeFn,
        VideoEncoderFactoryUniqueGetDartFn
      >('webrtc_VideoEncoderFactory_unique_get');
  late final videoEncoderFactoryUniqueGetPtr = _lib
      .lookup<NativeFunction<VideoEncoderFactoryUniqueGetNativeFn>>(
        'webrtc_VideoEncoderFactory_unique_get',
      );

  late final videoEncoderFactoryUniqueDelete = _lib
      .lookupFunction<
        VideoEncoderFactoryUniqueDeleteNativeFn,
        VideoEncoderFactoryUniqueDeleteDartFn
      >('webrtc_VideoEncoderFactory_unique_delete');
  late final videoEncoderFactoryUniqueDeletePtr = _lib
      .lookup<NativeFunction<VideoEncoderFactoryUniqueDeleteNativeFn>>(
        'webrtc_VideoEncoderFactory_unique_delete',
      );

  late final videoEncoderFactoryNew = _lib
      .lookupFunction<
        VideoEncoderFactoryNewNativeFn,
        VideoEncoderFactoryNewDartFn
      >('webrtc_VideoEncoderFactory_new');
  late final videoEncoderFactoryNewPtr = _lib
      .lookup<NativeFunction<VideoEncoderFactoryNewNativeFn>>(
        'webrtc_VideoEncoderFactory_new',
      );

  late final videoEncoderFactoryGetSupportedFormats = _lib
      .lookupFunction<
        VideoEncoderFactoryGetSupportedFormatsNativeFn,
        VideoEncoderFactoryGetSupportedFormatsDartFn
      >('webrtc_VideoEncoderFactory_GetSupportedFormats');
  late final videoEncoderFactoryGetSupportedFormatsPtr = _lib
      .lookup<NativeFunction<VideoEncoderFactoryGetSupportedFormatsNativeFn>>(
        'webrtc_VideoEncoderFactory_GetSupportedFormats',
      );

  late final simulcastEncoderAdapterNew = _lib
      .lookupFunction<
        SimulcastEncoderAdapterNewNativeFn,
        SimulcastEncoderAdapterNewDartFn
      >('webrtc_SimulcastEncoderAdapter_new');
  late final simulcastEncoderAdapterNewPtr = _lib
      .lookup<NativeFunction<SimulcastEncoderAdapterNewNativeFn>>(
        'webrtc_SimulcastEncoderAdapter_new',
      );

  late final simulcastEncoderAdapterUniqueGet = _lib
      .lookupFunction<
        SimulcastEncoderAdapterUniqueGetNativeFn,
        SimulcastEncoderAdapterUniqueGetDartFn
      >('webrtc_SimulcastEncoderAdapter_unique_get');
  late final simulcastEncoderAdapterUniqueGetPtr = _lib
      .lookup<NativeFunction<SimulcastEncoderAdapterUniqueGetNativeFn>>(
        'webrtc_SimulcastEncoderAdapter_unique_get',
      );

  late final simulcastEncoderAdapterUniqueDelete = _lib
      .lookupFunction<
        SimulcastEncoderAdapterUniqueDeleteNativeFn,
        SimulcastEncoderAdapterUniqueDeleteDartFn
      >('webrtc_SimulcastEncoderAdapter_unique_delete');
  late final simulcastEncoderAdapterUniqueDeletePtr = _lib
      .lookup<NativeFunction<SimulcastEncoderAdapterUniqueDeleteNativeFn>>(
        'webrtc_SimulcastEncoderAdapter_unique_delete',
      );

  late final simulcastEncoderAdapterCastToVideoEncoder = _lib
      .lookupFunction<
        SimulcastEncoderAdapterCastToVideoEncoderNativeFn,
        SimulcastEncoderAdapterCastToVideoEncoderDartFn
      >('webrtc_SimulcastEncoderAdapter_cast_to_webrtc_VideoEncoder');
  late final simulcastEncoderAdapterCastToVideoEncoderPtr = _lib
      .lookup<
        NativeFunction<SimulcastEncoderAdapterCastToVideoEncoderNativeFn>
      >('webrtc_SimulcastEncoderAdapter_cast_to_webrtc_VideoEncoder');

  late final createBuiltinVideoDecoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoDecoderFactoryUnique> Function(),
        Pointer<WebrtcVideoDecoderFactoryUnique> Function()
      >('webrtc_CreateBuiltinVideoDecoderFactory');

  late final objcDefaultVideoEncoderFactoryNew = _lib
      .lookupFunction<
        Pointer<WebrtcObjcRTCVideoEncoderFactory> Function(),
        Pointer<WebrtcObjcRTCVideoEncoderFactory> Function()
      >('webrtc_objc_RTCDefaultVideoEncoderFactory_new');

  late final objcVideoEncoderFactoryRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcObjcRTCVideoEncoderFactory>),
        void Function(Pointer<WebrtcObjcRTCVideoEncoderFactory>)
      >('webrtc_objc_RTCVideoEncoderFactory_release');

  late final objcToNativeVideoEncoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoEncoderFactoryUnique> Function(
          Pointer<WebrtcObjcRTCVideoEncoderFactory>,
        ),
        Pointer<WebrtcVideoEncoderFactoryUnique> Function(
          Pointer<WebrtcObjcRTCVideoEncoderFactory>,
        )
      >('webrtc_ObjCToNativeVideoEncoderFactory');

  late final objcDefaultVideoDecoderFactoryNew = _lib
      .lookupFunction<
        Pointer<WebrtcObjcRTCVideoDecoderFactory> Function(),
        Pointer<WebrtcObjcRTCVideoDecoderFactory> Function()
      >('webrtc_objc_RTCDefaultVideoDecoderFactory_new');

  late final objcVideoDecoderFactoryRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcObjcRTCVideoDecoderFactory>),
        void Function(Pointer<WebrtcObjcRTCVideoDecoderFactory>)
      >('webrtc_objc_RTCVideoDecoderFactory_release');

  late final objcToNativeVideoDecoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoDecoderFactoryUnique> Function(
          Pointer<WebrtcObjcRTCVideoDecoderFactory>,
        ),
        Pointer<WebrtcVideoDecoderFactoryUnique> Function(
          Pointer<WebrtcObjcRTCVideoDecoderFactory>,
        )
      >('webrtc_ObjCToNativeVideoDecoderFactory');

  late final videoDecoderFactoryUniqueGet = _lib
      .lookupFunction<
        VideoDecoderFactoryUniqueGetNativeFn,
        VideoDecoderFactoryUniqueGetDartFn
      >('webrtc_VideoDecoderFactory_unique_get');
  late final videoDecoderFactoryUniqueGetPtr = _lib
      .lookup<NativeFunction<VideoDecoderFactoryUniqueGetNativeFn>>(
        'webrtc_VideoDecoderFactory_unique_get',
      );

  late final videoDecoderFactoryUniqueDelete = _lib
      .lookupFunction<
        VideoDecoderFactoryUniqueDeleteNativeFn,
        VideoDecoderFactoryUniqueDeleteDartFn
      >('webrtc_VideoDecoderFactory_unique_delete');
  late final videoDecoderFactoryUniqueDeletePtr = _lib
      .lookup<NativeFunction<VideoDecoderFactoryUniqueDeleteNativeFn>>(
        'webrtc_VideoDecoderFactory_unique_delete',
      );

  late final videoDecoderFactoryGetSupportedFormats = _lib
      .lookupFunction<
        VideoDecoderFactoryGetSupportedFormatsNativeFn,
        VideoDecoderFactoryGetSupportedFormatsDartFn
      >('webrtc_VideoDecoderFactory_GetSupportedFormats');
  late final videoDecoderFactoryGetSupportedFormatsPtr = _lib
      .lookup<NativeFunction<VideoDecoderFactoryGetSupportedFormatsNativeFn>>(
        'webrtc_VideoDecoderFactory_GetSupportedFormats',
      );

  late final sdpVideoFormatVectorSize = _lib
      .lookupFunction<
        SdpVideoFormatVectorSizeNativeFn,
        SdpVideoFormatVectorSizeDartFn
      >('webrtc_SdpVideoFormat_vector_size');
  late final sdpVideoFormatVectorSizePtr = _lib
      .lookup<NativeFunction<SdpVideoFormatVectorSizeNativeFn>>(
        'webrtc_SdpVideoFormat_vector_size',
      );

  late final sdpVideoFormatVectorGet = _lib
      .lookupFunction<
        SdpVideoFormatVectorGetNativeFn,
        SdpVideoFormatVectorGetDartFn
      >('webrtc_SdpVideoFormat_vector_get');
  late final sdpVideoFormatVectorGetPtr = _lib
      .lookup<NativeFunction<SdpVideoFormatVectorGetNativeFn>>(
        'webrtc_SdpVideoFormat_vector_get',
      );

  late final sdpVideoFormatGetName = _lib
      .lookupFunction<
        SdpVideoFormatGetNameNativeFn,
        SdpVideoFormatGetNameDartFn
      >('webrtc_SdpVideoFormat_get_name');
  late final sdpVideoFormatGetNamePtr = _lib
      .lookup<NativeFunction<SdpVideoFormatGetNameNativeFn>>(
        'webrtc_SdpVideoFormat_get_name',
      );

  late final sdpVideoFormatVectorDelete = _lib
      .lookupFunction<
        SdpVideoFormatVectorDeleteNativeFn,
        SdpVideoFormatVectorDeleteDartFn
      >('webrtc_SdpVideoFormat_vector_delete');
  late final sdpVideoFormatVectorDeletePtr = _lib
      .lookup<NativeFunction<SdpVideoFormatVectorDeleteNativeFn>>(
        'webrtc_SdpVideoFormat_vector_delete',
      );

  late final jniAttachCurrentThreadIfNeeded = _lib
      .lookupFunction<
        Pointer<WebrtcJNIEnv> Function(),
        Pointer<WebrtcJNIEnv> Function()
      >('webrtc_jni_AttachCurrentThreadIfNeeded');

  late final jniGetClass = _lib
      .lookupFunction<
        Pointer<Void> Function(Pointer<WebrtcJNIEnv>, Pointer<Char>),
        Pointer<Void> Function(Pointer<WebrtcJNIEnv>, Pointer<Char>)
      >('webrtc_GetClass');

  late final jniGetMethodId = _lib
      .lookupFunction<
        Pointer<WebrtcJNIMethodId> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
          Pointer<Char>,
          Pointer<Char>,
        ),
        Pointer<WebrtcJNIMethodId> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
          Pointer<Char>,
          Pointer<Char>,
        )
      >('jni_JNIEnv_GetMethodID');

  late final jniNewObjectA = _lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
          Pointer<WebrtcJNIMethodId>,
          Pointer<JValue>,
        ),
        Pointer<Void> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
          Pointer<WebrtcJNIMethodId>,
          Pointer<JValue>,
        )
      >('jni_JNIEnv_NewObjectA');

  late final jniDeleteLocalRef = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcJNIEnv>, Pointer<Void>),
        void Function(Pointer<WebrtcJNIEnv>, Pointer<Void>)
      >('jni_JNIEnv_DeleteLocalRef');

  late final jniExceptionCheck = _lib
      .lookupFunction<
        Uint8 Function(Pointer<WebrtcJNIEnv>),
        int Function(Pointer<WebrtcJNIEnv>)
      >('jni_JNIEnv_ExceptionCheck');

  late final jniExceptionClear = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcJNIEnv>),
        void Function(Pointer<WebrtcJNIEnv>)
      >('jni_JNIEnv_ExceptionClear');

  late final javaToNativeVideoEncoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoEncoderFactoryUnique> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
        ),
        Pointer<WebrtcVideoEncoderFactoryUnique> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
        )
      >('webrtc_JavaToNativeVideoEncoderFactory');

  late final javaToNativeVideoDecoderFactory = _lib
      .lookupFunction<
        Pointer<WebrtcVideoDecoderFactoryUnique> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
        ),
        Pointer<WebrtcVideoDecoderFactoryUnique> Function(
          Pointer<WebrtcJNIEnv>,
          Pointer<Void>,
        )
      >('webrtc_JavaToNativeVideoDecoderFactory');

  // --- AudioProcessing ---
  // factory へ差し込む audio processing builder を生成する API。

  late final builtinAudioProcessingBuilderCreate = _lib
      .lookupFunction<
        Pointer<WebrtcAudioProcessingBuilderInterfaceUnique> Function(),
        Pointer<WebrtcAudioProcessingBuilderInterfaceUnique> Function()
      >('webrtc_BuiltinAudioProcessingBuilder_Create');

  // --- PeerConnectionFactoryDependencies ---
  // スレッド・ADM・codec factory・audio processing を束ねる依存注入 API。

  late final pcFactoryDependenciesNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionFactoryDependencies> Function(),
        Pointer<WebrtcPeerConnectionFactoryDependencies> Function()
      >('webrtc_PeerConnectionFactoryDependencies_new');

  late final pcFactoryDependenciesDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionFactoryDependencies>),
        void Function(Pointer<WebrtcPeerConnectionFactoryDependencies>)
      >('webrtc_PeerConnectionFactoryDependencies_delete');

  late final pcFactoryDependenciesSetNetworkThread = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_network_thread');

  late final pcFactoryDependenciesSetWorkerThread = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_worker_thread');

  late final pcFactoryDependenciesSetSignalingThread = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcThread>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_signaling_thread');

  late final pcFactoryDependenciesSetAdm = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioDeviceModuleRefcounted>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioDeviceModuleRefcounted>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_adm');

  late final pcFactoryDependenciesSetEventLogFactory = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcRtcEventLogFactoryUnique>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcRtcEventLogFactoryUnique>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_event_log_factory');

  late final pcFactoryDependenciesSetAudioEncoderFactory = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioEncoderFactoryRefcounted>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioEncoderFactoryRefcounted>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_audio_encoder_factory');

  late final pcFactoryDependenciesSetAudioDecoderFactory = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioDecoderFactoryRefcounted>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioDecoderFactoryRefcounted>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_audio_decoder_factory');

  late final pcFactoryDependenciesSetVideoEncoderFactory = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcVideoEncoderFactoryUnique>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcVideoEncoderFactoryUnique>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_video_encoder_factory');

  late final pcFactoryDependenciesSetVideoDecoderFactory = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcVideoDecoderFactoryUnique>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcVideoDecoderFactoryUnique>,
        )
      >('webrtc_PeerConnectionFactoryDependencies_set_video_decoder_factory');

  late final pcFactoryDependenciesSetAudioProcessingBuilder = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioProcessingBuilderInterfaceUnique>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
          Pointer<WebrtcAudioProcessingBuilderInterfaceUnique>,
        )
      >(
        'webrtc_PeerConnectionFactoryDependencies_set_audio_processing_builder',
      );

  late final enableMedia = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionFactoryDependencies>),
        void Function(Pointer<WebrtcPeerConnectionFactoryDependencies>)
      >('webrtc_EnableMedia');

  // --- PeerConnectionFactory ---
  // modular factory の生成と全体オプション設定を行う API。

  late final createModularPeerConnectionFactory = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted> Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
        ),
        Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted> Function(
          Pointer<WebrtcPeerConnectionFactoryDependencies>,
        )
      >('webrtc_CreateModularPeerConnectionFactory');

  late final pcFactoryRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionFactoryInterface> Function(
          Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted>,
        ),
        Pointer<WebrtcPeerConnectionFactoryInterface> Function(
          Pointer<WebrtcPeerConnectionFactoryInterfaceRefcounted>,
        )
      >('webrtc_PeerConnectionFactoryInterface_refcounted_get');

  late final pcFactoryRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionFactoryInterface>),
        void Function(Pointer<WebrtcPeerConnectionFactoryInterface>)
      >('webrtc_PeerConnectionFactoryInterface_Release');

  late final pcFactoryOptionsNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionFactoryInterfaceOptions> Function(),
        Pointer<WebrtcPeerConnectionFactoryInterfaceOptions> Function()
      >('webrtc_PeerConnectionFactoryInterface_Options_new');

  late final pcFactoryOptionsSetDisableEncryption = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>,
          Int32,
        ),
        void Function(Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>, int)
      >('webrtc_PeerConnectionFactoryInterface_Options_set_disable_encryption');

  late final pcFactoryOptionsSetSslMaxVersion = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>,
          Int32,
        ),
        void Function(Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>, int)
      >('webrtc_PeerConnectionFactoryInterface_Options_set_ssl_max_version');

  late final pcFactorySetOptions = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>,
        )
      >('webrtc_PeerConnectionFactoryInterface_SetOptions');

  late final pcFactoryOptionsDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>),
        void Function(Pointer<WebrtcPeerConnectionFactoryInterfaceOptions>)
      >('webrtc_PeerConnectionFactoryInterface_Options_delete');

  // --- PeerConnection RTCConfiguration ---
  // 各 PeerConnection に適用する SDP semantics・ICE policy・server 設定 API。

  late final rtcConfigurationNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration> Function(),
        Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration> Function()
      >('webrtc_PeerConnectionInterface_RTCConfiguration_new');

  late final rtcConfigurationDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>),
        void Function(Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>)
      >('webrtc_PeerConnectionInterface_RTCConfiguration_delete');

  late final rtcConfigurationSetSdpSemantics = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          Int32,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          int,
        )
      >('webrtc_PeerConnectionInterface_RTCConfiguration_set_sdp_semantics');

  late final rtcConfigurationSetEnableGcmCryptoSuites = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          Int32,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          int,
        )
      >(
        'webrtc_PeerConnectionInterface_RTCConfiguration_set_enable_gcm_crypto_suites',
      );

  late final rtcConfigurationSetType = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          Int32,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          int,
        )
      >('webrtc_PeerConnectionInterface_RTCConfiguration_set_type');

  late final rtcConfigurationGetServers = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionInterfaceIceServerVector> Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
        ),
        Pointer<WebrtcPeerConnectionInterfaceIceServerVector> Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
        )
      >('webrtc_PeerConnectionInterface_RTCConfiguration_get_servers');

  // --- ICE Server ---
  // `RTCConfiguration.iceServers` の 1 要素を構築する API。

  late final iceServerNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionInterfaceIceServer> Function(),
        Pointer<WebrtcPeerConnectionInterfaceIceServer> Function()
      >('webrtc_PeerConnectionInterface_IceServer_new');

  late final iceServerDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionInterfaceIceServer>),
        void Function(Pointer<WebrtcPeerConnectionInterfaceIceServer>)
      >('webrtc_PeerConnectionInterface_IceServer_delete');

  late final iceServerGetUrls = _lib
      .lookupFunction<
        Pointer<StdStringVector> Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
        ),
        Pointer<StdStringVector> Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
        )
      >('webrtc_PeerConnectionInterface_IceServer_get_urls');

  late final iceServerSetUsername = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
          Pointer<Char>,
          Size,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
          Pointer<Char>,
          int,
        )
      >('webrtc_PeerConnectionInterface_IceServer_set_username');

  late final iceServerSetPassword = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
          Pointer<Char>,
          Size,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
          Pointer<Char>,
          int,
        )
      >('webrtc_PeerConnectionInterface_IceServer_set_password');

  late final iceServerVectorPushBack = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServerVector>,
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceIceServerVector>,
          Pointer<WebrtcPeerConnectionInterfaceIceServer>,
        )
      >('webrtc_PeerConnectionInterface_IceServer_vector_push_back');

  // --- PeerConnectionObserver ---
  // callback 構造体から native `PeerConnectionObserver` 実体を作る API。

  late final pcObserverNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionObserver> Function(
          Pointer<PeerConnectionObserverCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcPeerConnectionObserver> Function(
          Pointer<PeerConnectionObserverCbs>,
          Pointer<Void>,
        )
      >('webrtc_PeerConnectionObserver_new');

  late final pcObserverDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionObserver>),
        void Function(Pointer<WebrtcPeerConnectionObserver>)
      >('webrtc_PeerConnectionObserver_delete');

  // --- PeerConnectionDependencies ---
  // observer を含む PeerConnection 生成依存をまとめる API。

  late final pcDependenciesNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionDependencies> Function(
          Pointer<WebrtcPeerConnectionObserver>,
        ),
        Pointer<WebrtcPeerConnectionDependencies> Function(
          Pointer<WebrtcPeerConnectionObserver>,
        )
      >('webrtc_PeerConnectionDependencies_new');

  late final pcDependenciesDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionDependencies>),
        void Function(Pointer<WebrtcPeerConnectionDependencies>)
      >('webrtc_PeerConnectionDependencies_delete');

  // --- PeerConnection ---
  // PeerConnection 本体生成、SDP/ICE 操作、track 追加、stats 取得の主要 API。

  late final pcFactoryCreatePeerConnectionOrError = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          Pointer<WebrtcPeerConnectionDependencies>,
          Pointer<Pointer<WebrtcPeerConnectionInterfaceRefcounted>>,
          Pointer<Pointer<WebrtcRTCErrorUnique>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcPeerConnectionInterfaceRTCConfiguration>,
          Pointer<WebrtcPeerConnectionDependencies>,
          Pointer<Pointer<WebrtcPeerConnectionInterfaceRefcounted>>,
          Pointer<Pointer<WebrtcRTCErrorUnique>>,
        )
      >('webrtc_PeerConnectionFactoryInterface_CreatePeerConnectionOrError');

  late final pcRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionInterface> Function(
          Pointer<WebrtcPeerConnectionInterfaceRefcounted>,
        ),
        Pointer<WebrtcPeerConnectionInterface> Function(
          Pointer<WebrtcPeerConnectionInterfaceRefcounted>,
        )
      >('webrtc_PeerConnectionInterface_refcounted_get');

  late final pcRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionInterface>),
        void Function(Pointer<WebrtcPeerConnectionInterface>)
      >('webrtc_PeerConnectionInterface_Release');

  // --- SDP ---
  // SDP 文字列と `SessionDescription` 実体の相互変換、および適用 API。

  late final createSessionDescription = _lib
      .lookupFunction<
        Pointer<WebrtcSessionDescriptionInterfaceUnique> Function(
          Int32,
          Pointer<Char>,
          Size,
        ),
        Pointer<WebrtcSessionDescriptionInterfaceUnique> Function(
          int,
          Pointer<Char>,
          int,
        )
      >('webrtc_CreateSessionDescription');

  late final sessionDescriptionUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcSessionDescriptionInterface> Function(
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
        ),
        Pointer<WebrtcSessionDescriptionInterface> Function(
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
        )
      >('webrtc_SessionDescriptionInterface_unique_get');

  late final sessionDescriptionUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcSessionDescriptionInterfaceUnique>),
        void Function(Pointer<WebrtcSessionDescriptionInterfaceUnique>)
      >('webrtc_SessionDescriptionInterface_unique_delete');

  late final sessionDescriptionToString = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcSessionDescriptionInterface>,
          Pointer<Pointer<StdStringUnique>>,
        ),
        void Function(
          Pointer<WebrtcSessionDescriptionInterface>,
          Pointer<Pointer<StdStringUnique>>,
        )
      >('webrtc_SessionDescriptionInterface_ToString');

  late final pcSetRemoteDescription = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
          Pointer<WebrtcSetRemoteDescriptionObserverInterfaceRefcounted>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
          Pointer<WebrtcSetRemoteDescriptionObserverInterfaceRefcounted>,
        )
      >('webrtc_PeerConnectionInterface_SetRemoteDescription');

  late final pcSetLocalDescription = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
          Pointer<WebrtcSetLocalDescriptionObserverInterfaceRefcounted>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcSessionDescriptionInterfaceUnique>,
          Pointer<WebrtcSetLocalDescriptionObserverInterfaceRefcounted>,
        )
      >('webrtc_PeerConnectionInterface_SetLocalDescription');

  late final pcCreateAnswer = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcCreateSessionDescriptionObserver>,
          Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcCreateSessionDescriptionObserver>,
          Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions>,
        )
      >('webrtc_PeerConnectionInterface_CreateAnswer');

  late final pcAddIceCandidate = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcIceCandidate>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcIceCandidate>,
        )
      >('webrtc_PeerConnectionInterface_AddIceCandidate');

  late final pcAddTrack = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
          Pointer<StdStringVector>,
          Pointer<Pointer<WebrtcRtpSenderInterfaceRefcounted>>,
          Pointer<Pointer<WebrtcRTCErrorUnique>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
          Pointer<StdStringVector>,
          Pointer<Pointer<WebrtcRtpSenderInterfaceRefcounted>>,
          Pointer<Pointer<WebrtcRTCErrorUnique>>,
        )
      >('webrtc_PeerConnectionInterface_AddTrack');

  late final pcGetStats = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<RTCStatsCollectorCallbackCbs>,
          Pointer<Void>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterface>,
          Pointer<RTCStatsCollectorCallbackCbs>,
          Pointer<Void>,
        )
      >('webrtc_PeerConnectionInterface_GetStats');

  late final pcClose = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcPeerConnectionInterface>),
        void Function(Pointer<WebrtcPeerConnectionInterface>)
      >('webrtc_PeerConnectionInterface_Close');

  // --- RTCOfferAnswerOptions ---
  // CreateOffer/CreateAnswer に渡すオプションオブジェクト API。

  late final rtcOfferAnswerOptionsNew = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions> Function(),
        Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions> Function()
      >('webrtc_PeerConnectionInterface_RTCOfferAnswerOptions_new');

  late final rtcOfferAnswerOptionsDelete = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionInterfaceRTCOfferAnswerOptions>,
        )
      >('webrtc_PeerConnectionInterface_RTCOfferAnswerOptions_delete');

  // --- SetRemoteDescriptionObserver ---
  // `SetRemoteDescription` 完了 callback から observer 実体を作る API。

  late final setRemoteDescriptionObserverMakeRefCounted = _lib
      .lookupFunction<
        Pointer<WebrtcSetRemoteDescriptionObserverInterfaceRefcounted> Function(
          Pointer<SetRemoteDescriptionObserverCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcSetRemoteDescriptionObserverInterfaceRefcounted> Function(
          Pointer<SetRemoteDescriptionObserverCbs>,
          Pointer<Void>,
        )
      >('webrtc_SetRemoteDescriptionObserverInterface_make_ref_counted');

  // --- SetLocalDescriptionObserver ---
  // `SetLocalDescription` 完了 callback から observer 実体を作る API。

  late final setLocalDescriptionObserverMakeRefCounted = _lib
      .lookupFunction<
        Pointer<WebrtcSetLocalDescriptionObserverInterfaceRefcounted> Function(
          Pointer<SetLocalDescriptionObserverCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcSetLocalDescriptionObserverInterfaceRefcounted> Function(
          Pointer<SetLocalDescriptionObserverCbs>,
          Pointer<Void>,
        )
      >('webrtc_SetLocalDescriptionObserverInterface_make_ref_counted');

  // --- CreateSessionDescriptionObserver ---
  // `CreateAnswer` / `CreateOffer` の success/failure observer を作る API。

  late final createSessionDescriptionObserverMakeRefCounted = _lib
      .lookupFunction<
        Pointer<WebrtcCreateSessionDescriptionObserver> Function(
          Pointer<CreateSessionDescriptionObserverCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcCreateSessionDescriptionObserver> Function(
          Pointer<CreateSessionDescriptionObserverCbs>,
          Pointer<Void>,
        )
      >('webrtc_CreateSessionDescriptionObserver_make_ref_counted');

  // --- ICE Candidate ---
  // candidate 文字列の parse、属性取得、破棄を行う API。

  late final createIceCandidate = _lib
      .lookupFunction<
        Pointer<WebrtcIceCandidate> Function(
          Pointer<Char>,
          Size,
          Int32,
          Pointer<Char>,
          Size,
          Pointer<Pointer<WebrtcSdpParseErrorUnique>>,
        ),
        Pointer<WebrtcIceCandidate> Function(
          Pointer<Char>,
          int,
          int,
          Pointer<Char>,
          int,
          Pointer<Pointer<WebrtcSdpParseErrorUnique>>,
        )
      >('webrtc_CreateIceCandidate');

  late final iceCandidateDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcIceCandidate>),
        void Function(Pointer<WebrtcIceCandidate>)
      >('webrtc_IceCandidate_delete');

  late final iceCandidateSdpMid = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcIceCandidate>,
          Pointer<Pointer<StdStringUnique>>,
        ),
        void Function(
          Pointer<WebrtcIceCandidate>,
          Pointer<Pointer<StdStringUnique>>,
        )
      >('webrtc_IceCandidate_sdp_mid');

  late final iceCandidateSdpMlineIndex = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcIceCandidate>),
        int Function(Pointer<WebrtcIceCandidate>)
      >('webrtc_IceCandidate_sdp_mline_index');

  late final iceCandidateToString = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<WebrtcIceCandidate>,
          Pointer<Pointer<StdStringUnique>>,
        ),
        int Function(
          Pointer<WebrtcIceCandidate>,
          Pointer<Pointer<StdStringUnique>>,
        )
      >('webrtc_IceCandidate_ToString');

  late final sdpParseErrorUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcSdpParseError> Function(
          Pointer<WebrtcSdpParseErrorUnique>,
        ),
        Pointer<WebrtcSdpParseError> Function(
          Pointer<WebrtcSdpParseErrorUnique>,
        )
      >('webrtc_SdpParseError_unique_get');

  late final sdpParseErrorDescription = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcSdpParseError>,
          Pointer<Pointer<Char>>,
          Pointer<Size>,
        ),
        void Function(
          Pointer<WebrtcSdpParseError>,
          Pointer<Pointer<Char>>,
          Pointer<Size>,
        )
      >('webrtc_SdpParseError_description');

  late final sdpParseErrorUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcSdpParseErrorUnique>),
        void Function(Pointer<WebrtcSdpParseErrorUnique>)
      >('webrtc_SdpParseError_unique_delete');

  // --- RTCError ---
  // 失敗理由の有無判定とエラーメッセージ取り出しに使う API。

  late final rtcErrorUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcRTCError> Function(Pointer<WebrtcRTCErrorUnique>),
        Pointer<WebrtcRTCError> Function(Pointer<WebrtcRTCErrorUnique>)
      >('webrtc_RTCError_unique_get');

  late final rtcErrorOk = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcRTCError>),
        int Function(Pointer<WebrtcRTCError>)
      >('webrtc_RTCError_ok');

  late final rtcErrorMessage = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRTCError>,
          Pointer<Pointer<Char>>,
          Pointer<Size>,
        ),
        void Function(
          Pointer<WebrtcRTCError>,
          Pointer<Pointer<Char>>,
          Pointer<Size>,
        )
      >('webrtc_RTCError_message');

  late final rtcErrorUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRTCErrorUnique>),
        void Function(Pointer<WebrtcRTCErrorUnique>)
      >('webrtc_RTCError_unique_delete');

  // --- DataChannel ---
  // DataChannel の参照管理、observer 登録、送受信を扱う API。

  late final dataChannelRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcDataChannelInterface> Function(
          Pointer<WebrtcDataChannelInterfaceRefcounted>,
        ),
        Pointer<WebrtcDataChannelInterface> Function(
          Pointer<WebrtcDataChannelInterfaceRefcounted>,
        )
      >('webrtc_DataChannelInterface_refcounted_get');

  late final dataChannelAddRef = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcDataChannelInterface>),
        void Function(Pointer<WebrtcDataChannelInterface>)
      >('webrtc_DataChannelInterface_AddRef');

  late final dataChannelRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcDataChannelInterface>),
        void Function(Pointer<WebrtcDataChannelInterface>)
      >('webrtc_DataChannelInterface_Release');

  late final dataChannelLabel = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(Pointer<WebrtcDataChannelInterface>),
        Pointer<StdStringUnique> Function(Pointer<WebrtcDataChannelInterface>)
      >('webrtc_DataChannelInterface_label');

  late final dataChannelState = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcDataChannelInterface>),
        int Function(Pointer<WebrtcDataChannelInterface>)
      >('webrtc_DataChannelInterface_state');

  late final dataChannelObserverNew = _lib
      .lookupFunction<
        Pointer<WebrtcDataChannelObserver> Function(
          Pointer<DataChannelObserverCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcDataChannelObserver> Function(
          Pointer<DataChannelObserverCbs>,
          Pointer<Void>,
        )
      >('webrtc_DataChannelObserver_new');

  late final dataChannelObserverDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcDataChannelObserver>),
        void Function(Pointer<WebrtcDataChannelObserver>)
      >('webrtc_DataChannelObserver_delete');

  late final dataChannelRegisterObserver = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcDataChannelInterface>,
          Pointer<WebrtcDataChannelObserver>,
        ),
        void Function(
          Pointer<WebrtcDataChannelInterface>,
          Pointer<WebrtcDataChannelObserver>,
        )
      >('webrtc_DataChannelInterface_RegisterObserver');

  late final dataChannelUnregisterObserver = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcDataChannelInterface>),
        void Function(Pointer<WebrtcDataChannelInterface>)
      >('webrtc_DataChannelInterface_UnregisterObserver');

  late final dataChannelSend = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<WebrtcDataChannelInterface>,
          Pointer<Uint8>,
          Size,
          Int32,
        ),
        int Function(
          Pointer<WebrtcDataChannelInterface>,
          Pointer<Uint8>,
          int,
          int,
        )
      >('webrtc_DataChannelInterface_Send');

  // --- MediaStreamTrack ---
  // kind / id / enabled 操作を track 種別共通で扱う API。

  late final mediaStreamTrackRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcMediaStreamTrackInterface> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcMediaStreamTrackInterface> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamTrackInterface_refcounted_get');

  late final mediaStreamTrackRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcMediaStreamTrackInterface>),
        void Function(Pointer<WebrtcMediaStreamTrackInterface>)
      >('webrtc_MediaStreamTrackInterface_Release');

  late final mediaStreamTrackKind = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(
          Pointer<WebrtcMediaStreamTrackInterface>,
        ),
        Pointer<StdStringUnique> Function(
          Pointer<WebrtcMediaStreamTrackInterface>,
        )
      >('webrtc_MediaStreamTrackInterface_kind');

  late final mediaStreamTrackId = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(
          Pointer<WebrtcMediaStreamTrackInterface>,
        ),
        Pointer<StdStringUnique> Function(
          Pointer<WebrtcMediaStreamTrackInterface>,
        )
      >('webrtc_MediaStreamTrackInterface_id');

  late final mediaStreamTrackSetEnabled = _lib
      .lookupFunction<
        Int8 Function(Pointer<WebrtcMediaStreamTrackInterface>, Int8),
        int Function(Pointer<WebrtcMediaStreamTrackInterface>, int)
      >('webrtc_MediaStreamTrackInterface_set_enabled');

  late final mediaStreamTrackEnabled = _lib
      .lookupFunction<
        Int8 Function(Pointer<WebrtcMediaStreamTrackInterface>),
        int Function(Pointer<WebrtcMediaStreamTrackInterface>)
      >('webrtc_MediaStreamTrackInterface_enabled');

  // --- VideoTrack ---
  // video track 固有の sink 管理と型変換を扱う API。

  late final videoTrackRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcVideoTrackInterface> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcVideoTrackInterface> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        )
      >('webrtc_VideoTrackInterface_refcounted_get');

  late final videoTrackAddRef = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoTrackInterface>),
        void Function(Pointer<WebrtcVideoTrackInterface>)
      >('webrtc_VideoTrackInterface_AddRef');

  late final videoTrackRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoTrackInterface>),
        void Function(Pointer<WebrtcVideoTrackInterface>)
      >('webrtc_VideoTrackInterface_Release');

  late final videoTrackAddOrUpdateSink = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcVideoTrackInterface>,
          Pointer<WebrtcVideoSinkInterface>,
          Pointer<WebrtcVideoSinkWants>,
        ),
        void Function(
          Pointer<WebrtcVideoTrackInterface>,
          Pointer<WebrtcVideoSinkInterface>,
          Pointer<WebrtcVideoSinkWants>,
        )
      >('webrtc_VideoTrackInterface_AddOrUpdateSink');

  late final videoTrackRemoveSink = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcVideoTrackInterface>,
          Pointer<WebrtcVideoSinkInterface>,
        ),
        void Function(
          Pointer<WebrtcVideoTrackInterface>,
          Pointer<WebrtcVideoSinkInterface>,
        )
      >('webrtc_VideoTrackInterface_RemoveSink');

  late final mediaStreamTrackCastToVideoTrack = _lib
      .lookupFunction<
        Pointer<WebrtcVideoTrackInterfaceRefcounted> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcVideoTrackInterfaceRefcounted> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        )
      >(
        'webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_VideoTrackInterface',
      );

  late final mediaStreamTrackCastToAudioTrack = _lib
      .lookupFunction<
        Pointer<WebrtcAudioTrackInterfaceRefcounted> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcAudioTrackInterfaceRefcounted> Function(
          Pointer<WebrtcMediaStreamTrackInterfaceRefcounted>,
        )
      >(
        'webrtc_MediaStreamTrackInterface_refcounted_cast_to_webrtc_AudioTrackInterface',
      );

  // --- VideoSinkWants ---
  // sink が望む解像度・fps 条件を表す補助オブジェクト API。

  late final videoSinkWantsNew = _lib
      .lookupFunction<
        Pointer<WebrtcVideoSinkWants> Function(),
        Pointer<WebrtcVideoSinkWants> Function()
      >('webrtc_VideoSinkWants_new');

  late final videoSinkWantsDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoSinkWants>),
        void Function(Pointer<WebrtcVideoSinkWants>)
      >('webrtc_VideoSinkWants_delete');

  // --- VideoSinkInterface ---
  // callback 構造体から native `VideoSinkInterface` を生成する API。

  late final videoSinkInterfaceNew = _lib
      .lookupFunction<
        Pointer<WebrtcVideoSinkInterface> Function(
          Pointer<VideoSinkInterfaceCbs>,
          Pointer<Void>,
        ),
        Pointer<WebrtcVideoSinkInterface> Function(
          Pointer<VideoSinkInterfaceCbs>,
          Pointer<Void>,
        )
      >('webrtc_VideoSinkInterface_new');

  late final videoSinkInterfaceDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoSinkInterface>),
        void Function(Pointer<WebrtcVideoSinkInterface>)
      >('webrtc_VideoSinkInterface_delete');

  // --- RtpTransceiver ---
  // onTrack で渡される transceiver から receiver を辿る API。

  late final rtpTransceiverRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcRtpTransceiverInterface> Function(
          Pointer<WebrtcRtpTransceiverInterfaceRefcounted>,
        ),
        Pointer<WebrtcRtpTransceiverInterface> Function(
          Pointer<WebrtcRtpTransceiverInterfaceRefcounted>,
        )
      >('webrtc_RtpTransceiverInterface_refcounted_get');

  late final rtpTransceiverRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpTransceiverInterface>),
        void Function(Pointer<WebrtcRtpTransceiverInterface>)
      >('webrtc_RtpTransceiverInterface_Release');

  late final rtpTransceiverReceiver = _lib
      .lookupFunction<
        Pointer<WebrtcRtpReceiverInterfaceRefcounted> Function(
          Pointer<WebrtcRtpTransceiverInterface>,
        ),
        Pointer<WebrtcRtpReceiverInterfaceRefcounted> Function(
          Pointer<WebrtcRtpTransceiverInterface>,
        )
      >('webrtc_RtpTransceiverInterface_receiver');

  // --- RtpReceiver ---
  // receiver から track を取り出し、参照寿命を扱う API。

  late final rtpReceiverRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcRtpReceiverInterface> Function(
          Pointer<WebrtcRtpReceiverInterfaceRefcounted>,
        ),
        Pointer<WebrtcRtpReceiverInterface> Function(
          Pointer<WebrtcRtpReceiverInterfaceRefcounted>,
        )
      >('webrtc_RtpReceiverInterface_refcounted_get');

  late final rtpReceiverRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpReceiverInterface>),
        void Function(Pointer<WebrtcRtpReceiverInterface>)
      >('webrtc_RtpReceiverInterface_Release');

  late final rtpReceiverTrack = _lib
      .lookupFunction<
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcRtpReceiverInterface>,
        ),
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcRtpReceiverInterface>,
        )
      >('webrtc_RtpReceiverInterface_track');

  // --- RtpSender ---
  // sender の track 差し替えと RTP parameters 更新に使う API。

  late final rtpSenderRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcRtpSenderInterface> Function(
          Pointer<WebrtcRtpSenderInterfaceRefcounted>,
        ),
        Pointer<WebrtcRtpSenderInterface> Function(
          Pointer<WebrtcRtpSenderInterfaceRefcounted>,
        )
      >('webrtc_RtpSenderInterface_refcounted_get');

  late final rtpSenderRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpSenderInterface>),
        void Function(Pointer<WebrtcRtpSenderInterface>)
      >('webrtc_RtpSenderInterface_Release');

  late final rtpSenderAddRef = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpSenderInterface>),
        void Function(Pointer<WebrtcRtpSenderInterface>)
      >('webrtc_RtpSenderInterface_AddRef');

  late final rtpSenderGetParameters = _lib
      .lookupFunction<
        Pointer<WebrtcRtpParameters> Function(
          Pointer<WebrtcRtpSenderInterface>,
        ),
        Pointer<WebrtcRtpParameters> Function(Pointer<WebrtcRtpSenderInterface>)
      >('webrtc_RtpSenderInterface_GetParameters');

  late final rtpSenderSetParameters = _lib
      .lookupFunction<
        Pointer<WebrtcRTCErrorUnique> Function(
          Pointer<WebrtcRtpSenderInterface>,
          Pointer<WebrtcRtpParameters>,
        ),
        Pointer<WebrtcRTCErrorUnique> Function(
          Pointer<WebrtcRtpSenderInterface>,
          Pointer<WebrtcRtpParameters>,
        )
      >('webrtc_RtpSenderInterface_SetParameters');

  late final rtpSenderSetTrack = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<WebrtcRtpSenderInterface>,
          Pointer<WebrtcMediaStreamTrackInterface>,
        ),
        int Function(
          Pointer<WebrtcRtpSenderInterface>,
          Pointer<WebrtcMediaStreamTrackInterface>,
        )
      >('webrtc_RtpSenderInterface_SetTrack');

  // --- RtpParameters ---
  // sender 全体の RTP パラメータオブジェクトを構築・編集する API。

  late final rtpParametersNew = _lib
      .lookupFunction<
        Pointer<WebrtcRtpParameters> Function(),
        Pointer<WebrtcRtpParameters> Function()
      >('webrtc_RtpParameters_new');

  late final rtpParametersDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpParameters>),
        void Function(Pointer<WebrtcRtpParameters>)
      >('webrtc_RtpParameters_delete');

  late final rtpParametersGetEncodings = _lib
      .lookupFunction<
        Pointer<WebrtcRtpEncodingParametersVector> Function(
          Pointer<WebrtcRtpParameters>,
        ),
        Pointer<WebrtcRtpEncodingParametersVector> Function(
          Pointer<WebrtcRtpParameters>,
        )
      >('webrtc_RtpParameters_get_encodings');

  late final rtpParametersSetEncodings = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpParameters>,
          Pointer<WebrtcRtpEncodingParametersVector>,
        ),
        void Function(
          Pointer<WebrtcRtpParameters>,
          Pointer<WebrtcRtpEncodingParametersVector>,
        )
      >('webrtc_RtpParameters_set_encodings');

  // --- RtpEncodingParameters ---
  // simulcast 各層の rid / bitrate / framerate などを編集する API。

  late final rtpEncodingParametersNew = _lib
      .lookupFunction<
        Pointer<WebrtcRtpEncodingParameters> Function(),
        Pointer<WebrtcRtpEncodingParameters> Function()
      >('webrtc_RtpEncodingParameters_new');

  late final rtpEncodingParametersDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpEncodingParameters>),
        void Function(Pointer<WebrtcRtpEncodingParameters>)
      >('webrtc_RtpEncodingParameters_delete');

  late final rtpEncodingParametersSetRid = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Char>,
          Size,
        ),
        void Function(Pointer<WebrtcRtpEncodingParameters>, Pointer<Char>, int)
      >('webrtc_RtpEncodingParameters_set_rid');

  late final rtpEncodingParametersGetRid = _lib
      .lookupFunction<
        Pointer<StdString> Function(Pointer<WebrtcRtpEncodingParameters>),
        Pointer<StdString> Function(Pointer<WebrtcRtpEncodingParameters>)
      >('webrtc_RtpEncodingParameters_get_rid');

  late final rtpEncodingParametersGetActive = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcRtpEncodingParameters>),
        int Function(Pointer<WebrtcRtpEncodingParameters>)
      >('webrtc_RtpEncodingParameters_get_active');

  late final rtpEncodingParametersSetActive = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpEncodingParameters>, Int32),
        void Function(Pointer<WebrtcRtpEncodingParameters>, int)
      >('webrtc_RtpEncodingParameters_set_active');

  late final rtpEncodingParametersGetMaxBitrateBps = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Int32>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Int32>,
        )
      >('webrtc_RtpEncodingParameters_get_max_bitrate_bps');

  late final rtpEncodingParametersSetMaxBitrateBps = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Int32,
          Pointer<Int32>,
        ),
        void Function(Pointer<WebrtcRtpEncodingParameters>, int, Pointer<Int32>)
      >('webrtc_RtpEncodingParameters_set_max_bitrate_bps');

  late final rtpEncodingParametersGetMinBitrateBps = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Int32>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Int32>,
        )
      >('webrtc_RtpEncodingParameters_get_min_bitrate_bps');

  late final rtpEncodingParametersSetMinBitrateBps = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Int32,
          Pointer<Int32>,
        ),
        void Function(Pointer<WebrtcRtpEncodingParameters>, int, Pointer<Int32>)
      >('webrtc_RtpEncodingParameters_set_min_bitrate_bps');

  late final rtpEncodingParametersGetMaxFramerate = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Double>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Double>,
        )
      >('webrtc_RtpEncodingParameters_get_max_framerate');

  late final rtpEncodingParametersSetMaxFramerate = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Int32,
          Pointer<Double>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          int,
          Pointer<Double>,
        )
      >('webrtc_RtpEncodingParameters_set_max_framerate');

  late final rtpEncodingParametersGetScaleResolutionDownBy = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Double>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Double>,
        )
      >('webrtc_RtpEncodingParameters_get_scale_resolution_down_by');

  late final rtpEncodingParametersSetScaleResolutionDownBy = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Int32,
          Pointer<Double>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          int,
          Pointer<Double>,
        )
      >('webrtc_RtpEncodingParameters_set_scale_resolution_down_by');

  late final rtpEncodingParametersGetScalabilityMode = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Pointer<StdString>>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Pointer<Int32>,
          Pointer<Pointer<StdString>>,
        )
      >('webrtc_RtpEncodingParameters_get_scalability_mode');

  late final rtpEncodingParametersSetScalabilityMode = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          Int32,
          Pointer<Char>,
          Size,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParameters>,
          int,
          Pointer<Char>,
          int,
        )
      >('webrtc_RtpEncodingParameters_set_scalability_mode');

  // --- RtpEncodingParameters Vector ---
  // encoding parameters の vector を列挙・参照する API。

  late final rtpEncodingParametersVectorNew = _lib
      .lookupFunction<
        Pointer<WebrtcRtpEncodingParametersVector> Function(Int32),
        Pointer<WebrtcRtpEncodingParametersVector> Function(int)
      >('webrtc_RtpEncodingParameters_vector_new');

  late final rtpEncodingParametersVectorDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRtpEncodingParametersVector>),
        void Function(Pointer<WebrtcRtpEncodingParametersVector>)
      >('webrtc_RtpEncodingParameters_vector_delete');

  late final rtpEncodingParametersVectorSize = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcRtpEncodingParametersVector>),
        int Function(Pointer<WebrtcRtpEncodingParametersVector>)
      >('webrtc_RtpEncodingParameters_vector_size');

  late final rtpEncodingParametersVectorGet = _lib
      .lookupFunction<
        Pointer<WebrtcRtpEncodingParameters> Function(
          Pointer<WebrtcRtpEncodingParametersVector>,
          Int32,
        ),
        Pointer<WebrtcRtpEncodingParameters> Function(
          Pointer<WebrtcRtpEncodingParametersVector>,
          int,
        )
      >('webrtc_RtpEncodingParameters_vector_get');

  late final rtpEncodingParametersVectorPushBack = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcRtpEncodingParametersVector>,
          Pointer<WebrtcRtpEncodingParameters>,
        ),
        void Function(
          Pointer<WebrtcRtpEncodingParametersVector>,
          Pointer<WebrtcRtpEncodingParameters>,
        )
      >('webrtc_RtpEncodingParameters_vector_push_back');

  // --- AudioSource ---
  // local audio track 作成前の source を factory から得る API。

  late final pcFactoryCreateAudioSource = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<Pointer<WebrtcAudioSourceInterfaceRefcounted>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<Pointer<WebrtcAudioSourceInterfaceRefcounted>>,
        )
      >('webrtc_PeerConnectionFactoryInterface_CreateAudioSource');

  late final audioSourceRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioSourceInterface> Function(
          Pointer<WebrtcAudioSourceInterfaceRefcounted>,
        ),
        Pointer<WebrtcAudioSourceInterface> Function(
          Pointer<WebrtcAudioSourceInterfaceRefcounted>,
        )
      >('webrtc_AudioSourceInterface_refcounted_get');

  late final audioSourceRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioSourceInterface>),
        void Function(Pointer<WebrtcAudioSourceInterface>)
      >('webrtc_AudioSourceInterface_Release');

  // --- PushAudioDevice (Sora SDK 独自) ---
  // Dart 側から PCM データを注入可能なカスタム AudioDeviceModule。

  late final soraCreatePushAudioDevice = _lib
      .lookupFunction<
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function(),
        Pointer<WebrtcAudioDeviceModuleRefcounted> Function()
      >('sora_create_push_audio_device');

  late final soraPushAudioOnData = _lib
      .lookupFunction<
        Void Function(Pointer<Int16>, Int32, Int32, Int32),
        void Function(Pointer<Int16>, int, int, int)
      >('sora_push_audio_on_data');

  late final soraPullAudioData = _lib
      .lookupFunction<
        Int32 Function(Pointer<Int16>, Int32, Int32, Int32),
        int Function(Pointer<Int16>, int, int, int)
      >('sora_pull_audio_data');

  // --- AudioTrack ---
  // local audio track と local media stream を生成・操作する API。

  late final pcFactoryCreateAudioTrack = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcAudioSourceInterfaceRefcounted>,
          Pointer<Char>,
          Size,
          Pointer<Pointer<WebrtcAudioTrackInterfaceRefcounted>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcAudioSourceInterfaceRefcounted>,
          Pointer<Char>,
          int,
          Pointer<Pointer<WebrtcAudioTrackInterfaceRefcounted>>,
        )
      >('webrtc_PeerConnectionFactoryInterface_CreateAudioTrack');

  late final pcFactoryCreateLocalMediaStream = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<Char>,
          Size,
          Pointer<Pointer<WebrtcMediaStreamInterfaceRefcounted>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<Char>,
          int,
          Pointer<Pointer<WebrtcMediaStreamInterfaceRefcounted>>,
        )
      >('webrtc_PeerConnectionFactoryInterface_CreateLocalMediaStream');

  late final mediaStreamRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcMediaStreamInterface> Function(
          Pointer<WebrtcMediaStreamInterfaceRefcounted>,
        ),
        Pointer<WebrtcMediaStreamInterface> Function(
          Pointer<WebrtcMediaStreamInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamInterface_refcounted_get');

  late final mediaStreamRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcMediaStreamInterface>),
        void Function(Pointer<WebrtcMediaStreamInterface>)
      >('webrtc_MediaStreamInterface_Release');

  late final mediaStreamId = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(Pointer<WebrtcMediaStreamInterface>),
        Pointer<StdStringUnique> Function(Pointer<WebrtcMediaStreamInterface>)
      >('webrtc_MediaStreamInterface_id');

  late final mediaStreamGetAudioTracks = _lib
      .lookupFunction<
        Pointer<WebrtcAudioTrackInterfaceRefcountedVector> Function(
          Pointer<WebrtcMediaStreamInterface>,
        ),
        Pointer<WebrtcAudioTrackInterfaceRefcountedVector> Function(
          Pointer<WebrtcMediaStreamInterface>,
        )
      >('webrtc_MediaStreamInterface_GetAudioTracks');

  late final mediaStreamGetVideoTracks = _lib
      .lookupFunction<
        Pointer<WebrtcVideoTrackInterfaceRefcountedVector> Function(
          Pointer<WebrtcMediaStreamInterface>,
        ),
        Pointer<WebrtcVideoTrackInterfaceRefcountedVector> Function(
          Pointer<WebrtcMediaStreamInterface>,
        )
      >('webrtc_MediaStreamInterface_GetVideoTracks');

  late final mediaStreamAddTrackWithAudioTrack = _lib
      .lookupFunction<
        Int8 Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        ),
        int Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamInterface_AddTrackWithAudioTrack');

  late final mediaStreamAddTrackWithVideoTrack = _lib
      .lookupFunction<
        Int8 Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        ),
        int Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamInterface_AddTrackWithVideoTrack');

  late final mediaStreamRemoveTrackWithAudioTrack = _lib
      .lookupFunction<
        Int8 Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        ),
        int Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamInterface_RemoveTrackWithAudioTrack');

  late final mediaStreamRemoveTrackWithVideoTrack = _lib
      .lookupFunction<
        Int8 Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        ),
        int Function(
          Pointer<WebrtcMediaStreamInterface>,
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        )
      >('webrtc_MediaStreamInterface_RemoveTrackWithVideoTrack');

  late final audioTrackRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioTrackInterface> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcAudioTrackInterface> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        )
      >('webrtc_AudioTrackInterface_refcounted_get');

  late final audioTrackAddRef = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioTrackInterface>),
        void Function(Pointer<WebrtcAudioTrackInterface>)
      >('webrtc_AudioTrackInterface_AddRef');

  late final audioTrackRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioTrackInterface>),
        void Function(Pointer<WebrtcAudioTrackInterface>)
      >('webrtc_AudioTrackInterface_Release');

  late final audioTrackCastToMediaStreamTrack = _lib
      .lookupFunction<
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcounted>,
        )
      >(
        'webrtc_AudioTrackInterface_refcounted_cast_to_webrtc_MediaStreamTrackInterface',
      );

  late final audioTrackRefcountedVectorDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAudioTrackInterfaceRefcountedVector>),
        void Function(Pointer<WebrtcAudioTrackInterfaceRefcountedVector>)
      >('webrtc_AudioTrackInterface_refcounted_vector_delete');

  late final audioTrackRefcountedVectorGet = _lib
      .lookupFunction<
        Pointer<WebrtcAudioTrackInterfaceRefcounted> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcountedVector>,
          Int32,
        ),
        Pointer<WebrtcAudioTrackInterfaceRefcounted> Function(
          Pointer<WebrtcAudioTrackInterfaceRefcountedVector>,
          int,
        )
      >('webrtc_AudioTrackInterface_refcounted_vector_get');

  late final audioTrackRefcountedVectorSize = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcAudioTrackInterfaceRefcountedVector>),
        int Function(Pointer<WebrtcAudioTrackInterfaceRefcountedVector>)
      >('webrtc_AudioTrackInterface_refcounted_vector_size');

  // --- VideoTrack (factory) ---
  // local video track 生成と track vector 列挙を行う API。

  late final pcFactoryCreateVideoTrack = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcVideoTrackSourceInterfaceRefcounted>,
          Pointer<Char>,
          Size,
          Pointer<Pointer<WebrtcVideoTrackInterfaceRefcounted>>,
        ),
        void Function(
          Pointer<WebrtcPeerConnectionFactoryInterface>,
          Pointer<WebrtcVideoTrackSourceInterfaceRefcounted>,
          Pointer<Char>,
          int,
          Pointer<Pointer<WebrtcVideoTrackInterfaceRefcounted>>,
        )
      >('webrtc_PeerConnectionFactoryInterface_CreateVideoTrack');

  late final videoTrackCastToMediaStreamTrack = _lib
      .lookupFunction<
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        ),
        Pointer<WebrtcMediaStreamTrackInterfaceRefcounted> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcounted>,
        )
      >(
        'webrtc_VideoTrackInterface_refcounted_cast_to_webrtc_MediaStreamTrackInterface',
      );

  late final videoTrackRefcountedVectorDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoTrackInterfaceRefcountedVector>),
        void Function(Pointer<WebrtcVideoTrackInterfaceRefcountedVector>)
      >('webrtc_VideoTrackInterface_refcounted_vector_delete');

  late final videoTrackRefcountedVectorGet = _lib
      .lookupFunction<
        Pointer<WebrtcVideoTrackInterfaceRefcounted> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcountedVector>,
          Int32,
        ),
        Pointer<WebrtcVideoTrackInterfaceRefcounted> Function(
          Pointer<WebrtcVideoTrackInterfaceRefcountedVector>,
          int,
        )
      >('webrtc_VideoTrackInterface_refcounted_vector_get');

  late final videoTrackRefcountedVectorSize = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcVideoTrackInterfaceRefcountedVector>),
        int Function(Pointer<WebrtcVideoTrackInterfaceRefcountedVector>)
      >('webrtc_VideoTrackInterface_refcounted_vector_size');

  // --- AdaptedVideoTrackSource ---
  // external video input の adapt 判定と frame 投入を行う API。

  late final adaptedVideoTrackSourceCreate = _lib
      .lookupFunction<
        Pointer<WebrtcAdaptedVideoTrackSourceRefcounted> Function(),
        Pointer<WebrtcAdaptedVideoTrackSourceRefcounted> Function()
      >('webrtc_AdaptedVideoTrackSource_Create');

  late final adaptedVideoTrackSourceRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcAdaptedVideoTrackSource> Function(
          Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>,
        ),
        Pointer<WebrtcAdaptedVideoTrackSource> Function(
          Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>,
        )
      >('webrtc_AdaptedVideoTrackSource_refcounted_get');

  late final adaptedVideoTrackSourceRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcAdaptedVideoTrackSource>),
        void Function(Pointer<WebrtcAdaptedVideoTrackSource>)
      >('webrtc_AdaptedVideoTrackSource_Release');

  late final adaptedVideoTrackSourceCastToVideoTrackSource = _lib
      .lookupFunction<
        Pointer<WebrtcVideoTrackSourceInterfaceRefcounted> Function(
          Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>,
        ),
        Pointer<WebrtcVideoTrackSourceInterfaceRefcounted> Function(
          Pointer<WebrtcAdaptedVideoTrackSourceRefcounted>,
        )
      >(
        'webrtc_AdaptedVideoTrackSource_refcounted_cast_to_webrtc_VideoTrackSourceInterface',
      );

  late final adaptedVideoTrackSourceAdaptFrame = _lib
      .lookupFunction<
        Int32 Function(
          Pointer<WebrtcAdaptedVideoTrackSource>,
          Int32,
          Int32,
          Int64,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
        ),
        int Function(
          Pointer<WebrtcAdaptedVideoTrackSource>,
          int,
          int,
          int,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
          Pointer<Int32>,
        )
      >('webrtc_AdaptedVideoTrackSource_AdaptFrame');

  late final adaptedVideoTrackSourceOnFrame = _lib
      .lookupFunction<
        Void Function(
          Pointer<WebrtcAdaptedVideoTrackSource>,
          Pointer<WebrtcVideoFrame>,
        ),
        void Function(
          Pointer<WebrtcAdaptedVideoTrackSource>,
          Pointer<WebrtcVideoFrame>,
        )
      >('webrtc_AdaptedVideoTrackSource_OnFrame');

  // --- I420Buffer ---
  // I420 プレーンバッファの生成・参照・スケーリング API。

  late final i420BufferCreate = _lib
      .lookupFunction<
        Pointer<WebrtcI420BufferRefcounted> Function(Int32, Int32),
        Pointer<WebrtcI420BufferRefcounted> Function(int, int)
      >('webrtc_I420Buffer_Create');

  late final i420BufferRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcI420Buffer> Function(Pointer<WebrtcI420BufferRefcounted>),
        Pointer<WebrtcI420Buffer> Function(Pointer<WebrtcI420BufferRefcounted>)
      >('webrtc_I420Buffer_refcounted_get');

  late final i420BufferRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcI420Buffer>),
        void Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_Release');

  late final i420BufferWidth = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcI420Buffer>),
        int Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_width');

  late final i420BufferHeight = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcI420Buffer>),
        int Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_height');

  late final i420BufferMutableDataY = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>),
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_MutableDataY');

  late final i420BufferMutableDataU = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>),
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_MutableDataU');

  late final i420BufferMutableDataV = _lib
      .lookupFunction<
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>),
        Pointer<Uint8> Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_MutableDataV');

  late final i420BufferStrideY = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcI420Buffer>),
        int Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_StrideY');

  late final i420BufferStrideU = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcI420Buffer>),
        int Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_StrideU');

  late final i420BufferStrideV = _lib
      .lookupFunction<
        Int32 Function(Pointer<WebrtcI420Buffer>),
        int Function(Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_StrideV');

  late final i420BufferScaleFrom = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcI420Buffer>, Pointer<WebrtcI420Buffer>),
        void Function(Pointer<WebrtcI420Buffer>, Pointer<WebrtcI420Buffer>)
      >('webrtc_I420Buffer_ScaleFrom');

  // --- VideoFrame ---
  // I420Buffer から VideoFrame を組み立てて sink/source へ渡す API。

  late final videoFrameUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcVideoFrame> Function(Pointer<WebrtcVideoFrameUnique>),
        Pointer<WebrtcVideoFrame> Function(Pointer<WebrtcVideoFrameUnique>)
      >('webrtc_VideoFrame_unique_get');

  late final videoFrameUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcVideoFrameUnique>),
        void Function(Pointer<WebrtcVideoFrameUnique>)
      >('webrtc_VideoFrame_unique_delete');

  late final videoFrameVideoFrameBuffer = _lib
      .lookupFunction<
        Pointer<WebrtcI420BufferRefcounted> Function(Pointer<WebrtcVideoFrame>),
        Pointer<WebrtcI420BufferRefcounted> Function(Pointer<WebrtcVideoFrame>)
      >('webrtc_VideoFrame_video_frame_buffer');

  late final soraVideoFrameCreate = _lib
      .lookupFunction<
        Pointer<SoraVideoFrameUnique> Function(
          Pointer<WebrtcI420BufferRefcounted>,
          Int32,
          Int64,
          Uint32,
        ),
        Pointer<SoraVideoFrameUnique> Function(
          Pointer<WebrtcI420BufferRefcounted>,
          int,
          int,
          int,
        )
      >('sora_video_frame_create');

  late final soraVideoFrameUniqueGet = _lib
      .lookupFunction<
        Pointer<WebrtcVideoFrame> Function(Pointer<SoraVideoFrameUnique>),
        Pointer<WebrtcVideoFrame> Function(Pointer<SoraVideoFrameUnique>)
      >('sora_video_frame_unique_get');

  late final soraVideoFrameUniqueDelete = _lib
      .lookupFunction<
        Void Function(Pointer<SoraVideoFrameUnique>),
        void Function(Pointer<SoraVideoFrameUnique>)
      >('sora_video_frame_unique_delete');

  // --- RTCStatsReport ---
  // `RTCStatsReport` を JSON 化して Dart へ返す API。

  late final rtcStatsReportRefcountedGet = _lib
      .lookupFunction<
        Pointer<WebrtcRTCStatsReport> Function(
          Pointer<WebrtcRTCStatsReportRefcounted>,
        ),
        Pointer<WebrtcRTCStatsReport> Function(
          Pointer<WebrtcRTCStatsReportRefcounted>,
        )
      >('webrtc_RTCStatsReport_refcounted_get');

  late final rtcStatsReportToJson = _lib
      .lookupFunction<
        Pointer<StdStringUnique> Function(Pointer<WebrtcRTCStatsReport>),
        Pointer<StdStringUnique> Function(Pointer<WebrtcRTCStatsReport>)
      >('webrtc_RTCStatsReport_ToJson');

  late final rtcStatsReportRelease = _lib
      .lookupFunction<
        Void Function(Pointer<WebrtcRTCStatsReport>),
        void Function(Pointer<WebrtcRTCStatsReport>)
      >('webrtc_RTCStatsReport_Release');

  // --- C コールバックブリッジ ---
  // WebRTC スレッド上の observer callback を安全なデータへ変換して
  // Dart 側 `NativeCallable.listener` へ中継する Sora 独自 bridge API。

  late final soraObserverBridgeCreate = _lib
      .lookupFunction<
        Pointer<SoraObserverBridge> Function(
          Pointer<
            NativeFunction<Void Function(Int32, Pointer<Void>)>
          >, // on_connection_change
          Pointer<
            NativeFunction<Void Function(Int32, Pointer<Void>)>
          >, // on_ice_connection_change
          Pointer<
            NativeFunction<Void Function(Int32, Pointer<Void>)>
          >, // on_ice_gathering_change
          Pointer<
            NativeFunction<
              Void Function(Pointer<Char>, Pointer<Char>, Int32, Pointer<Void>)
            >
          >, // on_ice_candidate
          Pointer<
            NativeFunction<
              Void Function(
                Pointer<Void>,
                Pointer<Char>,
                Pointer<Char>,
                Pointer<Void>,
              )
            >
          >, // on_track
          Pointer<
            NativeFunction<
              Void Function(
                Pointer<Void>,
                Pointer<Char>,
                Pointer<Char>,
                Pointer<Void>,
              )
            >
          >, // on_remove_track
          Pointer<
            NativeFunction<
              Void Function(Pointer<Void>, Pointer<Char>, Pointer<Void>)
            >
          >, // on_datachannel
          Pointer<
            NativeFunction<Void Function(Pointer<Char>, Pointer<Void>)>
          >, // on_debug
          Pointer<Void>, // dart_user_data
        ),
        Pointer<SoraObserverBridge> Function(
          Pointer<NativeFunction<Void Function(Int32, Pointer<Void>)>>,
          Pointer<NativeFunction<Void Function(Int32, Pointer<Void>)>>,
          Pointer<NativeFunction<Void Function(Int32, Pointer<Void>)>>,
          Pointer<
            NativeFunction<
              Void Function(Pointer<Char>, Pointer<Char>, Int32, Pointer<Void>)
            >
          >,
          Pointer<
            NativeFunction<
              Void Function(
                Pointer<Void>,
                Pointer<Char>,
                Pointer<Char>,
                Pointer<Void>,
              )
            >
          >,
          Pointer<
            NativeFunction<
              Void Function(
                Pointer<Void>,
                Pointer<Char>,
                Pointer<Char>,
                Pointer<Void>,
              )
            >
          >,
          Pointer<
            NativeFunction<
              Void Function(Pointer<Void>, Pointer<Char>, Pointer<Void>)
            >
          >,
          Pointer<NativeFunction<Void Function(Pointer<Char>, Pointer<Void>)>>,
          Pointer<Void>,
        )
      >('sora_observer_bridge_create');

  late final soraObserverBridgeGetObserver = _lib
      .lookupFunction<
        Pointer<WebrtcPeerConnectionObserver> Function(
          Pointer<SoraObserverBridge>,
        ),
        Pointer<WebrtcPeerConnectionObserver> Function(
          Pointer<SoraObserverBridge>,
        )
      >('sora_observer_bridge_get_observer');

  late final soraObserverBridgeDestroy = _lib
      .lookupFunction<
        Void Function(Pointer<SoraObserverBridge>),
        void Function(Pointer<SoraObserverBridge>)
      >('sora_observer_bridge_destroy');

  late final soraObserverBridgeSetupDc = _lib
      .lookupFunction<
        Pointer<Void> Function(
          Pointer<SoraObserverBridge>,
          Pointer<WebrtcDataChannelInterface>,
          Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
          Pointer<
            NativeFunction<
              Void Function(Pointer<Uint8>, Int32, Int32, Pointer<Void>)
            >
          >,
          Pointer<Void>,
        ),
        Pointer<Void> Function(
          Pointer<SoraObserverBridge>,
          Pointer<WebrtcDataChannelInterface>,
          Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
          Pointer<
            NativeFunction<
              Void Function(Pointer<Uint8>, Int32, Int32, Pointer<Void>)
            >
          >,
          Pointer<Void>,
        )
      >('sora_observer_bridge_setup_dc');

  late final soraObserverBridgeDestroyDc = _lib
      .lookupFunction<
        Void Function(Pointer<Void>, Pointer<WebrtcDataChannelInterface>),
        void Function(Pointer<Void>, Pointer<WebrtcDataChannelInterface>)
      >('sora_observer_bridge_destroy_dc');
}

// ---------------------------------------------------------------------------
// 定数 (extern const int をライブラリから読み取る)
// ---------------------------------------------------------------------------

// ライブラリのランタイム定数を保持する
class WebrtcConstants {
  final DynamicLibrary _lib;

  // extern const int 相当の値をランタイムから読む定数ビューを作る。
  //
  // プラットフォームごとの差分を C 側へ閉じ込め、Dart 側では
  // 数値リテラルを持たずに比較できるようにする。
  WebrtcConstants(this._lib);

  // 指定した extern 定数名を `Int32` として読み出す共通ヘルパー。
  int _lookup(String name) => _lib.lookup<Int32>(name).value;

  // AudioDeviceModule タイプ
  late final int kPlatformDefaultAudio = _lookup(
    'webrtc_AudioDeviceModule_kPlatformDefaultAudio',
  );
  late final int kLinuxPulseAudio = _lookup(
    'webrtc_AudioDeviceModule_kLinuxPulseAudio',
  );
  late final int kLinuxAlsaAudio = _lookup(
    'webrtc_AudioDeviceModule_kLinuxAlsaAudio',
  );
  late final int kDummyAudio = _lookup('webrtc_AudioDeviceModule_kDummyAudio');

  // SSL プロトコル
  late final int sslProtocolDtls12 = _lookup('webrtc_SSL_PROTOCOL_DTLS_12');

  // SDP Semantics
  late final int sdpSemanticsUnifiedPlan = _lookup(
    'webrtc_PeerConnectionInterface_SdpSemantics_kUnifiedPlan',
  );

  // ICE Transport Types
  late final int iceTransportsTypeRelay = _lookup(
    'webrtc_PeerConnectionInterface_IceTransportsType_kRelay',
  );

  // SDP Type
  late final int sdpTypeOffer = _lookup('webrtc_SdpType_kOffer');
  late final int sdpTypeAnswer = _lookup('webrtc_SdpType_kAnswer');

  // VideoRotation
  late final int videoRotation0 = _lookup('webrtc_VideoRotation_0');

  // PeerConnectionState
  late final int pcStateNew = _lookup(
    'webrtc_PeerConnectionInterface_PeerConnectionState_kNew',
  );
  late final int pcStateConnecting = _lookup(
    'webrtc_PeerConnectionInterface_PeerConnectionState_kConnecting',
  );
  late final int pcStateConnected = _lookup(
    'webrtc_PeerConnectionInterface_PeerConnectionState_kConnected',
  );
  late final int pcStateFailed = _lookup(
    'webrtc_PeerConnectionInterface_PeerConnectionState_kFailed',
  );
  late final int pcStateClosed = _lookup(
    'webrtc_PeerConnectionInterface_PeerConnectionState_kClosed',
  );

  // DataChannel DataState
  late final int dcStateConnecting = _lookup(
    'webrtc_DataChannelInterface_DataState_kConnecting',
  );
  late final int dcStateOpen = _lookup(
    'webrtc_DataChannelInterface_DataState_kOpen',
  );
  late final int dcStateClosing = _lookup(
    'webrtc_DataChannelInterface_DataState_kClosing',
  );
  late final int dcStateClosed = _lookup(
    'webrtc_DataChannelInterface_DataState_kClosed',
  );
}
