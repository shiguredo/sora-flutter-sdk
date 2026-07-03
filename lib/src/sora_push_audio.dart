/// PushAudioDevice (カスタム ADM) に PCM データを注入する API。
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/webrtc_client.dart';

/// PushAudioDevice に PCM データを注入する API。
abstract final class PushAudio {
  /// Pre-allocated native buffer for PCM data. null if not initialized.
  static Pointer<Int16>? _buffer;
  static int _bufferLength = 0;

  /// Push PCM データを ADM に注入する。
  ///
  /// [data] は 10ms 分の int16 PCM データ。
  /// [sampleRate] はサンプリングレート（通常 48000）。
  /// [channels] はチャンネル数（通常 1）。
  ///
  /// 初回呼び出し時にネイティブバッファを確保し、以降は再利用する。
  /// [dispose] でバッファを解放すること。
  static void pushPcm(Int16List data, int sampleRate, int channels) {
    final lib = WebrtcClient.sharedLib;
    final length = data.length;
    if (_buffer == null || _bufferLength < length) {
      _disposeBuffer();
      _buffer = calloc<Int16>(length);
      _bufferLength = length;
    }
    final ptr = _buffer!;
    for (var i = 0; i < length; i++) {
      ptr[i] = data[i];
    }
    lib.soraPushAudioOnData(ptr, sampleRate, channels, length ~/ channels);
  }

  /// ネイティブバッファを解放する。
  static void dispose() {
    _disposeBuffer();
  }

  static void _disposeBuffer() {
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
      _bufferLength = 0;
    }
  }
}
