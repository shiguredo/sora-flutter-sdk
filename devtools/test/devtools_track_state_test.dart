import 'package:flutter_test/flutter_test.dart';
import 'package:sora_devtools/src/devtools_track_state.dart';
import 'package:sora_sdk/sora_sdk.dart';

void main() {
  group('currentAudioTrackEnabled', () {
    test('localStream が null のとき fallback を返す', () {
      expect(currentAudioTrackEnabled(null, fallback: true), isTrue);
      expect(currentAudioTrackEnabled(null, fallback: false), isFalse);
    });

    test('audio track が空のとき fallback を返す', () {
      final stream = _FakeLocalMediaStream();

      expect(currentAudioTrackEnabled(stream, fallback: true), isTrue);
      expect(currentAudioTrackEnabled(stream, fallback: false), isFalse);
    });

    test('audio track があるとき最初の track の enabled を返す', () {
      final stream = _FakeLocalMediaStream(
        audioTracks: <LocalAudioTrack>[_FakeLocalAudioTrack(enabled: false)],
      );

      expect(currentAudioTrackEnabled(stream, fallback: true), isFalse);
    });
  });

  group('currentVideoTrackEnabled', () {
    test('localStream が null のとき fallback を返す', () {
      expect(currentVideoTrackEnabled(null, fallback: true), isTrue);
      expect(currentVideoTrackEnabled(null, fallback: false), isFalse);
    });

    test('video track が空のとき fallback を返す', () {
      final stream = _FakeLocalMediaStream();

      expect(currentVideoTrackEnabled(stream, fallback: true), isTrue);
      expect(currentVideoTrackEnabled(stream, fallback: false), isFalse);
    });

    test('video track があるとき最初の track の enabled を返す', () {
      final stream = _FakeLocalMediaStream(
        videoTracks: <LocalVideoTrack>[_FakeLocalVideoTrack(enabled: false)],
      );

      expect(currentVideoTrackEnabled(stream, fallback: true), isFalse);
    });
  });
}

class _FakeLocalMediaStream implements LocalMediaStream {
  _FakeLocalMediaStream({
    List<LocalAudioTrack> audioTracks = const <LocalAudioTrack>[],
    List<LocalVideoTrack> videoTracks = const <LocalVideoTrack>[],
  }) : _audioTracks = audioTracks,
       _videoTracks = videoTracks;

  final List<LocalAudioTrack> _audioTracks;
  final List<LocalVideoTrack> _videoTracks;

  @override
  List<LocalAudioTrack> getAudioTracks() => _audioTracks;

  @override
  List<LocalVideoTrack> getVideoTracks() => _videoTracks;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalAudioTrack implements LocalAudioTrack {
  _FakeLocalAudioTrack({required this.enabled});

  @override
  bool enabled;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLocalVideoTrack implements LocalVideoTrack {
  _FakeLocalVideoTrack({required this.enabled});

  @override
  bool enabled;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
