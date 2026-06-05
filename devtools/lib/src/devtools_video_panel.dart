/// DevTools 画面の映像表示パネルを提供するモジュール。
///
/// Remote video / audio の一覧表示と local preview の描画をまとめ、
/// `main.dart` から受け取った状態に応じて表示内容を切り替える。
library;

import 'package:flutter/material.dart';
import 'package:sora_sdk/sora_sdk.dart';

import 'devtools_models.dart';

class DevToolsVideoPanel extends StatelessWidget {
  // 映像表示パネルを構築する。
  const DevToolsVideoPanel({
    super.key,
    required this.showsRemoteVideo,
    required this.showsLocalPreview,
    required this.needsCamera,
    required this.localTextureId,
    required this.remoteVideos,
    required this.remoteAudios,
    required this.remoteClients,
    required this.selectedResolution,
  });

  final bool showsRemoteVideo;
  final bool showsLocalPreview;
  final bool needsCamera;
  final int? localTextureId;
  final List<RemoteMediaStreamTrack> remoteVideos;
  final List<RemoteMediaStreamTrack> remoteAudios;
  final List<DevToolsRemoteClientInfo> remoteClients;
  final DevToolsVideoInputResolutionOption? selectedResolution;

  @override
  /// Remote 映像一覧と local preview を縦並びで描画する。
  Widget build(BuildContext context) {
    if ((!showsLocalPreview && !showsRemoteVideo) ||
        (localTextureId == null &&
            remoteVideos.isEmpty &&
            remoteAudios.isEmpty)) {
      return const Center(child: Text('No video'));
    }

    final remoteVideoGroups = _groupRemoteVideosByConnection();
    final remoteAudioOnlyGroups = _groupRemoteAudioOnlyByConnection();
    final itemCount = _videoListItemCount(
      remoteVideoGroups: remoteVideoGroups,
      remoteAudioOnlyGroups: remoteAudioOnlyGroups,
    );

    return ListView.builder(
      itemCount: itemCount,
      itemBuilder: (context, index) {
        final remoteVideoCount = showsRemoteVideo
            ? remoteVideoGroups.length
            : 0;
        if (showsRemoteVideo && index < remoteVideoCount) {
          return _buildRemoteVideoGroup(remoteVideoGroups[index]);
        }

        final audioIndex = index - remoteVideoCount;
        if (audioIndex >= 0 && audioIndex < remoteAudioOnlyGroups.length) {
          return _buildRemoteAudioOnlyGroup(remoteAudioOnlyGroups[audioIndex]);
        }

        if (showsLocalPreview &&
            index == remoteVideoCount + remoteAudioOnlyGroups.length) {
          return _buildLocalPreviewPanel(context);
        }
        return const SizedBox.shrink();
      },
    );
  }

  // Remote video グリッドの列数を返す。
  int _remoteVideoColumns() {
    return 1;
  }

  // `connectionId` 単位で remote video track をグループ化する。
  List<_RemoteTrackGroup> _groupRemoteVideosByConnection() {
    final grouped = <String, List<RemoteMediaStreamTrack>>{};
    for (final video in remoteVideos) {
      grouped.putIfAbsent(video.connectionId, () => <RemoteMediaStreamTrack>[]);
      grouped[video.connectionId]!.add(video);
    }
    return grouped.entries
        .map((entry) {
          final client = _findClient(entry.key);
          return _RemoteTrackGroup(
            connectionId: entry.key,
            clientId: client?.clientId,
            tracks: entry.value,
          );
        })
        .toList(growable: false);
  }

