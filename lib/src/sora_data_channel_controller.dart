// ignore_for_file: public_member_api_docs
/// SoraConnection の DataChannel 管理責務を担当する内部サブシステム
///
/// DataChannel メッセージの routing、compress/decompress、RPC 管理、
/// opened label 追跡を行う。
/// `SoraConnection` がインスタンスを保持し、`_handleWebrtcEvent` から呼び出される。
/// このファイルは SDK 内部専用であり export しない。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'ffi/webrtc_client.dart';
import 'sora_data_channel_event.dart';
import 'sora_data_channel_message.dart';
import 'sora_rpc.dart';

// SoraConnection の DataChannel 管理責務を担当する内部サブシステム
@internal
class DataChannelController {
  DataChannelController({
    required this.webrtcClient,
    required this.onDebugMessage,
    required this.onPushMessage,
    required this.onNotifyMessage,
    required this.onDataChannelMessageEvent,
    required this.onDataChannelOpenEvent,
    required this.onSignalingEvent,
    required this.onLogEvent,
    required this.onSignalingClose,
    required this.onConnectionCreated,
    required this.decodeJsonMap,
    required this.decodeJson,
  });

  /// FFI 経由の libwebrtc クライアント
  final WebrtcClient webrtcClient;

  /// デバッグメッセージ出力用コールバック
  final void Function(String) onDebugMessage;

  /// push メッセージ受信時コールバック
  final void Function(Map<String, Object?>) onPushMessage;

  /// notify メッセージ受信時コールバック
  final void Function(Map<String, Object?>) onNotifyMessage;

  /// DataChannel メッセージ受信時コールバック
  final void Function(SoraDataChannelMessage) onDataChannelMessageEvent;

  /// DataChannel ラベル別 open 通知コールバック
  final void Function(SoraDataChannelEvent) onDataChannelOpenEvent;

  /// シグナリング送受信ログ用コールバック
  final void Function(
    String transport,
    String direction,
    Map<String, Object?>? data,
  )
  onSignalingEvent;

  /// ログイベント出力用コールバック
  final void Function(String title, [Object? message]) onLogEvent;

  /// DataChannel シグナリングの server 主導切断通知コールバック
  final Future<void> Function(Object? code, String? reason) onSignalingClose;

  /// connection.created 受信時コールバック
  final void Function(Map<String, Object?>) onConnectionCreated;

  /// Isolate 経由で JSON を Map にデコードするコールバック
  final Future<Map<String, Object?>?> Function(String) decodeJsonMap;

  /// Isolate 経由で JSON をデコードするコールバック
  final Future<Object?> Function(String) decodeJson;

  // ---------------------------------------------------------------------------
  // 状態
  // ---------------------------------------------------------------------------

  /// notify DataChannel の compress 有無
  bool _notifyDataChannelCompress = false;

  /// push DataChannel の compress 有無
  bool _pushDataChannelCompress = false;

  /// stats DataChannel の compress 有無
  bool _statsDataChannelCompress = false;

  /// signaling DataChannel の compress 有無
  bool _signalingDataChannelCompress = false;

  /// RPC DataChannel の compress 有無
  bool _rpcDataChannelCompress = false;

  /// deflate の raw モードフラグ (null: 未設定)
  bool? _dataChannelDeflateRaw;

  /// 受信済みの直近の offer メッセージ (再接続時 replay 用)
  Map<String, Object?>? _lastOfferMessage;

  /// RPC リクエスト ID の採番カウンタ
  int _rpcRequestIdCounter = 0;

  /// 保留中の RPC リクエスト Completer マップ
  final Map<int, Completer<Object?>> _rpcRequestCompleters = {};

  /// RPC リクエストのタイムアウトタイマーマップ
  final Map<int, Timer> _rpcTimeoutTimers = {};

  /// 開通済み DataChannel ラベルのセット
  final Set<String> _openedDataChannelLabels = <String>{};

  /// signaling メッセージを入力順で処理するための tail Future。
  Future<void>? _signalingMessageTail;

