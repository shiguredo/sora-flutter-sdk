// ignore_for_file: public_member_api_docs
/// SoraConnection の remote track 管理責務を担当する内部サブシステム
///
/// video track の attach/detach、audio track の追加/削除、
/// および接続ごとの `RemoteMediaStream` の維持を行う。
/// `SoraConnection` がインスタンスを保持し、`_handleWebrtcEvent` から呼び出される。
/// このファイルは SDK 内部専用であり export しない。
library;

import 'dart:async';
import 'dart:ffi';

import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

import 'ffi/bindings.dart';
import 'ffi/webrtc_client.dart';
import 'sora_remote_media_stream.dart';
import 'sora_remote_track.dart';

/// リモートトラックの管理エントリ
class _RemoteTrackEntry {
  _RemoteTrackEntry({
    required this.trackAddress,
    required this.trackId,
    required this.connectionId,
    required this.rendererId,
    required this.renderingSinkPtr,
    required this.videoSinkPtr,
    required this.textureId,
  });

  final int trackAddress;
  final String trackId;
  final String connectionId;
  final int rendererId;
  final int renderingSinkPtr;
  final int videoSinkPtr;
  final int textureId;

  RemoteMediaStreamTrack toTrack() {
    return RemoteMediaStreamTrack(
      trackId: trackId,
      kind: 'video',
      connectionId: connectionId,
      textureId: textureId,
    );
  }
}

/// SoraConnection の remote track 管理を担当する内部クラス
///
/// video track の attach/detach、audio track の追加/削除、
/// および接続ごとの `RemoteMediaStream` の維持を行う。
@internal
class RemoteTrackManager {
  RemoteTrackManager({
    required this.clientId,
    required this.soraMethodChannel,
    required this.onDebugMessage,
    required this.onTrackEvent,
    required this.onRemoveTrackEvent,
  });

  /// この manager が属する SoraConnection のクライアント ID
  final int clientId;

  /// プラットフォームとの通信用 MethodChannel
  final MethodChannel soraMethodChannel;

  /// デバッグメッセージ出力用コールバック
  final void Function(String) onDebugMessage;

  /// リモートトラック追加イベント通知用コールバック
  final void Function(RemoteMediaStreamTrack) onTrackEvent;

  /// リモートトラック削除イベント通知用コールバック
  final void Function(RemoteMediaStreamTrack) onRemoveTrackEvent;

  /// 全トラック一括 detach の進行中 Future (二重実行・競合防止)
  Future<void>? _ongoingDetachAll;

  /// attach/detach の世代カウンタ。
  ///
  /// 以下のタイミングでインクリメントされ、非同期処理中の attach/detach を
  /// 失効させるために使う。
  /// - `connect()` 開始時: 新規接続に切り替えるため、前回接続の途中処理を無効化
  /// - `disconnect()` 開始時: 切断に伴い、進行中の attach を打ち消す
  int _generation = 0;

  /// renderer 作成待ちの trackAddress (remove が先行してきた場合の打ち消し用)
  final Set<int> _pendingAttach = <int>{};

  /// attach 処理の完了を待機する Completer マップ
  final Map<int, Completer<void>> _pendingAttachWaiters =
      <int, Completer<void>>{};

  /// detach 処理の完了を待機する Completer マップ
  final Map<int, Completer<void>> _detachWaiters = <int, Completer<void>>{};

  /// attach 前に remove が先行してきた trackAddress。
  ///
  /// 以下の race condition に対処するための打ち消し用セット:
  /// 1. `remote_track_added` 受信 → renderer 作成を非同期開始
  ///    → `_pendingAttach` に追加
  /// 2. renderer 完了前に `remote_track_removed` が到着
  ///    → まだ attach 未完了のため `_removedBeforeAttach` に記録
  /// 3. renderer 作成完了時に `_removedBeforeAttach` をチェックし、
  ///    remove が先に来ていたことを検知して即解放する
  ///
  /// 切断時は `detachAllRemoteVideoTracks()` が `_pendingAttach` を
  /// 全件ここへ追加し、同様に打ち消しを行う。
  final Set<int> _removedBeforeAttach = <int>{};

  /// track address をキーとするリモートトラック管理エントリ
  final Map<int, _RemoteTrackEntry> _remoteTracks = {};