  // 映像を持たない remote audio track だけを `connectionId` 単位でまとめる。
  List<_RemoteTrackGroup> _groupRemoteAudioOnlyByConnection() {
    final videoConnections = remoteVideos
        .map((video) => video.connectionId)
        .toSet();
    final grouped = <String, List<RemoteMediaStreamTrack>>{};
    for (final audio in remoteAudios) {
      if (videoConnections.contains(audio.connectionId)) {
        continue;
      }
      grouped.putIfAbsent(audio.connectionId, () => <RemoteMediaStreamTrack>[]);
      grouped[audio.connectionId]!.add(audio);
    }
    return grouped.entries
        .map((entry) {
          final client = _findClient(entry.key);
          return _RemoteTrackGroup(
            connectionId: entry.key,
            clientId: client?.clientId,
            tracks: entry.value,
          );
        })
        .toList(growable: false);
  }

  // 表示対象に応じた `ListView` の要素数を計算する。
  int _videoListItemCount({
    required List<_RemoteTrackGroup> remoteVideoGroups,
    required List<_RemoteTrackGroup> remoteAudioOnlyGroups,
  }) {
    int count = 0;
    if (showsLocalPreview) {
      count += 1;
    }
    if (showsRemoteVideo) {
      count += remoteVideoGroups.length;
    }
    count += remoteAudioOnlyGroups.length;
    return count;
  }

  // `connectionId` に対応する remote client 情報を検索する。
  DevToolsRemoteClientInfo? _findClient(String connectionId) {
    for (final client in remoteClients) {
      if (client.connectionId == connectionId) {
        return client;
      }
    }
    return null;
  }

  // Remote video track 群を 1 つの接続単位で描画する。
  Widget _buildRemoteVideoGroup(_RemoteTrackGroup group) {
    final clientLabel = group.clientId != null
        ? 'connection_id: ${group.connectionId}, client_id: ${group.clientId}'
        : 'connection_id: ${group.connectionId}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              clientLabel,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _remoteVideoColumns(),
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 16 / 9,
            ),
            itemCount: group.tracks.length,
            itemBuilder: (context, videoIndex) {
              final video = group.tracks[videoIndex];
              final videoLabel =
                  group.clientId != null && group.clientId != video.connectionId
                  ? '${video.connectionId}\n${group.clientId}'
                  : video.connectionId;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SoraRemoteVideoWidget(track: video),
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            videoLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Remote audio only の接続をプレースホルダ付きで描画する。
  Widget _buildRemoteAudioOnlyGroup(_RemoteTrackGroup group) {
    final clientLabel = group.clientId != null
        ? 'connection_id: ${group.connectionId}, client_id: ${group.clientId} (audio only)'
        : 'connection_id: ${group.connectionId} (audio only)';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              clientLabel,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: _remoteVideoColumns(),
              crossAxisSpacing: 4,
              mainAxisSpacing: 4,
              childAspectRatio: 16 / 9,
            ),
            itemCount: group.tracks.length,
            itemBuilder: (context, audioIndex) {
              final audio = group.tracks[audioIndex];
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.volume_up,
                          color: Colors.white54,
                          size: 48,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Audio: ${audio.trackId}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 選択中解像度に応じた aspect ratio で local preview を描画する。
  Widget _buildLocalPreviewPanel(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final aspectRatio = needsCamera && selectedResolution != null
        ? (orientation == Orientation.portrait
              ? (selectedResolution!.height.toDouble() /
                    selectedResolution!.width.toDouble())
              : (selectedResolution!.width.toDouble() /
                    selectedResolution!.height.toDouble()))
        : (16.0 / 9.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'Local',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 200,
                maxHeight: 200,
                maxWidth: 200 * aspectRatio,
              ),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // ローカルプレビューは一般的なカメラ preview と同様に鏡表示にする
                        SoraLocalVideoWidget(
                          textureId: localTextureId,
                          mirror: true,
                        ),
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Local',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteTrackGroup {
  // 同一接続に属する remote track 群をまとめる。
  const _RemoteTrackGroup({
    required this.connectionId,
    required this.clientId,
    required this.tracks,
  });

  final String connectionId;
  final String? clientId;
  final List<RemoteMediaStreamTrack> tracks;
}
