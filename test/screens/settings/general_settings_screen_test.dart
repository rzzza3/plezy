import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/screens/settings/general_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  Future<({AppDatabase database, SiloHouseholdService households, ActiveProfileProvider activeProfile})>
  pumpGeneralScreen(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(database);
    final serverHome = SiloHouseholdService(connections: connections, loader: (_) async => null);
    // Never initialized: zero profiles, so hasMultipleProfiles stays false.
    final activeProfile = ActiveProfileProvider(households: serverHome, connections: connections);

    await tester.pumpWidget(
      ChangeNotifierProvider<ActiveProfileProvider>.value(
        value: activeProfile,
        child: MaterialApp(theme: monoTheme(dark: true), home: const GeneralSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    return (database: database, households: serverHome, activeProfile: activeProfile);
  }

  Future<void> disposeHarness(
    WidgetTester tester,
    ({AppDatabase database, SiloHouseholdService households, ActiveProfileProvider activeProfile}) harness,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    harness.activeProfile.dispose();
    harness.households.dispose();
    await harness.database.close();
  }

  testWidgets('shows language and startup tiles, hides the profile prompt for a single profile', (tester) async {
    final harness = await pumpGeneralScreen(tester);

    expect(find.text(t.settings.language), findsOneWidget);
    expect(find.text(t.settings.startupSection), findsOneWidget);
    // Only meaningful with several profiles; a lone profile has nothing to pick.
    expect(find.text(t.settings.requireProfileSelectionOnOpen), findsNothing);
    // The test host is a desktop OS, so the window group applies.
    expect(find.text(t.settings.startInFullscreen), findsOneWidget);

    await disposeHarness(tester, harness);
  });

  testWidgets('a fresh install starts on Library and can pick it back', (tester) async {
    final harness = await pumpGeneralScreen(tester);
    final settings = SettingsService.instance;
    final libraryLabel = allNavigationTabs.firstWhere((tab) => tab.id == NavigationTabId.library).getLabel();

    expect(settings.read(SettingsService.startupSection), NavigationTabId.library);
    expect(find.text(libraryLabel), findsOneWidget, reason: 'the tile subtitle names the default');

    await tester.tap(find.text(t.settings.startupSection));
    await tester.pumpAndSettle();
    final homeLabel = allNavigationTabs.firstWhere((tab) => tab.id == NavigationTabId.discover).getLabel();
    await tester.tap(find.text(homeLabel).last);
    await tester.pumpAndSettle();
    expect(settings.read(SettingsService.startupSection), NavigationTabId.discover);

    await tester.tap(find.text(t.settings.startupSection));
    await tester.pumpAndSettle();
    await tester.tap(find.text(libraryLabel).last);
    await tester.pumpAndSettle();
    expect(settings.prefs.getString(SettingsService.startupSection.key), 'library');

    await disposeHarness(tester, harness);
  });

  testWidgets('changes the persisted startup section', (tester) async {
    final harness = await pumpGeneralScreen(tester);

    await tester.tap(find.text(t.settings.startupSection));
    await tester.pumpAndSettle();
    final librariesLabel = allNavigationTabs.firstWhere((tab) => tab.id == NavigationTabId.libraries).getLabel();
    await tester.tap(find.text(librariesLabel).last);
    await tester.pumpAndSettle();

    final settings = SettingsService.instance;
    expect(settings.read(SettingsService.startupSection), NavigationTabId.libraries);
    expect(settings.prefs.getString(SettingsService.startupSection.key), 'libraries');

    await disposeHarness(tester, harness);
  });
}