  /// カスタム DataChannel の compress フラグキャッシュ。
  /// re-offer 時に data_channels からラベルが欠落しても
  /// 初回 offer で確立した compress 値を維持する。
  @visibleForTesting
  final Map<String, bool> customChannelCompress = <String, bool>{};

  // ---------------------------------------------------------------------------
  // 公開 getter
  // ---------------------------------------------------------------------------

  bool get signalingCompress => _signalingDataChannelCompress;
  bool? get deflateRaw => _dataChannelDeflateRaw;

  /// `_dataChannelDeflateRaw` の現在値で deflate エンコードする。
  Uint8List deflateEncode(List<int> data) {
    return Uint8List.fromList(_getCodec().encoder.convert(data));
  }

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  // offer メッセージから DataChannel 圧縮フラグを抽出して適用する。
  // re-offer 時に data_channels に対象ラベルが含まれない場合は
  // 既存の compress 設定を維持する。
  void applyOfferMessage(Map<String, Object?> payload) {
    _lastOfferMessage = payload;
    updateCompressFlagIfPresent(
      payload,
      'notify',
      (v) => _notifyDataChannelCompress = v,
    );
    updateCompressFlagIfPresent(
      payload,
      'push',
      (v) => _pushDataChannelCompress = v,
    );
    updateCompressFlagIfPresent(
      payload,
      'stats',
      (v) => _statsDataChannelCompress = v,
    );
    updateCompressFlagIfPresent(
      payload,
      'rpc',
      (v) => _rpcDataChannelCompress = v,
    );
    updateCompressFlagIfPresent(
      payload,
      'signaling',
      (v) => _signalingDataChannelCompress = v,
    );
    updateCustomChannelCompress(payload);
    _dataChannelDeflateRaw =
        payload['deflateraw'] as bool? ?? _dataChannelDeflateRaw;
    onDebugMessage(
      'offer: notify.compress=$_notifyDataChannelCompress '
      'push.compress=$_pushDataChannelCompress '
      'stats.compress=$_statsDataChannelCompress '
      'rpc.compress=$_rpcDataChannelCompress '
      'signaling.compress=$_signalingDataChannelCompress '
      'rpcMethods=${payload['rpc_methods'] ?? <String>[]}',
    );
  }

  @visibleForTesting
  // 指定ラベルの DataChannel config が payload に存在し、かつ
  // compress キーがある場合のみ compress フラグを更新する。
  // ラベルまたは compress キーが欠落している場合は何もせず、
  // 既存の compress 値を維持する。
  static void updateCompressFlagIfPresent(
    Map<String, Object?> payload,
    String label,
    void Function(bool value) update,
  ) {
    final config = findDataChannelConfig(payload, label: label);
    if (config != null && config.containsKey('compress')) {
      update(config['compress'] == true);
    }
  }

  @visibleForTesting
  // payload の data_channels からカスタムラベルの compress 値を
  // 抽出し customChannelCompress キャッシュを更新する。
  // re-offer 時にラベルが欠落しても既存値が維持される。
  void updateCustomChannelCompress(Map<String, Object?> payload) {
    final resolved = resolveCustomChannelCompress(payload);
    customChannelCompress.addAll(resolved);
  }

  @visibleForTesting
  // payload の data_channels から `#` プレフィックスを持つ
  // カスタムラベルの compress 値を抽出して返す。
  // テストから直接呼べるようインスタンス状態に依存しない。
  static Map<String, bool> resolveCustomChannelCompress(
    Map<String, Object?> payload,
  ) {
    final result = <String, bool>{};
    final channels = payload['data_channels'];
    if (channels is! List) return result;
    for (final channel in channels) {
      if (channel is! Map) continue;
      final label = channel['label'] as String?;
      if (label == null || !label.startsWith('#')) continue;
      final compress = channel['compress'];
      if (compress is bool) {
        result[label] = compress;
      }
    }
    return result;
  }

