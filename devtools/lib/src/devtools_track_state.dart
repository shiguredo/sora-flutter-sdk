import 'package:sora_sdk/sora_sdk.dart';

// local stream の audio track 状態を UI 表示用に取得する。
bool currentAudioTrackEnabled(
  LocalMediaStream? localStream, {
  required bool fallback,
}) {
  final tracks = localStream?.getAudioTracks();
  if (tracks == null || tracks.isEmpty) {
    return fallback;
  }
  return tracks.first.enabled;
}

// local stream の video track 状態を UI 表示用に取得する。
bool currentVideoTrackEnabled(
  LocalMediaStream? localStream, {
  required bool fallback,
}) {
  final tracks = localStream?.getVideoTracks();
  if (tracks == null || tracks.isEmpty) {
    return fallback;
  }
  return tracks.first.enabled;
}
