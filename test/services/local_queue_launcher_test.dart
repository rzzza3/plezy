import 'dart:async';

import 'package:flutter/material.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/ids.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/local_queue_launcher.dart';
import 'package:plezy/services/media_list_playback_launcher.dart';
import 'package:plezy/services/playlist_items_loader.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/widgets/dialog_action_button.dart';
import 'package:plezy/i18n/strings.g.dart';

import '../test_helpers/paged_fakes.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// Recording fake for the [MediaServerClient] surface the launcher uses.
class _RecordingClient implements MediaServerClient {
  final List<MediaItem> playableDescendantsResponse;
  final List<MediaItem> seriesEpisodesResponse;
  final List<MediaItem> playlistItemsResponse;
  final Completer<void>? playlistPageGate;
  final List<AbortController?> playlistPageAborts = [];
  final List<String> fetchPlayableDescendantsCalls = [];
  final List<String> fetchSeriesEpisodesCalls = [];
  final List<({String id, int offset, int limit})> fetchPlaylistItemsCalls = [];

  _RecordingClient({
    this.playableDescendantsResponse = const [],
    this.seriesEpisodesResponse = const [],
    this.playlistItemsResponse = const [],
    this.playlistPageGate,
  });

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    fetchPlayableDescendantsCalls.add(parentId);
    return playableDescendantsResponse;
  }

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) async {
    fetchSeriesEpisodesCalls.add(seriesId);
    return seriesEpisodesResponse;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async {
    final offset = start ?? 0;
    final limit = size ?? fakeMediaPageSize;
    fetchPlaylistItemsCalls.add((id: id, offset: offset, limit: limit));
    playlistPageAborts.add(abort);
    await _waitForGate(playlistPageGate, abort);
    return fakeLibraryPage(playlistItemsResponse, start: start, size: size);
  }

  Future<void> _waitForGate(Completer<void>? gate, AbortController? abort) async {
    if (gate == null) return;
    if (abort == null) {
      await gate.future;
      return;
    }
    await Future.any<void>([gate.future, abort.trigger]);
    abort.throwIfAborted();
  }

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Playlist fetch that fails before the loading dialog's first frame,
/// exercising `executeWithLoading`'s early-failure path.
class _ThrowingClient extends _RecordingClient {
  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async {
    fetchPlaylistItemsCalls.add((id: id, offset: start ?? 0, limit: size ?? fakeMediaPageSize));
    throw Exception('connection refused');
  }
}

MediaItem _ep(String id, {ServerId? serverId}) => testMediaItem(
  id: id,
  backend: MediaBackend.silo,
  kind: MediaKind.episode,
  title: 'Episode $id',
  serverId: serverId ?? ServerId('srv-silo'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
  });

  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext capturedContext;
    // Wrap in MaterialApp + Scaffold so ScaffoldMessenger is available
    // for the error-path snackbars the launcher emits.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return capturedContext;
  }

  group('LocalQueueLauncher', () {
    testWidgets('input guard rejects strings (neither MediaItem nor MediaPlaylist)', (tester) async {
      final ctx = await pumpContext(tester);
      final launcher = LocalQueueLauncher(context: ctx);

      final result = await launcher.launchFromCollectionOrPlaylist(item: 'not-an-item', shuffle: false);

      expect(result, isA<PlayQueueError>());
      final error = (result as PlayQueueError).error;
      expect(error.toString(), contains('collection or playlist'));
    });

    testWidgets('input guard rejects items without serverId', (tester) async {
      final ctx = await pumpContext(tester);
      final launcher = LocalQueueLauncher(context: ctx);

      final orphan = testMediaItem(
        id: 'col-1',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        // no serverId
      );

      final result = await launcher.launchFromCollectionOrPlaylist(item: orphan, shuffle: false);

      expect(result, isA<PlayQueueError>());
      expect((result as PlayQueueError).error.toString(), contains('serverId'));
    });

    testWidgets('collection path expands to playable items in order', (tester) async {
      final ctx = await pumpContext(tester);
      final fetched = [_ep('e1'), _ep('e2'), _ep('e3')];
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async {
          expect(playback.isQueueActive, isTrue);
          expect(playback.loadedItems, orderedEquals(fetched));
          expect(playback.currentQueueItem, same(fetched.first));
          navigated.add(m);
        },
      );

      final collection = testMediaItem(
        id: 'col-99',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: false,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(fakeClient.fetchPlayableDescendantsCalls, ['col-99']);
      // Queue is seeded in original order, current is items[0].
      expect(playback.loadedItems.map((m) => m.id).toList(), ['e1', 'e2', 'e3']);
      expect(playback.isQueueActive, isTrue);
      expect(playback.isShuffleActive, isFalse);
      // First item is what the player navigates to.
      expect(navigated.single.id, 'e1');
    });

    testWidgets('playlist path uses playlist page endpoint', (tester) async {
      final ctx = await pumpContext(tester);
      final fetched = [_ep('a'), _ep('b')];
      final fakeClient = _RecordingClient(playlistItemsResponse: fetched);
      final playback = PlaybackStateProvider();

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {},
      );

      final playlist = const MediaPlaylist(
        id: 'pl-7',
        backend: MediaBackend.silo,
        title: 'Mix',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: playlist,
        shuffle: false,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      // Playlist-defined order via the dedicated endpoint — no recursive
      // descendant expansion (which doesn't preserve playlist order).
      expect(fakeClient.fetchPlayableDescendantsCalls, isEmpty);
      expect(fakeClient.fetchPlaylistItemsCalls.map((c) => c.id).toList(), ['pl-7']);
      expect(fakeClient.fetchPlaylistItemsCalls.first.offset, 0);
      expect(playback.loadedItems.map((m) => m.id).toList(), ['a', 'b']);
    });

    testWidgets('playlist path pages through every item', (tester) async {
      final ctx = await pumpContext(tester);
      // Enough items to span 2 default playlist pages — the loop must keep paging until
      // the server returns a short page.
      final fetched = List.generate(playlistItemsPageSize + 50, (i) => _ep('p$i'));
      final fakeClient = _RecordingClient(playlistItemsResponse: fetched);
      final playback = PlaybackStateProvider();

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {},
      );

      final playlist = const MediaPlaylist(
        id: 'pl-big',
        backend: MediaBackend.silo,
        title: 'Big',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: playlist,
        shuffle: false,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.length, playlistItemsPageSize + 50);
      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(2));
      expect(fakeClient.fetchPlaylistItemsCalls.first.offset, 0);
      expect(fakeClient.fetchPlaylistItemsCalls[1].offset, playlistItemsPageSize);
    });

    testWidgets('collection containing a Series entry only seeds playable descendants', (tester) async {
      // Anchor: the recursive expansion is what skips the unplayable Series
      // container. If a future change reverts to fetchChildren the test
      // fails because a Series row would leak into the queue.
      final ctx = await pumpContext(tester);
      final movie = testMediaItem(
        id: 'movie-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        serverId: 'srv-silo',
      );
      final ep1 = _ep('series-A-ep1');
      final ep2 = _ep('series-A-ep2');
      final fakeClient = _RecordingClient(playableDescendantsResponse: [movie, ep1, ep2]);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async => navigated.add(m),
      );

      final collection = testMediaItem(
        id: 'col-mixed',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: false,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(playback.loadedItems.map((m) => m.id).toList(), ['movie-1', 'series-A-ep1', 'series-A-ep2']);
      // No Series rows leaked into the queue.
      expect(playback.loadedItems.any((m) => m.kind == MediaKind.show), isFalse);
      expect(navigated.single.id, 'movie-1');
    });

    testWidgets('shuffle=true reorders the queue (seed-stable assertion)', (tester) async {
      final ctx = await pumpContext(tester);
      // Use enough items that a coincidence-preserved order is statistically
      // unlikely (1 / 50! ~ 0).
      final originalIds = List.generate(50, (i) => 'e$i');
      final fetched = originalIds.map(_ep).toList();
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final playback = PlaybackStateProvider();

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {},
      );

      final collection = testMediaItem(
        id: 'col-1',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: true,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      // Same set of ids, just reordered.
      final shuffledIds = playback.loadedItems.map((m) => m.id).toList();
      expect(shuffledIds.toSet(), originalIds.toSet());
      expect(shuffledIds.length, originalIds.length);
      expect(playback.isShuffleActive, isTrue);
      // The shuffle should not preserve the original order.
      expect(shuffledIds, isNot(equals(originalIds)));
    });

    testWidgets('shuffled launch strips the launched item\'s resume offset when the pref is on (#2303)', (
      tester,
    ) async {
      final ctx = await pumpContext(tester);
      await SettingsService.instance.write(SettingsService.shuffleStartsFromBeginning, true);
      // Every item carries an offset so whichever one the shuffle lands on
      // proves the strip.
      final fetched = [_ep('a'), _ep('b'), _ep('c')].map((m) => m.copyWith(viewOffsetMs: 120_000)).toList();
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async => navigated.add(m),
      );

      final collection = testMediaItem(
        id: 'col-1',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: true,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(navigated.single.viewOffsetMs, 0);
      // The launched copy is the queue's own entry: membership is by identity,
      // and the player drops a queue that does not hold the item it opened.
      expect(playback.isItemInActiveQueue(navigated.single), isTrue);
      // The other queue items keep their server offsets; the in-player
      // override covers them.
      expect(
        playback.loadedItems.where((m) => !identical(m, navigated.single)).every((m) => m.viewOffsetMs == 120_000),
        isTrue,
      );
    });

    testWidgets('shuffled launch keeps the resume offset when the pref is off', (tester) async {
      final ctx = await pumpContext(tester);
      final fetched = [_ep('a'), _ep('b'), _ep('c')].map((m) => m.copyWith(viewOffsetMs: 120_000)).toList();
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: PlaybackStateProvider(),
        navigateForTesting: (m) async => navigated.add(m),
      );

      final collection = testMediaItem(
        id: 'col-1',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: true,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(navigated.single.viewOffsetMs, 120_000);
    });

    testWidgets('startItem positions playback at the matching index', (tester) async {
      final ctx = await pumpContext(tester);
      final fetched = [_ep('a'), _ep('b'), _ep('c'), _ep('d')];
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async => navigated.add(m),
      );

      final collection = testMediaItem(
        id: 'col-start',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: false,
        startItem: fetched[2], // 'c'
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      // Queue keeps original order; player navigates to the chosen item.
      expect(playback.loadedItems.map((m) => m.id).toList(), ['a', 'b', 'c', 'd']);
      expect(navigated.single.id, 'c');
    });

    testWidgets('startItem with no match falls back to head of queue', (tester) async {
      final ctx = await pumpContext(tester);
      final fetched = [_ep('a'), _ep('b')];
      final fakeClient = _RecordingClient(playableDescendantsResponse: fetched);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async => navigated.add(m),
      );

      final collection = testMediaItem(
        id: 'col',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: false,
        startItem: _ep('not-in-list'),
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueSuccess>());
      expect(navigated.single.id, 'a');
    });

    testWidgets('launchShuffledShow rejects non-show/season kinds', (tester) async {
      final ctx = await pumpContext(tester);
      final launcher = LocalQueueLauncher(context: ctx);

      final movie = testMediaItem(id: 'm1', backend: MediaBackend.silo, kind: MediaKind.movie, serverId: 'srv-silo');

      final result = await launcher.launchShuffledShow(metadata: movie, showLoadingIndicator: false);

      expect(result, isA<PlayQueueError>());
      expect((result as PlayQueueError).error.toString(), contains('shows and seasons'));
    });

    testWidgets('launchShuffledShow rejects season missing parentId', (tester) async {
      final ctx = await pumpContext(tester);
      final launcher = LocalQueueLauncher(context: ctx);

      final season = testMediaItem(id: 's1', backend: MediaBackend.silo, kind: MediaKind.season, serverId: 'srv-silo');

      final result = await launcher.launchShuffledShow(metadata: season, showLoadingIndicator: false);

      expect(result, isA<PlayQueueError>());
      expect((result as PlayQueueError).error.toString(), contains('parentId'));
    });

    testWidgets('launchShuffledShow rejects items missing serverId', (tester) async {
      final ctx = await pumpContext(tester);
      final launcher = LocalQueueLauncher(context: ctx);

      final orphan = testMediaItem(id: 'show-orphan', backend: MediaBackend.silo, kind: MediaKind.show);

      final result = await launcher.launchShuffledShow(metadata: orphan, showLoadingIndicator: false);

      expect(result, isA<PlayQueueError>());
      expect((result as PlayQueueError).error.toString(), contains('serverId'));
    });

    testWidgets('launchShuffledShow on a show fetches series episodes and shuffles', (tester) async {
      final ctx = await pumpContext(tester);
      // 50 episodes makes a coincident-original ordering effectively impossible.
      final originalIds = List.generate(50, (i) => 'ep$i');
      final fetched = originalIds.map(_ep).toList();
      final fakeClient = _RecordingClient(seriesEpisodesResponse: fetched);
      final playback = PlaybackStateProvider();
      final navigated = <MediaItem>[];

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (m) async => navigated.add(m),
      );

      final show = testMediaItem(
        id: 'show-1',
        backend: MediaBackend.silo,
        kind: MediaKind.show,
        serverId: 'srv-silo',
        serverName: 'My Silo',
      );

      final result = await launcher.launchShuffledShow(metadata: show, showLoadingIndicator: false);

      expect(result, isA<PlayQueueSuccess>());
      expect(fakeClient.fetchSeriesEpisodesCalls, ['show-1']);
      // Same set of episode ids, just reordered.
      final shuffledIds = playback.loadedItems.map((m) => m.id).toList();
      expect(shuffledIds.toSet(), originalIds.toSet());
      expect(shuffledIds.length, originalIds.length);
      expect(shuffledIds, isNot(equals(originalIds)));
      expect(playback.isShuffleActive, isTrue);
      expect(navigated.single.id, shuffledIds.first);
      // Server identity is propagated onto the queue items.
      expect(playback.loadedItems.first.serverId, 'srv-silo');
      expect(playback.loadedItems.first.serverName, 'My Silo');
    });

    testWidgets('launchShuffledShow on a season uses parentId as series anchor', (tester) async {
      final ctx = await pumpContext(tester);
      final fakeClient = _RecordingClient(seriesEpisodesResponse: [_ep('a'), _ep('b')]);
      final playback = PlaybackStateProvider();

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {},
      );

      final season = testMediaItem(
        id: 'season-2',
        backend: MediaBackend.silo,
        kind: MediaKind.season,
        serverId: 'srv-silo',
        parentId: 'show-7',
      );

      final result = await launcher.launchShuffledShow(metadata: season, showLoadingIndicator: false);

      expect(result, isA<PlayQueueSuccess>());
      expect(fakeClient.fetchSeriesEpisodesCalls, ['show-7']);
    });

    testWidgets('launchShuffledShow returns PlayQueueEmpty when series has no episodes', (tester) async {
      final ctx = await pumpContext(tester);
      final fakeClient = _RecordingClient(seriesEpisodesResponse: const []);
      final playback = PlaybackStateProvider();
      var didNavigate = false;

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );

      final show = testMediaItem(
        id: 'show-empty',
        backend: MediaBackend.silo,
        kind: MediaKind.show,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchShuffledShow(metadata: show, showLoadingIndicator: false);

      expect(result, isA<PlayQueueEmpty>());
      expect(playback.isQueueActive, isFalse);
      expect(didNavigate, isFalse);
    });

    testWidgets('empty fetch returns PlayQueueEmpty without seeding queue', (tester) async {
      final ctx = await pumpContext(tester);
      final fakeClient = _RecordingClient(playableDescendantsResponse: const []);
      final playback = PlaybackStateProvider();
      var didNavigate = false;

      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );

      final collection = testMediaItem(
        id: 'col-empty',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        serverId: 'srv-silo',
      );

      final result = await launcher.launchFromCollectionOrPlaylist(
        item: collection,
        shuffle: false,
        showLoadingIndicator: false,
      );

      expect(result, isA<PlayQueueEmpty>());
      expect(playback.isQueueActive, isFalse);
      expect(didNavigate, isFalse);
    });

    testWidgets('fetch starts before the loading dialog first frame renders', (tester) async {
      final ctx = await pumpContext(tester);
      final gate = Completer<void>();
      final fakeClient = _RecordingClient(playlistItemsResponse: [_ep('a'), _ep('b')], playlistPageGate: gate);
      final playback = PlaybackStateProvider();
      var didNavigate = false;
      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );
      const playlist = MediaPlaylist(
        id: 'pl-early-fetch',
        backend: MediaBackend.silo,
        title: 'Early fetch',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final resultFuture = launcher.launchFromCollectionOrPlaylist(item: playlist, shuffle: false);

      // No frame has been pumped, so the dialog has not built yet — but the
      // network operation must already be in flight.
      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(1));
      expect(find.byType(DialogActionButton), findsNothing);

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(await resultFuture, isA<PlayQueueSuccess>());
      expect(didNavigate, isTrue);
      expect(find.byType(DialogActionButton), findsNothing);
    });

    testWidgets('operation failure before the dialog first frame still dismisses the dialog', (tester) async {
      final ctx = await pumpContext(tester);
      final fakeClient = _ThrowingClient();
      final playback = PlaybackStateProvider();
      var didNavigate = false;
      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );
      const playlist = MediaPlaylist(
        id: 'pl-early-error',
        backend: MediaBackend.silo,
        title: 'Early error',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final resultFuture = launcher.launchFromCollectionOrPlaylist(item: playlist, shuffle: false);
      // The failure lands before the dialog's first frame; it must not
      // surface as an unhandled error, and the dialog must still come down.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(await resultFuture, isA<PlayQueueError>());
      expect(didNavigate, isFalse);
      expect(playback.isQueueActive, isFalse);
      expect(find.byType(DialogActionButton), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('dialog Cancel aborts playlist launch idempotently without queue or snackbar', (tester) async {
      final ctx = await pumpContext(tester);
      final gate = Completer<void>();
      final fakeClient = _RecordingClient(playlistItemsResponse: [_ep('a'), _ep('b')], playlistPageGate: gate);
      final playback = PlaybackStateProvider();
      var didNavigate = false;
      final launcher = LocalQueueLauncher(
        context: ctx,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );
      const playlist = MediaPlaylist(
        id: 'pl-cancel',
        backend: MediaBackend.silo,
        title: 'Cancel me',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final resultFuture = launcher.launchFromCollectionOrPlaylist(item: playlist, shuffle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(1));
      expect(fakeClient.playlistPageAborts.single, isNotNull);
      expect(find.text(t.common.cancel), findsOneWidget);
      final cancelButton = tester.widget<DialogActionButton>(find.byType(DialogActionButton));
      cancelButton.onPressed!();
      cancelButton.onPressed!();
      await tester.pump();
      expect(await resultFuture, isA<PlayQueueCancelled>());
      expect(fakeClient.playlistPageAborts.single!.isAborted, isTrue);
      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(1));
      expect(playback.isQueueActive, isFalse);
      expect(didNavigate, isFalse);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('disposing the initiating navigator aborts its active playlist launch', (tester) async {
      late BuildContext initiatingContext;
      late StateSetter replaceProfileSubtree;
      var showProfileSubtree = true;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              replaceProfileSubtree = setState;
              if (!showProfileSubtree) {
                return const Scaffold(body: Text('replacement profile', key: Key('replacement-profile')));
              }
              return Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: Builder(
                      builder: (context) {
                        initiatingContext = context;
                        return const Text('initiating profile');
                      },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final gate = Completer<void>();
      final fakeClient = _RecordingClient(playlistItemsResponse: [_ep('a')], playlistPageGate: gate);
      final playback = PlaybackStateProvider();
      var didNavigate = false;
      final launcher = LocalQueueLauncher(
        context: initiatingContext,
        clientForTesting: fakeClient,
        playbackStateForTesting: playback,
        navigateForTesting: (_) async {
          didNavigate = true;
        },
      );
      const playlist = MediaPlaylist(
        id: 'pl-teardown',
        backend: MediaBackend.silo,
        title: 'Teardown',
        playlistType: 'video',
        serverId: 'srv-silo',
      );

      final resultFuture = launcher.launchFromCollectionOrPlaylist(item: playlist, shuffle: false);
      await tester.pump();
      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(1));

      replaceProfileSubtree(() => showProfileSubtree = false);
      await tester.pump();

      expect(await resultFuture, isA<PlayQueueCancelled>());
      expect(fakeClient.playlistPageAborts.single!.isAborted, isTrue);
      expect(fakeClient.fetchPlaylistItemsCalls, hasLength(1));
      expect(playback.isQueueActive, isFalse);
      expect(didNavigate, isFalse);
      expect(find.byKey(const Key('replacement-profile')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('fetchAllPlaylistItems cancellation', () {
    test('aborts after a page await without returning a partial list or requesting page two', () async {
      final abort = AbortController();
      final fakeClient = _RecordingClient(
        playlistItemsResponse: List.generate(playlistItemsPageSize + 1, (i) => _ep('p$i')),
        playlistPageGate: Completer<void>(),
      );

      final resultFuture = fetchAllPlaylistItems(fakeClient, 'pl-abort', abort: abort);
      expect(fakeClient.fetchPlaylistItemsCalls.map((call) => call.offset), [0]);
      abort.abort();

      await expectLater(
        resultFuture,
        throwsA(isA<MediaServerHttpException>().having((e) => e.isCancellation, 'isCancellation', isTrue)),
      );
      expect(fakeClient.fetchPlaylistItemsCalls.map((call) => call.offset), [0]);
    });

    test('null controller preserves two-page complete-list success', () async {
      final items = List.generate(playlistItemsPageSize + 1, (i) => _ep('p$i'));
      final fakeClient = _RecordingClient(playlistItemsResponse: items);

      final result = await fetchAllPlaylistItems(fakeClient, 'pl-success');

      expect(result.map((item) => item.id), items.map((item) => item.id));
      expect(fakeClient.fetchPlaylistItemsCalls.map((call) => call.offset), [0, playlistItemsPageSize]);
      expect(fakeClient.playlistPageAborts, [null, null]);
    });
  });
}
