import 'package:meta/meta.dart';

import 'sora_media_stream_track_base.dart';
import 'sora_remote_track.dart';

/// リモートの MediaStream（connectionId でグルーピング）
///
/// 1 つのリモート接続あたり 1 つの `RemoteMediaStream` が作られ、
/// audio トラックと video トラックを保持する。
/// audio と video は到着タイミングが異なるため、最初は片方だけの状態がありうる。
///
/// `SoraConnection.remoteMediaStreams` から取得し、
/// `connectionId` / `audioTrack` / `videoTrack` を read-only で参照することができる。
/// track の追加・削除は SDK 内部で自動的に行われ、利用者が書き換えることはできない。
abstract interface class RemoteMediaStream implements MediaStream {
  /// 接続 ID
  String get connectionId;

  /// 音声トラック（到着前は null）
  RemoteMediaStreamTrack? get audioTrack;

  /// 映像トラック（到着前は null）
  RemoteMediaStreamTrack? get videoTrack;
}

/// `SoraConnection` が内部で保持する writable な `RemoteMediaStream` 実装。
///
/// トラック到着時に `setAudioTrack` / `setVideoTrack` で更新され、
/// 接続ごとにインスタンスが固定されるため、track 差し替え時も Dart オブジェクトの同一性と `connectionId` は変わらない。
@internal
final class MutableRemoteMediaStream implements RemoteMediaStream {
  MutableRemoteMediaStream({required this.connectionId});

  @override
  final String connectionId;

  RemoteMediaStreamTrack? _audioTrack;
  RemoteMediaStreamTrack? _videoTrack;

  @override
  String get id => connectionId;

  @override
  RemoteMediaStreamTrack? get audioTrack => _audioTrack;

  @override
  RemoteMediaStreamTrack? get videoTrack => _videoTrack;

  @internal
  void setAudioTrack(RemoteMediaStreamTrack? track) {
    _audioTrack = track;
  }

  @internal
  void setVideoTrack(RemoteMediaStreamTrack? track) {
    _videoTrack = track;
  }

  // W3C Media Capture and Streams の `MediaStream.getTracks()` と
  // 名前をそろえるため、`get` をあえて残している。
  @override
  List<MediaStreamTrack> getTracks() {
    final audio = _audioTrack;
    final video = _videoTrack;
    final tracks = <MediaStreamTrack>[];
    if (audio != null) {
      tracks.add(audio);
    }
    if (video != null) {
      tracks.add(video);
    }
    return tracks;
  }
}
