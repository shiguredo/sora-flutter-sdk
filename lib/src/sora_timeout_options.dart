import 'package:meta/meta.dart';

/// WebRTC 接続のライフサイクル各段階のタイムアウト設定
@immutable
class SoraTimeoutOptions {
  /// @nodoc
  const SoraTimeoutOptions({
    this.connectionTimeout = const Duration(seconds: 30),
    this.disconnectWaitTimeout = const Duration(seconds: 10),
    this.signalingCandidateTimeout = const Duration(seconds: 5),
  });

  /// WebRTC 接続確立までの制限時間
  ///
  /// WebSocket 接続から PeerConnection の接続完了まで
  /// この時間内に接続が確立されない場合、接続処理は中止される
  /// デフォルト値: 30 秒
  final Duration connectionTimeout;

  /// 切断処理待機中の制限時間
  ///
  /// disconnect() メソッド実行時にリソース解放が完了するまでの制限時間
  /// この時間を超過した場合は強制的にリソースを解放する
  /// デフォルト値: 10 秒
  final Duration disconnectWaitTimeout;

  /// シグナリング候補 URL 接続タイムアウト
  ///
  /// WebSocket (シグナリング) への接続確立までの制限時間
  /// この時間内に接続が確立されない場合は接続を中止する
  /// デフォルト値: 5 秒
  final Duration signalingCandidateTimeout;
}
