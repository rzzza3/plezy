import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/library_change_event.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/screens/collection_detail_screen.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/tabs/library_collections_tab.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/utils/library_content_notifier.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/widgets/card_inflation_budget.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/media_card_sliver_layout.dart';
import 'package:plezy/widgets/media_context_menu.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/download_fixtures.dart';
import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/paged_fakes.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_stack.dart';

final _serverId = ServerId('collection-server');
final _siloServerId = ServerId('silo-collection-server');
final _siloMusicLibrary = MediaLibrary(
  id: 'music-library',
  backend: MediaBackend.silo,
  title: 'Music',
  kind: MediaKind.artist,
  serverId: _siloServerId,
);
final _movieLibrary = MediaLibrary(
  id: 'movies',
  backend: MediaBackend.silo,
  title: 'Movies',
  kind: MediaKind.movie,
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

  testWidgets('Silo video collections keep poster geometry when opened from a music library', (tester) async {
    final harness = _CollectionHarness.silo();
    addTearDown(harness.dispose);
    TvDetectionService.debugSetAppleTVOverride(true);
    await SettingsService.instance.write(SettingsService.tvFullCardLayout, true);

    await _pumpTab(tester, harness: harness, library: _siloMusicLibrary);

    final layout = tester.widget<MediaCardSliverLayout>(find.byType(MediaCardSliverLayout));
    expect(layout.shape, isNull);
    expect(layout.fullBleedImage, isTrue);
    expect(tester.widget<FocusableMediaCard>(find.byType(FocusableMediaCard)).cardShapeOverride, isNull);
  });

  testWidgets('a server push repopulates the collections grid in place (#1646)', (tester) async {
    var count = 2;
    var first = 1;
    Completer<void>? gate;
    final harness = _CollectionHarness.movies(
      collectionCount: 2,
      currentCount: () => count,
      firstIndex: () => first,
      responseGate: () => gate?.future ?? Future<void>.value(),
    );
    addTearDown(harness.dispose);

    await _pumpTab(tester, harness: harness, library: _movieLibrary, isActive: true);
    expect(find.text('Collection 1'), findsOneWidget);
    expect(find.text('Collection 2'), findsOneWidget);

    // A D-pad session parked on the first card.
    await _enterGridAndFocusFirstCard(tester);

    // The server prepends a collection and pushes. The initial load credited
    // the live pacer's cooldown, so the pass lands at the trailing edge.
    count = 3;
    first = 0;
    gate = Completer<void>();
    LibraryContentNotifier().notifyChanged(
      LibraryChangeEvent(serverId: _serverId, libraryIds: const {'movies'}, itemsAdded: true),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(minutes: 2, seconds: 1));

    // In place: while the refetch is in flight the old cards stay rendered —
    // no clearing, no loading state (the P1 regression cleared the grid here).
    expect(find.text('Collection 1'), findsOneWidget);
    expect(find.text('Collection 2'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gate.complete();
    gate = null;
    await tester.pumpAndSettle();
    expect(find.text('Collection 0'), findsOneWidget, reason: 'the pushed addition materialized live');
    expect(find.text('Collection 1'), findsOneWidget);

    // Selection follows the surviving collection, not its former slot.
    expect(_cardFor(tester, 'Collection 1').focusNode!.hasPrimaryFocus, isTrue);
  });

  for (final hostedMenu in [true, false]) {
    testWidgets('a ${hostedMenu ? 'hosted menu' : 'root dialog'} restores the moved collection', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      var first = 1;
      var count = 3;
      Completer<void>? gate;
      final harness = _CollectionHarness.movies(
        collectionCount: 3,
        currentCount: () => count,
        firstIndex: () => first,
        responseGate: () => gate?.future ?? Future<void>.value(),
      );
      addTearDown(harness.dispose);
      final stack = await ProfileStack.create(db: harness.database, withStorage: false);
      addTearDown(stack.dispose);
      await _pumpTab(tester, harness: harness, library: _movieLibrary, isActive: true, profileStack: stack);
      await _enterGridAndFocusFirstCard(tester);
      final originalNode = _cardFor(tester, 'Collection 1').focusNode!;

      // Both directions across the dedicated first-item boundary. Open each
      // cover after the fetch starts so route TickerMode cannot hide the race.
      for (final nextFirst in [0, 1]) {
        first = nextFirst;
        count = nextFirst == 0 ? 4 : 3;
        gate = Completer<void>();
        LibraryContentNotifier().notifyChanged(
          LibraryChangeEvent(serverId: _serverId, libraryIds: const {'movies'}, itemsAdded: true),
        );
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(minutes: 2, seconds: 1));
        final card = find.ancestor(of: find.text('Collection 1'), matching: find.byType(FocusableMediaCard));
        final cardContext = tester.element(card);
        FocusNode? dialogFocus;
        if (hostedMenu) {
          final menu = tester.state<MediaContextMenuState>(
            find.descendant(of: card, matching: find.byType(MediaContextMenu)),
          );
          menu.showContextMenu(cardContext);
        } else {
          dialogFocus = FocusNode();
          addTearDown(dialogFocus.dispose);
          unawaited(
            showDialog<void>(
              context: cardContext,
              builder: (_) => AlertDialog(
                content: Focus(focusNode: dialogFocus, autofocus: true, child: const Text('Cover')),
              ),
            ),
          );
        }
        await tester.pumpAndSettle();
        final coveredFocus = FocusManager.instance.primaryFocus;
        expect(originalNode.hasFocus, isFalse);
        gate.complete();
        gate = null;
        await tester.pumpAndSettle();
        expect(
          FocusManager.instance.primaryFocus,
          same(coveredFocus),
          reason: 'the cover owns focus throughout commit',
        );
        expect(_cardFor(tester, 'Collection 1').focusNode, same(originalNode));
        if (hostedMenu) {
          OverlaySheetController.of(tester.element(find.byType(LibraryCollectionsTab))).close();
        } else {
          Navigator.of(dialogFocus!.context!).pop();
        }
        await tester.pumpAndSettle();
        expect(_cardFor(tester, 'Collection 1').focusNode!.hasPrimaryFocus, isTrue);
      }

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<CollectionDetailScreen>(find.byType(CollectionDetailScreen)).collection.id, 'collection-1');
    });
  }

  group('D-pad grid navigation', () {
    testWidgets('UP moves one row up without resetting the scroll position', (tester) async {
      final harness = _CollectionHarness.movies(collectionCount: 60);
      addTearDown(harness.dispose);

      await _pumpTab(tester, harness: harness, library: _movieLibrary);
      final columns = await _enterGridAndFocusFirstCard(tester);

      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(_cardFor(tester, 'Collection ${4 * columns}').focusNode!.hasPrimaryFocus, isTrue);

      final scrollable = Scrollable.of(FocusManager.instance.primaryFocus!.context!);
      final pixelsBeforeUp = scrollable.position.pixels;
      expect(pixelsBeforeUp, greaterThan(0));

      // Regression #1977: default directional traversal ran
      // Scrollable.ensureVisible through the NestedScrollView coordinator,
      // which reset the inner position to 0 and bounced focus to the header.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'Collection ${3 * columns}').focusNode!.hasPrimaryFocus, isTrue);
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets('focusing the first item scrolls back once its card has unmounted', (tester) async {
      final harness = _CollectionHarness.movies(collectionCount: 120);
      addTearDown(harness.dispose);

      await _pumpTab(tester, harness: harness, library: _movieLibrary);
      await _enterGridAndFocusFirstCard(tester);
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(find.text('Collection 0', skipOffstage: false), findsNothing);

      (tester.state(find.byType(LibraryCollectionsTab)) as dynamic).focusFirstItem();
      await tester.pumpAndSettle();

      expect(_cardFor(tester, 'Collection 0').focusNode!.hasPrimaryFocus, isTrue);
    });

    testWidgets('UP from the first row hands focus to onBack', (tester) async {
      final harness = _CollectionHarness.movies(collectionCount: 60);
      addTearDown(harness.dispose);
      var backCalls = 0;

      await _pumpTab(tester, harness: harness, library: _movieLibrary, onBack: () => backCalls++);
      await _enterGridAndFocusFirstCard(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(backCalls, 1);
    });

    testWidgets('LEFT and RIGHT move within a row; first column LEFT reaches the sidebar', (tester) async {
      final harness = _CollectionHarness.movies(collectionCount: 60);
      addTearDown(harness.dispose);
      var sidebarCalls = 0;

      await _pumpTab(tester, harness: harness, library: _movieLibrary, focusSidebar: () => sidebarCalls++);
      await _enterGridAndFocusFirstCard(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(_cardFor(tester, 'Collection 1').focusNode!.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(_cardFor(tester, 'Collection 0').focusNode!.hasPrimaryFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(sidebarCalls, 1);
    });
  });
}

Future<void> _pumpTab(
  WidgetTester tester, {
  required _CollectionHarness harness,
  required MediaLibrary library,
  VoidCallback? onBack,
  VoidCallback? focusSidebar,
  bool isActive = false,
  ProfileStack? profileStack,
}) async {
  final downloads = NoSyncRulesDownloadProvider();
  addTearDown(downloads.dispose);
  await pumpLibraryTab(
    tester,
    provider: harness.provider,
    downloads: downloads,
    tab: profileStack == null
        ? LibraryCollectionsTab(library: library, suppressAutoFocus: true, isActive: isActive, onBack: onBack ?? () {})
        : ChangeNotifierProvider<ActiveProfileProvider>.value(
            value: profileStack.active,
            child: OverlaySheetHost(
              child: FocusScope(
                child: LibraryCollectionsTab(
                  library: library,
                  suppressAutoFocus: true,
                  isActive: isActive,
                  onBack: onBack ?? () {},
                ),
              ),
            ),
          ),
    size: const Size(800, 600),
    focusSidebar: focusSidebar,
  );
  await tester.pumpAndSettle();
}

FocusableMediaCard _cardFor(WidgetTester tester, String title) =>
    tester.widget<FocusableMediaCard>(find.ancestor(of: find.text(title), matching: find.byType(FocusableMediaCard)));

/// Switches to keyboard input mode, focuses the first card, and returns the
/// grid's column count (cards sharing the first realized row's dy).
Future<int> _enterGridAndFocusFirstCard(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();

  final cards = find.byType(FocusableMediaCard);
  final firstRowDy = tester.getTopLeft(cards.first).dy;
  var columns = 0;
  for (final element in cards.evaluate()) {
    if (tester.getTopLeft(find.byWidget(element.widget)).dy == firstRowDy) columns++;
  }

  tester.widget<FocusableMediaCard>(cards.first).focusNode!.requestFocus();
  await tester.pumpAndSettle();
  expect(tester.widget<FocusableMediaCard>(cards.first).focusNode!.hasPrimaryFocus, isTrue);
  return columns;
}

class _CollectionHarness {
  final AppDatabase database;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  _CollectionHarness._({required this.database, required MediaServerClient client}) {
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  /// Movie library with [collectionCount] collections, served as one page.
  /// [currentCount] overrides the count per request, [firstIndex] the lowest
  /// collection number in the payload (so a refetch can prepend rather than
  /// append), and [responseGate] holds a response open, so live-refresh tests
  /// can stage a changed payload and observe the in-flight state.
  factory _CollectionHarness.movies({
    required int collectionCount,
    int Function()? currentCount,
    int Function()? firstIndex,
    Future<void> Function()? responseGate,
  }) {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = _SiloCollectionsClient.paged(
      serverId: _serverId,
      responseGate: responseGate,
      collections: () {
        final count = currentCount?.call() ?? collectionCount;
        final first = firstIndex?.call() ?? 0;
        return [
          for (var i = first; i < first + count; i++)
            testMediaItem(
              id: 'collection-$i',
              backend: MediaBackend.silo,
              kind: MediaKind.collection,
              title: 'Collection $i',
              childCount: 2,
              libraryId: 'movies',
              serverId: _serverId,
            ),
        ];
      },
      members: [
        for (var i = 1; i <= 2; i++)
          testMediaItem(
            id: 'member-$i',
            backend: MediaBackend.silo,
            kind: MediaKind.movie,
            title: 'Member $i',
            serverId: _serverId,
          ),
      ],
    );
    return _CollectionHarness._(database: database, client: client);
  }

  factory _CollectionHarness.silo() {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final client = _SiloCollectionsClient([
      testMediaItem(
        id: 'video-collection-1',
        backend: MediaBackend.silo,
        kind: MediaKind.collection,
        title: 'Movie Collection',
        serverId: _siloServerId,
      ),
    ]);
    return _CollectionHarness._(database: database, client: client);
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
    await database.close();
  }
}

/// A Silo client serving the library's collection rows and their members.
class _SiloCollectionsClient implements MediaServerClient {
  _SiloCollectionsClient(List<MediaItem> collections)
    : serverId = _siloServerId,
      collections = (() => collections),
      responseGate = null,
      members = const [];

  /// Collections answered per request by [collections] (so a test can change
  /// the payload between fetches), each held by [responseGate] when given.
  /// Every collection holds [members].
  _SiloCollectionsClient.paged({
    required this.serverId,
    required this.collections,
    this.responseGate,
    this.members = const [],
  });

  final List<MediaItem> Function() collections;
  final Future<void> Function()? responseGate;
  final List<MediaItem> members;

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Silo';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    await responseGate?.call();
    return fakeLibraryPage(collections(), start: start, size: size);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    AbortController? abort,
    String? libraryId,
    String? libraryTitle,
  }) async => fakeLibraryPage(members, start: start, size: size);

  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) => '';

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
