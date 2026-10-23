import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/profiles/active_profile_binder.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/providers/companion_remote_provider.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/providers/playback_state_provider.dart';
import 'package:plezy/screens/profile/profile_teardown.dart';
import 'package:plezy/services/credential_vault.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/system_shelf_service.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_stack.dart';

class _Binder implements ActiveProfileBinder {
  _Binder(this.events);
  final List<String> events;

  @override
  Future<void> rebindActive() async => events.add('rebind');

  @override
  Future<void> rebindIfActive(String profileId) async => events.add('rebind:$profileId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Downloads extends ChangeNotifier implements DownloadProvider {
  _Downloads(this.events);
  final List<String> events;
  int deleteFailuresRemaining = 1;

  @override
  Future<void> deleteDownloadsForProfile(String profileId) async {
    events.add('delete-downloads:$profileId');
    if (deleteFailuresRemaining > 0) {
      deleteFailuresRemaining--;
      throw StateError('injected download deletion failure');
    }
  }

  @override
  Future<void> releaseDownloadsForProfileServers(String profileId, Set<String> serverIds) async {
    events.add('release-downloads:$profileId:${serverIds.toList()..sort()}');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Companion extends ChangeNotifier implements CompanionRemoteProvider {
  _Companion(this.events);
  final List<String> events;

  @override
  Future<void> resetForLogout() async {
    events.add('companion-reset');
    throw StateError('stop after first logout mutation');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Playback extends ChangeNotifier implements PlaybackStateProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/profile_teardown_shelf');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    resetSharedPreferencesForTest();
    CredentialVault.resetKeyForTesting();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    SystemShelfService.debugOverrideInstance(null);
  });

  testWidgets('full logout clears shelf before companion, identity, or credential teardown', (tester) async {
    final events = <String>[];
    final harness = await _pumpHarness(tester, events: events, channel: channel);
    addTearDown(harness.dispose);

    await expectLater(logoutAllProfiles(harness.context), throwsStateError);

    expect(events.take(2), ['clear:silo:srv/active', 'companion-reset']);
  });

  testWidgets('cancelling a server sign-out keeps the connection and the session', (tester) async {
    final events = <String>[];
    final harness = await _pumpHarness(tester, events: events, channel: channel);
    addTearDown(harness.dispose);
    final connection = harness.active.connectionFor(harness.active.active!)!;

    final signOut = confirmAndSignOutSiloServer(harness.context, connection: connection);
    await tester.pumpAndSettle();
    expect(find.text('Sign out of srv?'), findsOneWidget);
    Navigator.of(harness.context, rootNavigator: true).pop(false);
    await tester.pumpAndSettle();

    expect(await signOut, isFalse);
    expect(await harness.stack.connections.get(connection.id), isNotNull);
    expect(harness.active.activeId, 'silo:srv/active');
    expect(events, isEmpty);
  });
}

class _Harness {
  _Harness({required this.context, required this.stack, required this.multiServer, required this.manager});

  final BuildContext context;
  final ProfileStack stack;
  final MultiServerProvider multiServer;
  final MultiServerManager manager;

  ActiveProfileProvider get active => stack.active;

  Future<void> dispose() async {
    multiServer.dispose();
    manager.dispose();
    await stack.dispose();
  }
}

Future<_Harness> _pumpHarness(
  WidgetTester tester, {
  required List<String> events,
  required MethodChannel channel,
}) async {
  final stack = await ProfileStack.create();
  final storage = stack.storage;
  await stack.addServer('srv', testHousehold([('active', 'Active')]));
  await storage.setActiveProfileId('silo:srv/active');
  await stack.active.reloadFromStorage();
  final manager = MultiServerManager();
  final multiServer = testMultiServerProvider(manager);
  final shelf = SystemShelfService.forTesting(channel: channel, isSupported: () async => true);
  shelf.beginProfileSession(stack.active.activeId!);
  SystemShelfService.debugOverrideInstance(shelf);
  messengerFor(channel).setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'clear') {
      events.add('clear:${(call.arguments as Map)['ownerId']}');
    }
    return true;
  });

  BuildContext? captured;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storage),
        Provider<AppDatabase>.value(value: stack.db),
        Provider<ConnectionRegistry>.value(value: stack.connections),
        Provider<SiloHouseholdService>.value(value: stack.households),
        ChangeNotifierProvider<ActiveProfileProvider>.value(value: stack.active),
        Provider<ActiveProfileBinder>.value(value: _Binder(events)),
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
        ChangeNotifierProvider<DownloadProvider>.value(value: _Downloads(events)),
        ChangeNotifierProvider<CompanionRemoteProvider>.value(value: _Companion(events)),
        ChangeNotifierProvider<PlaybackStateProvider>.value(value: _Playback()),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return _Harness(context: captured!, stack: stack, multiServer: multiServer, manager: manager);
}

TestDefaultBinaryMessenger messengerFor(MethodChannel channel) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
