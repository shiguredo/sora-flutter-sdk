// PushAudioDevice を使う E2E 向けのダミー音声トラック補助。
//
// `useAudioDevice: false` で接続した場合でも local audio track を送信できるよう、
// PushAudio へ 10 ms ごとに PCM を流し続ける。

import 'dart:async';
import 'dart:typed_data';

import 'package:sora_sdk/sora_sdk.dart';

/// PushAudioDevice 向けの PCM 供給を伴う local audio track。
final class E2ePushAudioTrack {
  E2ePushAudioTrack._({
    required this.audioTrack,
    required this.sampleRate,
    required this.channels,
  });

  /// E2E で stream に積む local audio track。
  final LocalAudioTrack audioTrack;

  /// PushAudio に渡すサンプリングレート。
  final int sampleRate;

  /// PushAudio に渡すチャンネル数。
  final int channels;

  Timer? _timer;
  bool _disposed = false;

  /// PushAudioDevice と組み合わせて使う local audio track を生成する。
  static Future<E2ePushAudioTrack> create() async {
    final audioTrack = await MediaDevices.createAudioTrack();
    return E2ePushAudioTrack._(
      audioTrack: audioTrack,
      sampleRate: 48000,
      channels: 1,
    );
  }

  /// 10 ms ごとに無音 PCM を PushAudio へ流し続ける。
  void start() {
    if (_disposed) {
      throw StateError('E2ePushAudioTrack is disposed.');
    }
    _timer?.cancel();
    final samplesPer10ms = sampleRate ~/ 100;
    final silentBlock = Int16List(samplesPer10ms * channels);
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_disposed) {
        return;
      }
      PushAudio.pushPcm(silentBlock, sampleRate, channels);
    });
  }

  /// PushAudio への PCM 供給を停止する。
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// PushAudio 用の native buffer を解放し、タイマーを停止する。
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    stop();
    PushAudio.dispose();
  }
}
