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
  // FFI 副作用ヘルパー (テスト差し替え可)
  // ---------------------------------------------------------------------------

  /// テスト専用に `_releaseTrackRef` の FFI 呼び出しを差し替えるフック。
  ///
  /// C 側の `webrtc_VideoTrackInterface_Release` は Dart から refcount を
  /// 直接観測できず、real FFI 呼び出しでは 0 番地等のダミー trackAddress を
  /// 与えると SEGV する。テストでは release 呼び出しの回数を list に記録
  /// するだけの差し替え関数をここに設定して、経路別に release 回数を
  /// 観測する。
  ///
  /// production では `null` のままにしておく。
  @visibleForTesting
  void Function(int trackAddress)? releaseTrackRefForTest;

  /// テスト専用に `_attachSinkToTrack` の FFI 呼び出しを差し替えるフック。
  ///
  /// `videoTrackAddOrUpdateSink` はダミー trackAddress で SEGV するため、
  /// テストでは呼び出し記録用の差し替え関数をここに設定して attach happy path
  /// でも実 FFI を回避する。production では `null` のままにしておく。
  @visibleForTesting
  void Function(int trackAddress, int videoSinkPtr)? attachSinkToTrackForTest;

  /// テスト専用に `_removeSinkFromTrack` の FFI 呼び出しを差し替えるフック。
  ///
  /// `videoTrackRemoveSink` はダミー trackAddress で SEGV するため、
  /// テストでは呼び出し記録用の差し替え関数をここに設定して detach happy path
  /// でも実 FFI を回避する。production では `null` のままにしておく。
  @visibleForTesting
  void Function(int trackAddress, int videoSinkPtr)? removeSinkFromTrackForTest;

  /// トラック参照 (`webrtc_VideoTrackInterface_AddRef` で追加された refcount)
  /// を 1 回返却する。すべての release 経路はこのヘルパを経由することで、
  /// テストからの観測と差し替えを 1 箇所に集約する。
  void _releaseTrackRef(int trackAddress) {
    final testHook = releaseTrackRefForTest;
    if (testHook != null) {
      testHook(trackAddress);
      return;
    }
    WebrtcClient.sharedLib.videoTrackRelease(
      Pointer<WebrtcVideoTrackInterface>.fromAddress(trackAddress),
    );
  }

  /// attach happy path の FFI sink 登録処理。
  /// テスト差し替えを可能にするためヘルパに集約している。
  void _attachSinkToTrack(int trackAddress, int videoSinkPtr) {
    final hook = attachSinkToTrackForTest;
    if (hook != null) {
      hook(trackAddress, videoSinkPtr);
      return;
    }
    final lib = WebrtcClient.sharedLib;
    final trackPtr = Pointer<WebrtcVideoTrackInterface>.fromAddress(
      trackAddress,
    );
    final sinkPtr = Pointer<WebrtcVideoSinkInterface>.fromAddress(videoSinkPtr);
    final wants = lib.videoSinkWantsNew();
    lib.videoTrackAddOrUpdateSink(trackPtr, sinkPtr, wants);
    lib.videoSinkWantsDelete(wants);
  }

  /// attach が中断した際の共通後処理。プラットフォーム側 renderer を
  /// 破棄しつつ、**add 分の参照を `_releaseTrackRef` で返却する**。
  /// 世代変化 / `_removedBeforeAttach` 打ち消しの両経路で使う。
  ///
  /// 名前は「pending attach を丸ごとキャンセルする」意味合いで、
  /// renderer dispose と track release の両方を含むことをここで明示する。
  Future<void> _cancelPendingAttach(
    Map<Object?, Object?>? response,
    int trackAddress,
  ) async {
    if (response != null) {
      await soraMethodChannel.invokeMethod<void>(
        'disposeRemoteVideoRenderer',
        <String, Object?>{
          'clientId': clientId,
          'rendererId': (response['rendererId'] as num).toInt(),
        },
      );
    }
    _releaseTrackRef(trackAddress);
  }

  /// detach happy path の FFI sink 解除処理。
  /// テスト差し替えを可能にするためヘルパに集約している。
  void _removeSinkFromTrack(int trackAddress, int videoSinkPtr) {
    final hook = removeSinkFromTrackForTest;
    if (hook != null) {
      hook(trackAddress, videoSinkPtr);
      return;
    }
    final lib = WebrtcClient.sharedLib;
    final trackPtr = Pointer<WebrtcVideoTrackInterface>.fromAddress(
      trackAddress,
    );
    final sinkPtr = Pointer<WebrtcVideoSinkInterface>.fromAddress(videoSinkPtr);
    lib.videoTrackRemoveSink(trackPtr, sinkPtr);
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
  ///
  /// C 側 bridge (`linux/linux_bridge.c` の `bridge_on_track` および
  /// Apple / Windows / JNI の対応関数) は add / remove の両イベントで
  /// `webrtc_VideoTrackInterface_AddRef` を呼んでから `trackAddress` を
  /// Dart に渡す。本メソッドはそのうち **add イベントで追加された参照** を
  /// 一意に扱う責務を持つ:
  ///
  /// - happy path: `_RemoteTrackEntry` に保持し、`_detachRemoteVideoTrackUnsafe`
  ///   の happy path で `_releaseTrackRef` により返却する。
  /// - 各早期 return 経路: その場で `_releaseTrackRef` により返却する
  ///   (renderer 作成後の中断経路は `_cancelPendingAttach` 経由で dispose と
  ///   合わせて実行する)。
  ///
  /// remove イベントで追加された参照は `detachRemoteVideoTrack` の入口で
  /// 別途返却される (本メソッドでは扱わない)。
  Future<void> attachRemoteVideoTrack(
    int trackAddress, {
    required String trackId,
  }) async {
    if (_ongoingDetachAll != null) {
      _releaseTrackRef(trackAddress);
      return;
    }
    if (_remoteTracks.containsKey(trackAddress)) {
      // 同一 trackAddress の再通知でも add 分の参照は AddRef されているので
      // 返却する必要がある。
      _releaseTrackRef(trackAddress);
      return;
    }

    // remove が先行してきた場合は打ち消す。
    // remove 分は `detachRemoteVideoTrack` 入口で既に返却済みのため、
    // ここでは add 分のみを返却する。
    if (_removedBeforeAttach.contains(trackAddress)) {
      _removedBeforeAttach.remove(trackAddress);
      _releaseTrackRef(trackAddress);
      return;
    }

    _beginPendingAttach(trackAddress);
    final currentGeneration = _generation;
    try {
      // detach-all 開始直後にこの attach が登録された場合も、
      // renderer 作成へ進まずその場で無効化する。
      if (_ongoingDetachAll != null) {
        _releaseTrackRef(trackAddress);
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
        await _cancelPendingAttach(response, trackAddress);
        return;
      }

      // remove が先行してきた場合は打ち消す。
      // remove 分は `detachRemoteVideoTrack` 入口で既に返却済みのため、
      // ここでは add 分のみを返却する。
      if (_removedBeforeAttach.contains(trackAddress)) {
        _removedBeforeAttach.remove(trackAddress);
        await _cancelPendingAttach(response, trackAddress);
        return;
      }

      if (response == null) {
        // プラットフォーム側の防御パス。add 分の参照が漏れないよう返却する。
        _releaseTrackRef(trackAddress);
        return;
      }

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

      // FFI でシンクをアタッチする。ヘルパ経由にすることでテスト差し替え
      // (SEGV 回避) を可能にする。
      _attachSinkToTrack(trackAddress, videoSinkPtr);

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
      // 後段 (entry map への登録以降) で throw した場合、entry を map に
      // 残したまま release すると次回 detach で `_remoteTracks.containsKey`
      // にヒットして二重 release になる。add 分 release の前に entry を
      // 除去して map 汚染を防ぐ。まだ entry を入れていない early 段階の
      // throw では remove は no-op。
      _remoteTracks.remove(trackAddress);
      _releaseTrackRef(trackAddress);
      rethrow;
    } finally {
      _finishPendingAttach(trackAddress);
    }
  }

  /// リモートビデオトラックをデタッチする
  ///
  /// C 側 bridge は remove イベントで `webrtc_VideoTrackInterface_AddRef` を
  /// 呼んでから `trackAddress` を Dart に渡す。本メソッドはその remove 分の
  /// 参照を入口で必ず返却する責務を持つ (`_detachRemoteVideoTrackUnsafe` は
  /// `detachAllRemoteVideoTracks` からも呼ばれるため remove 分は扱わない)。
  ///
  /// 全 track 一括 detach 実行中は個別 detach 本体はスキップし、そちらに
  /// 任せるが、remove 分の返却はこのメソッドの責務として実行済みになる。
  ///
  /// **前提**: `_releaseTrackRef` (production では `videoTrackRelease`) は
  /// 正常終了する。もし throw した場合、以降の `_runTrackedDetach` は起動
  /// せず、例外は呼び出し元まで伝播する (テスト差し替えの `releaseTrackRefForTest`
  /// も throw させない実装を利用側の責任で守ること)。
  Future<void> detachRemoteVideoTrack(int trackAddress) async {
    // remove 分の参照を入口で必ず 1 回返却する。以降の early return や
    // `_ongoingDetachAll` によるスキップを通っても収支が 0 になる。
    _releaseTrackRef(trackAddress);
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
  ///
  /// 本メソッドで `_releaseTrackRef` を呼ぶのは **happy path 1 経路のみ**
  /// (entry を得て sink を外した直後に entry.trackAddress を 1 回返却する)。
  /// 残りの early return 経路では、以下の理由で release を持たない:
  ///
  /// - `_pendingAttach` にヒットする early return 経路: `_removedBeforeAttach`
  ///   に登録するだけで、add 分の返却は `attachRemoteVideoTrack` 側の
  ///   いずれかの early return 経路 (`_removedBeforeAttach` 打ち消し /
  ///   `_generation` 変化 / `_ongoingDetachAll` / `response == null` /
  ///   catch 節) が担う。
  /// - `entry == null` の early return 経路: attach 側の early return で
  ///   add 分は既に返却済み。attach を通っていないアドレスなら AddRef も
  ///   されていないため返却対象がない。
  ///
  /// remove 分の返却は `detachRemoteVideoTrack` の入口責務で、本メソッドは
  /// `detachAllRemoteVideoTracks` からも呼ばれるため remove 分は扱わない。
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

    // FFI で Sink を解除してトラックを解放する。ヘルパ経由にすることで
    // テスト差し替え (SEGV 回避) を可能にする。
    _removeSinkFromTrack(trackAddress, entry.videoSinkPtr);
    // add 分の参照を返却する。`_releaseTrackRef` を経由することで、
    // 全経路の release を単一箇所で観測・差し替えできる。
    _releaseTrackRef(entry.trackAddress);

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
