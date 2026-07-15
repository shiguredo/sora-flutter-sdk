// PushAudioDevice を使う E2E 向けのダミー音声トラック補助。
//
// 実音声デバイスを使わない接続でも local audio track を送信できるよう、
// PushAudio へ 10 ms ごとに PCM を流し続ける。

import 'dart:async';
import 'dart:math' as math;
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
  var _decodedEnergy = 0.0;
  var _decodedSamples = 0;

  /// これまでに pull したデコード後 PCM の累積値を返す。
  DecodedAudioObservation get decodedAudioObservation {
    return DecodedAudioObservation(
      totalEnergy: _decodedEnergy,
      totalSamples: _decodedSamples,
    );
  }

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
      _pushAndCapture(silentBlock);
    });
  }

  /// 10 ms ごとに連続した正弦波 PCM を PushAudio へ流し続ける。
  ///
  /// 無音 PCM と符号化後の payload サイズを比較し、実際の音声サンプルが相手まで
  /// 届いたことを検証する E2E ではこのメソッドを使う。
  void startTone({double frequencyHz = 440, int amplitude = 12000}) {
    if (_disposed) {
      throw StateError('E2ePushAudioTrack is disposed.');
    }
    if (frequencyHz <= 0 || frequencyHz >= sampleRate / 2) {
      throw ArgumentError.value(
        frequencyHz,
        'frequencyHz',
        'frequencyHz must be between 0 and the Nyquist frequency.',
      );
    }
    if (amplitude <= 0 || amplitude > 32767) {
      throw ArgumentError.value(
        amplitude,
        'amplitude',
        'amplitude must be between 1 and 32767.',
      );
    }

    _timer?.cancel();
    final samplesPer10ms = sampleRate ~/ 100;
    final phaseStep = 2 * math.pi * frequencyHz / sampleRate;
    var phase = 0.0;

    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_disposed) {
        return;
      }
      final block = Int16List(samplesPer10ms * channels);
      for (var sample = 0; sample < samplesPer10ms; sample++) {
        final value = (math.sin(phase) * amplitude).round();
        for (var channel = 0; channel < channels; channel++) {
          block[sample * channels + channel] = value;
        }
        phase += phaseStep;
        if (phase >= 2 * math.pi) {
          phase -= 2 * math.pi;
        }
      }
      _pushAndCapture(block);
    });
  }

  /// 送信 PCM を注入し、同じ 10 ms 区間の受信 PCM を pull する。
  void _pushAndCapture(Int16List block) {
    PushAudio.pushPcm(block, sampleRate, channels);
    final decoded = PushAudio.pullPcm(sampleRate, channels);
    for (final sample in decoded) {
      final normalized = sample / 32768.0;
      _decodedEnergy += normalized * normalized;
    }
    _decodedSamples += decoded.length;
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

/// デコード後 PCM の累積 energy とサンプル数。
final class DecodedAudioObservation {
  const DecodedAudioObservation({
    required this.totalEnergy,
    required this.totalSamples,
  });

  final double totalEnergy;
  final int totalSamples;

  @override
  String toString() {
    return 'DecodedAudioObservation('
        'totalEnergy=$totalEnergy, '
        'totalSamples=$totalSamples)';
  }
}
