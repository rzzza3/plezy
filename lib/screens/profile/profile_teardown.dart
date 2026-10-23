import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../database/app_database.dart';
import '../../database/download_collection_operations.dart';
import '../../database/download_operations.dart';
import '../../i18n/strings.g.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../media/ids.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_activation.dart';
import '../../profiles/silo_household_service.dart';
import '../../providers/companion_remote_provider.dart';
import '../../providers/download_provider.dart';
import '../../providers/discover_provider.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../providers/playback_state_provider.dart';
import '../../services/api_cache.dart';
import '../../services/multi_server_manager.dart';
import '../../services/silo_client.dart';
import '../../services/storage_service.dart';
import '../../services/system_shelf_service.dart';
import '../../silo/silo_app.dart';
import '../../utils/app_logger.dart';
import '../../utils/dialogs.dart';
import '../../utils/snackbar_helper.dart';
import '../auth_screen.dart';

/// The collaborators every teardown flow needs, snapshotted from [context]
/// BEFORE the first await so no flow touches `context.read` mid-teardown.
class SessionTeardownScope {
  final ActiveProfileProvider active;
  final ActiveProfileBinder binder;
  final SiloHouseholdService households;
  final ConnectionRegistry connections;
  final MultiServerProvider multiServer;
  final HiddenLibrariesProvider? hiddenLibraries;
  final DiscoverProvider? discover;
  final DownloadProvider downloads;
  final AppDatabase database;
  final StorageService storage;
  final NavigatorState navigator;
  final SystemShelfService shelf;

  MultiServerManager get serverManager => multiServer.serverManager;

  SessionTeardownScope.of(BuildContext context)
    : active = context.read<ActiveProfileProvider>(),
      binder = context.read<ActiveProfileBinder>(),
      households = context.read<SiloHouseholdService>(),
      connections = context.read<ConnectionRegistry>(),
      multiServer = context.read<MultiServerProvider>(),
      hiddenLibraries = context.read<HiddenLibrariesProvider?>(),
      discover = context.read<DiscoverProvider?>(),
      downloads = context.read<DownloadProvider>(),
      database = context.read<AppDatabase>(),
      storage = context.read<StorageService>(),
      shelf = SystemShelfService(),
      navigator = Navigator.of(context, rootNavigator: true);
}

/// Decide where the session lands after any profile/connection removal and
/// apply it. Mirrors the boot guard: no connections, or connections but no
/// resolvable profile, routes to [AuthScreen]; otherwise the active profile
/// is kept (optionally rebound) or the next non-PIN-protected profile is
/// activated so the picker can force an explicit, PIN-checked choice when
/// only protected profiles remain.
///
/// Returns true when it navigated to [AuthScreen] — the caller must stop
/// touching its own UI in that case.
Future<bool> settleSessionAfterRemoval(
  SessionTeardownScope scope, {
  bool rebindIfActiveKept = false,
  String? endedShelfOwner,
}) async {
  final hasConnections = (await scope.connections.list()).whereType<SiloConnection>().isNotEmpty;
  await scope.active.reloadFromStorage();
  final profiles = scope.active.profiles;

  if (!hasConnections || profiles.isEmpty) {
    await scope.active.clearActiveProfile();
    await scope.binder.rebindActive();
    if (scope.navigator.mounted) {
      unawaited(
        scope.navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false),
      );
    }
    return true;
  }

  final activeId = scope.storage.getActiveProfileId();
  final activeStillExists = activeId != null && profiles.any((p) => p.id == activeId);
  if (activeStillExists) {
    if (rebindIfActiveKept) {
      if (endedShelfOwner == activeId) {
        await resumeFreshSystemShelf(scope, activeId);
      } else {
        await scope.binder.rebindActive();
      }
    }
  } else {
    // Auto-activation must not bypass PIN gates — skip protected profiles,
    // so the picker forces an explicit, PIN-checked choice instead.
    Profile? next;
    for (final profile in profiles) {
      if (!profile.isPinProtected) {
        next = profile;
        break;
      }
    }
    // The removal was a user action: mark the hand-off activation as
    // user-initiated so the binder binds it (bypassing the initial-bind
    // defer and any suppressed failed-bind marker).
    if (next != null) scope.binder.markUserInitiatedActivation(next.id);
    final activated = next != null && await _enterAndActivate(scope, next);
    if (!activated) {
      await scope.active.clearActiveProfile();
      await scope.binder.rebindActive();
    }
  }
  await scope.hiddenLibraries?.refresh();
  return false;
}

