// PushAudio を使ったビープ音トラック (devtools 用)。

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:sora_sdk/sora_sdk.dart';

class _BeepAudioGenerator {
  _BeepAudioGenerator({
    this.sampleRate = 48000,
    this.channels = 1,
    this.frequency = 440,
    this.durationMs = 100,
    this.volume = 0.5,
  });

  final int sampleRate;
  final int channels;
  final int frequency;
  final int durationMs;
  final double volume;

  int get _samplesPer10ms => sampleRate ~/ 100;
  int get _blockSize => _samplesPer10ms * channels;
  int get _totalBlocks => durationMs ~/ 10;

  int _beepBlockCounter = 0;
  int _remainingBeepBlocks = 0;

  void trigger() {
    _beepBlockCounter = 0;
    _remainingBeepBlocks = _totalBlocks;
  }

  Int16List generate10msBlock() {
    final block = Int16List(_blockSize);
    if (_remainingBeepBlocks <= 0) return block;
    _remainingBeepBlocks--;
    final startSample = _beepBlockCounter * _samplesPer10ms;
    _beepBlockCounter++;
    for (var i = 0; i < _samplesPer10ms; i++) {
      final sampleIndex = startSample + i;
      final value =
          (volume * sin(2 * pi * frequency / sampleRate * sampleIndex) * 32767)
              .round();
      for (var ch = 0; ch < channels; ch++) {
        block[i * channels + ch] = value;
      }
    }
    return block;
  }
}

class DevToolsBeepAudioTrack {
  DevToolsBeepAudioTrack._({required this.audioTrack});

  final LocalAudioTrack audioTrack;
  final _BeepAudioGenerator _generator = _BeepAudioGenerator();
  Timer? _timer;
  bool _disposed = false;

  factory DevToolsBeepAudioTrack.fromTrack(LocalAudioTrack track) {
    return DevToolsBeepAudioTrack._(audioTrack: track);
  }

  void start() {
    if (_disposed) throw StateError('DevToolsBeepAudioTrack is disposed.');
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_disposed) return;
      final pcm = _generator.generate10msBlock();
      PushAudio.pushPcm(pcm, _generator.sampleRate, _generator.channels);
    });
  }

  void triggerBeep() => _generator.trigger();

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stop();
    PushAudio.dispose();
    await audioTrack.dispose();
  }
}
