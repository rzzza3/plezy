import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/utils/delete_impact.dart';

import '../test_helpers/media_items.dart';

void main() {
  // Direct contract of the predicate every delete-impact verdict rests on. Neither
  // mapper can currently produce a version with zero parts, so this is the
  // only place that shape is pinned.
  group('completePartFiles', () {
    test('rejects an empty version list', () {
      expect(completePartFiles(const []), isNull);
    });

    test('rejects a version with no parts rather than reporting zero files', () {
      expect(completePartFiles(const [MediaVersion(id: 'v-1')]), isNull);
    });

    test('rejects a version where any single part lacks a path', () {
      expect(
        completePartFiles(const [
          MediaVersion(
            id: 'v-1',
            parts: [
              MediaPart(id: 'p-1', file: '/tv/a.mkv'),
              MediaPart(id: 'p-2'),
            ],
          ),
        ]),
        isNull,
        reason: 'one unknown path makes the whole file list untrustworthy',
      );
    });

    test('collapses duplicate paths across versions into one file', () {
      expect(
        completePartFiles(const [
          MediaVersion(
            id: 'v-1',
            parts: [MediaPart(id: 'p-1', file: '/tv/a.mkv')],
          ),
          MediaVersion(
            id: 'v-2',
            parts: [MediaPart(id: 'p-2', file: '/tv/a.mkv')],
          ),
        ]),
        {'/tv/a.mkv'},
      );
    });

    test('returns every distinct path of a multi-part version', () {
      expect(
        completePartFiles(const [
          MediaVersion(
            id: 'v-1',
            parts: [
              MediaPart(id: 'p-1', file: '/tv/cd1.mkv'),
              MediaPart(id: 'p-2', file: '/tv/cd2.mkv'),
            ],
          ),
        ]),
        {'/tv/cd1.mkv', '/tv/cd2.mkv'},
      );
    });
  });

  // Cancellation is backend-neutral, so it is pinned here against a narrow
  // fake under `fakeAsync` — deterministic, and no wall-clock waiting.
  group('cancellation on timeout', () {
    const timeout = Duration(seconds: 10);

    MediaItem pathlessEpisode(String id, int index) => testMediaItem(
      id: id,
      kind: MediaKind.episode,
      title: 'Episode $index',
      parentId: 'season-1',
      parentIndex: 1,
      index: index,
      grandparentId: 'show-1',
      serverId: 'srv-1',
      mediaVersions: const [
        MediaVersion(
          id: 'v',
          parts: [MediaPart(id: 'p')],
        ),
      ],
    );

    test('no further sibling is fetched once the deadline has returned', () {
      final target = testMediaItem(
        id: 'ep-2',
        kind: MediaKind.episode,
        title: 'Cat in the Bag',
        parentId: 'season-1',
        parentIndex: 1,
        index: 2,
        grandparentId: 'show-1',
        serverId: 'srv-1',
        mediaVersions: const [
          MediaVersion(
            id: 'v-2',
            parts: [MediaPart(id: 'p-2', file: '/tv/bb/S01E02.mkv')],
          ),
        ],
      );
      // Every sibling row lacks a path, so each one costs a detail lookup.
      final client = _GatedClient(
        children: [target, for (var index = 3; index < 30; index++) pathlessEpisode('ep-$index', index)],
      );

      DeleteImpact? impact;
      fakeAsync((async) {
        resolveDeleteImpact(item: target, client: client, timeout: timeout).then((value) => impact = value);

        // Let the children lookup land and the first sibling fetch begin.
        async.flushMicrotasks();
        expect(client.itemFetches, 1, reason: 'one sibling in flight');
        expect(impact, isNull);

        async.elapse(timeout + const Duration(seconds: 1));
        expect(impact?.scope, DeleteImpactScope.unverified);
        expect(impact?.reason, DeleteImpactUnverifiedReason.probeFailed);
        expect(client.itemFetches, 1, reason: 'the deadline must not have started another');

        // The abandoned request finally answers. The loop resumes here — and
        // must stop instead of walking the remaining 26 siblings.
        client.releaseFetch();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));

        expect(
          client.itemFetches,
          1,
          reason: 'a completed in-flight fetch must not restart the walk after the probe gave up',
        );
      });
    });

    test('an uninterrupted probe still visits every sibling', () {
      final target = testMediaItem(
        id: 'ep-2',
        kind: MediaKind.episode,
        parentId: 'season-1',
        index: 2,
        grandparentId: 'show-1',
        serverId: 'srv-1',
        mediaVersions: const [
          MediaVersion(
            id: 'v-2',
            parts: [MediaPart(id: 'p-2', file: '/tv/bb/S01E02.mkv')],
          ),
        ],
      );
      final client = _GatedClient(children: [target, pathlessEpisode('ep-3', 3), pathlessEpisode('ep-4', 4)])
        ..autoRelease = true
        ..detailFile = '/tv/bb/S01E02.mkv';

      DeleteImpact? impact;
      fakeAsync((async) {
        resolveDeleteImpact(item: target, client: client, timeout: timeout).then((value) => impact = value);
        async.flushMicrotasks();

        expect(client.itemFetches, 2, reason: 'both path-less siblings resolved');
        expect(impact?.scope, DeleteImpactScope.broad);
        expect(impact?.sharedWith.map((item) => item.id), ['ep-3', 'ep-4']);
      });
    });

    test('the season is never listed when the deadline expires on the item itself', () {
      // The target's own row carries no path, so its lookup is the first thing
      // outstanding. Resuming past it would ask the server for the children of
      // a season nobody is waiting on any more.
      final target = pathlessEpisode('ep-2', 2);
      final client = _GatedClient(children: [target, pathlessEpisode('ep-3', 3)]);

      DeleteImpact? impact;
      fakeAsync((async) {
        resolveDeleteImpact(item: target, client: client, timeout: timeout).then((value) => impact = value);
        async.flushMicrotasks();
        expect(client.itemFetches, 1);
        expect(client.childrenFetches, 0);

        async.elapse(timeout + const Duration(seconds: 1));
        expect(impact?.reason, DeleteImpactUnverifiedReason.probeFailed);

        client.releaseFetch();
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));

        expect(client.childrenFetches, 0, reason: 'an abandoned probe must not go on to list the season');
        expect(client.itemFetches, 1);
      });
    });
  });
}

/// Neutral client whose item lookups can be held open, so a test can place the
/// probe deadline in the middle of one.
class _GatedClient implements MediaServerClient {
  _GatedClient({required this.children});

  final List<MediaItem> children;

  /// Answer item lookups immediately instead of gating them.
  bool autoRelease = false;

  /// Path reported by a released lookup.
  String detailFile = '/tv/bb/other.mkv';

  int itemFetches = 0;
  int childrenFetches = 0;
  final List<Completer<MediaItem?>> _pending = [];

  void releaseFetch() {
    for (final completer in _pending) {
      if (!completer.isCompleted) completer.complete(_detail());
    }
    _pending.clear();
  }

  MediaItem _detail() => testMediaItem(
    id: 'resolved',
    kind: MediaKind.episode,
    serverId: 'srv-1',
    mediaVersions: [
      MediaVersion(
        id: 'v',
        parts: [MediaPart(id: 'p', file: detailFile)],
      ),
    ],
  );

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    childrenFetches++;
    return children;
  }

  @override
  Future<MediaItem?> fetchItem(String id) {
    itemFetches++;
    if (autoRelease) return Future.value(_detail());
    final completer = Completer<MediaItem?>();
    _pending.add(completer);
    return completer.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
