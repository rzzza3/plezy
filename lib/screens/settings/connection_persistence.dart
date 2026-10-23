import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/silo_household_service.dart';
import '../../services/storage_service.dart';
import '../../silo/silo_profiles.dart';
import '../../utils/app_logger.dart';

/// Commit a finished Silo sign-in: store [connection], cache [household],
/// and make [entered] — the profile the session just entered — the active
/// profile.
///
/// All collaborators are captured before the first await, so a route unmount
/// cannot interrupt the command between steps. When activation rejects or
/// throws, the prior connection row and active-profile marker are restored
/// before the original error is rethrown. The helper itself does not
/// navigate.
Future<void> persistSiloSignIn({
  required BuildContext context,
  required SiloConnection connection,
  required SiloHousehold household,
  required SiloProfile entered,
}) async {
  final connections = context.read<ConnectionRegistry>();
  final households = context.read<SiloHouseholdService>();
  final activeProfiles = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();
  final storage = context.read<StorageService>();

  final priorActiveProfileId = storage.getActiveProfileId();
  final priorConnection = await connections.get(connection.id);

  await connections.upsert(connection);
  await households.put(connection, household);
  await activeProfiles.reloadFromStorage();

  final index = household.profiles.indexWhere((profile) => profile.id == entered.id);
  final profile = Profile.fromSilo(serverId: connection.serverId, profile: entered, sortOrder: index < 0 ? 0 : index);
  try {
    binder.markUserInitiatedActivation(profile.id);
    final activated = await activeProfiles.activate(profile);
    if (!activated) throw StateError('The signed-in profile could not be activated');
    if (priorConnection != null) await binder.rebindIfActive(profile.id);
  } catch (error, stackTrace) {
    await _restore(
      connections: connections,
      activeProfiles: activeProfiles,
      storage: storage,
      attempted: connection,
      priorConnection: priorConnection,
      priorActiveProfileId: priorActiveProfileId,
    );
    Error.throwWithStackTrace(error, stackTrace);
  }
}

Future<void> _restore({
  required ConnectionRegistry connections,
  required ActiveProfileProvider activeProfiles,
  required StorageService storage,
  required SiloConnection attempted,
  required Connection? priorConnection,
  required String? priorActiveProfileId,
}) async {
  try {
    if (priorConnection == null) {
      await connections.remove(attempted.id);
    } else {
      await connections.upsert(priorConnection);
    }
  } catch (error, stackTrace) {
    appLogger.e('Sign-in connection compensation failed', error: error, stackTrace: stackTrace);
  }

  try {
    if (priorActiveProfileId == null) {
      await storage.clearActiveProfileId();
    } else {
      await storage.setActiveProfileId(priorActiveProfileId);
    }
  } catch (error, stackTrace) {
    appLogger.e('Sign-in active marker compensation failed', error: error, stackTrace: stackTrace);
  }

  try {
    await activeProfiles.reloadFromStorage();
  } catch (error, stackTrace) {
    appLogger.e('Sign-in active profile reload failed', error: error, stackTrace: stackTrace);
  }
}
