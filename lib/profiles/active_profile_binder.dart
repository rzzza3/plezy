import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../media/ids.dart';
import '../providers/multi_server_provider.dart';
import '../services/multi_server_manager.dart';
import '../utils/app_logger.dart';
import 'active_profile_provider.dart';
import 'profile.dart';

typedef ShouldDeferInitialBind = FutureOr<bool> Function(Profile profile);

/// Wires the active profile's Silo server into [MultiServerManager]: one
/// client, scoped to the profile, and nothing else. An empty bound set is
/// propagated as `{}` so no profile shows another profile's server.
class ActiveProfileBinder {
  ActiveProfileBinder({
    required this.activeProfile,
    required this.connections,
    required this.serverManager,
    required this.multiServerProvider,
    this.shouldDeferInitialBind,
  });

  final ActiveProfileProvider activeProfile;
  final ConnectionRegistry connections;
  final MultiServerManager serverManager;
  final MultiServerProvider multiServerProvider;
  final ShouldDeferInitialBind? shouldDeferInitialBind;

  bool _started = false;
  bool _isSwitching = false;
  String? _lastBoundProfileId;
  String? _bindingProfileId;

  /// Profile whose most recent bind failed (offline, refused, error).
  /// Passive provider notifications must not retry it; explicit paths
  /// ([rebindActive], a user-initiated activation) clear the marker.
  String? _lastFailedProfileId;

  /// True when the most recently completed rebind pass failed purely for
  /// connectivity: the profile expected at least one server, reached none,
  /// and no expected server was auth-rejected. Superseded/cancelled passes
  /// and thrown binds leave this false. Read by `switchProfileFromUi` to
  /// keep a downloads-owning profile active in offline mode instead of
  /// rolling back to a profile whose scope does not own those downloads.
  bool _lastBindFailureConnectivityOnly = false;
  bool _pendingRebind = false;
  // Set when something asks for a rebind of the *currently-active* profile
  // while a rebind is already in flight. The normal `_pendingRebind` path
  // only loops when the active id has drifted — this flag covers same-id
  // re-runs, e.g. after a sign-in replaces the server's connection.
  bool _pendingSameIdRebind = false;
  int _bindGeneration = 0;

  /// True after the binder has bound a profile with its server in this
  /// session; the initial-bind deferral only applies before that.
  bool _hasBoundOnce = false;

  final Set<String> _userInitiatedActivations = {};

  @visibleForTesting
  String? get debugLastBoundProfileId => _lastBoundProfileId;

  bool get lastBindFailureConnectivityOnly => _lastBindFailureConnectivityOnly;

  void markUserInitiatedActivation(String profileId) {
    _userInitiatedActivations.add(profileId);
    if (_lastFailedProfileId == profileId) _lastFailedProfileId = null;
  }

  @visibleForTesting
  bool consumeUserInitiatedActivation(String profileId) {
    return _userInitiatedActivations.remove(profileId);
  }

  void start() {
    if (_started) return;
    _started = true;
    // Flip `isBinding` before anything else: callers navigate right after
    // start(), and screens (DiscoverScreen's no-servers gate) read the flag
    // synchronously during their first build. Deferring the mark to the
    // microtask below leaves a started-but-flag-false gap in which the gate
    // throws "No servers available" on fresh login. Marking before
    // addListener keeps the binder's own listener from reacting to this
    // notification — the microtask stays the single initial-rebind entry.
    activeProfile.markBindingStarted();
    activeProfile.addListener(_onActiveProfileChanged);
    // Callers invoke start() from async contexts once the active profile is
    // hydrated (SetupScreen, MainScreen post-frame, AuthScreen). The
    // microtask keeps the initial rebind out of the caller's current frame.
    scheduleMicrotask(() {
      if (!_started) {
        // Disposed before the rebind could run — settle the flag we set
        // above so awaitBindingSettle callers aren't stranded.
        activeProfile.markBindingFinished(success: true);
        return;
      }
      unawaited(_rebind());
    });
  }