  // 接続切断時に内部状態をクリアする
  void clear() {
    _lastOfferMessage = null;
    _notifyDataChannelCompress = false;
    _pushDataChannelCompress = false;
    _statsDataChannelCompress = false;
    _signalingDataChannelCompress = false;
    _rpcDataChannelCompress = false;
    _dataChannelDeflateRaw = null;
    _openedDataChannelLabels.clear();
    _signalingMessageTail = null;
    customChannelCompress.clear();
    for (final timer in _rpcTimeoutTimers.values) {
      timer.cancel();
    }
    _rpcTimeoutTimers.clear();
    for (final completer in _rpcRequestCompleters.values) {
      completer.completeError(
        const SoraRpcError(code: -1, message: 'Disconnected'),
      );
    }
    _rpcRequestCompleters.clear();
    _rpcRequestIdCounter = 0;
  }

  // ---------------------------------------------------------------------------
  // DataChannel open 通知
  // ---------------------------------------------------------------------------

  // DataChannel が利用可能となった通知を送信する。
  // compress は実際の送受信で使われる値（re-offer 後も維持された値）を反映する。
  void emitDataChannelAvailable(String label) {
    if (_openedDataChannelLabels.contains(label)) {
      return;
    }
    _openedDataChannelLabels.add(label);

    final config = findDataChannelConfig(_lastOfferMessage ?? {}, label: label);
    final compress = _resolveCompressForLabel(label, config);
    onDataChannelOpenEvent(
      SoraDataChannelEvent(
        label: label,
        direction: config?['direction'] as String?,
        compress: compress,
        header: config?['header'],
      ),
    );
  }

  // 指定ラベルの実際の送受信で使われる compress 値を返す。
  // 組み込みラベルは保持済みフラグ、カスタムラベルは
  // customChannelCompress キャッシュを優先し、
  // それ以外は config (初回 offer の情報) を返す。
  bool? _resolveCompressForLabel(String label, Map<String, Object?>? config) {
    switch (label) {
      case 'notify':
        return _notifyDataChannelCompress;
      case 'push':
        return _pushDataChannelCompress;
      case 'stats':
        return _statsDataChannelCompress;
      case 'rpc':
        return _rpcDataChannelCompress;
      case 'signaling':
        return _signalingDataChannelCompress;
      default:
        if (label.startsWith('#')) {
          return customChannelCompress[label] ?? config?['compress'] as bool?;
        }
        return config?['compress'] as bool?;
    }
  }

  // ---------------------------------------------------------------------------
  // メッセージ routing
  // ---------------------------------------------------------------------------

  // DataChannel メッセージを label ごとに dispatch する
  Future<void> handleMessage(String label, Object? data) async {
    if (label == 'signaling') {
      await _enqueueSignalingDataChannelMessage(data);
      return;
    }
    if (label == 'push') {
      await _handlePushDataChannelMessage(data);
      return;
    }
    if (label == 'rpc') {
      _handleRpcDataChannelMessage(data);
      return;
    }
    if (label == 'stats') {
      await _handleStatsDataChannelMessage(data);
      return;
    }
    if (label != 'notify') {
      // カスタムラベル (#* プレフィックス) のメッセージを処理する
      if (label.startsWith('#')) {
        _handleCustomDataChannelMessage(label, data);
      }
      return;
    }

    // Uint8List の場合は compress 有無に応じて deflate 展開し UTF-8 文字列化、
    // String の場合はそのまま text として扱う。
    final text = _decodeDataChannelMessage(
      label,
      data,
      _notifyDataChannelCompress,
    );
    if (text == null) {
      return;
    }
    onDebugMessage('dc($label) recv: $text');
    await _handleNotifyDataChannelText(label, text);
  }

  // ---------------------------------------------------------------------------
  // 送信 API
  // ---------------------------------------------------------------------------

