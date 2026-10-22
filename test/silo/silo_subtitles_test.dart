import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/silo/silo_models.dart';
import 'package:plezy/silo/silo_problem.dart';
import 'package:plezy/silo/silo_subtitles.dart';

import 'fake_silo.dart';

const _candidate = SiloSubtitleCandidate(
  id: 'os-77',
  provider: 'opensubtitles',
  language: 'en',
  releaseName: 'Secret.Title.2024.1080p',
  format: 'srt',
  score: 9.5,
  hearingImpaired: true,
);

void main() {
  group('search (SubtitleReadsV2Api.kt:12-23, 41-47)', () {
    test('posts the file id as a string with the languages, and maps the results', () async {
      final fake = FakeSilo(
        (_) => jsonResponse({
          'results': [
            {
              'id': 77,
              'provider': 'opensubtitles',
              'language': 'en',
              'release_name': 'Secret.Title.2024.1080p',
              'format': 'srt',
              'score': 9.5,
              'downloads': 1200,
              'hearing_impaired': false,
            },
            {'id': 'broken'},
          ],
          'warnings': ['podnapisi skipped'],
        }, 200),
      );
      final (session, _) = await signedInSession();
      await session.selectProfile('p-1', null);

      final found = await SiloSubtitles(siloHttpFor(fake, session)).search(41, ['en']);

      final request = fake.to('/api/v2/subtitles/search').single;
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {
        'media_file_id': '41',
        'languages': ['en'],
      });
      expect(request.header('X-Profile-Id'), 'p-1');
      expect(found.results.map((r) => (r.id, r.provider, r.releaseName, r.score, r.downloads)), [
        ('77', 'opensubtitles', 'Secret.Title.2024.1080p', 9.5, 1200),
      ], reason: 'a row missing its fields is dropped, not the whole answer');
      expect(found.warnings, ['podnapisi skipped']);
    });

    test('a server error surfaces as a SiloApiException', () async {
      final fake = FakeSilo((_) => jsonResponse({'detail': 'no providers'}, 503));
      final (session, _) = await signedInSession();

      await expectLater(
        SiloSubtitles(siloHttpFor(fake, session)).search(41, ['en']),
        throwsA(isA<SiloApiException>().having((e) => e.status, 'status', 503)),
      );
    });

    test('an invalid file is refused before any request', () async {
      final fake = FakeSilo((_) => jsonResponse({}, 200));
      final (session, _) = await signedInSession();

      await expectLater(
        SiloSubtitles(siloHttpFor(fake, session)).search(0, ['en']),
        throwsA(isA<SiloDecodeException>()),
      );
      expect(fake.requests, isEmpty);
    });
  });

  group('download (SubtitleDownloadV2Api.kt:12-20, 43-56)', () {
    test('sends the candidate once and returns the stored row id', () async {
      final fake = FakeSilo(
        (_) => jsonResponse({
          'subtitle': {
            'id': 9,
            'media_file_id': '41',
            'provider': 'opensubtitles',
            'language': 'en',
            'format': 'srt',
            'release_name': 'Secret.Title.2024.1080p',
            'score': 9.5,
            'hearing_impaired': true,
            'created_at': '2026-10-22T00:00:00Z',
          },
        }, 200),
      );
      final (session, _) = await signedInSession();

      final id = await SiloSubtitles(siloHttpFor(fake, session)).download(41, _candidate);

      expect(id, '9');
      expect(jsonDecode(fake.to('/api/v2/subtitles/download').single.body), {
        'media_file_id': '41',
        'provider': 'opensubtitles',
        'subtitle_id': 'os-77',
        'language': 'en',
        'release_name': 'Secret.Title.2024.1080p',
        'score': 9.5,
        'hearing_impaired': true,
      });
    });

    test('a failed download is not retried', () async {
      final fake = FakeSilo((_) => jsonResponse({}, 502));
      final (session, _) = await signedInSession();

      await expectLater(
        SiloSubtitles(siloHttpFor(fake, session)).download(41, _candidate),
        throwsA(isA<SiloApiException>()),
      );
      expect(fake.to('/api/v2/subtitles/download'), hasLength(1));
    });

    test('a stored row for another file is refused', () async {
      final fake = FakeSilo(
        (_) => jsonResponse({
          'subtitle': {'id': 9, 'media_file_id': '42'},
        }, 200),
      );
      final (session, _) = await signedInSession();

      await expectLater(
        SiloSubtitles(siloHttpFor(fake, session)).download(41, _candidate),
        throwsA(isA<SiloDecodeException>()),
      );
    });
  });
}
