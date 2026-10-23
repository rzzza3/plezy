import '../test_helpers/paged_fakes.dart';
import 'dart:async';

import 'package:plezy/services/playback_launch_observer.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/profile_navigation_scope.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_file_info.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/offline_mode_provider.dart';
import 'package:plezy/screens/music/album_detail_screen.dart';
import 'package:plezy/screens/music/artist_detail_screen.dart';
import 'package:plezy/services/download_manager_service.dart';
import 'package:plezy/services/download_storage_service.dart';
import 'package:plezy/services/music/music_playback_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/file_info_bottom_sheet.dart';
import 'package:plezy/widgets/media_context_menu.dart';
import 'package:provider/provider.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';
import '../test_helpers/stub_music_playback_service.dart';

void main() {
  testWidgets('cancelled media menu restores its live captured item', (tester) async {
    final destination = FocusNode();
    addTearDown(destination.dispose);
    var selected = false;
    final menuKey = await _pumpMovieMenu(
      tester,
      wrapMenu: (menu) => FocusableWrapper(focusNode: destination, onSelect: () => selected = true, child: menu),
    );
    destination.requestFocus();
    await tester.pump();
    menuKey.currentState!.showContextMenu(tester.element(find.text('picker target')));
    await tester.pumpAndSettle();
    expect(destination.hasPrimaryFocus, isFalse);
    Navigator.of(menuKey.currentContext!).pop();
    await tester.pumpAndSettle();
    expect(destination.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, isTrue);
  });

  testWidgets('queued media menu restoration cannot outlive its profile owner', (tester) async {
    final destination = FocusNode();
    final nextProfile = FocusNode();
    final showOwner = ValueNotifier(true);
    addTearDown(destination.dispose);
    addTearDown(nextProfile.dispose);
    addTearDown(showOwner.dispose);
    String? selected;
    final menuKey = await _pumpMovieMenu(
      tester,
      wrapMenu: (menu) => ValueListenableBuilder<bool>(
        valueListenable: showOwner,
        builder: (_, visible, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusableWrapper(
              focusNode: destination,
              onSelect: () => selected = 'old profile',
              child: visible ? menu : const Text('Removed profile menu'),
            ),
            FocusableWrapper(
              focusNode: nextProfile,
              onSelect: () => selected = 'new profile',
              child: const Text('New profile'),
            ),
          ],
        ),
      ),
    );
    destination.requestFocus();
    await tester.pump();
    menuKey.currentState!.showContextMenu(tester.element(find.text('picker target')));
    await tester.pumpAndSettle();
    Navigator.of(menuKey.currentContext!).pop();
    await tester.idle(); // The menu has queued its post-frame restore.
    showOwner.value = false;
    nextProfile.requestFocus();
    await tester.pumpAndSettle();
    expect(menuKey.currentState, isNull);
    expect(
      destination.context!.mounted,
      isTrue,
      reason: 'the external destination survives, but its menu owner does not',
    );
    expect(nextProfile.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(selected, 'new profile');
    expect(tester.takeException(), isNull);
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaContextMenu actions', () {
    testWidgets('audio playlist play and shuffle actions use music playback', (tester) async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final tracks = [
        testMediaItem(
          id: 'track-1',
          backend: MediaBackend.silo,
          kind: MediaKind.track,
          title: 'Track One',
          serverId: 'srv-1',
        ),
        testMediaItem(
          id: 'track-2',
          backend: MediaBackend.silo,
          kind: MediaKind.track,
          title: 'Track Two',
          serverId: 'srv-1',
        ),
      ];
      final client = _AudioPlaylistClient(tracks);
      final music = _RecordingMusicPlaybackService();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final multiServerProvider = testMultiServerProvider(manager);
      final stack = await ProfileStack.create(withStorage: false);
      addTearDown(() async {
        await stack.dispose();
        music.dispose();
        multiServerProvider.dispose();
        manager.dispose();
      });

      final menuKey = GlobalKey<MediaContextMenuState>();
      const playlist = MediaPlaylist(
        id: 'playlist-1',
        backend: MediaBackend.silo,
        title: 'Road Trip',
        playlistType: 'audio',
        serverId: 'srv-1',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
              ChangeNotifierProvider<MusicPlaybackService>.value(value: music),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: Center(
                  child: MediaContextMenu(
                    key: menuKey,
                    item: playlist,
                    child: const SizedBox(width: 120, height: 80, child: Text('audio target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      menuKey.currentState!.showContextMenu(tester.element(find.text('audio target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.play));
      await tester.pumpAndSettle();

      expect(music.playedTracks, tracks);
      expect(music.playedContext?.title, playlist.title);
      expect(music.playedContext?.kind, MusicPlayContextKind.playlist);
      expect(music.shuffle, isFalse);

      menuKey.currentState!.showContextMenu(tester.element(find.text('audio target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.mediaMenu.shufflePlay));
      await tester.pumpAndSettle();

      expect(music.callCount, 2);
      expect(music.playedTracks, tracks);
      expect(music.shuffle, isTrue);

      final staleFetchGate = Completer<void>();
      client.fetchGate = staleFetchGate;
      menuKey.currentState!.showContextMenu(tester.element(find.text('audio target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.common.play));
      await tester.pump();

      final newerTrack = testMediaItem(
        id: 'newer-track',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Newer Track',
        serverId: 'srv-1',
      );
      await music.playFromList(
        tracks: [newerTrack],
        playContext: const MusicPlayContext(title: 'Newer Queue', kind: MusicPlayContextKind.tracks),
      );
      staleFetchGate.complete();
      await tester.pumpAndSettle();

      expect(music.callCount, 3, reason: 'the stale playlist fetch must not start a fourth queue');
      expect(music.playedTracks, [newerTrack]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('file info client resolution failure shows an error without popping another route', (tester) async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      final manager = MultiServerManager();
      final multiServerProvider = testMultiServerProvider(manager);
      final stack = await ProfileStack.create(withStorage: false);
      addTearDown(() async {
        await stack.dispose();
        multiServerProvider.dispose();
        manager.dispose();
      });

      final menuKey = GlobalKey<MediaContextMenuState>();
      final item = testMediaItem(
        id: 'movie-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Movie',
        serverId: 'missing-server',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
            ],
            child: MaterialApp(
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: Center(
                  child: MediaContextMenu(
                    key: menuKey,
                    item: item,
                    child: const SizedBox(width: 120, height: 80, child: Text('target')),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      menuKey.currentState!.showContextMenu(tester.element(find.text('target')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.mediaMenu.fileInfo));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('target'), findsOneWidget);
    });

    testWidgets('file info spinner is dismissed when the launching card unmounts mid-fetch', (tester) async {
      LocaleSettings.setLocaleSync(AppLocale.en);
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

      // Gate the file info fetch so the launching card can be unmounted
      // while getFileInfo is still pending.
      final gate = Completer<void>();
      final client = _RecordingClient(fileInfoGate: gate);
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final multiServerProvider = testMultiServerProvider(manager);
      final offlineMode = OfflineModeProvider(manager);
      final stack = await ProfileStack.create(withStorage: false);
      final showCard = ValueNotifier<bool>(true);
      addTearDown(() async {
        await stack.dispose();
        offlineMode.dispose();
        multiServerProvider.dispose();
        manager.dispose();
        showCard.dispose();
      });

      final menuKey = GlobalKey<MediaContextMenuState>();
      final navigatorKey = GlobalKey<NavigatorState>();
      final item = testMediaItem(
        id: 'movie-1',
        backend: MediaBackend.silo,
        kind: MediaKind.movie,
        title: 'Movie',
        serverId: 'srv-1',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
              ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              theme: monoTheme(dark: true),
              home: Scaffold(
                body: Center(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: showCard,
                    builder: (context, visible, child) => visible
                        ? MediaContextMenu(
                            key: menuKey,
                            item: item,
                            child: const SizedBox(width: 120, height: 80, child: Text('file info target')),
                          )
                        : const SizedBox(width: 120, height: 80),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      menuKey.currentState!.showContextMenu(tester.element(find.text('file info target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.mediaMenu.fileInfo));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Unmount the launching card while the fetch is pending — a list refresh
      // dropping the row. The captured card context going stale is exactly what
      // defeated the old `Navigator.pop(context)` cleanup.
      showCard.value = false;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'the fetch is still pending');

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'the finally must dismiss the spinner through the dialog route, not the dead card context',
      );
      expect(find.byType(FileInfoBottomSheet), findsNothing);
      expect(navigatorKey.currentState!.canPop(), isFalse, reason: 'no modal route may remain stuck above the screen');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Mark as Watched reports a failure when the item server has no client', (tester) async {
      final client = _RecordingClient();
      final menuKey = await _pumpItemMenu(
        tester,
        client: client,
        item: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          title: 'Movie',
          serverId: 'missing-server',
        ),
      );
      await _openMenu(tester, menuKey);
      client.calls.clear();

      await tester.tap(find.text(t.mediaMenu.markAsWatched));
      await tester.pumpAndSettle();

      expect(find.text(t.messages.markedAsWatched), findsNothing);
      expect(find.text(t.messages.errorLoading(error: t.errors.reasonUnreachable)), findsOneWidget);
      expect(client.calls, isEmpty);
    });

    testWidgets('an item whose server has no client is never sent to another server', (tester) async {
      final client = _RecordingClient();
      final menuKey = await _pumpItemMenu(
        tester,
        client: client,
        item: testMediaItem(
          id: 'movie-1',
          backend: MediaBackend.silo,
          kind: MediaKind.movie,
          title: 'Movie',
          serverId: 'missing-server',
        ),
      );
      await _openMenu(tester, menuKey);
      client.calls.clear();

      await tester.tap(find.text(t.mediaMenu.fileInfo));
      await tester.pumpAndSettle();

      expect(client.calls, isEmpty, reason: 'the registered srv-1 must not be asked about another server item');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('the music menu gives Instant Mix an icon it shares with no sibling row', (tester) async {
      final track = testMediaItem(
        id: 'track-1',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Track',
        parentId: 'album-1',
        parentTitle: 'Album',
        grandparentId: 'artist-1',
        grandparentTitle: 'Artist',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: track, relatedItems: const []);

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('mini-player menu target')));
      await tester.pumpAndSettle();

      expect(find.text(t.music.instantMix), findsOneWidget);
      expect(find.byIcon(Symbols.wand_stars_rounded), findsOneWidget);

      // #1629: the fader glyph reads as an equalizer, and the neighbouring
      // rows must stay tellable apart at a glance on a TV.
      expect(find.byIcon(Symbols.instant_mix_rounded), findsNothing);
      expect(find.byIcon(Symbols.tune_rounded), findsNothing);
      final musicIcons = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((icon) => icon.icon)
          .whereType<IconData>()
          .toList();
      expect(
        musicIcons.where((icon) => icon == Symbols.wand_stars_rounded),
        hasLength(1),
        reason: 'Instant Mix must not reuse the glyph of Play, Play next, Add to queue, or Go to artist',
      );
    });

    testWidgets('track album action uses the profile navigator from the sibling menu overlay', (tester) async {
      final track = testMediaItem(
        id: 'track-1',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Track',
        parentId: 'album-1',
        parentTitle: 'Album',
        grandparentId: 'artist-1',
        grandparentTitle: 'Artist',
        serverId: 'srv-1',
      );
      final album = testMediaItem(
        id: 'album-1',
        backend: MediaBackend.silo,
        kind: MediaKind.album,
        title: 'Album',
        parentId: 'artist-1',
        parentTitle: 'Artist',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: track, relatedItems: [album]);

      await _selectSiblingMusicMenuAction(tester, harness, t.music.goToAlbum);

      expect(find.byType(AlbumDetailScreen), findsOneWidget);
      expect(harness.profileNavigatorKey.currentState!.canPop(), isTrue);
      expect(harness.rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(
        Provider.of<MusicPlaybackService>(tester.element(find.byType(AlbumDetailScreen)), listen: false),
        same(harness.music),
      );
    });

    testWidgets('album artist action uses the profile navigator from the sibling menu overlay', (tester) async {
      final album = testMediaItem(
        id: 'album-1',
        backend: MediaBackend.silo,
        kind: MediaKind.album,
        title: 'Album',
        parentId: 'artist-1',
        parentTitle: 'Artist',
        serverId: 'srv-1',
      );
      final artist = testMediaItem(
        id: 'artist-1',
        backend: MediaBackend.silo,
        kind: MediaKind.artist,
        title: 'Artist',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: album, relatedItems: [artist]);

      await _selectSiblingMusicMenuAction(tester, harness, t.music.goToArtist);

      expect(find.byType(ArtistDetailScreen), findsOneWidget);
      expect(harness.profileNavigatorKey.currentState!.canPop(), isTrue);
      expect(harness.rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(
        Provider.of<MusicPlaybackService>(tester.element(find.byType(ArtistDetailScreen)), listen: false),
        same(harness.music),
      );
    });

    testWidgets('track artist action uses the profile navigator from the sibling menu overlay', (tester) async {
      final track = testMediaItem(
        id: 'track-1',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Track',
        parentId: 'album-1',
        parentTitle: 'Album',
        grandparentId: 'artist-1',
        grandparentTitle: 'Artist',
        serverId: 'srv-1',
      );
      final artist = testMediaItem(
        id: 'artist-1',
        backend: MediaBackend.silo,
        kind: MediaKind.artist,
        title: 'Artist',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: track, relatedItems: [artist]);

      await _selectSiblingMusicMenuAction(tester, harness, t.music.goToArtist);

      expect(find.byType(ArtistDetailScreen), findsOneWidget);
      expect(harness.profileNavigatorKey.currentState!.canPop(), isTrue);
      expect(harness.rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(
        Provider.of<MusicPlaybackService>(tester.element(find.byType(ArtistDetailScreen)), listen: false),
        same(harness.music),
      );
    });

    testWidgets('a slow music enqueue does not append to a newer queue session', (tester) async {
      final album = testMediaItem(
        id: 'album-1',
        backend: MediaBackend.silo,
        kind: MediaKind.album,
        title: 'Album',
        serverId: 'srv-1',
      );
      final albumTrack = testMediaItem(
        id: 'album-track',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Album Track',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: album, relatedItems: [albumTrack]);
      final fetchGate = Completer<void>();
      harness.client.albumTracksGate = fetchGate;

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('mini-player menu target')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.music.playNext));
      await tester.pump();

      final newerTrack = testMediaItem(
        id: 'newer-track',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Newer Track',
        serverId: 'srv-1',
      );
      await harness.music.playFromList(
        tracks: [newerTrack],
        playContext: const MusicPlayContext(title: 'Newer Queue', kind: MusicPlayContextKind.tracks),
      );
      fetchGate.complete();
      await tester.pumpAndSettle();

      expect(harness.music.addedNext, isEmpty);
      expect(harness.music.playedTracks, [newerTrack]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('track file info fetches the tapped track and renders its audio-only sheet', (tester) async {
      const trackPath = '/music/Boards of Canada/Geogaddi/01 Ready Lets Go.flac';
      final track = testMediaItem(
        id: 'track-1',
        backend: MediaBackend.silo,
        kind: MediaKind.track,
        title: 'Ready Lets Go',
        parentId: 'album-1',
        parentTitle: 'Geogaddi',
        grandparentId: 'artist-1',
        grandparentTitle: 'Boards of Canada',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: track, relatedItems: const []);
      harness.client.fileInfo = const MediaFileInfo(
        versions: [
          MediaFileVersion(
            container: 'flac',
            parts: [
              MediaFilePart(
                filePath: trackPath,
                fileSize: 35651584,
                streams: [MediaStreamDetails(kind: MediaStreamKind.audio, ordinal: 1, codec: 'flac', channels: 2)],
              ),
            ],
          ),
        ],
      );

      await _selectSiblingMusicMenuAction(tester, harness, t.mediaMenu.fileInfo);

      expect(harness.client.fileInfoRequests, [same(track)]);
      expect(find.byType(FileInfoBottomSheet), findsOneWidget);
      expect(find.text('Ready Lets Go'), findsOneWidget);
      expect(find.text(trackPath), findsOneWidget);
      expect(find.text(t.fileInfo.audio), findsOneWidget);
      expect(find.text(t.fileInfo.video), findsNothing);
      // The loading dialog must be gone and no error snackbar raised.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('album menu omits file info because containers carry no media sources', (tester) async {
      final album = testMediaItem(
        id: 'album-1',
        backend: MediaBackend.silo,
        kind: MediaKind.album,
        title: 'Geogaddi',
        parentId: 'artist-1',
        parentTitle: 'Boards of Canada',
        serverId: 'srv-1',
      );
      final harness = await _pumpSiblingMusicMenu(tester, item: album, relatedItems: const []);

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('mini-player menu target')));
      await tester.pumpAndSettle();

      expect(find.text(t.music.playNext), findsOneWidget);
      expect(find.text(t.mediaMenu.fileInfo), findsNothing);
      expect(harness.client.fileInfoRequests, isEmpty);
    });
  });

  group('watchlist entry', () {
    testWidgets('cold open offers Add and adds to the single capable source', (tester) async {
      final source = _MenuWatchlistSource(CatalogSourceId.trakt, 'Trakt', resolveTo: const CatalogItemIds(imdb: 'tt1'));
      final harness = await _pumpWatchlistMenu(
        tester,
        sources: [source],
        ids: const ExternalIds(imdb: 'tt1'),
      );

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('watchlist target')));
      await tester.pumpAndSettle();

      expect(find.text(t.explore.addToWatchlist), findsOneWidget);
      expect(find.text(t.explore.removeFromWatchlist), findsNothing);

      await tester.tap(find.text(t.explore.addToWatchlist));
      await tester.pumpAndSettle();

      expect(source.mutations.map((m) => m.add), [true]);
      expect(source.mutations.single.ids.imdb, 'tt1');
      expect(find.text(t.explore.addedToWatchlist), findsOneWidget);
      // Opening also kicked the membership snapshot load for the next open.
      expect(source.ensureLoadedCalls, greaterThan(0));
    });

    testWidgets('offers Remove once cached membership is known, and removes', (tester) async {
      final source = _MenuWatchlistSource(CatalogSourceId.trakt, 'Trakt', resolveTo: const CatalogItemIds(imdb: 'tt1'))
        ..membership = true;
      final harness = await _pumpWatchlistMenu(tester, sources: [source]);
      await harness.catalogSources.watchlistCandidatesFor(
        harness.item,
        client: _SeedIdsClient(const ExternalIds(imdb: 'tt1')),
      );

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('watchlist target')));
      await tester.pumpAndSettle();

      expect(find.text(t.explore.removeFromWatchlist), findsOneWidget);

      await tester.tap(find.text(t.explore.removeFromWatchlist));
      await tester.pumpAndSettle();

      expect(source.mutations.map((m) => m.add), [false]);
      expect(find.text(t.explore.removedFromWatchlist), findsOneWidget);
    });

    testWidgets('hides the entry when the item resolved in no capable source', (tester) async {
      final source = _MenuWatchlistSource(CatalogSourceId.mal, 'MAL'); // resolves null: out of domain
      final harness = await _pumpWatchlistMenu(tester, sources: [source]);
      await harness.catalogSources.watchlistCandidatesFor(
        harness.item,
        client: _SeedIdsClient(const ExternalIds(imdb: 'tt1')),
      );

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('watchlist target')));
      await tester.pumpAndSettle();

      expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget);
      expect(find.text(t.explore.addToWatchlist), findsNothing);
      expect(find.text(t.explore.removeFromWatchlist), findsNothing);
    });

    testWidgets('reports when the tapped item matches no watchlist', (tester) async {
      final source = _MenuWatchlistSource(CatalogSourceId.trakt, 'Trakt', resolveTo: const CatalogItemIds(imdb: 'tt1'));
      // The item carries no external ids.
      final harness = await _pumpWatchlistMenu(tester, sources: [source]);

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('watchlist target')));
      await tester.pumpAndSettle();

      await tester.tap(find.text(t.explore.addToWatchlist));
      await tester.pumpAndSettle();

      expect(source.mutations, isEmpty);
      expect(find.text(t.explore.watchlistNoMatch), findsOneWidget);
    });

    testWidgets('several capable sources open a per-source chooser', (tester) async {
      final trakt = _MenuWatchlistSource(CatalogSourceId.trakt, 'Trakt', resolveTo: const CatalogItemIds(imdb: 'tt1'));
      final simkl = _MenuWatchlistSource(CatalogSourceId.simkl, 'Simkl', resolveTo: const CatalogItemIds(imdb: 'tt1'))
        ..membership = true;
      final harness = await _pumpWatchlistMenu(tester, sources: [trakt, simkl]);
      await harness.catalogSources.watchlistCandidatesFor(
        harness.item,
        client: _SeedIdsClient(const ExternalIds(imdb: 'tt1')),
      );

      harness.menuKey.currentState!.showContextMenu(tester.element(find.text('watchlist target')));
      await tester.pumpAndSettle();

      // Membership known-true on one source labels the entry Remove.
      await tester.tap(find.text(t.explore.removeFromWatchlist));
      await tester.pumpAndSettle();

      // The chooser names each source with its own pending action.
      expect(find.text('Trakt'), findsOneWidget);
      expect(find.text('Simkl'), findsOneWidget);
      expect(find.text(t.explore.addToWatchlist), findsOneWidget);
      expect(find.text(t.explore.removeFromWatchlist), findsOneWidget);

      await tester.tap(find.text('Simkl'));
      await tester.pumpAndSettle();

      expect(simkl.mutations.map((m) => m.add), [false]);
      expect(trakt.mutations, isEmpty);
      expect(find.text(t.explore.removedFromWatchlist), findsOneWidget);
    });
  });
}

/// Pumps a Silo movie's context menu, optionally wrapped by [wrapMenu].
Future<GlobalKey<MediaContextMenuState>> _pumpMovieMenu(
  WidgetTester tester, {
  Widget Function(Widget menu)? wrapMenu,
}) async {
  LocaleSettings.setLocaleSync(AppLocale.en);
  TvDetectionService.debugSetAppleTVOverride(true);
  addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  SiloApiCache.initialize(db);
  final manager = MultiServerManager()..debugRegisterClientForTesting(_RecordingClient());
  final multiServerProvider = testMultiServerProvider(manager);
  final stack = await ProfileStack.create(db: db, withStorage: false);
  addTearDown(() async {
    await stack.dispose();
    multiServerProvider.dispose();
    manager.dispose();
    await db.close();
  });

  final menuKey = GlobalKey<MediaContextMenuState>();
  final item = testMediaItem(
    id: 'movie-1',
    backend: MediaBackend.silo,
    kind: MediaKind.movie,
    title: 'Movie',
    serverId: 'srv-1',
  );
  final menu = MediaContextMenu(
    key: menuKey,
    item: item,
    child: const SizedBox(width: 120, height: 80, child: Text('picker target')),
  );
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(body: Center(child: wrapMenu?.call(menu) ?? menu)),
        ),
      ),
    ),
  );
  return menuKey;
}

Future<GlobalKey<MediaContextMenuState>> _pumpItemMenu(
  WidgetTester tester, {
  required MediaServerClient client,
  required MediaItem item,
}) async {
  LocaleSettings.setLocaleSync(AppLocale.en);
  TvDetectionService.debugSetAppleTVOverride(true);
  addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServerProvider = testMultiServerProvider(manager);
  final offlineMode = OfflineModeProvider(manager);
  final stack = await ProfileStack.create(withStorage: false);
  addTearDown(() async {
    await stack.dispose();
    offlineMode.dispose();
    multiServerProvider.dispose();
    manager.dispose();
  });

  final menuKey = GlobalKey<MediaContextMenuState>();
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Center(
              child: MediaContextMenu(
                key: menuKey,
                item: item,
                child: const SizedBox(width: 120, height: 80, child: Text('delete target')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return menuKey;
}

Future<void> _openMenu(WidgetTester tester, GlobalKey<MediaContextMenuState> menuKey) async {
  menuKey.currentState!.showContextMenu(tester.element(find.text('delete target')));
  await tester.pumpAndSettle();
}

class _AudioPlaylistClient implements MediaServerClient {
  final List<MediaItem> tracks;
  Completer<void>? fetchGate;

  _AudioPlaylistClient(this.tracks);

  @override
  ServerId get serverId => ServerId('srv-1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async {
    await fetchGate?.future;
    return fakeLibraryPage(tracks, start: start, size: size);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Silo client on `srv-1` that records every method the menu calls on it.
/// [fileInfoGate] holds [getFileInfo] open until completed.
class _RecordingClient implements MediaServerClient {
  _RecordingClient({this.fileInfoGate});

  final Completer<void>? fileInfoGate;
  final calls = <String>[];

  @override
  ServerId get serverId => ServerId('srv-1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    calls.add('getFileInfo ${item.id}');
    await fileInfoGate?.future;
    return const MediaFileInfo(versions: []);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.isMethod) calls.add('${invocation.memberName}');
    return super.noSuchMethod(invocation);
  }
}

class _RecordingMusicPlaybackService extends StubMusicPlaybackService {
  List<MediaItem>? playedTracks;
  final List<MediaItem> addedNext = [];
  MusicPlayContext? playedContext;
  bool? shuffle;
  int callCount = 0;

  @override
  Future<void> playFromList({
    required List<MediaItem> tracks,
    MediaItem? startTrack,
    required MusicPlayContext playContext,
    bool shuffle = false,
    Duration? initialPosition,
    bool offline = false,
    PlaybackLaunchObserver? launchObserver,
  }) async {
    await super.playFromList(tracks: tracks, startTrack: startTrack, playContext: playContext, shuffle: shuffle);
    callCount++;
    playedTracks = tracks;
    playedContext = playContext;
    this.shuffle = shuffle;
  }

  @override
  void addNext(List<MediaItem> tracks) {
    addedNext.addAll(tracks);
  }
}

class _RelatedMusicClient implements MediaServerClient {
  _RelatedMusicClient(Iterable<MediaItem> items)
    : _items = {for (final item in items) item.id: item},
      albumTracks = items.where((item) => item.kind == MediaKind.track).toList();

  final Map<String, MediaItem> _items;
  final List<MediaItem> albumTracks;
  Completer<void>? albumTracksGate;

  @override
  ServerId get serverId => ServerId('srv-1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  // Silo serves no instant mix; the music menu's Instant Mix row needs a
  // server that does.
  @override
  ServerCapabilities get capabilities => const ServerCapabilities(instantMix: true);

  @override
  Future<MediaItem?> fetchItem(String id) async => _items[id];

  @override
  Future<List<MediaItem>> fetchAlbumTracks(String albumId) async {
    await albumTracksGate?.future;
    return albumTracks;
  }

  @override
  Future<List<MediaItem>> fetchArtistAlbums(MediaItem artist) async => const [];

  /// Items the menu asked file info for, in call order — the track menu must
  /// resolve the client for the tapped item, not for whatever is playing.
  final List<MediaItem> fileInfoRequests = [];
  MediaFileInfo? fileInfo;

  @override
  Future<MediaFileInfo?> getFileInfo(MediaItem item) async {
    fileInfoRequests.add(item);
    return fileInfo;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SiblingMusicMenuHarness {
  const _SiblingMusicMenuHarness({
    required this.rootNavigatorKey,
    required this.profileNavigatorKey,
    required this.menuKey,
    required this.music,
    required this.client,
  });

  final GlobalKey<NavigatorState> rootNavigatorKey;
  final GlobalKey<NavigatorState> profileNavigatorKey;
  final GlobalKey<MediaContextMenuState> menuKey;
  final _RecordingMusicPlaybackService music;
  final _RelatedMusicClient client;
}

Future<_SiblingMusicMenuHarness> _pumpSiblingMusicMenu(
  WidgetTester tester, {
  required MediaItem item,
  required List<MediaItem> relatedItems,
}) async {
  resetSharedPreferencesForTest();
  SettingsService.resetForTesting();
  await SettingsService.getInstance();
  LocaleSettings.setLocaleSync(AppLocale.en);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  SiloApiCache.initialize(db);
  final downloadManager = DownloadManagerService(
    database: db,
    storageService: DownloadStorageService.instance,
    clientResolver: (serverId, {clientScopeId}) => null,
  );
  downloadManager.recoveryFuture = Future<void>.value();
  final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
  await downloadProvider.ensureInitialized();
  final client = _RelatedMusicClient(relatedItems);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServerProvider = testMultiServerProvider(manager);
  final stack = await ProfileStack.create(db: db, withStorage: false);
  final music = _RecordingMusicPlaybackService();
  final rootNavigatorKey = GlobalKey<NavigatorState>();
  final profileNavigatorKey = GlobalKey<NavigatorState>();
  final menuKey = GlobalKey<MediaContextMenuState>();

  addTearDown(() async {
    downloadProvider.dispose();
    downloadManager.dispose();
    await stack.dispose();
    music.dispose();
    multiServerProvider.dispose();
    manager.dispose();
    await db.close();
  });

  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        theme: monoTheme(dark: true).copyWith(platform: TargetPlatform.macOS),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
            ChangeNotifierProvider<MusicPlaybackService>.value(value: music),
          ],
          child: ProfileNavigationScope(
            navigatorKey: profileNavigatorKey,
            routeObserver: RouteObserver<PageRoute<dynamic>>(),
            mainScaffoldMessengerKey: GlobalKey<ScaffoldMessengerState>(),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Navigator(
                  key: profileNavigatorKey,
                  onGenerateRoute: (_) => MaterialPageRoute<void>(
                    builder: (_) => const Scaffold(body: Center(child: Text('profile content'))),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Material(
                    child: MediaContextMenu(
                      key: menuKey,
                      item: item,
                      child: const SizedBox(
                        width: 180,
                        height: 64,
                        child: Center(child: Text('mini-player menu target')),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  return _SiblingMusicMenuHarness(
    rootNavigatorKey: rootNavigatorKey,
    profileNavigatorKey: profileNavigatorKey,
    menuKey: menuKey,
    music: music,
    client: client,
  );
}

Future<void> _selectSiblingMusicMenuAction(
  WidgetTester tester,
  _SiblingMusicMenuHarness harness,
  String actionLabel,
) async {
  harness.menuKey.currentState!.showContextMenu(tester.element(find.text('mini-player menu target')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(actionLabel));
  await tester.pumpAndSettle();
}

class _MenuWatchlistSource implements CatalogSource {
  _MenuWatchlistSource(this.id, this.displayName, {this.resolveTo});

  @override
  final CatalogSourceId id;

  @override
  final String displayName;

  final CatalogItemIds? resolveTo;
  bool? membership;
  int ensureLoadedCalls = 0;
  final List<({MediaKind kind, CatalogItemIds ids, bool add})> mutations = [];

  @override
  bool get supportsWatchlist => true;

  @override
  Future<void> ensureWatchlistLoaded() async {
    ensureLoadedCalls++;
  }

  @override
  bool? isOnWatchlist(MediaKind kind, CatalogItemIds ids) => membership;

  @override
  Future<CatalogItemIds?> resolveItemIds(MediaKind kind, ExternalIds external) async => resolveTo;

  @override
  Future<void> addToWatchlist(MediaKind kind, CatalogItemIds ids) async =>
      mutations.add((kind: kind, ids: ids, add: true));

  @override
  Future<void> removeFromWatchlist(MediaKind kind, CatalogItemIds ids) async =>
      mutations.add((kind: kind, ids: ids, add: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WatchlistSourcesProvider extends CatalogSourcesProvider {
  _WatchlistSourcesProvider(this.sources);

  final List<CatalogSource> sources;

  @override
  List<CatalogSource> get connectedSources => sources;
}

/// A Silo client on `srv-1` that answers the external-id fetch with [ids].
class _SeedIdsClient implements MediaServerClient {
  _SeedIdsClient(this.ids);

  final ExternalIds ids;

  @override
  ServerId get serverId => ServerId('srv-1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  void close() {}

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => ids;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Pumps a Silo movie's context menu with [sources] connected as catalog
/// sources. The client answers the external-id fetch with [ids] (default:
/// the item carries no external ids).
Future<({GlobalKey<MediaContextMenuState> menuKey, MediaItem item, CatalogSourcesProvider catalogSources})>
_pumpWatchlistMenu(
  WidgetTester tester, {
  required List<CatalogSource> sources,
  ExternalIds ids = const ExternalIds(),
}) async {
  LocaleSettings.setLocaleSync(AppLocale.en);
  TvDetectionService.debugSetAppleTVOverride(true);
  addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  SiloApiCache.initialize(db);
  final client = _SeedIdsClient(ids);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServerProvider = testMultiServerProvider(manager);
  final offlineMode = OfflineModeProvider(manager);
  final catalogSources = _WatchlistSourcesProvider(sources);
  final stack = await ProfileStack.create(db: db, withStorage: false);
  addTearDown(() async {
    await stack.dispose();
    catalogSources.dispose();
    offlineMode.dispose();
    multiServerProvider.dispose();
    manager.dispose();
    await db.close();
  });

  final menuKey = GlobalKey<MediaContextMenuState>();
  final item = testMediaItem(
    id: 'movie-1',
    backend: MediaBackend.silo,
    kind: MediaKind.movie,
    title: 'Movie',
    serverId: 'srv-1',
  );
  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
          ChangeNotifierProvider<CatalogSourcesProvider>.value(value: catalogSources),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: Center(
              child: MediaContextMenu(
                key: menuKey,
                item: item,
                child: const SizedBox(width: 120, height: 80, child: Text('watchlist target')),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (menuKey: menuKey, item: item, catalogSources: catalogSources);
}