  /// カスタム DataChannel ラベルを指定してメッセージを送信する。
  /// offer から該当ラベルの compress フラグを参照し、
  /// compress 有効なら deflate 圧縮、無効なら生データを送る。
  void sendDataChannelMessage(String label, Uint8List data) {
    final compress =
        customChannelCompress[label] ??
        _findDataChannelCompressFlag(_lastOfferMessage ?? {}, label: label);
    final Uint8List sendData;
    if (compress) {
      // deflate 圧縮して送信
      sendData = Uint8List.fromList(_getCodec().encoder.convert(data));
    } else {
      // 生データをそのまま送信
      sendData = data;
    }
    webrtcClient.sendCustomDataChannelMessage(label, sendData);
  }

  // JSON-RPC リクエストを rpc DataChannel 経由で送信する
  Future<Object?> rpc(
    String method, {
    Object? params,
    required bool isNotification,
    required int? timeoutMs,
  }) async {
    final int? id = isNotification ? null : ++_rpcRequestIdCounter;

    final request = <String, Object?>{'jsonrpc': '2.0', 'method': method};
    if (id != null) {
      request['id'] = id;
    }
    if (params != null) {
      request['params'] = params;
    }

    final text = jsonEncode(request);
    onDebugMessage('dc(rpc) send: $text');
    final encoded = utf8.encode(text);
    final Uint8List sendData;
    if (_rpcDataChannelCompress) {
      sendData = Uint8List.fromList(_getCodec().encoder.convert(encoded));
    } else {
      sendData = encoded;
    }
    webrtcClient.sendRpcMessage(sendData);

    // Notification であれば送信して終える
    if (isNotification || id == null) {
      return null;
    }

    final completer = Completer<Object?>();
    _rpcRequestCompleters[id] = completer;

    if (timeoutMs case final timeout?) {
      _rpcTimeoutTimers[id] = Timer(Duration(milliseconds: timeout), () {
        _rpcTimeoutTimers.remove(id);
        final c = _rpcRequestCompleters.remove(id);
        c?.completeError(
          TimeoutException(
            'RPC request timeout: $method',
            Duration(milliseconds: timeout),
          ),
        );
      });
    }

    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // ラベル別ハンドラ
  // ---------------------------------------------------------------------------

  // DataChannel メッセージを notify として処理する
  Future<void> _handleNotifyDataChannelText(String label, String text) async {
    try {
      final decoded = await decodeJsonMap(text);
      if (decoded == null) {
        return;
      }
      onNotifyMessage(decoded);
      if (decoded['event_type'] == 'connection.created') {
        onConnectionCreated(decoded);
      }
    } catch (error) {
      onDebugMessage('dc($label) json decode failed: error=$error');
    }
  }

  // signaling DataChannel からのメッセージを処理する
  Future<void> _enqueueSignalingDataChannelMessage(Object? data) async {
    final previous = _signalingMessageTail ?? Future<void>.value();
    final current = previous
        .catchError((Object _, StackTrace _) {
          // 先行メッセージ失敗でチェーン全体が停止しないようにする。
        })
        .then((_) => _handleSignalingDataChannelMessage(data));
    _signalingMessageTail = current;
    await current;
  }

  // signaling DataChannel からのメッセージを処理する
  Future<void> _handleSignalingDataChannelMessage(Object? data) async {
    final text = _decodeDataChannelMessage(
      'signaling',
      data,
      _signalingDataChannelCompress,
    );
    if (text == null) return;

    onDebugMessage('dc(signaling) recv: $text');
    try {
      final decoded = await decodeJsonMap(text);
      if (decoded == null) {
        return;
      }
      onSignalingEvent('datachannel', 'received', decoded);

      final type = decoded['type'] as String?;
      if (type == 're-offer') {
        applyOfferMessage(decoded);
        onLogEvent('SIGNALING RE OFFER MESSAGE', decoded);
        if (decoded['sdp'] case final sdp?) {
          onLogEvent('RE OFFER SDP', sdp);
        }
        webrtcClient.handleReOffer(decoded);
      } else if (type == 'close') {
        final code = decoded['code'];
        final reason = decoded['reason'] as String?;
        onDebugMessage('dc(signaling) close: code=$code reason=$reason');
        await onSignalingClose(code, reason);
      }
    } catch (error) {
      onDebugMessage('dc(signaling) json decode failed: error=$error');
    }
  }

  // push DataChannel からのメッセージを処理する
  Future<void> _handlePushDataChannelMessage(Object? data) async {
    final text = _decodeDataChannelMessage(
      'push',
      data,
      _pushDataChannelCompress,
    );
    if (text == null) return;

    onDebugMessage('dc(push) recv: $text');
    await _handlePushDataChannelText(text);
  }

  Future<void> _handlePushDataChannelText(String text) async {
    try {
      final decoded = await decodeJsonMap(text);
      if (decoded == null) {
        return;
      }
      onPushMessage(decoded);
    } catch (error) {
      onDebugMessage('dc(push) json decode failed: error=$error');
    }
  }

  // rpc DataChannel からのレスポンスを処理する
  void _handleRpcDataChannelMessage(Object? data) {
    final text = _decodeDataChannelMessage(
      'rpc',
      data,
      _rpcDataChannelCompress,
    );
    if (text == null) return;

    onDebugMessage('dc(rpc) recv: $text');
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return;
      final id = decoded['id'];
      if (id is! int) {
        onDebugMessage('dc(rpc) response without valid id: $id');
        return;
      }

      final completer = _rpcRequestCompleters.remove(id);
      if (completer == null) {
        onDebugMessage('dc(rpc) no pending request for id: $id');
        return;
      }
      _rpcTimeoutTimers.remove(id)?.cancel();

      if (decoded.containsKey('error')) {
        final error = decoded['error'];
        if (error is Map) {
          completer.completeError(
            SoraRpcError(
              code: (error['code'] as num?)?.toInt() ?? -1,
              message: error['message'] as String? ?? 'Unknown error',
              data: error['data'],
            ),
          );
        } else {
          completer.completeError(
            const SoraRpcError(code: -1, message: 'Unknown RPC error'),
          );
        }
      } else {
        completer.complete(decoded['result']);
      }
    } catch (error) {
      onDebugMessage('dc(rpc) json decode failed: error=$error');
    }
  }

