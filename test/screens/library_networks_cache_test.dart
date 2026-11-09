import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/silo_api_cache.dart';

import '../test_helpers/prefs.dart';
import 'library_networks_fixtures.dart';

// Its own file: the API cache, once installed, stays for the isolate.
void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('a later visit shows cached matches without reading the library', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    SiloApiCache.initialize(db);

    await pumpNetworksSection(tester);
    expect(find.text('Title 2130'), findsWidgets);
    // Let the unawaited cache writes land.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpWidget(const SizedBox());

    final (silo, fake) = (await tester.runAsync(() => networksSilo(libraryFails: true)))!;
    await pumpNetworksSection(tester, silo: silo);
    // The database answers in real time; let each read land and rebuild.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Netflix'), findsOneWidget);
    expect(find.bySemanticsLabel('HBO'), findsOneWidget);
    expect(find.text('Title 2130'), findsWidgets);
    expect(fake.requests.where((request) => request.url.path.startsWith('/api/v2/catalog')), isEmpty);
  });
}
