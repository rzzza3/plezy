import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/database/download_operations.dart';
import 'package:plezy/profiles/active_profile_binder.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_activation.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/screens/profile/pin_entry_dialog.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/system_shelf_service.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_stack.dart';

const _server = 'srv';

/// The client scope of the Silo profile [name] on [_server].
String _id(String name) => 'silo:$_server/$name';

Profile _profile(String name, String displayName, int sortOrder) =>
    Profile(serverId: _server, siloProfileId: name, displayName: displayName, sortOrder: sortOrder);

/// The household of [_server], cached as sign-in leaves it.
Future<SiloHouseholdService> _households(ConnectionRegistry connections) async {
  final connection = testSiloConnection(_server);
  final household = testHousehold([('owner', 'Owner'), ('target', 'Target'), ('newer', 'Newer'), ('latest', 'Latest')]);
  final households = SiloHouseholdService(connections: connections, loader: (_) async => household);
  await connections.upsert(connection);
  await households.put(connection, household);
  return households;
}

/// Stands in for the server: a PIN profile asks through the real PIN dialog
/// and is entered with 1234; backing out cancels.
Future<SiloProfileEntryOutcome> _enterWithoutServer(BuildContext context, Profile profile) async {
  if (!profile.hasPin) return SiloProfileEntryOutcome.entered;
  final pin = await pinPromptFor(context, profile.displayName)(null);
  if (pin == null) return SiloProfileEntryOutcome.cancelled;
  return pin == '1234' ? SiloProfileEntryOutcome.entered : SiloProfileEntryOutcome.failed;
}

class _Binder implements ActiveProfileBinder {
  _Binder(this.events);
  final List<String> events;

  @override
  bool lastBindFailureConnectivityOnly = false;

  @override
  void markUserInitiatedActivation(String profileId) => events.add('mark:$profileId');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RollbackBinder implements ActiveProfileBinder {
  _RollbackBinder(this.active, this.events, {this.targetBindingRelease}) : boundClientProfileId = active.activeId {
    active.addListener(_handleActiveChanged);
  }

  final ActiveProfileProvider active;
  final List<String> events;
  final Completer<void> rebindStarted = Completer<void>();
  final Completer<void> allowRebind = Completer<void>();
  final Completer<void> targetBindingStarted = Completer<void>();
  final Completer<void>? targetBindingRelease;
  String? boundClientProfileId;
  @override
  bool lastBindFailureConnectivityOnly = false;
  bool _targetFailed = false;
  final Set<String> _successfullyBoundProfileIds = {};

  @override
  void markUserInitiatedActivation(String profileId) {
    events.add('mark:$profileId');
  }

  void _handleActiveChanged() {
    if (active.activeId == _id('target') && !_targetFailed) {
      _targetFailed = true;
      boundClientProfileId = null;
      SystemShelfService().beginProfileSession(_id('target'));
      active.markBindingStarted();
      targetBindingStarted.complete();
      final release = targetBindingRelease;
      if (release == null) {
        scheduleMicrotask(() => active.markBindingFinished(success: false));
      } else {
        unawaited(
          release.future.then((_) {
            if (active.activeId == _id('target')) {
              active.markBindingFinished(success: false);
            }
          }),
        );
      }
      return;
    }
    final profileId = active.activeId;
    if ((profileId == _id('newer') || profileId == _id('latest')) && _successfullyBoundProfileIds.add(profileId!)) {
      boundClientProfileId = profileId;
      SystemShelfService().beginProfileSession(profileId);
      active.markBindingStarted();
      scheduleMicrotask(() => active.markBindingFinished(success: true));
    }
  }

  @override
  Future<void> rebindActive() async {
    events.add('rebind:${active.activeId}');
    active.markBindingStarted();
    rebindStarted.complete();
    await allowRebind.future;
    boundClientProfileId = active.activeId;
    active.markBindingFinished(success: true);
  }

  @override
  void dispose() {
    active.removeListener(_handleActiveChanged);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ThrowingActiveProfileProvider extends ActiveProfileProvider {
  _ThrowingActiveProfileProvider({
    required super.households,
    required super.connections,
    required super.storage,
    super.activeProfileIdWriter,
  });

  bool throwOnActivation = false;

  @override
  Future<bool> activate(Profile profile) {
    if (throwOnActivation) throw StateError('synthetic activation failure');
    return super.activate(profile);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/profile_activation_shelf');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    resetSharedPreferencesForTest();
    debugSiloProfileEntryOverride = _enterWithoutServer;
  });
  tearDown(() {
    debugSiloProfileEntryOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    SystemShelfService.debugOverrideInstance(null);
  });

  testWidgets('successful different-profile activation clears old owner before identity publication', (tester) async {
    final harness = await _pumpHarness(tester, channel);
    addTearDown(harness.dispose);
    final events = harness.events;
    harness.active.addListener(() => events.add('active:${harness.active.activeId}'));

    final activated = await switchProfileFromUi(harness.context, harness.target);

    expect(activated, isTrue);
    expect(events, ['clear:${_id('owner')}', 'mark:${_id('target')}', 'active:${_id('target')}']);
    expect(SystemShelfService().debugActiveOwner, isNull);
  });

  testWidgets('newer switch overtakes an older switch blocked clearing the same shelf owner', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final ownerClearStarted = Completer<void>();
    final allowOwnerClear = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') {
        final ownerId = (call.arguments as Map)['ownerId'];
        harness.events.add('clear:$ownerId');
        if (ownerId == _id('owner')) {
          ownerClearStarted.complete();
          await allowOwnerClear.future;
        }
      }
      return true;
    });

