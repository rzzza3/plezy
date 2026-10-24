import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/app_database.dart';
import '../database/download_operations.dart';
import '../i18n/strings.g.dart';
import '../screens/profile/pin_entry_dialog.dart';
import '../utils/snackbar_helper.dart';
import '../utils/app_logger.dart';
import '../services/system_shelf_service.dart';
import '../silo/silo_app.dart';
import '../silo/silo_http.dart';
import '../silo/silo_profiles.dart';
import 'active_profile_binder.dart';
import 'active_profile_provider.dart';
import 'profile.dart';

/// How a UI-driven activation attempt ended. `cancelled` (user backed out
/// of a PIN dialog) is not an error and must not surface a failure message.
enum ProfileActivationOutcome { activated, cancelled, failed }

class _ProfileActivationResult {
  const _ProfileActivationResult(this.outcome, {this.rollbackProfile, this.activationGeneration});

  final ProfileActivationOutcome outcome;
  final Profile? rollbackProfile;
  final int? activationGeneration;
}

/// How entering a profile on its server ended.
enum SiloProfileEntryOutcome { entered, cancelled, failed }

/// Enter [profile] on the server behind [http], asking for its PIN through
/// [promptPin] until the server accepts one or the user backs out. Every
/// switch goes through `enter`, PIN or not: selecting a profile bumps the
/// session generation, so reads still in flight for the previous profile
/// are dropped instead of landing in the new one.
Future<SiloProfileEntryOutcome> enterSiloProfile({
  required SiloHttp http,
  required Profile profile,
  required Future<String?> Function(String? errorMessage) promptPin,
}) async {
  final silo = SiloProfiles(http);
  final target = SiloProfile(id: profile.siloProfileId, name: profile.displayName, hasPin: profile.hasPin);
  String? errorMessage;
  while (true) {
    String? pin;
    if (target.hasPin) {
      pin = await promptPin(errorMessage);
      if (pin == null) return SiloProfileEntryOutcome.cancelled;
    }
    final SiloEnterResult result;
    try {
      result = await silo.enter(target, pin: pin);
    } on Exception catch (error) {
      appLogger.w('Silo: entering a profile failed (${error.runtimeType})');
      return SiloProfileEntryOutcome.failed;
    }
    switch (result) {
      case SiloProfileEntered():
        return SiloProfileEntryOutcome.entered;
      case SiloPinRejected():
        errorMessage = t.profiles.incorrectPinTryAgain;
      case SiloEnterSuperseded():
        return SiloProfileEntryOutcome.failed;
    }
  }
}

/// Replaces the server step of a UI switch ([enterSiloProfile] against the
/// profile's server) in tests.
@visibleForTesting
Future<SiloProfileEntryOutcome> Function(BuildContext context, Profile profile)? debugSiloProfileEntryOverride;

Future<SiloProfileEntryOutcome> _enterOnServer(BuildContext context, Profile profile) async {
  final override = debugSiloProfileEntryOverride;
  if (override != null) return override(context, profile);
  final connection = context.read<ActiveProfileProvider>().connectionFor(profile);
  if (connection == null) return SiloProfileEntryOutcome.failed;
  final prompt = pinPromptFor(context, profile.displayName);
  final http = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
  return enterSiloProfile(http: http, profile: profile, promptPin: prompt);
}

