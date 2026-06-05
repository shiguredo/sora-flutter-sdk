import 'package:meta/meta.dart';

/// RPC オプション
@immutable
class SoraRpcOptions {
  /// @nodoc
  const SoraRpcOptions({this.timeout, this.notification = false});

  /// タイムアウト (ミリ秒、null の場合はタイムアウトなし)
  final int? timeout;

  /// 通知モード (レスポンス不要)
  final bool notification;
}

/// RPC エラー
class SoraRpcError implements Exception {
  /// @nodoc
  const SoraRpcError({required this.code, required this.message, this.data});

  /// エラーコード。
  final int code;

  /// エラーメッセージ。
  final String message;

  /// エラーに付随する任意のデータ。
  final Object? data;

  @override
  String toString() => 'SoraRpcError(code=$code, message=$message)';
}
