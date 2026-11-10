// ignore_for_file: public_member_api_docs
import 'sora_log_event.dart';
import 'sora_timeline_event.dart';

/// `SoraConnection.debugEvents` で購読する debug event の基底型
///
/// `SoraConnectionEvent` と異なり、利用者が順序付きで観測するドメインイベントではなく、
/// SDK 内部の診断目的で発行されるイベントを表す。
sealed class SoraDebugEvent {
  /// @nodoc
  const SoraDebugEvent();
}

/// log イベント
final class SoraLogDebugEvent extends SoraDebugEvent {
  /// @nodoc
  const SoraLogDebugEvent(this.event);

  final SoraLogEvent event;
}

/// timeline イベント
final class SoraTimelineDebugEvent extends SoraDebugEvent {
  /// @nodoc
  const SoraTimelineDebugEvent(this.event);

  final SoraTimelineEvent event;
}
