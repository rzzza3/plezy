import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/focusable_wrapper.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/profile_avatar.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/screens/profile/profile_switch_screen.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/silo/silo_profiles.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_stack.dart';

const _owner = SiloProfile(id: 'owner', name: 'Owner', isPrimary: true);
const _kids = SiloProfile(id: 'kids', name: 'Kids');
const _account = SiloAccount(id: 'acct-1', username: 'alice', role: 'admin');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('D-pad can focus profile actions and open the tile menu', (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [_owner]),
      },
    );

    expect(find.text('Owner'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProfileTile:silo:srv/owner');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProfileActions:silo:srv/owner');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text(t.profiles.signOut), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('orders profiles by recent usage from storage', (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [_owner, _kids]),
      },
      lastUsedAt: {'silo:srv/kids': DateTime(2026, 1, 3)},
    );

    expect(tester.getTopLeft(find.text('Kids')).dy, lessThan(tester.getTopLeft(find.text('Owner')).dy));
  });

  testWidgets("passes each profile's avatar, resolved against its server, to its tile", (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [
          SiloProfile(id: 'owner', name: 'Owner', avatarUrl: '/api/v2/profiles/owner/avatar'),
          _kids,
        ]),
      },
    );

    ProfileAvatar avatarOf(String id) => tester.widget<ProfileAvatar>(
      find.byWidgetPredicate((widget) => widget is ProfileAvatar && widget.profile?.id == id),
    );
    expect(avatarOf('silo:srv/owner').avatarUrl, 'https://srv.example/api/v2/profiles/owner/avatar');
    expect(avatarOf('silo:srv/kids').avatarUrl, isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('names the server each profile belongs to', (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'den': const SiloHousehold(_account, [_owner]),
        'cabin': const SiloHousehold(_account, [_kids]),
      },
      serverNames: {'den': 'Den', 'cabin': 'Cabin'},
    );

    expect(find.descendant(of: _tileFor('Owner'), matching: find.text('Den')), findsOneWidget);
    expect(find.descendant(of: _tileFor('Kids'), matching: find.text('Cabin')), findsOneWidget);
  });

  testWidgets('paints the recency order on the first frame that shows profiles', (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [_owner, _kids]),
      },
      lastUsedAt: {'silo:srv/kids': DateTime(2026, 1, 3)},
      settle: false,
    );

    // Frame-by-frame, not pumpAndSettle: the regression was an intermediate
    // order that only existed for one frame, which a settled assertion cannot
    // see (#1792).
    final paintedOrders = <String>[];
    for (var frame = 0; frame < 6; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      final order = _visibleProfileNames(tester);
      if (order.isNotEmpty) paintedOrders.add(order.join(','));
    }

    expect(paintedOrders, isNotEmpty, reason: 'the picker never painted a profile');
    expect(paintedOrders.toSet(), {'Kids,Owner'}, reason: 'the recency sort must not arrive a frame late');
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ProfileTile:silo:srv/kids');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('keeps the focused tile highlighted when the list re-sorts after first paint', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    PlatformDetector.debugSetIsDesktopOSOverride(false);
    addTearDown(() {
      TvDetectionService.debugSetAppleTVOverride(null);
      PlatformDetector.debugSetIsDesktopOSOverride(null);
    });

    final picker = await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [_owner, _kids]),
      },
      withInputMode: true,
    );

    expect(_visibleProfileNames(tester), ['Owner', 'Kids']);
    final focused = FocusManager.instance.primaryFocus;
    expect(focused?.debugLabel, 'ProfileTile:silo:srv/owner');
    expect(_tileIsHighlighted(tester, 'Owner'), isTrue, reason: 'the focused tile starts highlighted');

    // A refreshed household can re-sort the list after first paint. The tile
    // must move with its focus node instead of the node being rebound to
    // whatever profile now occupies its index.
    await tester.runAsync(
      () => picker.households.put(testSiloConnection('srv'), const SiloHousehold(_account, [_kids, _owner])),
    );
    await tester.pumpAndSettle();

    expect(_visibleProfileNames(tester), ['Kids', 'Owner'], reason: 'the household should have re-sorted the list');
    expect(FocusManager.instance.primaryFocus, same(focused), reason: 'the reorder must not move focus off the tile');
    expect(_tileIsHighlighted(tester, 'Owner'), isTrue, reason: 'the focused tile must still draw focus chrome');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Sign out on a tile asks before signing out of its server', (tester) async {
    await _pumpPicker(
      tester,
      households: {
        'srv': const SiloHousehold(_account, [_owner]),
      },
      serverNames: {'srv': 'Den'},
    );

    await _openTileMenu(tester, 'Owner');
    await tester.tap(find.text(t.profiles.signOut));
    await tester.pumpAndSettle();

    expect(find.text(t.profiles.signOutServerTitle(serverName: 'Den')), findsOneWidget);
    await tester.tap(find.text(t.common.cancel));
    await tester.pumpAndSettle();
    expect(find.text('Owner'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _Picker {
  _Picker(this.connections, this.households, this.active);

  final ConnectionRegistry connections;
  final SiloHouseholdService households;
  final ActiveProfileProvider active;
}

/// Boots the picker over the signed-in servers in [households] (server id →
/// household), the way boot leaves it: households cached, provider
/// initialized.
Future<_Picker> _pumpPicker(
  WidgetTester tester, {
  required Map<String, SiloHousehold> households,
  Map<String, String> serverNames = const {},
  Map<String, DateTime> lastUsedAt = const {},
  bool settle = true,
  bool withInputMode = false,
}) async {
  final stack = (await tester.runAsync(() async {
    final stack = await ProfileStack.create();
    for (final entry in lastUsedAt.entries) {
      await stack.storage.markProfileUsed(entry.key, entry.value);
    }
    for (final entry in households.entries) {
      await stack.addServer(entry.key, entry.value, serverName: serverNames[entry.key]);
    }
    return stack;
  }))!;
  addTearDown(() => tester.runAsync(stack.dispose));

  Widget app = TranslationProvider(
    child: MultiProvider(
      providers: [
        Provider<StorageService>.value(value: stack.storage),
        Provider<AppDatabase>.value(value: stack.db),
        Provider<ConnectionRegistry>.value(value: stack.connections),
        Provider<SiloHouseholdService>.value(value: stack.households),
        ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
      ],
      child: MaterialApp(theme: monoTheme(dark: true), home: const ProfileSwitchScreen()),
    ),
  );
  if (withInputMode) app = InputModeTracker(child: app);
  await tester.pumpWidget(app);
  if (settle) await tester.pumpAndSettle();
  return _Picker(stack.connections, stack.households, stack.active);
}

Finder _tileFor(String displayName) {
  return find.ancestor(of: find.text(displayName), matching: find.byType(FocusableWrapper));
}

/// Opens the actions menu on the tile named [name] via its trailing button.
Future<void> _openTileMenu(WidgetTester tester, String name) async {
  await tester.tap(find.descendant(of: _tileFor(name), matching: find.byTooltip(t.profiles.manage)));
  await tester.pumpAndSettle();
}

/// Tile labels in painted order. Only the two names the reorder tests seed are
/// considered, so surrounding chrome text cannot pollute the sequence.
List<String> _visibleProfileNames(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data)
      .where((label) => label == 'Owner' || label == 'Kids')
      .cast<String>()
      .toList();
}

/// Whether the tile showing [name] draws its focus border.
///
/// [FocusableWrapper] paints an opaque border only while it believes it holds
/// focus, so this catches the state where primary focus is correct but the
/// wrapper's chrome was reset by a rebuilt element.
bool _tileIsHighlighted(WidgetTester tester, String name) {
  final wrapper = find.ancestor(of: find.text(name), matching: find.byType(FocusableWrapper));
  final containers = tester.widgetList<AnimatedContainer>(
    find.descendant(of: wrapper, matching: find.byType(AnimatedContainer)),
  );
  return containers.any((container) {
    final decoration = container.decoration as BoxDecoration?;
    final border = decoration?.border?.top;
    final fill = decoration?.color;
    return (border != null && border.style != BorderStyle.none && border.color.a > 0) || (fill != null && fill.a > 0);
  });
}
