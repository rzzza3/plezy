import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/profiles/profile.dart';
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

  Profile profile(String id) =>
      Profile.local(id: id, displayName: id, sortOrder: 0, createdAt: DateTime.fromMillisecondsSinceEpoch(0));

  testWidgets('offers Silo only', (tester) async {
    await tester.pumpWidget(app(const AddConnectionScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Connect to Silo'), findsOneWidget);
    expect(find.text('Sign in with Plex'), findsNothing);
    expect(find.text('Connect to Jellyfin'), findsNothing);
    expect(find.text('Connect to Emby'), findsNothing);
    expect(find.byType(FocusableWrapper), findsOneWidget);

    final badges = tester.widgetList<BackendBadge>(find.byType(BackendBadge)).map((b) => b.backend).toList();
    expect(badges, [MediaBackend.silo]);
  });

  testWidgets('a scoped picker offers Silo and borrowing, and no other backend', (tester) async {
    await tester.pumpWidget(app(AddConnectionScreen(targetProfile: profile('Living Room'))));
    await tester.pumpAndSettle();

    expect(find.text('Connect to Silo'), findsOneWidget);
    expect(find.text('Borrow from another profile'), findsOneWidget);
    expect(find.text('Sign in with Plex'), findsNothing);
    expect(find.text('Connect to Jellyfin'), findsNothing);
    expect(find.text('Connect to Emby'), findsNothing);
    final badges = tester.widgetList<BackendBadge>(find.byType(BackendBadge)).map((b) => b.backend).toList();
    expect(badges, [MediaBackend.silo]);
  });

  testWidgets('the Silo card opens the server address screen for the target profile', (tester) async {
    final target = profile('Living Room');
    await tester.pumpWidget(app(AddConnectionScreen(targetProfile: target)));
    await tester.pumpAndSettle();

    expect(find.text('Add a Silo server to Living Room'), findsOneWidget);
    await tester.tap(find.text('Connect to Silo'));
    await tester.pumpAndSettle();

    expect(tester.widget<SiloServerScreen>(find.byType(SiloServerScreen)).targetProfile?.id, target.id);
    expect(find.text('Server address'), findsOneWidget);
  });

  testWidgets('the D-pad reaches both scoped cards', (tester) async {
    await tester.pumpWidget(app(AddConnectionScreen(targetProfile: profile('Living Room'))));
    await tester.pumpAndSettle();

    // The cards share a debugLabel, so track focus-node identity instead.
    final visited = <FocusNode>{};
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final focused = FocusManager.instance.primaryFocus;
      if (focused != null) visited.add(focused);
    }

    expect(find.byType(FocusableWrapper), findsNWidgets(2));
    expect(visited.length, greaterThanOrEqualTo(2), reason: 'D-pad did not reach every card');
  });
}
