import 'sora_connection.dart';
import 'sora_connection_config.dart';

/// Sora SDK のエントリポイント
abstract final class Sora {
  const Sora._();

  /// SoraConnection インスタンスを作成する
  static Future<SoraConnection> createConnection(SoraConnectionConfig config) =>
      SoraConnection.internalCreate(config);
}
