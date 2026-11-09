import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/library_calendar_section.dart';
import 'package:plezy/screens/library_for_you_section.dart';
import 'package:plezy/screens/library_genres_section.dart';
import 'package:plezy/screens/library_home_screen.dart';
import 'package:plezy/screens/library_networks_section.dart';
import 'package:plezy/screens/library_runtime_section.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/tmdb/tmdb_client.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

/// Where focus starts on the Library tab (TV).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => initializeDateFormatting('en'));

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// The Library tab inside a content scope like MainScreen's, beside a
  /// stand-in sidebar button. Returns the content scope, the sidebar button's
  /// node and how many times the tab asked for the sidebar.
  Future<({FocusScopeNode content, FocusNode sidebar, List<int> sidebarCalls})> pumpLibrary(
    WidgetTester tester, {
    required bool focusSidebarFirst,
  }) async {
    await SettingsService.getInstance();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1920, 1080);
    addTearDown(tester.view.reset);

    final manager = MultiServerManager();
    final multiServer = testMultiServerProvider(manager);
    final hidden = HiddenLibrariesProvider();
    final libraries = LibrariesProvider();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final registry = _NoConnections(db);
    final storage = await StorageService.getInstance();
    final households = SiloHouseholdService(connections: registry, loader: (_) async => null);
    final profiles = ActiveProfileProvider(households: households, connections: registry, storage: storage);
    final discover = DiscoverProvider(
      multiServer,
      hidden,
      libraries,
      profileId: null,
      isProfileBinding: () => profiles.isBinding,
    );
    final tmdb = TmdbClient(token: '', apiKey: '');
    addTearDown(() async {
      discover.dispose();
      profiles.dispose();
      libraries.dispose();
      hidden.dispose();
      multiServer.dispose();
      households.dispose();
      tmdb.dispose();
      await db.close();
    });

    final content = FocusScopeNode(debugLabel: 'Content');
    final sidebar = FocusNode(debugLabel: 'sidebar_item');
    addTearDown(content.dispose);
    addTearDown(sidebar.dispose);
    final sidebarCalls = <int>[];

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
            ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: profiles),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
            Provider<TmdbClient>.value(value: tmdb),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: MainScreenFocusScope(
              focusSidebar: () {
                sidebarCalls.add(1);
                sidebar.requestFocus();
              },
              sideNavigationWidth: 0,
              child: Row(
                children: [
                  Focus(focusNode: sidebar, child: const SizedBox(width: 80, height: 80)),
                  Expanded(
                    child: FocusScope(node: content, child: const LibraryHomeScreen()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // As MainScreen does: focus the content scope itself on a cold start, or
    // keep focus on the sidebar item that opened the tab.
    if (focusSidebarFirst) {
      sidebar.requestFocus();
    } else {
      content.requestFocus();
    }
    await tester.pump();
    await tester.pump();
    return (content: content, sidebar: sidebar, sidebarCalls: sidebarCalls);
  }

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  testWidgets('a cold start puts focus on the hero, so LEFT opens the sidebar without scrolling', (tester) async {
    final (:content, :sidebar, :sidebarCalls) = await pumpLibrary(tester, focusSidebarFirst: false);

    // Nothing in progress, so no Resume: the first button is Browse All.
    expect(focusedLabel(), 'library_home_browse_all');
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(scroll.pixels, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(sidebarCalls, hasLength(1));
    expect(sidebar.hasFocus, isTrue);
    expect(scroll.pixels, 0);
  });

  /// The Library's row widgets, top to bottom.
  List<Type> rowTypes(WidgetTester tester) => [
    for (final widget in tester.widgetList(
      find.byWidgetPredicate(
        (widget) =>
            widget is LibraryCalendarSection ||
            widget is LibraryRuntimeSection ||
            widget is LibraryForYouSection ||
            widget is LibraryNetworksSection ||
            widget is LibraryGenresSection,
      ),
    ))
      widget.runtimeType,
  ];

  testWidgets('rows follow the order set on the Edit page, and hidden ones are not built', (tester) async {
    await SettingsService.getInstance();
    await SettingsService.instance.write(SettingsService.libraryRowOrder, const ['genres', 'runtime', 'calendar']);
    await SettingsService.instance.write(SettingsService.libraryRowsHidden, const ['calendar', 'forYou']);
    await pumpLibrary(tester, focusSidebarFirst: false);
    expect(rowTypes(tester), [LibraryGenresSection, LibraryRuntimeSection, LibraryNetworksSection]);

    // A change on the Edit page shows on the Library straight away.
    await SettingsService.instance.reset(SettingsService.libraryRowsHidden);
    await tester.pump();
    expect(rowTypes(tester), [
      LibraryGenresSection,
      LibraryRuntimeSection,
      LibraryCalendarSection,
      LibraryForYouSection,
      LibraryNetworksSection,
    ]);
  });

  testWidgets('focus on a real control, such as the sidebar item that opened the tab, stays put', (tester) async {
    final (:content, :sidebar, :sidebarCalls) = await pumpLibrary(tester, focusSidebarFirst: true);
    expect(sidebar.hasFocus, isTrue);
    expect(content.hasFocus, isFalse);
  });
}

class _NoConnections extends ConnectionRegistry {
  _NoConnections(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}