  void _onActiveProfileChanged() {
    final id = activeProfile.activeId;
    if (_isSwitching) {
      // Ignore our own markBindingStarted/markBindingFinished
      // notifications. They don't mean the active profile changed, and a
      // failed bind intentionally leaves `_lastBoundProfileId` unset so the
      // same profile can be retried later.
      if (id == _bindingProfileId) {
        // The active id can briefly move away and back while this pass is
        // awaiting multiple connection binds. Any component that observed the
        // intermediate id may already have returned an empty stale result, so
        // the current pass cannot be committed as the final same-id bind.
        if (_pendingRebind) _pendingSameIdRebind = true;
        return;
      }
      // A rebind is already in flight — flag a follow-up so the loop in
      // [_rebind] picks up the new active id once the current pass settles.
      // Otherwise the switch is silently dropped (the early-return on
      // `_isSwitching` would leave storage saying B is active while the
      // binder is still wired to A).
      _pendingRebind = true;
      return;
    }
    if (id == _lastBoundProfileId) return;
    // Don't retry a failed profile from a passive notification — see
    // [_lastFailedProfileId]. A different profile id still rebinds.
    if (id != null && id == _lastFailedProfileId) return;
    unawaited(_rebind());
  }

  /// Force the binder to re-run for the currently-active profile, even
  /// when the active id hasn't changed — e.g. after signing in to its
  /// server again.
  ///
  /// Safe to call while a rebind is in flight; the request is queued and
  /// the loop runs an extra pass when the current one settles.
  Future<void> rebindActive() async {
    _lastFailedProfileId = null;
    if (_isSwitching) {
      _pendingSameIdRebind = true;
      return;
    }
    await _rebind();
  }

  /// Convenience: rebind only when [profileId] matches the active profile.
  /// No-op otherwise — the change will be picked up on next activation.
  /// Use this from screens that mutate a specific profile's connections.
  Future<void> rebindIfActive(String profileId) async {
    if (activeProfile.activeId != profileId) return;
    await rebindActive();
  }

  Future<void> _rebind() async {
    if (_isSwitching) return;
    _isSwitching = true;
    // Binding is marked per CYCLE, not per pass: `awaitBindingSettle`
    // waiters must observe the FINAL outcome. Settling between passes hands
    // a caller who activated profile B mid-pass the outcome of profile A's
    // pass — reporting a switch as succeeded/failed before B's bind ran.
    _bindingProfileId = activeProfile.activeId;
    activeProfile.markBindingStarted();
    var success = false;
    try {
      do {
        _pendingRebind = false;
        _pendingSameIdRebind = false;
        success = await _runRebindOnce();
        // Loop only when the active id has drifted to something we haven't
        // bound yet, OR when an explicit same-id rebind was queued (a
        // connection mutation while a rebind was in flight). Bare
        // `_pendingRebind` would spin forever if the user taps the active
        // profile while we're binding (id matches, no work to do, flag
        // re-asserts).
      } while (_pendingSameIdRebind || (_pendingRebind && activeProfile.activeId != _lastBoundProfileId));
    } finally {
      // Notify while `_isSwitching`/`_bindingProfileId` still attribute the
      // notification to this cycle — otherwise the binder's own listener
      // would treat it as an external change and immediately re-rebind.
      activeProfile.markBindingFinished(success: success);
      _bindingProfileId = null;
      _isSwitching = false;
    }
  }

