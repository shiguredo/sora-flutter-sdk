import 'sora_connection_state.dart';
import 'sora_data_channel_event.dart';
import 'sora_data_channel_message.dart';
import 'sora_remote_track.dart';
import 'sora_signaling_event.dart';

/// `SoraConnection.events` で購読する統合イベントの基底型
///
/// 利用者が順序付きで観測したいドメインイベントをこのクラスのサブクラスとして定義する。
///
/// `localVideo` については texture 準備を伴う非同期通知であり、
/// 順序付きイベント列とは責務が異なるため含めていない。
sealed class SoraConnectionEvent {
  /// @nodoc
  const SoraConnectionEvent();
}

/// 接続状態イベント
final class SoraConnectionStateChangedEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraConnectionStateChangedEvent(this.state);

  /// 遷移後の接続状態。
  final SoraConnectionState state;
}

/// 接続エラーイベント
final class SoraConnectionErrorEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraConnectionErrorEvent({
    this.code,
    this.message,
    this.retriable,
    this.details,
  });

  /// エラーコード (SoraErrorCode 定数値)。
  final String? code;

  /// エラーメッセージ。
  final String? message;

  /// リトライ可能かどうか。
  ///
  /// 接続の再試行で回復できるエラー (capture backend の開始失敗など) は
  /// true、再接続しても回復しないエラー (キャプチャ実行中のウィンドウ消失
  /// など) は false になる。
  final bool? retriable;

  /// エラーの詳細情報。
  final SoraConnectionErrorDetails? details;
}

/// 接続エラーの詳細情報
final class SoraConnectionErrorDetails {
  /// @nodoc
  const SoraConnectionErrorDetails({this.attempts, this.platformError});

  /// リトライ試行回数。
  final int? attempts;

  /// プラットフォーム固有のエラー情報。
  final String? platformError;
}

/// notify メッセージイベント
final class SoraNotifyEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraNotifyEvent(this.message);

  /// 受信した notify メッセージ。
  final Map<String, Object?> message;
}

/// push メッセージイベント
final class SoraPushEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraPushEvent(this.message);

  /// 受信した push メッセージ。
  final Map<String, Object?> message;
}

/// switched メッセージイベント
final class SoraSwitchedEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraSwitchedEvent(this.message);

  /// 受信した switched メッセージ。
  final Map<String, Object?> message;
}

/// signaling メッセージイベント
final class SoraSignalingMessageEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraSignalingMessageEvent(this.event);

  /// シグナリングイベントの詳細。
  final SoraSignalingEvent event;
}

/// DataChannel open イベント
final class SoraDataChannelOpenEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraDataChannelOpenEvent(this.event);

  /// オープンした DataChannel の情報。
  final SoraDataChannelEvent event;
}

/// DataChannel メッセージイベント
final class SoraDataChannelMessageEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraDataChannelMessageEvent(this.message);

  /// 受信した DataChannel メッセージ。
  final SoraDataChannelMessage message;
}

/// remote track 追加イベント
final class SoraTrackEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraTrackEvent(this.track);

  /// 追加されたリモートメディアトラック。
  final RemoteMediaStreamTrack track;
}

/// remote track 削除イベント
final class SoraRemoveTrackEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraRemoveTrackEvent(this.track);

  /// 削除されたリモートメディアトラック。
  final RemoteMediaStreamTrack track;
}

/// timeout イベント
final class SoraTimeoutEvent extends SoraConnectionEvent {
  /// @nodoc
  const SoraTimeoutEvent();
}
