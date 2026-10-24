import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/utils/media_version_resolver.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/media_items.dart';

MediaItem _item({List<MediaVersion>? mediaVersions}) =>
    testMediaItem(id: 'movie-1', title: 'Movie', mediaVersions: mediaVersions);

MediaVersion _version(String id) => MediaVersion(id: id, videoResolution: '1080', videoCodec: 'h264');

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('resolveMediaVersions', () {
    test('fetches full metadata when the browse row has no versions', () async {
      final requests = <Uri>[];
      final client = testPlexClient(
        handler: (request) async {
          requests.add(request.url);
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'Metadata': [
                  {
                    'ratingKey': 'movie-1',
                    'type': 'movie',
                    'title': 'Movie',
                    'Media': [
                      {'id': 1080, 'videoResolution': '1080', 'videoCodec': 'h264', 'height': 1080, 'width': 1920},
                      {'id': 2160, 'videoResolution': '4k', 'videoCodec': 'hevc', 'height': 2160, 'width': 3840},
                    ],
                  },
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      addTearDown(client.close);

      final versions = await resolveMediaVersions(_item(), client);

      expect(versions.map((version) => version.id), ['1080', '2160']);
      expect(requests, hasLength(1));
      expect(requests.single.path, '/library/metadata/movie-1');
      expect(requests.single.queryParameters['includeStreams'], '1');
    });

    test('uses inline versions without fetching full metadata', () async {
      var requested = false;
      final client = testPlexClient(
        handler: (request) async {
          requested = true;
          return http.Response('unexpected', 500);
        },
      );
      addTearDown(client.close);
      final inlineVersions = [_version('inline')];

      final versions = await resolveMediaVersions(_item(mediaVersions: inlineVersions), client);

      expect(versions, same(inlineVersions));
      expect(requested, isFalse);
    });

    test('uses fallback versions without fetching full metadata', () async {
      var requested = false;
      final client = testPlexClient(
        handler: (request) async {
          requested = true;
          return http.Response('unexpected', 500);
        },
      );
      addTearDown(client.close);
      final fallbackVersions = [_version('fallback')];

      final versions = await resolveMediaVersions(_item(), client, fallbackVersions: fallbackVersions);

      expect(versions, same(fallbackVersions));
      expect(requested, isFalse);
    });

    test('returns an empty list when detail lookup fails', () async {
      final client = testPlexClient(handler: (request) async => http.Response('server error', 500));
      addTearDown(client.close);

      final versions = await resolveMediaVersions(_item(), client);

      expect(versions, isEmpty);
    });
  });
}
