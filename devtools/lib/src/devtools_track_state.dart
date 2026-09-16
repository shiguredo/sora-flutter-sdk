import 'package:sora_sdk/sora_sdk.dart';

// track の enabled 値から UI 表示値を決定する。
// SDK 型に依存しないため、境界値は実値だけで検証できる。
bool currentTrackEnabled(
  Iterable<bool>? trackEnabledValues, {
  required bool fallback,
}) {
  final iterator = trackEnabledValues?.iterator;
  if (iterator == null || !iterator.moveNext()) {
    return fallback;
  }
  return iterator.current;
}

// local stream の audio track 状態を UI 表示用に取得する。
bool currentAudioTrackEnabled(
  LocalMediaStream? localStream, {
  required bool fallback,
}) {
  return currentTrackEnabled(
    localStream?.getAudioTracks().map((track) => track.enabled),
    fallback: fallback,
  );
}

// local stream の video track 状態を UI 表示用に取得する。
bool currentVideoTrackEnabled(
  LocalMediaStream? localStream, {
  required bool fallback,
}) {
  return currentTrackEnabled(
    localStream?.getVideoTracks().map((track) => track.enabled),
    fallback: fallback,
  );
}