/// Rebinds a surviving owner before admitting fresh shelf publication.
///
/// A failed rebind deliberately leaves the owner invalidated and the native
/// shelf empty.
Future<void> resumeFreshSystemShelf(SessionTeardownScope scope, String profileId) async {
  if (scope.active.activeId != profileId) return;
  try {
    await scope.binder.rebindIfActive(profileId);
    if (scope.active.activeId != profileId) return;
    scope.shelf.beginProfileSession(profileId);
    if (scope.multiServer.hasConnectedServers) {
      await scope.discover?.load();
    }
  } catch (error, stackTrace) {
    appLogger.w('Failed to restore system shelf after profile teardown', error: error, stackTrace: stackTrace);
  }
}

/// Enter [profile] on its server without a PIN prompt, then activate it.
Future<bool> _enterAndActivate(SessionTeardownScope scope, Profile profile) async {
  final connection = scope.active.connectionFor(profile);
  if (connection == null) return false;
  final http = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
  final entered = await enterSiloProfile(http: http, profile: profile, promptPin: (_) async => null);
  return entered == SiloProfileEntryOutcome.entered && await scope.active.activate(profile);
}

/// Ends [endedOwner]'s system-shelf session (when non-null), runs [body], and
/// on failure resumes a fresh shelf session for that owner before rethrowing.
///
/// Only the pause/recover scaffolding is shared: the success-path resume
/// decision (re-begin vs rebind) belongs to each teardown flow's [body].
Future<T> withEndedProfileSession<T>(SessionTeardownScope scope, String? endedOwner, Future<T> Function() body) async {
  if (endedOwner != null) {
    await scope.shelf.endProfileSession(endedOwner);
  }
  try {
    return await body();
  } catch (_) {
    if (endedOwner != null) {
      await resumeFreshSystemShelf(scope, endedOwner);
    }
    rethrow;
  }
}