/// Activate [profile] from a UI surface: enter it on its server, prompting
/// for the PIN when it has one, then make it the active profile. The profile
/// already active is already entered, so re-selecting it asks for nothing.
///
/// A switch claims its place in the identity order when the user commits to
/// it: at once for a profile without a PIN, so a later tap overtakes it even
/// while its server entry is in flight; after the PIN is accepted otherwise,
/// so an open PIN dialog holds nothing back.
Future<_ProfileActivationResult> _activateProfileWithPin(BuildContext context, Profile profile) async {
  final active = context.read<ActiveProfileProvider>();
  if (active.activeId == profile.id) return _activateVerifiedProfile(context, profile);
  final claimed = profile.hasPin ? null : active.beginIdentityMutationRequest();
  final entered = await _enterOnServer(context, profile);
  final superseded = claimed != null && !active.isIdentityMutationRequestCurrent(claimed);
  if (!context.mounted || superseded || entered != SiloProfileEntryOutcome.entered) {
    if (claimed != null) active.finishIdentityMutationRequest(claimed);
    if (!context.mounted || superseded) return const _ProfileActivationResult(ProfileActivationOutcome.cancelled);
    return _ProfileActivationResult(
      entered == SiloProfileEntryOutcome.cancelled
          ? ProfileActivationOutcome.cancelled
          : ProfileActivationOutcome.failed,
    );
  }
  return _activateVerifiedProfile(context, profile, requestGeneration: claimed);
}

/// [requestGeneration] is the claim [_activateProfileWithPin] already holds;
/// without one the activation claims its own.
Future<_ProfileActivationResult> _activateVerifiedProfile(
  BuildContext context,
  Profile profile, {
  int? requestGeneration,
}) async {
  final active = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();
  final shelf = SystemShelfService();
  final oldOwner = active.activeId;
  requestGeneration ??= active.beginIdentityMutationRequest();
  int? activationGeneration;

  try {
    if (oldOwner != null && oldOwner != profile.id) {
      await shelf.endProfileSession(oldOwner);
      if (!active.isIdentityMutationRequestCurrent(requestGeneration)) {
        return const _ProfileActivationResult(ProfileActivationOutcome.cancelled);
      }
    }

    // Capture the rollback owner only once this verified request has been
    // admitted. Protected-profile verification may have awaited while another
    // profile became authoritative, so anything captured by the UI caller is
    // stale by this point.
    final rollbackProfile = active.active;
    binder.markUserInitiatedActivation(profile.id);
    final activation = active.activate(profile);
    activationGeneration = active.identityMutationGeneration;
    final activated = await activation;
    if (activated) {
      return _ProfileActivationResult(
        ProfileActivationOutcome.activated,
        rollbackProfile: rollbackProfile,
        activationGeneration: activationGeneration,
      );
    }
  } catch (error, stackTrace) {
    final stillCurrent = activationGeneration == null
        ? active.isIdentityMutationRequestCurrent(requestGeneration)
        : active.identityMutationGeneration == activationGeneration;
    if (stillCurrent) {
      appLogger.w('Failed to activate profile ${profile.id}', error: error, stackTrace: stackTrace);
    }
  } finally {
    active.finishIdentityMutationRequest(requestGeneration);
  }

  final stillCurrent = activationGeneration == null
      ? active.isIdentityMutationRequestCurrent(requestGeneration)
      : active.identityMutationGeneration == activationGeneration;
  if (!stillCurrent) {
    return const _ProfileActivationResult(ProfileActivationOutcome.cancelled);
  }

  // Activation may fail or throw while the prior identity is still
  // authoritative. Admit it again, but never replay rows captured before the
  // failed switch.
  if (oldOwner != null && active.activeId == oldOwner) {
    shelf.beginProfileSession(oldOwner);
  }
  return const _ProfileActivationResult(ProfileActivationOutcome.failed);
}

