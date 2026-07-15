/// PushAudioDevice (カスタム ADM) で PCM データを送受信する API。
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi/webrtc_client.dart';

/// PushAudioDevice で PCM データを送受信する API。
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
    final ptr = _ensureBuffer(length);
    for (var i = 0; i < length; i++) {
      ptr[i] = data[i];
    }
    lib.soraPushAudioOnData(ptr, length ~/ channels, channels, sampleRate);
  }

  /// PushAudioDevice が受信した音声を PCM として取り出す。
  ///
  /// 物理出力デバイスを使わずに受信音声のデコードを進めるため、10 ms ごとに
  /// 呼び出す。[sampleRate] と [channels] は出力 PCM の形式を指定する。
  /// playout が開始していない場合は空のリストを返す。
  static Int16List pullPcm(
    int sampleRate,
    int channels, {
    int durationMs = 10,
  }) {
    if (sampleRate <= 0) {
      throw ArgumentError.value(sampleRate, 'sampleRate', 'must be positive');
    }
    if (channels <= 0) {
      throw ArgumentError.value(channels, 'channels', 'must be positive');
    }
    if (durationMs <= 0) {
      throw ArgumentError.value(durationMs, 'durationMs', 'must be positive');
    }

    final samples = sampleRate * durationMs ~/ 1000;
    final ptr = _ensureBuffer(samples * channels);
    final samplesOut = WebrtcClient.sharedLib.soraPullAudioData(
      ptr,
      samples,
      channels,
      sampleRate,
    );
    if (samplesOut < 0 || samplesOut > samples) {
      throw StateError('Failed to pull PCM data: samplesOut=$samplesOut');
    }
    if (samplesOut == 0) {
      return Int16List(0);
    }
    return Int16List.fromList(ptr.asTypedList(samplesOut * channels));
  }

  /// ネイティブバッファを解放する。
  static void dispose() {
    _disposeBuffer();
  }

  static Pointer<Int16> _ensureBuffer(int length) {
    if (_buffer == null || _bufferLength < length) {
      _disposeBuffer();
      _buffer = calloc<Int16>(length);
      _bufferLength = length;
    }
    return _buffer!;
  }

  static void _disposeBuffer() {
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
      _bufferLength = 0;
    }
  }
}