  /// connectionId をキーとするリモート MediaStream マップ
  final Map<String, MutableRemoteMediaStream> _remoteMediaStreams = {};

  /// リモート接続ごとの MediaStream 一覧を snapshot として返す
  Map<String, RemoteMediaStream> get remoteMediaStreams =>
      Map<String, RemoteMediaStream>.unmodifiable(_remoteMediaStreams);

  /// 内部状態をクリアする
  void clear() {
    for (final completer in _pendingAttachWaiters.values.toList()) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _remoteTracks.clear();
    _remoteMediaStreams.clear();
    _pendingAttach.clear();
    _pendingAttachWaiters.clear();
    _detachWaiters.clear();
    _removedBeforeAttach.clear();
  }

  /// 新しい接続・切断サイクルを開始する。
  ///
  /// 世代カウンタをインクリメントし、非同期処理中の attach/detach を失効させる。
  /// `_removedBeforeAttach` は新世代では意味をなさないためクリアするが、
  /// `_pendingAttach` は後続の `detachAllRemoteVideoTracks()` が await して
  /// 片付ける責務を持つため、ここでは消さない。
  void invalidateGeneration() {
    _generation++;
    _removedBeforeAttach.clear();
  }

  void _beginPendingAttach(int trackAddress) {
    _pendingAttach.add(trackAddress);
    _pendingAttachWaiters[trackAddress] = Completer<void>();
  }

  void _finishPendingAttach(int trackAddress) {
    _pendingAttach.remove(trackAddress);
    final waiter = _pendingAttachWaiters.remove(trackAddress);
    if (waiter != null && !waiter.isCompleted) {
      waiter.complete();
    }
  }

