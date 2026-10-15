import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/screens/video_player_screen.dart';

/// Pins the precedence contract of [resolveOpenResumePosition] (#2303):
/// explicit request > shuffle-starts-from-beginning > offline progress >
/// server view offset.
void main() {
  group('resolveOpenResumePosition', () {
    test('explicit request wins over every other source', () {
      expect(
        resolveOpenResumePosition(
          requested: const Duration(minutes: 7),
          shuffleFromBeginning: true,
          offlineOffsetMs: 60_000,
          viewOffsetMs: 120_000,
        ),
        const Duration(minutes: 7),
      );
    });

    test('shuffle override returns zero even with stored offsets', () {
      expect(
        resolveOpenResumePosition(shuffleFromBeginning: true, offlineOffsetMs: 60_000, viewOffsetMs: 120_000),
        Duration.zero,
      );
    });

    test('offline progress beats the server view offset', () {
      expect(resolveOpenResumePosition(offlineOffsetMs: 60_000, viewOffsetMs: 120_000), const Duration(minutes: 1));
    });

    test('falls back to the server view offset', () {
      expect(resolveOpenResumePosition(viewOffsetMs: 120_000), const Duration(minutes: 2));
    });

    test('returns null when nothing is known', () {
      expect(resolveOpenResumePosition(), isNull);
      expect(resolveOpenResumePosition(offlineOffsetMs: 0), isNull);
    });

    test('a Silo resume of 30 s or more starts 7 s earlier (PlaybackStartPosition.kt:59-72)', () {
      expect(resolveOpenResumePosition(viewOffsetMs: 120_000, rewindResume: true), const Duration(seconds: 113));
      expect(resolveOpenResumePosition(viewOffsetMs: 30_000, rewindResume: true), const Duration(seconds: 23));
      expect(resolveOpenResumePosition(viewOffsetMs: 29_000, rewindResume: true), const Duration(seconds: 29));
    });

    test('an explicit request or shuffle is never rewound', () {
      expect(
        resolveOpenResumePosition(requested: const Duration(minutes: 5), viewOffsetMs: 120_000, rewindResume: true),
        const Duration(minutes: 5),
      );
      expect(resolveOpenResumePosition(shuffleFromBeginning: true, rewindResume: true), Duration.zero);
    });
  });
}