/// Activate [profile] from a UI surface, then wait until the active profile's
/// server/token binding has settled. Shows the standard switch failure message
/// for activation and binding failures — but not for a PIN-dialog cancel,
/// which is the user changing their mind, not an error.
///
/// Past the PIN prompt nothing here needs [context]: a switch started from a
/// profile-scoped screen (Discover's profile menu) outlives that screen,
/// whose subtree the activation rebuilds, so the offline keep-active decision
/// and the failure message must not depend on it staying mounted.
Future<bool> switchProfileFromUi(BuildContext context, Profile profile) async {
  final activeProvider = context.read<ActiveProfileProvider>();
  final binder = context.read<ActiveProfileBinder>();
  final database = context.read<AppDatabase>();
  final shelf = SystemShelfService();
  void showSwitchFailed() {
    final message = t.errors.failedToSwitchProfile(displayName: profile.displayName);
    if (context.mounted) {
      showErrorSnackBar(context, message);
    } else {
      showGlobalErrorSnackBar(message);
    }
  }

  final activation = await _activateProfileWithPin(context, profile);
  switch (activation.outcome) {
    case ProfileActivationOutcome.cancelled:
      return false;
    case ProfileActivationOutcome.failed:
      showSwitchFailed();
      return false;
    case ProfileActivationOutcome.activated:
      break;
  }

  final previousProfile = activation.rollbackProfile;
  var activationGeneration = activation.activationGeneration;
  if (activationGeneration == null) return false;
  bool isCurrentActivation(String expectedProfileId) =>
      activeProvider.committedIdentityGeneration == activationGeneration &&
      activeProvider.activeId == expectedProfileId;

  if (!isCurrentActivation(profile.id)) return false;
  final bound = await activeProvider.awaitBindingSettle();
  if (!isCurrentActivation(profile.id)) return false;
  if (bound) return true;

  if (binder.lastBindFailureConnectivityOnly) {
    // The bind failed purely for connectivity — the server already checked
    // the PIN when the profile was entered. When
    // the profile owns downloads, keep it active instead of rolling back: the
    // rollback profile's scope does not own them, so they would vanish from
    // the Downloads UI while the files sit on disk. OfflineModeProvider drives
    // the offline UI from the empty visible-server set. Auth-classified bind
    // failures never set the flag and keep today's rollback + snackbar.
    final ownedDownloadKeys = await database.getDownloadOwnerKeysForProfile(profile.id);
    if (!isCurrentActivation(profile.id)) return false;
    if (ownedDownloadKeys.isNotEmpty) {
      appLogger.i(
        'Profile switch: keeping ${profile.displayName} active with no reachable servers '
        '(${ownedDownloadKeys.length} offline downloads owned)',
      );
      return true;
    }
  }

  if (previousProfile != null && previousProfile.id != profile.id && isCurrentActivation(profile.id)) {
    final rollbackRequestGeneration = activeProvider.beginIdentityMutationRequest();
    try {
      await shelf.endProfileSession(profile.id);
      if (!isCurrentActivation(profile.id)) return false;

      final rollbackGeneration = await activeProvider.restoreAfterFailedActivation(
        previousProfile,
        expectedActiveId: profile.id,
        expectedCommittedGeneration: activationGeneration,
        requestGeneration: rollbackRequestGeneration,
      );
      if (rollbackGeneration == null) return false;
      activationGeneration = rollbackGeneration;
      if (!isCurrentActivation(previousProfile.id)) return false;

      // Returning to the profile the user was already on is not a new
      // switch: its PIN was checked when it became active. Its profile token
      // is gone from the session, though, so SiloClient.create reselects it
      // without one; a PIN profile then reads as refused until re-entered.
      binder.markUserInitiatedActivation(previousProfile.id);
      final rebind = binder.rebindActive();
      final restored = await activeProvider.awaitBindingSettle();
      if (!isCurrentActivation(previousProfile.id)) {
        await rebind;
        return false;
      }
      await rebind;
      if (!isCurrentActivation(previousProfile.id)) return false;

      if (restored) {
        shelf.beginProfileSession(previousProfile.id);
      }
    } catch (error, stackTrace) {
      appLogger.w(
        'Failed to restore ${previousProfile.id} after profile switch failure',
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      activeProvider.finishIdentityMutationRequest(rollbackRequestGeneration);
    }
  }
  if (activeProvider.committedIdentityGeneration == activationGeneration) showSwitchFailed();
  return false;
}
