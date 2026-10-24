import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_playlist.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/tabs/library_playlists_tab.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/layout_constants.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/card_inflation_budget.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/optimized_media_image.dart';

import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/paged_fakes.dart';
import '../../test_helpers/prefs.dart';

final _serverId = ServerId('playlist-server');
final _library = MediaLibrary(
  id: 'movies',
  backend: MediaBackend.silo,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: _serverId,
);
final _musicLibrary = MediaLibrary(
  id: 'music',
  backend: MediaBackend.silo,
  title: 'Music',
  kind: MediaKind.artist,
  serverId: _serverId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    CardInflationBudget.reset();
    TvDetectionService.debugSetAppleTVOverride(false);
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('grid lazily builds playlist cards and preserves focus navigation', (tester) async {
    final harness = _PlaylistHarness();
    addTearDown(harness.dispose);
    var backCalls = 0;
    var sidebarCalls = 0;

    await _pumpTab(
      tester,
      harness: harness,
      library: _library,
      onBack: () => backCalls++,
      onSidebar: () => sidebarCalls++,
    );

    expect(find.byType(SliverGrid), findsOneWidget);
    final cards = tester.widgetList<FocusableMediaCard>(find.byType(FocusableMediaCard)).toList();
    expect(cards, isNotEmpty);
    expect(cards.length, lessThan(_PlaylistHarness.totalPlaylists));

    await _focusFirstCard(tester);

    // Within a row, RIGHT and LEFT move between neighbours.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 1).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isTrue);

    // First column LEFT reaches the sidebar instead of moving inside the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sidebarCalls, 1);
    expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isTrue);

    // Below the top row, UP moves focus up a row rather than leaving the grid
    // (default directional traversal resets the NestedScrollView on UP).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isTrue);
    expect(backCalls, 0);

    // First row: UP and BACK hand off to the tab bar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(backCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(backCalls, 2);

    final scrollableFinder = find.descendant(of: find.byType(LibraryPlaylistsTab), matching: find.byType(Scrollable));
    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(harness.requestStarts, contains(200));
    final pagedCards = tester.widgetList<FocusableMediaCard>(find.byType(FocusableMediaCard)).toList();
    expect(pagedCards.length, lessThan(_PlaylistHarness.totalPlaylists));
    expect(
      pagedCards.map((card) => int.parse((card.item as MediaPlaylist).id.substring('playlist-'.length))),
      contains(greaterThanOrEqualTo(200)),
    );
  });

  testWidgets('list stays lazy without changing row navigation', (tester) async {
    await SettingsService.instance.write(SettingsService.viewMode, ViewMode.list);
    final harness = _PlaylistHarness();
    addTearDown(harness.dispose);
    var backCalls = 0;
    var sidebarCalls = 0;

    await _pumpTab(
      tester,
      harness: harness,
      library: _library,
      onBack: () => backCalls++,
      onSidebar: () => sidebarCalls++,
    );

    expect(find.byType(SliverList), findsOneWidget);
    final cards = tester.widgetList<FocusableMediaCard>(find.byType(FocusableMediaCard)).toList();
    expect(cards, isNotEmpty);
    expect(cards.length, lessThan(_PlaylistHarness.totalPlaylists));
    expect(_cardFor(tester, 0).disableScale, isTrue);

    await _focusFirstCard(tester);

    // One card per row: DOWN and UP move between rows, and LEFT always
    // reaches the sidebar.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 1).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sidebarCalls, 1);
    expect(_cardFor(tester, 1).focusNode!.hasPrimaryFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isTrue);
    expect(backCalls, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(backCalls, 1);
  });

  testWidgets('music library playlists render square artwork, captions and square gutters', (tester) async {
    final harness = _PlaylistHarness(playlistType: 'audio');
    addTearDown(harness.dispose);
    TvDetectionService.debugSetAppleTVOverride(true);
    await SettingsService.instance.write(SettingsService.tvFullCardLayout, true);

    await _pumpTab(tester, harness: harness, library: _musicLibrary, onBack: () {}, onSidebar: () {});

    // Square artwork rather than a poster: a poster cell renders artwork
    // roughly half again as tall as it is wide.
    final artwork = tester.getSize(
      find.descendant(of: find.byKey(const Key('playlist-0')), matching: find.byType(OptimizedMediaImage)),
    );
    expect(artwork.height, lessThan(artwork.width * 1.1));

    // TV full-card layout never applies to square shapes, so the caption band
    // outside the artwork stays rendered.
    expect(find.text('Playlist 0'), findsOneWidget);

    // Square grids keep their square gutter spacing even on TV full-card
    // layout.
    expect(
      tester.getTopLeft(find.byKey(const Key('playlist-1'))).dx -
          tester.getTopRight(find.byKey(const Key('playlist-0'))).dx,
      GridLayoutConstants.squareGridSpacing,
    );
  });
}

FocusableMediaCard _cardFor(WidgetTester tester, int index) =>
    tester.widget<FocusableMediaCard>(find.byKey(Key('playlist-$index')));

/// Switches to keyboard input mode and parks focus on the first card, the way
/// a D-pad session enters the grid.
Future<void> _focusFirstCard(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  _cardFor(tester, 0).focusNode!.requestFocus();
  await tester.pumpAndSettle();
  expect(_cardFor(tester, 0).focusNode!.hasPrimaryFocus, isTrue);
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required _PlaylistHarness harness,
  required MediaLibrary library,
  required VoidCallback onBack,
  required VoidCallback onSidebar,
}) async {
  await pumpLibraryTab(
    tester,
    provider: harness.provider,
    tab: LibraryPlaylistsTab(library: library, suppressAutoFocus: true, onBack: onBack),
    size: const Size(800, 600),
    focusSidebar: onSidebar,
  );
  await tester.pumpAndSettle();
}

class _PlaylistHarness {
  static const totalPlaylists = 400;

  final String playlistType;
  final requestStarts = <int>[];
  late final _PlaylistClient client;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  _PlaylistHarness({this.playlistType = 'video'}) {
    client = _PlaylistClient(
      playlists: [
        for (var index = 0; index < totalPlaylists; index++)
          MediaPlaylist(
            id: 'playlist-$index',
            backend: MediaBackend.silo,
            title: 'Playlist $index',
            playlistType: playlistType,
            serverId: _serverId,
          ),
      ],
      requestStarts: requestStarts,
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
  }
}

/// A Silo client whose playlist pages slice [playlists], recording each
/// requested page start.
class _PlaylistClient implements MediaServerClient {
  _PlaylistClient({required this.playlists, required this.requestStarts});

  final List<MediaPlaylist> playlists;
  final List<int> requestStarts;

  @override
  ServerId get serverId => _serverId;

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    requestStarts.add(start ?? 0);
    return fakeLibraryPage(playlists, start: start, size: size);
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
