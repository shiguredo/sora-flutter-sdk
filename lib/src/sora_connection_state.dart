import 'package:meta/meta.dart';

/// 接続状態を表す sealed クラス。
///
/// サブクラス: `SoraConnectingState`、`SoraConnectedState`、`SoraDisconnectedState`。
sealed class SoraConnectionState {
  /// @nodoc
  const SoraConnectionState();
}

/// 接続処理の開始後、シグナリング接続の確立に入った状態
final class SoraConnectingState extends SoraConnectionState {
  /// @nodoc
  const SoraConnectingState();
}

/// 接続が確立した状態
final class SoraConnectedState extends SoraConnectionState {
  /// @nodoc
  const SoraConnectedState();
}

/// 切断された状態
///
/// `closeInfo` には取得できた切断コードと理由を保持する。
final class SoraDisconnectedState extends SoraConnectionState {
  /// @nodoc
  const SoraDisconnectedState({this.closeInfo});

  /// 切断時の closeInfo。取得できなかった場合は null。
  final SoraDisconnectCloseInfo? closeInfo;
}

/// 切断時の close code / reason を保持する情報
@immutable
class SoraDisconnectCloseInfo {
  /// @nodoc
  const SoraDisconnectCloseInfo({required this.code, this.reason});

  /// WebSocket close frame のコード、または signaling close の切断コード。
  final int code;

  /// 切断理由文字列。取得できなかった場合は null。
  final String? reason;
}