  // stats DataChannel からの req-stats メッセージを処理する
  Future<void> _handleStatsDataChannelMessage(Object? data) async {
    final text = _decodeDataChannelMessage(
      'stats',
      data,
      _statsDataChannelCompress,
    );
    if (text == null) return;

    onDebugMessage('dc(stats) recv: $text');
    try {
      final decoded = await decodeJsonMap(text);
      if (decoded == null) return;
      final type = decoded['type'] as String?;
      if (type == 'req-stats') {
        final statsJson = await webrtcClient.getStats();
        final reports = statsJson != null ? await decodeJson(statsJson) : null;
        final statsMessage = <String, Object?>{'type': 'stats'};
        if (reports != null) {
          statsMessage['reports'] = reports;
        }
        final responseText = jsonEncode(statsMessage);
        onDebugMessage('dc(stats) send: $responseText');
        final encoded = utf8.encode(responseText);
        final Uint8List sendData;
        if (_statsDataChannelCompress) {
          sendData = Uint8List.fromList(_getCodec().encoder.convert(encoded));
        } else {
          sendData = encoded;
        }
        webrtcClient.sendStatsMessage(sendData);
      }
    } catch (error) {
      onDebugMessage('dc(stats) getStats or json decode failed: error=$error');
    }
  }

  // カスタムラベル DataChannel からのメッセージを処理する
  void _handleCustomDataChannelMessage(String label, Object? data) {
    Uint8List? bytes;
    if (data is Uint8List) {
      final compress =
          customChannelCompress[label] ??
          _findDataChannelCompressFlag(_lastOfferMessage ?? {}, label: label);
      if (compress) {
        try {
          bytes = _deflateDecompress(data);
        } catch (error) {
          onDebugMessage('dc($label) decode failed: error=$error');
          return;
        }
      } else {
        bytes = data;
      }
    } else if (data is String) {
      bytes = utf8.encode(data);
    }
    if (bytes == null) return;

    onDebugMessage('dc($label) recv: ${bytes.length} bytes');
    onDataChannelMessageEvent(
      SoraDataChannelMessage(label: label, data: bytes),
    );
  }

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  // _dataChannelDeflateRaw の現在値に応じた ZLibCodec を返す。
  ZLibCodec _getCodec() {
    return ZLibCodec(raw: _dataChannelDeflateRaw ?? false);
  }

