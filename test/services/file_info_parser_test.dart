import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/file_info_parser.dart';

/// Unit tests for the backend-agnostic stream walker. Each backend is
/// represented by its own [FileInfoStreamReader] implementation, so the
/// tests fix two things:
///   1. The walker's accounting (single video pointer, every audio + sub
///      tracked, raw video stream retained once).
///   2. Each reader's mapping from raw JSON to the neutral track classes.
void main() {
  group('walkStreams (Plex reader)', () {
    const reader = PlexFileInfoStreamReader();

    test('captures the first video stream and accumulates audio + subs', () {
      final streams = [
        // streamType 1=video, 2=audio, 3=subtitle
        {'streamType': '1', 'id': '100', 'frameRate': 23.976, 'colorSpace': 'bt709'},
        {
          'streamType': '2',
          'id': '101',
          'index': '1',
          'codec': 'eac3',
          'language': 'English',
          'channels': '6',
          'selected': true,
          'displayTitle': 'English (EAC3 5.1)',
        },
        {
          'streamType': 2,
          'id': 102,
          'index': 2,
          'codec': 'aac',
          'language': 'French',
          'channels': 2,
          'selected': false,
        },
        {
          'streamType': '3',
          'id': '200',
          'index': '3',
          'codec': 'srt',
          'language': 'English',
          'forced': false,
          'selected': false,
          'key': '/library/streams/200',
        },
      ];

      final out = walkStreams(streams, reader);

      expect(out.videoStream?['id'], '100');
      expect(out.videoStream?['frameRate'], closeTo(23.976, 1e-6));
      expect(out.audioTracks.map((t) => t.id), [101, 102]);
      expect(out.audioTracks[0].channels, 6);
      expect(out.audioTracks[0].selected, isTrue);
      expect(out.audioTracks[1].selected, isFalse);
      expect(out.subtitleTracks, hasLength(1));
      expect(out.subtitleTracks.first.key, '/library/streams/200');
    });

    test('null and empty inputs short-circuit to FileInfoStreams.empty', () {
      expect(identical(walkStreams(null, reader), FileInfoStreams.empty), isTrue);
      expect(identical(walkStreams(const [], reader), FileInfoStreams.empty), isTrue);
    });

    test('skips entries with unknown streamType', () {
      final streams = [
        {'streamType': 99, 'id': 1}, // unknown
        {'streamType': 'audio', 'id': 2}, // wrong type
        {'streamType': 1, 'id': 3, 'frameRate': 24},
      ];
      final out = walkStreams(streams, reader);
      expect(out.audioTracks, isEmpty);
      expect(out.subtitleTracks, isEmpty);
      expect(out.videoStream?['id'], 3);
      expect(out.videoStream?['frameRate'], 24);
    });

    test('skips non-Map entries gracefully', () {
      final streams = ['not a map', 42, null];
      final out = walkStreams(streams, reader);
      expect(out.videoStream, isNull);
      expect(out.audioTracks, isEmpty);
      expect(out.subtitleTracks, isEmpty);
    });
  });
}
