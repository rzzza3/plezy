import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/library_genres_section.dart';
import 'package:plezy/screens/library_home_screen.dart';
import 'package:plezy/screens/library_networks_section.dart';
import 'package:plezy/screens/settings/library_networks_screen.dart';
import 'package:plezy/services/library_rows.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/services/tmdb/tmdb_genres.dart';
import 'package:plezy/services/tmdb/tmdb_networks.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import 'library_networks_fixtures.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('shows networks with enough library titles, newest added first', (tester) async {
    await pumpNetworksSection(tester);

    expect(SettingsService.instance.read(SettingsService.libraryNetworks), TmdbNetworks.defaultIds);
    expect(find.bySemanticsLabel('Netflix'), findsOneWidget);
    expect(find.bySemanticsLabel('HBO'), findsOneWidget);
    // Three titles and none: too few to show.
    expect(find.bySemanticsLabel('Prime Video'), findsNothing);
    expect(find.bySemanticsLabel('Paramount+'), findsNothing);
    // Library cards, not TMDB's: Netflix's films, added last, then its series.
    expect(find.text('Title 2130'), findsWidgets);
    expect(find.text('Title 80'), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Title 80').first).dx,
      lessThan(tester.getTopLeft(find.text('Title 2130').first).dx),
    );
    expect(find.textContaining('TMDB'), findsNothing);

    await tester.tap(find.bySemanticsLabel('HBO'));
    await tester.pumpAndSettle();
    expect(find.text('Title 490'), findsWidgets);
    expect(find.text('Title 2130'), findsNothing);
  });

  testWidgets("shows a placeholder while it matches, which focus passes over", (tester) async {
    final discovered = Completer<void>();
    await pumpNetworksSection(tester, tmdb: networksTmdb(discovered: discovered.future), settle: false);
    await tester.pump();
    final section = tester.state<LibraryNetworksSectionState>(find.byType(LibraryNetworksSection));
    expect(find.text(t.libraryHome.networks), findsOneWidget);
    expect(find.text(t.common.loading), findsOneWidget);
    // Every chosen network, before it is known which have enough titles.
    expect(find.bySemanticsLabel('Prime Video'), findsOneWidget);
    expect(section.isShown, isFalse);

    discovered.complete();
    await tester.pumpAndSettle();
    expect(find.text(t.common.loading), findsNothing);
    expect(find.bySemanticsLabel('Prime Video'), findsNothing);
    expect(find.bySemanticsLabel('Netflix'), findsOneWidget);
    expect(section.isShown, isTrue);
  });

  testWidgets('a retry loads it once the server is online', (tester) async {
    // Straight after sign-in the tab can open before its server is online;
    // the Library tab retries its sections when one comes online.
    final (:manager, :client) = await pumpNetworksSection(tester, offline: true);
    final section = tester.state<LibraryNetworksSectionState>(find.byType(LibraryNetworksSection));
    section.retryIfUnavailable();
    await tester.pumpAndSettle();
    expect(find.text(t.libraryHome.networks), findsNothing);

    manager.updateServerStatus(client.serverId, true);
    section.retryIfUnavailable();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Netflix'), findsOneWidget);
  });

  testWidgets('the header filter narrows the rows and leaves out thin networks', (tester) async {
    // Netflix has two films in the library and HBO none: nothing to show.
    await pumpNetworksSection(tester, filter: LibraryHomeFilter.movies);
    expect(find.text(t.libraryHome.networks), findsNothing);
  });

  testWidgets('follows the setting and hides with no network chosen', (tester) async {
    await pumpNetworksSection(tester);

    await SettingsService.instance.write(SettingsService.libraryNetworks, ['49', '2739']);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Netflix'), findsNothing);
    expect(find.text('Title 490'), findsWidgets);

    await SettingsService.instance.write(SettingsService.libraryNetworks, const <String>[]);
    await tester.pumpAndSettle();
    expect(find.text(t.libraryHome.networks), findsNothing);
  });

  testWidgets('hides when the build has no TMDB credentials', (tester) async {
    await pumpNetworksSection(
      tester,
      tmdb: TmdbClient(token: '', apiKey: ''),
    );
    expect(find.text(t.libraryHome.networks), findsNothing);
  });

  testWidgets("genres show the library's titles Silo lists in them, without TMDB too", (tester) async {
    Widget genres(LibraryHomeFilter filter) =>
        LibraryGenresSection(filter: filter, onNavigateUp: () {}, onNavigateToSidebar: () {});
    await pumpNetworksSection(
      tester,
      tmdb: TmdbClient(token: '', apiKey: ''),
      section: genres,
    );

    expect(find.text(t.libraryHome.genres), findsOneWidget);
    expect(find.bySemanticsLabel('Drama'), findsOneWidget);
    // Two comedies: too few to show.
    expect(find.bySemanticsLabel('Comedy'), findsNothing);
    expect(find.text('Title 2130'), findsWidgets);
    expect(find.text('Title 80'), findsNothing);
  });

  testWidgets('the Networks row follows the order the setting lists', (tester) async {
    await SettingsService.instance.write(SettingsService.libraryNetworks, ['49', '213']);
    await pumpNetworksSection(tester);
    expect(
      tester.getCenter(find.bySemanticsLabel('HBO')).dx,
      lessThan(tester.getCenter(find.bySemanticsLabel('Netflix')).dx),
    );
  });

  /// The Edit page, on [tab]'s rail entry (it opens on Rows).
  Future<void> pumpEditPage(WidgetTester tester, {String tab = 'networks'}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      Provider<TmdbClient>.value(
        value: networksTmdb(),
        child: InputModeTracker(
          child: MaterialApp(theme: appTheme, home: const LibraryNetworksScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (tab != 'rows') {
      await tester.tap(find.byKey(ValueKey('edit-library-$tab')));
      await tester.pumpAndSettle();
    }
  }

  List<String> networks() => SettingsService.instance.read(SettingsService.libraryNetworks);

  testWidgets('edit page lists every network; picking one adds it to the end of the row', (tester) async {
    await pumpEditPage(tester);
    expect(find.text(t.libraryHome.editLibrary), findsOneWidget);
    for (final network in TmdbNetworks.all) {
      expect(find.byKey(ValueKey('library-network-${network.id}')), findsOneWidget, reason: network.name);
    }
    expect(find.text(t.libraryHome.editLibraryShown(count: 4, total: TmdbNetworks.all.length)), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('library-network-2739')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-network-213')));
    await tester.pumpAndSettle();
    expect(networks(), ['1024', '49', '4330', '2739']);
    expect(find.byKey(const ValueKey('library-row-networks-2739')), findsOneWidget);
    expect(find.byKey(const ValueKey('library-row-networks-213')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('edit-library-reset')));
    await tester.pumpAndSettle();
    expect(networks(), TmdbNetworks.defaultIds);
  });

  testWidgets('with nothing picked the page says the row is hidden', (tester) async {
    await SettingsService.instance.write(SettingsService.libraryNetworks, const <String>[]);
    await pumpEditPage(tester);
    expect(find.text(t.libraryHome.editLibraryEmpty), findsOneWidget);
  });

  testWidgets('OK picks up a row tile, RIGHT moves it, OK puts it down; BACK drops the move', (tester) async {
    await pumpEditPage(tester);
    FocusNode rowNode(String id) => tester
        .widget<Focus>(
          find.descendant(of: find.byKey(ValueKey('library-row-networks-$id')), matching: find.byType(Focus)).first,
        )
        .focusNode!;

    rowNode('213').requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // Not written until it is put down.
    expect(networks(), TmdbNetworks.defaultIds);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(networks(), ['1024', '49', '213', '4330']);
    expect(rowNode('213').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(networks(), ['1024', '49', '213', '4330']);
    expect(find.byType(LibraryNetworksScreen), findsOneWidget);
  });

  testWidgets("the system's back drops a move without leaving the page", (tester) async {
    await pumpEditPage(tester);
    tester
        .widget<Focus>(
          find
              .descendant(of: find.byKey(const ValueKey('library-row-networks-213')), matching: find.byType(Focus))
              .first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(LibraryNetworksScreen), findsOneWidget);
    expect(find.text(t.libraryHome.editLibraryMovingHint), findsNothing);
    expect(networks(), TmdbNetworks.defaultIds);
  });

  testWidgets("Android TV's back order (down, platform back, up) drops a move and keeps the page", (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 2400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      Provider<TmdbClient>.value(
        value: networksTmdb(),
        child: MaterialApp(theme: appTheme, navigatorKey: navigator, home: const SizedBox()),
      ),
    );
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const LibraryNetworksScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-library-networks')));
    await tester.pumpAndSettle();

    tester
        .widget<Focus>(
          find
              .descendant(of: find.byKey(const ValueKey('library-row-networks-213')), matching: find.byType(Focus))
              .first,
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(LibraryNetworksScreen), findsOneWidget);
    expect(find.text(t.libraryHome.editLibraryMovingHint), findsNothing);
    expect(networks(), TmdbNetworks.defaultIds);

    // The next BACK closes the page as usual.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(LibraryNetworksScreen), findsNothing);
  });

  FocusNode focusOf(WidgetTester tester, String key) => tester
      .widget<Focus>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Focus)).first)
      .focusNode!;

  testWidgets('the remote moves between the rail and the tiles by row, not by distance', (tester) async {
    await pumpEditPage(tester);
    focusOf(tester, 'edit-library-networks').requestFocus();
    await tester.pump();

    // RIGHT enters the row strip; LEFT off its first tile returns to the rail.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(focusOf(tester, 'library-row-networks-213').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusOf(tester, 'edit-library-networks').hasFocus, isTrue);

    // A first-column grid tile far below the rail still goes back to the
    // row being edited, and RIGHT returns to that tile.
    final firstChannel = TmdbNetworks.all.firstWhere((network) => network.group == TmdbNetworkGroup.usChannels);
    final channel = focusOf(tester, 'library-network-${firstChannel.id}');
    channel.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(focusOf(tester, 'edit-library-networks').hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(channel.hasFocus, isTrue);
  });

  testWidgets('after Reset, focus is on the row being edited and UP leaves it', (tester) async {
    await SettingsService.instance.write(SettingsService.libraryGenres, const ['western']);
    await pumpEditPage(tester);
    focusOf(tester, 'edit-library-networks').requestFocus();
    await tester.pump();
    // The first arrow puts the app in remote mode, where the rail follows focus.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusOf(tester, 'edit-library-reset').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.libraryGenres), TmdbGenres.defaultIds);
    expect(focusOf(tester, 'edit-library-genres').hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(focusOf(tester, 'edit-library-networks').hasFocus, isTrue);
  });

  testWidgets('the rail switches to genres, which toggle the same way', (tester) async {
    await pumpEditPage(tester);
    await tester.tap(find.byKey(const ValueKey('edit-library-genres')));
    await tester.pumpAndSettle();
    for (final genre in TmdbGenres.all) {
      expect(find.byKey(ValueKey('library-genre-${genre.id}')), findsOneWidget, reason: genre.name);
    }
    await tester.tap(find.byKey(const ValueKey('library-genre-western')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-genre-horror')));
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.libraryGenres), [
      ...TmdbGenres.defaultIds.where((id) => id != 'horror'),
      'western',
    ]);
  });

  group('Rows', () {
    List<String> order() => SettingsService.instance.read(SettingsService.libraryRowOrder);
    List<String> hidden() => SettingsService.instance.read(SettingsService.libraryRowsHidden);

    testWidgets('the page opens on Rows, listing every Library row in order', (tester) async {
      await pumpEditPage(tester, tab: 'rows');
      expect(find.text(t.libraryHome.editLibraryRowsHeading), findsOneWidget);
      expect(
        find.text(t.libraryHome.editLibraryShown(count: LibraryRow.values.length, total: LibraryRow.values.length)),
        findsOneWidget,
      );
      final tops = [
        for (final row in LibraryRow.values) tester.getTopLeft(find.byKey(ValueKey('library-rows-${row.name}'))).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
    });

    testWidgets('the toggle hides a row and shows it again; Reset clears it', (tester) async {
      await pumpEditPage(tester, tab: 'rows');
      await tester.tap(find.byKey(const ValueKey('library-rows-calendar-toggle')));
      await tester.pumpAndSettle();
      expect(hidden(), ['calendar']);
      expect(LibraryRow.shown(), isNot(contains(LibraryRow.calendar)));
      expect(find.text(t.libraryHome.editLibraryRowHidden), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('library-rows-genres-toggle')));
      await tester.pumpAndSettle();
      expect(hidden(), ['calendar', 'genres']);

      await tester.tap(find.byKey(const ValueKey('edit-library-reset')));
      await tester.pumpAndSettle();
      expect(hidden(), isEmpty);
      expect(LibraryRow.shown(), LibraryRow.values);
    });

    testWidgets('OK picks up a row, DOWN moves it, OK puts it down; BACK drops the move', (tester) async {
      await pumpEditPage(tester, tab: 'rows');
      FocusNode node(String name) => tester
          .widget<Focus>(
            find.descendant(of: find.byKey(ValueKey('library-rows-$name')), matching: find.byType(Focus)).first,
          )
          .focusNode!;

      node('continueWatching').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text(t.libraryHome.editLibraryRowsMovingHint), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      // Sideways stays on the row while it is picked up.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(order(), isEmpty);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(LibraryRow.savedOrder(), [
        LibraryRow.calendar,
        LibraryRow.seasonal,
        LibraryRow.continueWatching,
        LibraryRow.runtime,
        LibraryRow.forYou,
        LibraryRow.networks,
        LibraryRow.genres,
      ]);
      expect(node('continueWatching').hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(LibraryRow.savedOrder()[2], LibraryRow.continueWatching);
      expect(find.byType(LibraryNetworksScreen), findsOneWidget);

      // Moved back to where it started, the order is the default again.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(order(), isEmpty);
    });
  });

  group('LibraryRow.orderOf', () {
    test('drops unknown names and repeats, and appends rows the list lacks', () {
      expect(LibraryRow.orderOf(const []), LibraryRow.values);
      expect(LibraryRow.orderOf(const ['genres', 'bogus', 'calendar', 'genres']), [
        LibraryRow.genres,
        LibraryRow.calendar,
        LibraryRow.continueWatching,
        LibraryRow.seasonal,
        LibraryRow.runtime,
        LibraryRow.forYou,
        LibraryRow.networks,
      ]);
    });
  });
}