  Future<bool> _runRebindOnce() async {
    _bindingProfileId = activeProfile.activeId;
    final generation = ++_bindGeneration;
    final stopwatch = Stopwatch()..start();
    var success = false;
    _lastBindFailureConnectivityOnly = false;
    String? attemptedProfileId;
    try {
      final profile = activeProfile.active;
      if (profile == null) {
        // No active profile is a valid quiescent state (e.g. fresh sign-in
        // before the picker fires) — report success so a waiting picker
        // doesn't surface a spurious "switch failed" error, and clear the
        // runtime filter so the previous profile's client cannot leak.
        _clearBoundServers();
        success = true;
        return success;
      }
      attemptedProfileId = profile.id;

      final userInitiated = consumeUserInitiatedActivation(profile.id);
      if (!userInitiated && !_hasBoundOnce && await _shouldDeferInitialBind(profile)) {
        appLogger.i('ActiveProfileBinder: deferring initial bind for ${profile.displayName} until profile selection');
        _clearBoundServers();
        attemptedProfileId = null;
        success = true;
        return success;
      }

      appLogger.i('ActiveProfileBinder: rebinding for ${profile.displayName} (${profile.id})');
      final connection = await connections.get(profile.connectionId);
      if (!_isCurrentBind(profile.id, generation)) return false;
      if (connection is! SiloConnection) {
        appLogger.w('ActiveProfileBinder: ${profile.displayName} has no signed-in server');
        _clearBoundServers();
        return false;
      }

      final serverId = connection.serverId;
      multiServerProvider.setExpectedVisibleServerIds({serverId});
      final reached = await serverManager.addSiloConnection(connection, profileId: profile.siloProfileId);
      if (!_isCurrentBind(profile.id, generation)) return false;
      // A refusing server still counts as bound: the refusal is what the UI
      // shows, and reconnecting the same profile is the way out.
      final refused = serverManager.refusedServerIds.contains(serverId);
      final visible = reached || refused;

      // Only this profile's server stays registered.
      for (final registered in serverManager.registeredServerIds) {
        if (registered == serverId &&
            !serverManager.isRegisteredForOtherProfile(ServerId(registered), profileId: profile.id)) {
          continue;
        }
        serverManager.removeServer(ServerId(registered));
      }
      multiServerProvider.setExpectedVisibleServerIds({serverId});
      multiServerProvider.setVisibleServerIds(visible ? {serverId} : <String>{});
      success = visible;
      if (!success) _lastBindFailureConnectivityOnly = true;
      if (success) _hasBoundOnce = true;
    } catch (e, st) {
      appLogger.e('ActiveProfileBinder: rebind failed', error: e, stackTrace: st);
      success = false;
    } finally {
      if (success) {
        _lastBoundProfileId = attemptedProfileId;
        _lastFailedProfileId = null;
      } else {
        if (_lastBoundProfileId == attemptedProfileId) {
          _lastBoundProfileId = null;
        }
        _lastFailedProfileId = attemptedProfileId;
      }
      appLogger.i(
        'ActiveProfileBinder: rebind settled',
        error: {'profileId': attemptedProfileId, 'success': success, 'elapsedMs': stopwatch.elapsedMilliseconds},
      );
    }
    return success;
  }

  bool _isCurrentBind(String profileId, int generation) {
    return _bindGeneration == generation && activeProfile.activeId == profileId;
  }

  Future<bool> _shouldDeferInitialBind(Profile profile) async {
    final shouldDefer = shouldDeferInitialBind;
    if (shouldDefer == null) return false;
    try {
      return await shouldDefer(profile);
    } catch (e, st) {
      appLogger.w('ActiveProfileBinder: defer check failed; continuing with bind', error: e, stackTrace: st);
      return false;
    }
  }

  void _clearBoundServers() {
    for (final serverId in serverManager.registeredServerIds) {
      serverManager.removeServer(ServerId(serverId));
    }
    multiServerProvider.setExpectedVisibleServerIds(<String>{});
    multiServerProvider.setVisibleServerIds(<String>{});
  }

  void dispose() {
    _bindGeneration++;
    if (!_started) return;
    activeProfile.removeListener(_onActiveProfileChanged);
    _userInitiatedActivations.clear();
    _lastFailedProfileId = null;
    _started = false;
  }
}
