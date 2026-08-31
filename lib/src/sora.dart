import 'ffi/webrtc_client.dart';
import 'sora_codec_type.dart';
import 'sora_connection.dart';
import 'sora_connection_config.dart';

/// Sora SDK のエントリポイント
abstract final class Sora {
  const Sora._();

  /// SoraConnection インスタンスを作成する
  static Future<SoraConnection> createConnection(SoraConnectionConfig config) =>
      SoraConnection.internalCreate(config);

  /// プラットフォームのビデオデコーダがサポートする [VideoCodecType] の一覧。
  ///
  /// 実際にハードウェア / ソフトウェアデコードが可能なコーデックのみが含まれる。
  static List<VideoCodecType> get supportedVideoCodecTypes =>
      WebrtcClient.supportedVideoCodecTypes;
}
