import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/dpad_navigator.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/silo_api_cache.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/library_management_sheet.dart';
import 'package:plezy/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';

import '../test_helpers/prefs.dart';

const _qualifiedLibrary = MediaLibrary(
  id: 'shared-section',
  backend: MediaBackend.plex,
  title: 'Movies',
  kind: MediaKind.movie,
  serverId: 'server-a',
);

Future<({int Function() selects, int Function() backs, LibrariesProvider libraries})> _pumpLibraryManagementLauncher(
  WidgetTester tester, {
  MediaLibrary library = _qualifiedLibrary,
  List<MediaLibrary>? libraries,
  MultiServerProvider? multiServerProvider,
}) async {
  final librariesProvider = LibrariesProvider();
  await librariesProvider.updateLibraryOrder(libraries ?? [library]);
  addTearDown(librariesProvider.dispose);

  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  await hiddenLibrariesProvider.ensureInitialized();
  addTearDown(hiddenLibrariesProvider.dispose);

  final fallbackManager = multiServerProvider == null ? MultiServerManager() : null;
  final effectiveMultiServerProvider = multiServerProvider ?? testMultiServerProvider(fallbackManager!);
  if (fallbackManager != null) {
    addTearDown(() {
      effectiveMultiServerProvider.dispose();
      fallbackManager.dispose();
    });
  }

  var underlyingSelects = 0;
  var underlyingBacks = 0;

  await tester.pumpWidget(
    TranslationProvider(
      child: InputModeTracker(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<MultiServerProvider>.value(value: effectiveMultiServerProvider),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent && event.logicalKey.isSelectKey) underlyingSelects++;
                if (event is KeyDownEvent && event.logicalKey.isBackKey) underlyingBacks++;
                return KeyEventResult.ignored;
              },
              child: OverlaySheetHost(
                child: Scaffold(
                  body: Center(
                    child: Builder(
                      builder: (context) => ElevatedButton(
                        autofocus: true,
                        onPressed: () => showLibraryManagementSheet(context),
                        child: const Text('Open library management'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (selects: () => underlyingSelects, backs: () => underlyingBacks, libraries: librariesProvider);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase database;

  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.setForceTVSync(false);
    PlatformDetector.debugSetIsDesktopOSOverride(false);
    database = AppDatabase.forTesting(NativeDatabase.memory());
    SiloApiCache.initialize(database);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDetectionService.setForceTVSync(false);
    PlatformDetector.debugSetIsDesktopOSOverride(null);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
  });
  tearDown(() => database.close());

  testWidgets('the D-pad cursor stays on screen while walking a long library list', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    // Shield-class TV output: 1080p at a 2.0 ratio.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpLibraryManagementLauncher(
      tester,
      libraries: [
        for (var i = 0; i < 60; i++)
          MediaLibrary(
            id: 'section-$i',
            backend: MediaBackend.plex,
            title: 'Library $i',
            kind: MediaKind.movie,
            serverId: 'server-a',
          ),
      ],
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // One server means no server subtitle, so rows are shorter than the
    // two-line height the reveal arithmetic used to assume.
    final firstRow = tester.getRect(find.byType(ListTile).at(0));
    final rowPitch = tester.getRect(find.byType(ListTile).at(1)).top - firstRow.top;
    expect(rowPitch, lessThan(72.0));

    final viewport = tester.getRect(find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);

    for (var index = 1; index <= 20; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final row = find.text('Library $index');
      expect(row, findsOneWidget, reason: 'focused row $index scrolled out of the built range');
      final rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(viewport.top), reason: 'focused row $index sits above the viewport');
      expect(rect.bottom, lessThanOrEqualTo(viewport.bottom), reason: 'focused row $index sits below the viewport');
    }
  });

  test('reconcileLibraryOrder keeps the sheet order over the current libraries', () {
    MediaLibrary library(String id, {String title = ''}) =>
        MediaLibrary(id: id, backend: MediaBackend.plex, title: title, kind: MediaKind.movie, serverId: 'server-a');

    final reconciled = reconcileLibraryOrder(
      [library('b'), library('gone'), library('a')],
      [library('a', title: 'fresh'), library('b'), library('new')],
    );

    expect(reconciled.map((l) => l.id), ['b', 'a', 'new']);
    expect(reconciled[1].title, 'fresh');
  });

  testWidgets('a reorder after libraries load mid-sheet keeps the new libraries', (tester) async {
    MediaLibrary library(String id) => MediaLibrary(
      id: id,
      backend: MediaBackend.plex,
      title: 'Library $id',
      kind: MediaKind.movie,
      serverId: 'server-a',
    );

    final launcher = await _pumpLibraryManagementLauncher(tester, libraries: [library('a'), library('b')]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    // Another server's libraries finish loading while the sheet is open.
    await launcher.libraries.updateLibraryOrder([library('a'), library('b'), library('c')]);
    await tester.pumpAndSettle();
    expect(find.text('Library c'), findsOneWidget);

    // Move the first row down one place and confirm.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(launcher.libraries.libraries.map((l) => l.id), ['b', 'a', 'c']);
  });
}