  /// trackAddress 単位で排他制御しながら detach を実行する。
  ///
  /// 同一 trackAddress に対する並行 detach を防ぐため、
  /// 既存の処理があればその完了を待ち、なければ新規に実行する。
  Future<void> _runTrackedDetach(int trackAddress) async {
    final existing = _detachWaiters[trackAddress];
    if (existing != null) {
      await existing.future;
      return;
    }

    final waiter = Completer<void>();
    _detachWaiters[trackAddress] = waiter;
    try {
      await _detachRemoteVideoTrackUnsafe(trackAddress);
    } finally {
      _detachWaiters.remove(trackAddress);
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 純粋ヘルパー
  // ---------------------------------------------------------------------------

  /// Track IDから Connection ID を取得する。
  ///
  /// Sora サーバー仕様により、remote MediaStreamTrack.id は
  /// `{connection_id}-audio` / `{connection_id}-video` の形式になる。
  static String? _connectionIdFromTrackId(String? trackId) {
    if (trackId == null || trackId.isEmpty) {
      return null;
    }
    const suffixes = <String>['-audio', '-video'];
    for (final suffix in suffixes) {
      if (trackId.endsWith(suffix) && trackId.length > suffix.length) {
        return trackId.substring(0, trackId.length - suffix.length);
      }
    }
    return null;
  }

  /// Track IDから Connection ID を取得する。
  ///
  /// 取得できない場合は `StateError` を throw する。
  static String _requireRemoteConnectionId(
    String trackId, {
    required String type,
  }) {
    final connectionId = _connectionIdFromTrackId(trackId);
    if (connectionId == null || connectionId.isEmpty) {
      throw StateError(
        '$type requires trackId with Sora connection id format: $trackId',
      );
    }
    return connectionId;
  }

  // ---------------------------------------------------------------------------
  // Audio track ハンドリング
  // ---------------------------------------------------------------------------

  /// remote audio track が追加された時の処理
  void handleRemoteAudioTrackAdded(String trackId) {
    final connectionId = _requireRemoteConnectionId(
      trackId,
      type: 'remote_track_added',
    );
    final track = RemoteMediaStreamTrack(
      trackId: trackId,
      kind: 'audio',
      connectionId: connectionId,
    );
    final remoteStream = _remoteMediaStreams.putIfAbsent(
      connectionId,
      () => MutableRemoteMediaStream(connectionId: connectionId),
    );
    remoteStream.setAudioTrack(track);
    onTrackEvent(track);
  }

  /// remote audio track が削除された時の処理
  void handleRemoteAudioTrackRemoved(String trackId) {
    final connectionId = _requireRemoteConnectionId(
      trackId,
      type: 'remote_track_removed',
    );
    final track = RemoteMediaStreamTrack(
      trackId: trackId,
      kind: 'audio',
      connectionId: connectionId,
    );
    final remoteStream = _remoteMediaStreams[connectionId];
    if (remoteStream != null) {
      remoteStream.setAudioTrack(null);
      if (remoteStream.videoTrack == null) {
        _remoteMediaStreams.remove(connectionId);
      }
    }
    onRemoveTrackEvent(track);
  }

  // ---------------------------------------------------------------------------
  // Video track attach / detach
  // ---------------------------------------------------------------------------

  /// リモートビデオトラックをアタッチする
  Future<void> attachRemoteVideoTrack(
    int trackAddress, {
    required String trackId,
  }) async {
    if (_ongoingDetachAll != null) {
      WebrtcClient.sharedLib.videoTrackRelease(
        Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
      );
      return;
    }
    if (_remoteTracks.containsKey(trackAddress)) return;

    // remove が先行してきた場合は打ち消す
    if (_removedBeforeAttach.contains(trackAddress)) {
      _removedBeforeAttach.remove(trackAddress);
      WebrtcClient.sharedLib.videoTrackRelease(
        Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
      );
      return;
    }

    _beginPendingAttach(trackAddress);
    final currentGeneration = _generation;
    try {
      // detach-all 開始直後にこの attach が登録された場合も、
      // renderer 作成へ進まずその場で無効化する。
      if (_ongoingDetachAll != null) {
        WebrtcClient.sharedLib.videoTrackRelease(
          Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
        );
        return;
      }

      // プラットフォーム側でレンダラーを作成する
      final response = await soraMethodChannel
          .invokeMethod<Map<Object?, Object?>>(
            'createRemoteVideoRenderer',
            <String, Object?>{'clientId': clientId},
          );
      _pendingAttach.remove(trackAddress);

      // 世代が変わっていれば、この attach は失効
      if (_generation != currentGeneration) {
        if (response != null) {
          await soraMethodChannel.invokeMethod<void>(
            'disposeRemoteVideoRenderer',
            <String, Object?>{
              'clientId': clientId,
              'rendererId': (response['rendererId'] as num).toInt(),
            },
          );
        }
        WebrtcClient.sharedLib.videoTrackRelease(
          Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
        );
        return;
      }

      // remove が先行してきた場合は打ち消す
      if (_removedBeforeAttach.contains(trackAddress)) {
        _removedBeforeAttach.remove(trackAddress);
        if (response != null) {
          await soraMethodChannel.invokeMethod<void>(
            'disposeRemoteVideoRenderer',
            <String, Object?>{
              'clientId': clientId,
              'rendererId': (response['rendererId'] as num).toInt(),
            },
          );
        }
        WebrtcClient.sharedLib.videoTrackRelease(
          Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
        );
        return;
      }

      if (response == null) return;

      final rendererId = (response['rendererId'] as num).toInt();
      final renderingSinkPtr = (response['renderingSinkPtr'] as num).toInt();
      final videoSinkPtr = (response['videoSinkPtr'] as num).toInt();
      final textureId = (response['textureId'] as num).toInt();

      final entry = _RemoteTrackEntry(
        trackAddress: trackAddress,
        trackId: trackId,
        connectionId: _requireRemoteConnectionId(
          trackId,
          type: 'remote_video_track_added',
        ),
        rendererId: rendererId,
        renderingSinkPtr: renderingSinkPtr,
        videoSinkPtr: videoSinkPtr,
        textureId: textureId,
      );
      _remoteTracks[trackAddress] = entry;

      // FFI でシンクをアタッチする
      final lib = WebrtcClient.sharedLib;
      final trackPtr = Pointer<WebrtcVideoTrackInterface>.fromAddress(
        trackAddress,
      );
      final sinkPtr = Pointer<WebrtcVideoSinkInterface>.fromAddress(
        videoSinkPtr,
      );
      final wants = lib.videoSinkWantsNew();
      lib.videoTrackAddOrUpdateSink(trackPtr, sinkPtr, wants);
      lib.videoSinkWantsDelete(wants);

      onDebugMessage(
        'remote_track_attached: trackAddress=$trackAddress textureId=$textureId',
      );

      final remoteTrack = entry.toTrack();
      final remoteStream = _remoteMediaStreams.putIfAbsent(
        entry.connectionId,
        () => MutableRemoteMediaStream(connectionId: entry.connectionId),
      );
      remoteStream.setVideoTrack(remoteTrack);
      onTrackEvent(remoteTrack);
    } catch (e) {
      WebrtcClient.sharedLib.videoTrackRelease(
        Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
      );
      rethrow;
    } finally {
      _finishPendingAttach(trackAddress);
    }
  }

  /// リモートビデオトラックをデタッチする
  ///
  /// 全 track 一括 detach 実行中は個別 detach をスキップし、そちらに任せる。
  Future<void> detachRemoteVideoTrack(int trackAddress) async {
    if (_ongoingDetachAll != null) {
      return;
    }
    await _runTrackedDetach(trackAddress);
  }

  /// 排他制御なしでリモートビデオトラックをデタッチする。
  ///
  /// attach 待ちの場合は `_removedBeforeAttach` に記録して打ち消す。
  /// 既存のトラックに対しては、native Sink 解除・トラック解放・
  /// プラットフォーム側レンダラー破棄・`RemoteMediaStream` 更新・
  /// remove イベント発火を順次行う。
  /// 排他制御は呼び出し元の責務とする。
  Future<void> _detachRemoteVideoTrackUnsafe(int trackAddress) async {
    // attach 待ちの場合は先行 remove として記録し、resume 後に打ち消す
    if (_pendingAttach.contains(trackAddress)) {
      _removedBeforeAttach.add(trackAddress);
      final pendingWaiter = _pendingAttachWaiters[trackAddress];
      if (pendingWaiter != null) {
        await pendingWaiter.future;
      }
      return;
    }

    final entry = _remoteTracks.remove(trackAddress);
    if (entry == null) return;

    // FFI で Sink を解除してトラックを解放する
    final lib = WebrtcClient.sharedLib;
    final trackPtr = Pointer<WebrtcVideoTrackInterface>.fromAddress(
      trackAddress,
    );
    final sinkPtr = Pointer<WebrtcVideoSinkInterface>.fromAddress(
      entry.videoSinkPtr,
    );
    lib.videoTrackRemoveSink(trackPtr, sinkPtr);
    lib.videoTrackRelease(trackPtr);

    // プラットフォーム側でレンダラーを破棄する
    await soraMethodChannel.invokeMethod<void>(
      'disposeRemoteVideoRenderer',
      <String, Object?>{'clientId': clientId, 'rendererId': entry.rendererId},
    );

    onDebugMessage(
      'remote_track_detached: trackAddress=$trackAddress textureId=${entry.textureId}',
    );

    final remoteTrack = entry.toTrack();
    final remoteStream = _remoteMediaStreams[entry.connectionId];
    if (remoteStream != null) {
      remoteStream.setVideoTrack(null);
      if (remoteStream.audioTrack == null) {
        _remoteMediaStreams.remove(entry.connectionId);
      }
    }
    onRemoveTrackEvent(remoteTrack);
  }

  /// 全リモートビデオトラックをデタッチする
  ///
  /// 個別の detach に失敗しても残りの track は継続して処理する。
  Future<void> detachAllRemoteVideoTracks() async {
    final existing = _ongoingDetachAll;
    if (existing != null) {
      await existing;
      return;
    }
    final completer = Completer<void>();
    _ongoingDetachAll = completer.future;
    try {
      _removedBeforeAttach.addAll(_pendingAttach);
      final pendingWaits = _pendingAttachWaiters.values
          .map((waiter) => waiter.future)
          .toList(growable: false);
      final detachWaits = _detachWaiters.values
          .map((waiter) => waiter.future)
          .toList(growable: false);
      final addresses = _remoteTracks.keys.toList();
      for (final addr in addresses) {
        try {
          await _runTrackedDetach(addr);
        } catch (e) {
          onDebugMessage('remote_track detach failed during detach-all: $e');
        }
      }
      if (pendingWaits.isNotEmpty) {
        await Future.wait(pendingWaits);
      }
      if (detachWaits.isNotEmpty) {
        await Future.wait(detachWaits);
      }
    } finally {
      completer.complete();
      _ongoingDetachAll = null;
    }
  }
}
