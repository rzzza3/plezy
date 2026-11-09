import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/filters_bottom_sheet.dart';
import 'package:plezy/screens/libraries/sort_bottom_sheet.dart';
import 'package:plezy/screens/library_network_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/silo_client.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_media_card.dart';
import 'package:plezy/widgets/hub_section.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../silo/fake_silo.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';
import 'library_networks_fixtures.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets("the row's last card opens the network's page of its library titles", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 3000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpNetworksSection(tester);

    // The 11th slot: after the row's titles (here nine).
    await tester.scrollUntilVisible(
      find.text(t.common.viewAll),
      300,
      scrollable: find.descendant(of: find.byType(HubSection), matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(find.text(t.common.viewAll));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.common.viewAll));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryNetworkScreen), findsOneWidget);
    // The name stands in for the logo, in the display face's capitals.
    expect(find.text('NETFLIX'), findsOneWidget);
    // A rail per row, stacked in order with its own header; Continue
    // Watching first.
    final rails = find.byType(HubSection);
    expect(rails, findsNWidgets(4));
    final headers = [
      t.discover.continueWatching,
      t.libraryHome.networkTabTrending,
      t.libraryHome.networkTopMovies,
      t.libraryHome.networkTopShows,
    ];
    for (final (index, header) in headers.indexed) {
      expect(
        find.descendant(of: rails.at(index), matching: find.text(header)),
        findsOneWidget,
        reason: header,
      );
    }
    // Trending on TMDB this week, kept to Netflix's titles: not the HBO series.
    final trending = rails.at(1);
    expect(find.descendant(of: trending, matching: find.byType(MediaCard)), findsNWidgets(2));
    expect(find.descendant(of: trending, matching: find.text('Title 81')), findsOneWidget);
    expect(find.descendant(of: trending, matching: find.text('Title 2133')), findsOneWidget);
    expect(find.textContaining('Title 491'), findsNothing);

    // Continue Watching keeps Netflix's titles: not the HBO episode.
    final continueWatching = rails.at(0);
    expect(find.descendant(of: continueWatching, matching: find.text('Title 80')), findsOneWidget);
    expect(find.textContaining('HBO Episode'), findsNothing);
    expect(find.textContaining('Title 490'), findsNothing);
    expect(find.textContaining(t.libraryHome.networkInProgress(count: ''), findRichText: true), findsOneWidget);

    // Browse all is every title in a grid, not a row with a View All card.
    await tester.scrollUntilVisible(
      find.textContaining(t.libraryHome.networkBrowseAll(count: '')),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining(t.libraryHome.networkBrowseAll(count: '')));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryNetworkBrowseScreen), findsOneWidget);
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.descendant(of: find.byType(SliverGrid), matching: find.byType(FocusableMediaCard)), findsWidgets);
    expect(find.text(t.common.viewAll), findsNothing);

    // Its Filters and Sort chips open the Library's sheets, built from the
    // network's own titles.
    await tester.tap(find.text(t.libraries.filters));
    await tester.pumpAndSettle();
    expect(find.byType(FiltersBottomSheet), findsOneWidget);
    expect(find.text(t.libraryHome.networkType), findsOneWidget);
    await tester.tapAt(const Offset(800, 20));
    await tester.pumpAndSettle();
    expect(find.byType(FiltersBottomSheet), findsNothing);

    await tester.tap(find.text(t.libraries.sort));
    await tester.pumpAndSettle();
    expect(find.byType(SortBottomSheet), findsOneWidget);
    expect(find.text(t.libraryHome.networkPopularity), findsOneWidget);
  });

  testWidgets('shows skeleton rows until Continue Watching loads', (tester) async {
    final home = Completer<void>();
    final (session, _) = (await tester.runAsync(signedInSession))!;
    final fake = FakeSilo((request) async {
      await home.future;
      return jsonResponse({'sections': <Object>[]}, 200);
    });
    final (client, _) = (await tester.runAsync(networksSilo))!;
    final silo = SiloClient(connection: client.connection, profileId: 'p-1', http: siloHttpFor(fake, session));
    final servers = testMultiServer(clients: [silo]);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 3000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final items = [
      for (final (index, kind) in [MediaKind.movie, MediaKind.show].indexed)
        MediaItem.silo(id: 'c$index', kind: kind, title: 'Title $index', serverId: 'server-1', serverName: 'Silo'),
    ];

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers.provider,
        child: MaterialApp(
          theme: appTheme,
          home: LibraryNetworkScreen(name: 'HBO', items: items),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HBO'), findsOneWidget);
    expect(find.byType(SkeletonLoader), findsWidgets);
    expect(find.textContaining(t.libraryHome.networkTitleCount(n: 2), findRichText: true), findsOneWidget);
    expect(find.text(t.libraryHome.networkTopMovies), findsNothing);

    home.complete();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(SkeletonLoader), findsNothing);
    // Nothing in progress: no Continue Watching rail.
    expect(find.text(t.discover.continueWatching), findsNothing);
    expect(find.text(t.libraryHome.networkTopMovies), findsOneWidget);
    expect(find.text(t.libraryHome.networkTopShows), findsOneWidget);
  });

  testWidgets('on TV the rows stack as rails, and UP and DOWN move between them', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final servers = testMultiServer();
    final items = [
      for (var index = 0; index < 6; index++)
        MediaItem.silo(
          id: 'c$index',
          kind: index.isEven ? MediaKind.movie : MediaKind.show,
          title: 'Title $index',
          serverId: 'server-1',
          serverName: 'Silo',
        ),
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: servers.provider,
        child: MaterialApp(
          theme: appTheme,
          home: LibraryNetworkScreen(name: 'HBO', items: items),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // No TMDB and nothing in progress: Top Movies over Top TV, each headed.
    final rails = find.byType(TvBrowseRail);
    expect(rails, findsNWidgets(2));
    expect(find.descendant(of: rails.at(0), matching: find.text(t.libraryHome.networkTopMovies)), findsOneWidget);
    expect(find.descendant(of: rails.at(1), matching: find.text(t.libraryHome.networkTopShows)), findsOneWidget);
    expect(tester.getTopLeft(rails.at(0)).dy, lessThan(tester.getTopLeft(rails.at(1)).dy));

    /// Which rail holds focus, or -1.
    int focusedRail() {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return -1;
      final railElements = [for (var i = 0; i < 2; i++) tester.element(rails.at(i))];
      var found = -1;
      focused.visitAncestorElements((element) {
        found = railElements.indexOf(element);
        return found < 0;
      });
      return found;
    }

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'library_network_browse');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedRail(), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedRail(), 1);
    // The page scrolled to bring the second rail up.
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, greaterThan(0));
    // The last rail keeps DOWN.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedRail(), 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusedRail(), 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'library_network_browse');
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels, 0);
  });
}