/// Sign this device out of [connection] after confirmation: the server ends
/// the session, and the connection and its cached household go. Downloads
/// its profiles own are kept unless the user opts in to deleting them; kept
/// rows stay owned by `silo:<server_id>/<profile_id>` scopes, so they come
/// back when the same account signs in to that server again.
///
/// Returns true when the sign-out ran, false when cancelled.
Future<bool> confirmAndSignOutSiloServer(BuildContext context, {required SiloConnection connection}) async {
  final active = context.read<ActiveProfileProvider>();
  final database = context.read<AppDatabase>();
  final profileIds = [
    for (final profile in active.profiles)
      if (profile.connectionId == connection.id) profile.id,
  ];
  var hasDownloads = false;
  for (final profileId in profileIds) {
    if ((await database.getDownloadOwnerKeysForProfile(profileId)).isNotEmpty) hasDownloads = true;
  }
  if (!context.mounted) return false;

  final title = t.profiles.signOutServerTitle(serverName: connection.serverName);
  final message = t.profiles.signOutServerMessage(serverName: connection.serverName);
  final bool deleteDownloads;
  if (hasDownloads) {
    final choice = await showConfirmWithSwitchDialog(
      context,
      title: title,
      message: message,
      confirmText: t.profiles.signOut,
      switchTitle: t.profiles.signOutDeleteDownloads,
      switchSubtitle: t.profiles.signOutServerDeleteDownloadsDescription,
      isDestructive: true,
    );
    if (choice == null) return false;
    deleteDownloads = choice;
  } else {
    final confirmed = await showDeleteConfirmation(
      context,
      title: title,
      message: message,
      confirmText: t.profiles.signOut,
    );
    if (!confirmed) return false;
    deleteDownloads = false;
  }
  if (!context.mounted) return false;

  final scope = SessionTeardownScope.of(context);
  try {
    final activeProfile = scope.active.active;
    final endedOwner = activeProfile != null && activeProfile.connectionId == connection.id ? activeProfile.id : null;
    final navigatedAway = await withEndedProfileSession(scope, endedOwner, () async {
      if (deleteDownloads) {
        // Physical download cleanup can fail. Finish it while the connection
        // still exists so a retry resolves the same profiles.
        for (final profileId in profileIds) {
          await scope.downloads.deleteDownloadsForProfile(profileId);
        }
      }
      await signOutSiloConnection(connection);
      await scope.connections.remove(connection.id);
      final serverId = ServerId.tryParse(connection.serverId);
      if (serverId != null) {
        scope.serverManager.removeServer(serverId);
        await scope.storage.clearLibraryPreferencesForServerEverywhere(serverId);
      }
      for (final profileId in profileIds) {
        await scope.database.deleteSyncRulesForProfile(profileId);
        await scope.database.deleteDownloadCollectionsForProfile(profileId);
        await scope.database.deleteWatchActionsForProfile(profileId);
        await scope.database.deleteMusicSessionForProfile(profileId);
      }
      return settleSessionAfterRemoval(scope, rebindIfActiveKept: true, endedShelfOwner: endedOwner);
    });
    if (!navigatedAway && context.mounted) {
      showSuccessSnackBar(context, t.profiles.signedOutServer(serverName: connection.serverName));
    }
    return true;
  } catch (e, st) {
    appLogger.w('Sign-out failed for ${connection.serverName}', error: e, stackTrace: st);
    if (context.mounted) {
      showErrorSnackBar(context, t.profiles.signOutFailed);
    }
    return false;
  }
}

/// Full logout: sign out of every server and clear every connection,
/// credential, cached API row, and user-scoped pref, then reset to
/// [AuthScreen]. The caller confirms first.
Future<void> logoutAllProfiles(BuildContext context) async {
  final scope = SessionTeardownScope.of(context);
  final companionRemote = context.read<CompanionRemoteProvider>();
  final playbackState = context.read<PlaybackStateProvider>();

  final activeOwner = scope.active.activeId;
  if (activeOwner != null) {
    await scope.shelf.endProfileSession(activeOwner);
  }

  await companionRemote.resetForLogout();
  // Every server ends this device's session while the bearer is still here,
  // before the rows and credentials go.
  for (final connection in (await scope.connections.list()).whereType<SiloConnection>()) {
    await signOutSiloConnection(connection);
  }
  // Credentials go first so nothing below can read them back as the next
  // sign-in's defaults.
  await scope.storage.clearUserData();
  // Downloads are device-local data, not credentials. Keep their physical
  // files and pinned metadata, but detach profile ownership before deleting
  // the profiles so the next selected profile can adopt them.
  await scope.downloads.detachDownloadsForLogout();
  scope.multiServer.clearAllConnections();
  // Drop the connection rows and cached households so the next sign-in
  // starts clean.
  await scope.connections.clear();
  await scope.households.clearAll();
  await scope.storage.clearActiveProfileId();
  await scope.storage.clearAllProfileLastUsed();
  await scope.storage.clearAllUserScopedPreferences();
  // Queued watch actions, sync rules and downloads' collection membership are
  // keyed by profiles this device no longer signs in to; left behind they'd
  // strand forever (or worse, replay through the next sign-in's clients).
  await scope.database.clearAllWatchActions();
  await scope.database.clearAllSyncRules();
  await scope.database.clearAllDownloadCollections();
  // Preserve pinned rows backing offline downloads; all session/API data is
  // volatile and must not cross into the next sign-in.
  await ApiCache.clearRegisteredVolatile();
  await scope.hiddenLibraries?.refresh();
  playbackState.clearShuffle();

  if (scope.navigator.mounted) {
    unawaited(scope.navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthScreen()), (_) => false));
  }
}
