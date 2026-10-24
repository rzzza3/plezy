import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/utils/media_version_resolver.dart';

import '../test_helpers/media_items.dart';

MediaItem _item({List<MediaVersion>? mediaVersions}) =>
    testMediaItem(id: 'movie-1', backend: MediaBackend.silo, title: 'Movie', mediaVersions: mediaVersions);

MediaVersion _version(String id) => MediaVersion(id: id, videoResolution: '1080', videoCodec: 'h264');

/// Answers [fetchItem] with [detail] (or throws [error]) and records each id.
class _DetailClient implements MediaServerClient {
  _DetailClient({this.detail, this.error});

  final MediaItem? detail;
  final Object? error;
  final requests = <String>[];

  @override
  Future<MediaItem?> fetchItem(String id) async {
    requests.add(id);
    if (error != null) throw error!;
    return detail;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('resolveMediaVersions', () {
    test('fetches full metadata when the browse row has no versions', () async {
      final client = _DetailClient(
        detail: _item(
          mediaVersions: const [
            MediaVersion(id: '1080', videoResolution: '1080', videoCodec: 'h264', height: 1080, width: 1920),
            MediaVersion(id: '2160', videoResolution: '4k', videoCodec: 'hevc', height: 2160, width: 3840),
          ],
        ),
      );

      final versions = await resolveMediaVersions(_item(), client);

      expect(versions.map((version) => version.id), ['1080', '2160']);
      expect(client.requests, ['movie-1']);
    });

    test('uses inline versions without fetching full metadata', () async {
      final client = _DetailClient();
      final inlineVersions = [_version('inline')];

      final versions = await resolveMediaVersions(_item(mediaVersions: inlineVersions), client);

      expect(versions, same(inlineVersions));
      expect(client.requests, isEmpty);
    });

    test('uses fallback versions without fetching full metadata', () async {
      final client = _DetailClient();
      final fallbackVersions = [_version('fallback')];

      final versions = await resolveMediaVersions(_item(), client, fallbackVersions: fallbackVersions);

      expect(versions, same(fallbackVersions));
      expect(client.requests, isEmpty);
    });

    test('returns an empty list when detail lookup fails', () async {
      final client = _DetailClient(error: Exception('server error'));

      final versions = await resolveMediaVersions(_item(), client);

      expect(versions, isEmpty);
    });
  });
}
