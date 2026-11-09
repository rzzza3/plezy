import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/widgets/auth_error_banner.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';

void main() {
  late MultiServerManager manager;
  late MultiServerProvider provider;

  setUp(() {
    manager = MultiServerManager();
    provider = testMultiServerProvider(manager);
  });

  tearDown(() {
    provider.dispose();
    manager.dispose();
  });

  Future<void> pumpBanner(WidgetTester tester) => tester.pumpWidget(
    ChangeNotifierProvider<MultiServerProvider>.value(
      value: provider,
      child: const MaterialApp(home: Scaffold(body: AuthErrorBanner())),
    ),
  );

  testWidgets('a server refusing the account (403) is explained without a sign-in that cannot help', (tester) async {
    manager.debugMarkAccessDeniedForTesting(ServerId('denied'));

    await pumpBanner(tester);

    expect(find.text(t.connections.accessDeniedOne(name: 'denied')), findsOneWidget);
    expect(find.textContaining(t.connections.sessionExpiredOne(name: 'denied')), findsNothing);
  });

  testWidgets('a rejected token is left to the automatic sign-out, not the banner', (tester) async {
    manager.debugMarkAuthErrorForTesting(ServerId('expired'));

    await pumpBanner(tester);

    expect(find.descendant(of: find.byType(AuthErrorBanner), matching: find.byType(Material)), findsNothing);
    expect(find.textContaining(t.connections.sessionExpiredOne(name: 'expired')), findsNothing);
  });
}