  // DataChannel 受信データを UTF-8 文字列にデコードする。
  // compress フラグに応じて deflate 展開を試みる。
  String? _decodeDataChannelMessage(String label, Object? data, bool compress) {
    if (data is Uint8List) {
      try {
        if (compress) {
          final decompressed = _deflateDecompress(data);
          return utf8.decode(decompressed);
        } else {
          return utf8.decode(data);
        }
      } catch (error) {
        onDebugMessage('dc($label) decode failed: error=$error');
        return null;
      }
    } else if (data is String) {
      return data;
    }
    return null;
  }

  // DataChannel メッセージが圧縮されていれば展開する
  Uint8List _deflateDecompress(Uint8List input) {
    final preferred = _dataChannelDeflateRaw;
    final (:output, :detectedRaw) = deflateDecompress(input, preferred);
    if (detectedRaw != _dataChannelDeflateRaw) {
      if (_dataChannelDeflateRaw == null) {
        onDebugMessage('dc deflateRaw detected: $detectedRaw');
      }
      _dataChannelDeflateRaw = detectedRaw;
    }
    return output;
  }

  /// deflate 展開を行う。
  ///
  /// [preferred] が null の場合は raw=false → raw=true の順で試行し、
  /// 最初に成功した raw モードを [detectedRaw] として返す。
  /// [preferred] が非 null の場合は preferred を試し、
  /// 失敗時のみ !preferred へ fallback する。
  @visibleForTesting
  static ({Uint8List output, bool detectedRaw}) deflateDecompress(
    Uint8List input,
    bool? preferred,
  ) {
    final candidates = preferred == null
        ? const <bool>[false, true]
        : <bool>[preferred];

    Object? lastError;
    for (final raw in candidates) {
      try {
        final output = Uint8List.fromList(
          ZLibCodec(raw: raw).decoder.convert(input),
        );
        return (output: output, detectedRaw: raw);
      } catch (error) {
        lastError = error;
      }
    }

    if (preferred != null) {
      try {
        final output = Uint8List.fromList(
          ZLibCodec(raw: !preferred).decoder.convert(input),
        );
        return (output: output, detectedRaw: !preferred);
      } catch (error) {
        lastError = error;
      }
    }
    throw lastError ?? const FormatException('deflate decode failed');
  }

  // 指定ラベルの DataChannel compress フラグを取得する。
  // config が存在しない場合は false を返す。
  // カスタムラベルの送受信では customChannelCompress キャッシュが
  // 優先されるため、このメソッドはフォールバックとして使う。
  bool _findDataChannelCompressFlag(
    Map<String, Object?> message, {
    required String label,
  }) {
    final config = findDataChannelConfig(message, label: label);
    return config?['compress'] == true;
  }

  @visibleForTesting
  // offer メッセージの data_channels から指定ラベルの config を取得する。
  // ラベルが存在しない場合や data_channels が List でない場合は null を返す。
  static Map<String, Object?>? findDataChannelConfig(
    Map<String, Object?> message, {
    required String label,
  }) {
    final channels = message['data_channels'];
    if (channels is! List) {
      return null;
    }
    for (final channel in channels) {
      if (channel is! Map) {
        continue;
      }
      if (channel['label'] == label) {
        return Map<String, Object?>.from(
          channel.map((Object? key, Object? value) => MapEntry('$key', value)),
        );
      }
    }
    return null;
  }
}