    final olderSwitch = switchProfileFromUi(harness.context, harness.target);
    await ownerClearStarted.future;

    expect(await switchProfileFromUi(harness.context, harness.newer), isTrue);
    expect(harness.active.activeId, _id('newer'));
    expect(harness.rollbackBinder!.boundClientProfileId, _id('newer'));
    expect(harness.events, contains('mark:${_id('newer')}'));
    expect(harness.events, isNot(contains('mark:${_id('target')}')));

    allowOwnerClear.complete();
    expect(await olderSwitch, isFalse);
    await tester.pump();

    expect(harness.active.activeId, _id('newer'));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('newer'));
    expect(SystemShelfService().debugActiveOwner, _id('newer'));
    expect(harness.events, isNot(contains('rebind:${_id('target')}')));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('selecting current profile and cancelling PIN verification do not clear', (tester) async {
    final harness = await _pumpHarness(tester, channel);
    addTearDown(harness.dispose);

    expect(await switchProfileFromUi(harness.context, harness.active.active!), isTrue);
    expect(harness.events, ['mark:${_id('owner')}']);

    const protected = Profile(serverId: _server, siloProfileId: 'protected', displayName: 'Protected', hasPin: true);
    final attempt = switchProfileFromUi(harness.context, protected);
    await tester.pumpAndSettle();
    Navigator.of(harness.context, rootNavigator: true).pop();
    await tester.pumpAndSettle();

    expect(await attempt, isFalse);
    expect(harness.events.where((event) => event.startsWith('clear:')), isEmpty);
  });

  testWidgets('activation exception restores the previous shelf owner', (tester) async {
    final harness = await _pumpHarness(tester, channel, throwOnTargetActivation: true);
    addTearDown(harness.dispose);

    final activated = await switchProfileFromUi(harness.context, harness.target);

    expect(activated, isFalse);
    expect(harness.active.activeId, _id('owner'));
    expect(SystemShelfService().debugActiveOwner, _id('owner'));
    expect(harness.events, ['clear:${_id('owner')}', 'mark:${_id('target')}']);
  });

  testWidgets('failed target binding explicitly restores prior clients before returning', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    var switchCompleted = false;

    final switchFuture = switchProfileFromUi(harness.context, harness.target).then((result) {
      switchCompleted = true;
      return result;
    });
    await binder.rebindStarted.future;

    expect(harness.active.activeId, _id('owner'));
    expect(binder.boundClientProfileId, isNull);
    expect(switchCompleted, isFalse);

    binder.allowRebind.complete();
    expect(await switchFuture, isFalse);
    expect(binder.boundClientProfileId, _id('owner'));
    expect(harness.active.lastBindingSucceeded, isTrue);
    expect(SystemShelfService().debugActiveOwner, _id('owner'));
  });

  testWidgets('connectivity-only bind failure keeps a downloads-owning profile active offline', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    binder.lastBindFailureConnectivityOnly = true;
    await harness.database.addDownloadOwner(profileId: _id('target'), globalKey: 'srv-1/episode-1');

    final activated = await switchProfileFromUi(harness.context, harness.target);

    expect(activated, isTrue);
    expect(harness.active.activeId, _id('target'));
    expect(SystemShelfService().debugActiveOwner, _id('target'));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('target'));
    expect(binder.rebindStarted.isCompleted, isFalse);
    expect(harness.events, isNot(contains('rebind:${_id('owner')}')));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a switch whose screen is torn down mid-switch still keeps a downloads-owning profile offline', (
    tester,
  ) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true, gateTargetBindingFailure: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    binder.lastBindFailureConnectivityOnly = true;
    await harness.database.addDownloadOwner(profileId: _id('target'), globalKey: 'srv-1/episode-1');

    final switchFuture = switchProfileFromUi(harness.context, harness.target);
    await binder.targetBindingStarted.future;
    // Discover's profile menu: the activation rebuilds the profile-scoped
    // subtree the switch was started from.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(harness.context.mounted, isFalse);
    binder.targetBindingRelease!.complete();

    expect(await switchFuture, isTrue);
    expect(harness.active.activeId, _id('target'));
    expect(binder.rebindStarted.isCompleted, isFalse);
  });

  testWidgets('connectivity-only bind failure without owned downloads still rolls back', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    binder.lastBindFailureConnectivityOnly = true;

    final switchFuture = switchProfileFromUi(harness.context, harness.target);
    await binder.rebindStarted.future;
    binder.allowRebind.complete();

    expect(await switchFuture, isFalse);
    expect(harness.active.activeId, _id('owner'));
    expect(binder.boundClientProfileId, _id('owner'));
    expect(SystemShelfService().debugActiveOwner, _id('owner'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('non-connectivity bind failure rolls back even when the profile owns downloads', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    await harness.database.addDownloadOwner(profileId: _id('target'), globalKey: 'srv-1/episode-1');

    final switchFuture = switchProfileFromUi(harness.context, harness.target);
    await binder.rebindStarted.future;
    binder.allowRebind.complete();

    expect(await switchFuture, isFalse);
    expect(harness.active.activeId, _id('owner'));
    expect(binder.boundClientProfileId, _id('owner'));
    expect(SystemShelfService().debugActiveOwner, _id('owner'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('protected switch rolls back to profile active when its activation is admitted', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true, gateTargetBindingFailure: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    final protectedTarget = harness.target.copyWith(displayName: 'Protected Target', hasPin: true);

    final pendingProtectedSwitch = switchProfileFromUi(harness.context, protectedTarget);
    await tester.pumpAndSettle();
    expect(find.text('Protected Target'), findsOneWidget);
    expect(harness.active.activeId, _id('owner'));

    expect(await switchProfileFromUi(harness.context, harness.newer), isTrue);
    expect(harness.active.activeId, _id('newer'));
    expect(binder.boundClientProfileId, _id('newer'));

    final pinField = find.byType(TextField);
    if (pinField.evaluate().isNotEmpty) {
      await tester.enterText(pinField, '1234');
    } else {
      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
      }
    }
    await tester.pump();
    await binder.targetBindingStarted.future;
    binder.targetBindingRelease!.complete();
    await binder.rebindStarted.future;
    final restoredProfileId = harness.active.activeId;

    binder.allowRebind.complete();
    expect(await pendingProtectedSwitch, isFalse);
    await tester.pump();

    expect(restoredProfileId, _id('newer'));
    expect(harness.active.activeId, _id('newer'));
    expect(binder.boundClientProfileId, _id('newer'));
    expect(SystemShelfService().debugActiveOwner, _id('newer'));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('newer'));
  });

  testWidgets('newer activation supersedes a failed switch while rollback shelf clear is pending', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    final targetClearStarted = Completer<void>();
    final allowTargetClear = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') {
        final ownerId = (call.arguments as Map)['ownerId'];
        harness.events.add('clear:$ownerId');
        if (ownerId == _id('target')) {
          targetClearStarted.complete();
          await allowTargetClear.future;
        }
      }
      return true;
    });

    final failedSwitch = switchProfileFromUi(harness.context, harness.target);
    await targetClearStarted.future;

    expect(await switchProfileFromUi(harness.context, harness.newer), isTrue);
    expect(harness.active.activeId, _id('newer'));
    expect(binder.boundClientProfileId, _id('newer'));

    allowTargetClear.complete();
    expect(await failedSwitch, isFalse);
    expect(harness.active.activeId, _id('newer'));
    expect(binder.boundClientProfileId, _id('newer'));
    expect(SystemShelfService().debugActiveOwner, _id('newer'));
    expect(binder.rebindStarted.isCompleted, isFalse);
    expect(harness.events, isNot(contains('mark:${_id('owner')}')));
    expect(harness.events, isNot(contains('rebind:${_id('owner')}')));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('newer'));
    await tester.pump();
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('rollback waits for successive reserved switches and never rebinds the stale owner', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true, gateTargetBindingFailure: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    final firstTargetClearStarted = Completer<void>();
    final allowFirstTargetClear = Completer<void>();
    final secondTargetClearStarted = Completer<void>();
    final allowSecondTargetClear = Completer<void>();
    var targetClearCount = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'clear') {
        final ownerId = (call.arguments as Map)['ownerId'];
        harness.events.add('clear:$ownerId');
        if (ownerId == _id('target')) {
          targetClearCount++;
          if (targetClearCount == 1) {
            firstTargetClearStarted.complete();
            await allowFirstTargetClear.future;
          } else {
            secondTargetClearStarted.complete();
            await allowSecondTargetClear.future;
          }
        }
      }
      return true;
    });

    final failedSwitch = switchProfileFromUi(harness.context, harness.target);
    await binder.targetBindingStarted.future;
    binder.targetBindingRelease!.complete();
    await firstTargetClearStarted.future;

    // Model the still-authoritative target binder reasserting its shelf marker
    // while the first native clear is pending. The next request reserves C
    // synchronously, enters its profile, and blocks behind that clear before
    // entering the identity queue.
    SystemShelfService().beginProfileSession(_id('target'));
    final middleSwitch = switchProfileFromUi(harness.context, harness.newer);
    final middleReservation = harness.active.identityMutationGeneration;
    // Let its server entry finish so it queues the shelf clear.
    await tester.pump();

    final latestSwitch = switchProfileFromUi(harness.context, harness.latest);
    expect(harness.active.identityMutationGeneration, greaterThan(middleReservation));
    expect(await latestSwitch, isTrue);
    expect(harness.active.activeId, _id('latest'));
    expect(binder.boundClientProfileId, _id('latest'));

    allowFirstTargetClear.complete();
    await secondTargetClearStarted.future;
    expect(await failedSwitch, isFalse);
    expect(harness.active.activeId, _id('latest'));
    expect(harness.events, isNot(contains('mark:${_id('owner')}')));
    expect(harness.events, isNot(contains('rebind:${_id('owner')}')));

    allowSecondTargetClear.complete();
    expect(await middleSwitch, isFalse);
    await tester.pump();

    expect(targetClearCount, 2);
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('latest'));
    expect(SystemShelfService().debugActiveOwner, _id('latest'));
    expect(harness.events, isNot(contains('mark:${_id('newer')}')));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('new activation during a held restore write prevents stale prior-profile publication', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true, gateOwnerRestoreWrite: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    final publishedProfileIds = <String?>[];
    harness.active.addListener(() => publishedProfileIds.add(harness.active.activeId));

    final failedSwitch = switchProfileFromUi(harness.context, harness.target);
    await harness.restoreWriteStarted.future;
    expect(harness.active.activeId, _id('target'));
    final restoreGeneration = harness.active.identityMutationGeneration;

    final newerSwitch = switchProfileFromUi(harness.context, harness.newer);
    await tester.pump();
    expect(harness.active.identityMutationGeneration, greaterThan(restoreGeneration));

    harness.allowRestoreWrite.complete();
    expect(await newerSwitch, isTrue);
    expect(await failedSwitch, isFalse);
    expect(harness.active.activeId, _id('newer'));
    expect(binder.boundClientProfileId, _id('newer'));
    expect(publishedProfileIds, isNot(contains(_id('owner'))));
    expect(harness.events, isNot(contains('mark:${_id('owner')}')));
    expect(harness.events, isNot(contains('rebind:${_id('owner')}')));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('newer'));
    expect(harness.identityWrites, [_id('target'), _id('owner'), _id('target'), _id('newer')]);
  });

  testWidgets('cancelled newer PIN attempt does not suppress pending failed-switch rollback', (tester) async {
    final harness = await _pumpHarness(tester, channel, simulateBindingRollback: true, gateTargetBindingFailure: true);
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;
    final failedSwitch = switchProfileFromUi(harness.context, harness.target);
    await binder.targetBindingStarted.future;
    final failedGeneration = harness.active.identityMutationGeneration;
    const protectedNewer = Profile(
      serverId: _server,
      siloProfileId: 'protected-newer',
      displayName: 'Protected Newer',
      hasPin: true,
    );

    final cancelledSwitch = switchProfileFromUi(harness.context, protectedNewer);
    await tester.pumpAndSettle();
    Navigator.of(harness.context, rootNavigator: true).pop();
    await tester.pumpAndSettle();
    expect(await cancelledSwitch, isFalse);
    expect(harness.active.identityMutationGeneration, failedGeneration);

    binder.targetBindingRelease!.complete();
    await binder.rebindStarted.future;
    binder.allowRebind.complete();
    expect(await failedSwitch, isFalse);
    expect(harness.active.activeId, _id('owner'));
    expect(binder.boundClientProfileId, _id('owner'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('failed queued activation lets superseded restore retry the prior profile', (tester) async {
    final harness = await _pumpHarness(
      tester,
      channel,
      simulateBindingRollback: true,
      gateOwnerRestoreWrite: true,
      failNewerIdentityWrite: true,
    );
    addTearDown(harness.dispose);
    final binder = harness.rollbackBinder!;

    final failedSwitch = switchProfileFromUi(harness.context, harness.target);
    await harness.restoreWriteStarted.future;
    final restoreGeneration = harness.active.identityMutationGeneration;

    final newerSwitch = switchProfileFromUi(harness.context, harness.newer);
    await tester.pump();
    expect(harness.active.identityMutationGeneration, greaterThan(restoreGeneration));

    harness.allowRestoreWrite.complete();
    expect(await newerSwitch, isFalse);
    await binder.rebindStarted.future;
    binder.allowRebind.complete();
    expect(await failedSwitch, isFalse);

    expect(harness.active.activeId, _id('owner'));
    expect(binder.boundClientProfileId, _id('owner'));
    expect(harness.active.committedIdentityGeneration, greaterThan(restoreGeneration));
    expect(harness.events, contains('mark:${_id('owner')}'));
    expect(harness.events, contains('rebind:${_id('owner')}'));
    expect((await StorageService.getInstance()).getActiveProfileId(), _id('owner'));
    expect(harness.identityWrites, [
      _id('target'),
      _id('owner'),
      _id('target'),
      _id('newer'),
      _id('target'),
      _id('owner'),
    ]);
  });

  test('superseded failing profile write cannot overwrite the newer committed profile', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(database);
    final storage = await StorageService.getInstance();
    final households = await _households(connections);
    final targetWriteStarted = Completer<void>();
    final allowTargetWriteToFail = Completer<void>();
    final newerWriteStarted = Completer<void>();
    final identityWrites = <String>[];
    Future<void> writer(String profileId) async {
      identityWrites.add(profileId);
      await storage.setActiveProfileId(profileId);
      if (profileId == _id('target')) {
        targetWriteStarted.complete();
        await allowTargetWriteToFail.future;
        throw StateError('synthetic target persistence failure');
      }
      if (profileId == _id('newer')) newerWriteStarted.complete();
    }

    final active = _ThrowingActiveProfileProvider(
      households: households,
      connections: connections,
      storage: storage,
      activeProfileIdWriter: writer,
    );
    addTearDown(() async {
      active.dispose();
      households.dispose();
      await database.close();
    });
    final owner = _profile('owner', 'Owner', 0);
    final target = _profile('target', 'Target', 1);
    final newer = _profile('newer', 'Newer', 2);
    await storage.setActiveProfileId(owner.id);
    await active.initialize();

    final targetActivation = active.activate(target);
    final targetFailure = expectLater(targetActivation, throwsA(isA<StateError>()));
    await targetWriteStarted.future;
    final newerActivation = active.activate(newer);

    expect(newerWriteStarted.isCompleted, isFalse);
    expect(storage.getActiveProfileId(), target.id);
    expect(identityWrites, [_id('target')]);

    allowTargetWriteToFail.complete();
    await targetFailure;
    expect(await newerActivation, isTrue);
    expect(newerWriteStarted.isCompleted, isTrue);
    expect(active.activeId, newer.id);
    expect(storage.getActiveProfileId(), newer.id);
    expect(identityWrites, [_id('target'), _id('owner'), _id('newer')]);
  });
}

class _Harness {
  _Harness({
    required this.context,
    required this.active,
    required this.target,
    required this.newer,
    required this.events,
    required this.latest,
    required this.households,
    required this.rollbackBinder,
    required this.database,
    required this.restoreWriteStarted,
    required this.allowRestoreWrite,
    required this.identityWrites,
  });

  final BuildContext context;
  final ActiveProfileProvider active;
  final Profile target;
  final Profile newer;
  final Profile latest;
  final List<String> events;
  final SiloHouseholdService households;
  final _RollbackBinder? rollbackBinder;
  final AppDatabase database;
  final Completer<void> restoreWriteStarted;
  final Completer<void> allowRestoreWrite;
  final List<String> identityWrites;

  Future<void> dispose() async {
    rollbackBinder?.dispose();
    active.dispose();
    households.dispose();
    await database.close();
  }
}

Future<_Harness> _pumpHarness(
  WidgetTester tester,
  MethodChannel channel, {
  bool throwOnTargetActivation = false,
  bool simulateBindingRollback = false,
  bool gateTargetBindingFailure = false,
  bool gateOwnerRestoreWrite = false,
  bool failNewerIdentityWrite = false,
}) async {
  final events = <String>[];
  final identityWrites = <String>[];
  final database = AppDatabase.forTesting(NativeDatabase.memory());
  final connections = ConnectionRegistry(database);
  final storage = await StorageService.getInstance();
  final households = await _households(connections);
  final restoreWriteStarted = Completer<void>();
  final allowRestoreWrite = Completer<void>();
  Future<void> activeProfileIdWriter(String profileId) async {
    identityWrites.add(profileId);
    await storage.setActiveProfileId(profileId);
    if (gateOwnerRestoreWrite && profileId == _id('owner')) {
      if (!restoreWriteStarted.isCompleted) restoreWriteStarted.complete();
      await allowRestoreWrite.future;
    }
    if (failNewerIdentityWrite && profileId == _id('newer')) {
      throw StateError('synthetic newer identity write failure');
    }
  }

  final active = _ThrowingActiveProfileProvider(
    households: households,
    connections: connections,
    storage: storage,
    activeProfileIdWriter: gateOwnerRestoreWrite || failNewerIdentityWrite ? activeProfileIdWriter : null,
  );
  final owner = _profile('owner', 'Owner', 0);
  final target = _profile('target', 'Target', 1);
  final newer = _profile('newer', 'Newer', 2);
  final latest = _profile('latest', 'Latest', 3);
  await storage.setActiveProfileId(owner.id);
  await active.initialize();
  active.throwOnActivation = throwOnTargetActivation;
  final targetBindingRelease = gateTargetBindingFailure ? Completer<void>() : null;
  final rollbackBinder = simulateBindingRollback
      ? _RollbackBinder(active, events, targetBindingRelease: targetBindingRelease)
      : null;
  final ActiveProfileBinder binder = rollbackBinder ?? _Binder(events);

  final shelf = SystemShelfService.forTesting(channel: channel, isSupported: () async => true);
  shelf.beginProfileSession(owner.id);
  SystemShelfService.debugOverrideInstance(shelf);
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'clear') events.add('clear:${(call.arguments as Map)['ownerId']}');
    return true;
  });

  BuildContext? captured;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ActiveProfileProvider>.value(value: active),
        Provider<ActiveProfileBinder>.value(value: binder),
        Provider<AppDatabase>.value(value: database),
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
  return _Harness(
    context: captured!,
    active: active,
    target: target,
    newer: newer,
    latest: latest,
    rollbackBinder: rollbackBinder,
    events: events,
    households: households,
    restoreWriteStarted: restoreWriteStarted,
    allowRestoreWrite: allowRestoreWrite,
    identityWrites: identityWrites,
    database: database,
  );
}
