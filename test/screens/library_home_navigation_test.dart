import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/library_calendar_section.dart';
import 'package:plezy/screens/library_runtime_section.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/silo_client.dart';

import '../silo/fake_silo.dart';
import '../test_helpers/prefs.dart';
import 'library_networks_fixtures.dart';

/// D-pad moves into and out of the Library tab's calendar and runtime rows
/// while they load, and before a Silo server is online.
void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  /// A Silo server that holds every answer until [answer] completes, so the
  /// sections stay loading.
  late Completer<http.Response> answer;
  Future<SiloClient> silentSilo(WidgetTester tester) async {
    answer = Completer<http.Response>();
    final fake = FakeSilo((_) => answer.future);
    final (session, _) = (await tester.runAsync(signedInSession))!;
    return SiloClient(
      connection: SiloConnection(
        origin: siloTestOrigin.toString(),
        serverId: 'server-1',
        serverName: 'Silo',
        username: 'alice',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
      profileId: 'p-1',
      http: siloHttpFor(fake, session),
    );
  }

  ({List<String> moves, void Function() up, void Function() down}) recorder() {
    final moves = <String>[];
    return (moves: moves, up: () => moves.add('up'), down: () => moves.add('down'));
  }

  group('before a server is online', () {
    testWidgets('the calendar passes focus on in the direction it came', (tester) async {
      final nav = recorder();
      await pumpNetworksSection(
        tester,
        offline: true,
        section: (_) =>
            LibraryCalendarSection(onNavigateUp: nav.up, onNavigateDown: nav.down, onNavigateToSidebar: () {}),
      );
      final section = tester.state<LibraryCalendarSectionState>(find.byType(LibraryCalendarSection));

      section.requestFocus();
      expect(nav.moves, ['down']);
      section.requestFocusFromBelow();
      expect(nav.moves, ['down', 'up']);
    });

    testWidgets('the runtime row passes focus on in the direction it came', (tester) async {
      final nav = recorder();
      await pumpNetworksSection(
        tester,
        offline: true,
        section: (_) =>
            LibraryRuntimeSection(onNavigateUp: nav.up, onNavigateDown: nav.down, onNavigateToSidebar: () {}),
      );
      final section = tester.state<LibraryRuntimeSectionState>(find.byType(LibraryRuntimeSection));

      section.requestFocus();
      expect(nav.moves, ['down']);
      section.requestFocusFromBelow();
      expect(nav.moves, ['down', 'up']);
    });
  });

  group('while the row loads', () {
    testWidgets('DOWN from the calendar strip stays put instead of skipping the episodes', (tester) async {
      final nav = recorder();
      await pumpNetworksSection(
        tester,
        silo: await silentSilo(tester),
        settle: false,
        section: (_) =>
            LibraryCalendarSection(onNavigateUp: nav.up, onNavigateDown: nav.down, onNavigateToSidebar: () {}),
      );
      await tester.pump();
      final section = tester.state<LibraryCalendarSectionState>(find.byType(LibraryCalendarSection));
      section.requestFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(nav.moves, isEmpty);
      expect(FocusManager.instance.primaryFocus, same(focused));

      // Let the held reads finish so no request timer outlives the test.
      answer.complete(jsonResponse({}, 500));
      await tester.pumpAndSettle();
    });

    testWidgets('DOWN from the runtime strip stays put instead of skipping the movies', (tester) async {
      final nav = recorder();
      await pumpNetworksSection(
        tester,
        silo: await silentSilo(tester),
        settle: false,
        section: (_) =>
            LibraryRuntimeSection(onNavigateUp: nav.up, onNavigateDown: nav.down, onNavigateToSidebar: () {}),
      );
      await tester.pump();
      final section = tester.state<LibraryRuntimeSectionState>(find.byType(LibraryRuntimeSection));
      section.requestFocus();
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(nav.moves, isEmpty);
      expect(FocusManager.instance.primaryFocus, same(focused));

      // Let the held reads finish so no request timer outlives the test.
      answer.complete(jsonResponse({}, 500));
      await tester.pumpAndSettle();
    });
  });
}
