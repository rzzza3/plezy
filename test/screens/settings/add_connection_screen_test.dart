import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/screens/auth/silo_server_screen.dart';
import 'package:plezy/screens/settings/add_connection_screen.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/backend_badge.dart';

/// The "Add connection" picker is the only route to a new server, so a backend
/// missing from this list is unreachable no matter how complete its client is.
void main() {
  Widget app(Widget home) => MaterialApp(
    theme: monoTheme(dark: true),
    home: InputModeTracker(child: home),
  );

  testWidgets('offers Silo only', (tester) async {
    await tester.pumpWidget(app(const AddConnectionScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Connect to Silo'), findsOneWidget);
    expect(find.byType(FocusableWrapper), findsOneWidget);

    final badges = tester.widgetList<BackendBadge>(find.byType(BackendBadge)).map((b) => b.backend).toList();
    expect(badges, [MediaBackend.silo]);
  });

  testWidgets('the Silo card opens the server address screen', (tester) async {
    await tester.pumpWidget(app(const AddConnectionScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Connect to Silo'));
    await tester.pumpAndSettle();

    expect(find.byType(SiloServerScreen), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
  });
}
