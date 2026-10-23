import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/tvos_database_recovery_store.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/main.dart';
import 'package:plezy/screens/auth_screen.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  test('only recoveryRequired bypasses setup; fresh follows ordinary bootstrap path', () {
    expect(shouldBypassSetupForDatabaseRecovery(TvosDatabaseRecoveryOutcome.recoveryRequired), isTrue);
    expect(shouldBypassSetupForDatabaseRecovery(TvosDatabaseRecoveryOutcome.fresh), isFalse);
    expect(shouldBypassSetupForDatabaseRecovery(TvosDatabaseRecoveryOutcome.adoptedExistingDatabase), isFalse);
    expect(shouldBypassSetupForDatabaseRecovery(TvosDatabaseRecoveryOutcome.restored), isFalse);
    expect(shouldBypassSetupForDatabaseRecovery(TvosDatabaseRecoveryOutcome.notApplicable), isFalse);
  });

  testWidgets('recoveryRequired routes localized notice before legacy bootstrap writes', (tester) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString('plex_token', 'LEGACY-TOKEN-MUST-REMAIN');
    await prefs.setString('current_user_uuid', 'legacy-user');
    String? routedMessage;

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: SetupScreen(
            databaseRecoveryOutcome: TvosDatabaseRecoveryOutcome.recoveryRequired,
            debugRecoveryRequiredRouter: (_, message) {
              routedMessage = message;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(routedMessage, t.auth.localDataRecoveryRequired);
    expect(prefs.getString('plex_token'), 'LEGACY-TOKEN-MUST-REMAIN');
    expect(prefs.getString('current_user_uuid'), 'legacy-user');
  });

  testWidgets('AuthScreen renders the recovery notice with the Silo action only', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          home: AuthScreen(initialErrorMessage: t.auth.localDataRecoveryRequired, databaseRecoveryRequired: true),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(t.auth.localDataRecoveryRequired), findsOneWidget);
    _expectSiloOnly();
  });

  testWidgets('fresh AuthScreen offers Silo only, without the recovery notice', (tester) async {
    await tester.pumpWidget(TranslationProvider(child: const MaterialApp(home: AuthScreen())));
    await tester.pump();

    expect(find.text(t.auth.localDataRecoveryRequired), findsNothing);
    _expectSiloOnly();
  });
}

void _expectSiloOnly() {
  expect(find.text(t.silo.connectCard), findsOneWidget);
  expect(find.byType(ElevatedButton), findsOneWidget);
  expect(find.byType(OutlinedButton), findsNothing);
}
