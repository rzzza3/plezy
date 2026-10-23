import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/storage_service.dart';
import '../silo/silo_profiles.dart';
import '../utils/active_client_scope.dart';
import '../utils/app_logger.dart';
import 'profile.dart';
import 'silo_household_service.dart';

/// Holds the currently active [Profile] and the list of every profile the
/// signed-in Silo servers offer, built from [SiloHouseholdService]'s cached
/// households.
///
/// The active id (in storage) is a Silo client scope
/// `silo:<server_id>/<profile_id>`. When it is missing or predates Silo
/// profiles, the provider adopts the profile the server's session already
/// has selected. A household that loads without the active profile clears
/// the selection so the picker opens.
class ActiveProfileProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  ActiveProfileProvider({
    required this._households,
    required this._connections,
    this._storage,
    this._activeProfileIdWriter,
  });

  final SiloHouseholdService _households;
  final ConnectionRegistry _connections;
  StorageService? _storage;
  final Future<void> Function(String profileId)? _activeProfileIdWriter;

  Profile? _active;
  List<Profile> _profiles = const [];
  Map<String, SiloHousehold> _householdsByConnection = const {};
  Map<String, SiloConnection> _connectionsById = const {};

  StreamSubscription<List<Connection>>? _connSub;
  StreamSubscription<Map<String, SiloHousehold>>? _householdSub;
  Future<void>? _initializeFuture;
  Future<void>? _reloadFromStorageFuture;
  bool _initialized = false;

  bool _isBinding = false;
  bool _lastBindingSucceeded = true;
  final List<Completer<bool>> _bindingSettleWaiters = [];
  Future<void>? _identityMutationQueue;
  int _identityMutationGeneration = 0;
  int _committedIdentityGeneration = 0;
  int _pendingIdentityMutations = 0;
  final Map<int, Completer<void>> _identityMutationReservations = {};

  Profile? get active => _active;
  String? get activeId => _active?.id;
  List<Profile> get profiles => _profiles;

  /// Picture URL for [profileId], or null when initials should render.
  String? avatarUrlFor(String profileId) {
    for (final profile in _profiles) {
      if (profile.id == profileId) return _absoluteAvatarUrl(profile);
    }
    return null;
  }

  String? _absoluteAvatarUrl(Profile profile) {
    final url = profile.avatarThumbUrl;
    if (url == null || url.isEmpty) return null;
    final parsed = Uri.tryParse(url);
    if (parsed == null) return null;
    if (parsed.hasScheme) return url;
    final origin = _connectionsById[profile.connectionId]?.origin;
    return origin == null ? null : Uri.parse(origin).resolveUri(parsed).toString();
  }

  /// Signed-in Silo servers by connection id.
  Map<String, SiloConnection> get connectionsById => _connectionsById;

  /// The connection [profile] signs in through, or null when it was removed.
  SiloConnection? connectionFor(Profile profile) => _connectionsById[profile.connectionId];

  /// Cached household per connection id.
  Map<String, SiloHousehold> get householdsByConnection => _householdsByConnection;

  SiloHouseholdService get households => _households;

  bool get hasMultipleProfiles => _profiles.length > 1;
  bool get isInitialized => _initialized;

  /// Monotonically identifies the last active-profile identity that
  /// successfully committed. Failed and cancelled activation attempts do not
  /// advance it.
  int get committedIdentityGeneration => _committedIdentityGeneration;

  int get identityMutationGeneration => _identityMutationGeneration;

  /// True while [ActiveProfileBinder] is wiring the active profile's server.
  /// The picker reads this so it can stay open until binding settles.
  bool get isBinding => _isBinding;

  /// Outcome of the most recent settled bind.
  bool get lastBindingSucceeded => _lastBindingSucceeded;

  /// Called by [ActiveProfileBinder] at the start of a rebind cycle.
  /// Re-entrant — no-ops if already in [isBinding].
  void markBindingStarted() {
    if (_isBinding) return;
    _isBinding = true;
    _lastBindingSucceeded = true;
    safeNotifyListeners();
  }

  /// Called by [ActiveProfileBinder] when the rebind settles. [success]
  /// means the active profile's server was reached.
  void markBindingFinished({required bool success}) {
    if (!_isBinding && _lastBindingSucceeded == success) return;
    _isBinding = false;
    _lastBindingSucceeded = success;
    safeNotifyListeners();
  }

  /// Resolves once the binder reports done. Returns immediately when no
  /// rebind is in flight. The boolean reflects [lastBindingSucceeded] at
  /// the moment binding settles, so the picker can decide whether to
  /// dismiss or surface an error.
  ///
  /// Pending completers are tracked so [dispose] can settle them.
  Future<bool> awaitBindingSettle() {
    if (!_isBinding) return Future.value(_lastBindingSucceeded);
    final completer = Completer<bool>();
    _bindingSettleWaiters.add(completer);
    void listener() {
      if (_isBinding) return;
      removeListener(listener);
      if (_bindingSettleWaiters.remove(completer) && !completer.isCompleted) {
        completer.complete(_lastBindingSucceeded);
      }
    }

    addListener(listener);
    return completer.future;
  }

  Future<void> initialize() {
    if (_initialized) return Future.value();
    final pending = _initializeFuture;
    if (pending != null) return pending;

    final future = _initialize().catchError((Object error, StackTrace stackTrace) {
      _initializeFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
    _initializeFuture = future;
    return future;
  }

  /// Re-read connections, cached households, and the active id.
  Future<void> reloadFromStorage() {
    final pending = _reloadFromStorageFuture;
    if (pending != null) return pending;

    final future = _reloadFromStorage();
    _reloadFromStorageFuture = future;
    return future;
  }

  Future<void> _reloadFromStorage() async {
    try {
      await initialize();
      await _households.reloadFromStorage();
      await _reloadSnapshot();
      safeNotifyListeners();
    } finally {
      _reloadFromStorageFuture = null;
    }
  }

  Future<void> _initialize() async {
    await _reloadSnapshot();

    // Both listeners diff first: drift re-emits on any table write.
    _connSub = _connections.watchConnections().listen((list) {
      final byId = _siloConnections(list);
      if (_sameConnections(byId, _connectionsById)) return;
      _connectionsById = byId;
      _recomputeProfiles();
      _resolveActive();
      safeNotifyListeners();
    });
    _householdSub = _households.stream.listen((households) {
      if (mapEquals(households, _householdsByConnection)) return;
      _householdsByConnection = households;
      _recomputeProfiles();
      _resolveActive();
      safeNotifyListeners();
    });

    _initialized = true;
    safeNotifyListeners();
  }

  Future<void> _reloadSnapshot() async {
    final storage = _storage ??= await StorageService.getInstance();
    await _households.hydrate();
    _connectionsById = _siloConnections(await _connections.list());
    _householdsByConnection = _households.current;
    await _adoptSessionProfileIfNeeded(storage);
    _recomputeProfiles();
    _resolveActive();
  }

  static Map<String, SiloConnection> _siloConnections(List<Connection> list) => {
    for (final connection in list.whereType<SiloConnection>()) connection.id: connection,
  };

  /// An upgrade from a build with Plezy-owned profiles, or a sign-in that
  /// stored no choice, leaves no Silo profile id in storage. The server's
  /// session already names the profile it entered, so adopt that one rather
  /// than ask again.
  Future<void> _adoptSessionProfileIfNeeded(StorageService storage) async {
    final stored = storage.getActiveProfileId();
    if (stored != null && SiloProfileScopeId.tryParse(stored) != null) return;
    for (final connection in _connectionsById.values) {
      final profileId = await _households.sessionProfileId(connection);
      if (profileId == null || profileId.isEmpty) continue;
      final scope = SiloProfileScopeId.tryParse('silo:${connection.serverId}/$profileId');
      if (scope == null) continue;
      await _writeActiveProfileId(storage, scope);
      appLogger.i('ActiveProfileProvider: adopted the session profile of ${connection.serverName}');
      return;
    }
    if (stored != null) await storage.clearActiveProfileId();
  }

  bool _sameConnections(Map<String, SiloConnection> a, Map<String, SiloConnection> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other == null) return false;
      if (identical(entry.value, other)) continue;
      if (!_connections.hasSameConfig(entry.value, other)) return false;
    }
    return true;
  }

  void _recomputeProfiles() {
    final storage = _storage;
    final out = <Profile>[];
    for (final connection in _connectionsById.values) {
      final household = _householdsByConnection[connection.id];
      if (household == null) continue;
      for (final (index, profile) in household.profiles.indexed) {
        final built = Profile.fromSilo(serverId: connection.serverId, profile: profile, sortOrder: index);
        out.add(built.copyWith(lastUsedAt: storage?.getProfileLastUsed(built.id)));
      }
    }
    _profiles = sortProfilesByLastUsed(out);
  }

  void _resolveActive() {
    if (_pendingIdentityMutations > 0) return;
    final id = _storage?.getActiveProfileId();
    // No saved id means "fresh state" — leave the active profile null so
    // MainScreen prompts the user via the picker.
    if (id == null) {
      _active = null;
      return;
    }
    for (final p in _profiles) {
      if (p.id == id) {
        _active = p;
        return;
      }
    }
    final scope = SiloProfileScopeId.tryParse(id);
    final connection = scope == null ? null : _connectionsById[SiloConnection.idFor(scope.publicServerId)];
    if (scope == null || connection == null) {
      // Keep the persisted id: an early snapshot (boot before connections
      // load) must not wipe the selection. Unresolvable states clear it at
      // their decision points.
      _active = null;
      return;
    }
    if (_householdsByConnection.containsKey(connection.id)) {
      // The server's own list no longer has the profile.
      appLogger.i('ActiveProfileProvider: the active profile left ${connection.serverName}; opening the picker');
      _active = null;
      unawaited(_storage?.clearActiveProfileId());
      return;
    }
    // Household not read yet: bind the stored profile under a provisional
    // name until the first read lands.
    _active = Profile(
      serverId: connection.serverId,
      siloProfileId: scope.profileId,
      displayName: connection.username.isEmpty ? connection.serverName : connection.username,
      lastUsedAt: _storage?.getProfileLastUsed(id),
    );
  }

  /// Claims ownership for an identity change that must perform asynchronous
  /// preparation before it can enter the serialized mutation queue.
  ///
  /// The claim is synchronous so a newer user request can invalidate older
  /// preparation immediately. Callers must always pair this with
  /// [finishIdentityMutationRequest].
  int beginIdentityMutationRequest() {
    final generation = ++_identityMutationGeneration;
    _identityMutationReservations[generation] = Completer<void>();
    return generation;
  }

  bool isIdentityMutationRequestCurrent(int generation) => generation == _identityMutationGeneration;

  void finishIdentityMutationRequest(int generation) {
    final reservation = _identityMutationReservations.remove(generation);
    if (reservation != null && !reservation.isCompleted) reservation.complete();
  }

  /// Activate [profile]. The caller has already entered it on the server
  /// ([enterSiloProfile]), which checks a PIN.
  Future<bool> activate(Profile profile) async {
    final storage = _storage;
    if (storage == null) return false;
    return _serializeIdentityMutation<bool>((generation) async {
      if (generation != _identityMutationGeneration) return false;
      final now = DateTime.now();
      await storage.markProfileUsed(profile.id, now);
      if (generation != _identityMutationGeneration) return false;
      final previousActiveProfileId = storage.getActiveProfileId();
      try {
        await _writeActiveProfileId(storage, profile.id);
      } catch (_) {
        await _restoreActiveProfileId(storage, previousActiveProfileId);
        rethrow;
      }
      if (generation != _identityMutationGeneration) {
        await _restoreActiveProfileId(storage, previousActiveProfileId);
        return false;
      }

      final activated = profile.copyWith(lastUsedAt: now);
      _active = activated;
      _committedIdentityGeneration = generation;
      _profiles = sortProfilesByLastUsed([for (final p in _profiles) p.id == profile.id ? activated : p]);
      safeNotifyListeners();
      appLogger.i('ActiveProfileProvider: activated ${profile.displayName} (${profile.id})');
      return true;
    });
  }

  /// Restore the profile that owned the current authenticated session when a
  /// later activation fails. The caller must supply the profile captured
  /// before that activation; no PIN prompt is repeated for the session that
  /// was already unlocked.
  Future<int?> restoreAfterFailedActivation(
    Profile profile, {
    required String expectedActiveId,
    required int expectedCommittedGeneration,
    int? requestGeneration,
  }) async {
    final storage = _storage;
    if (storage == null) {
      throw StateError('ActiveProfileProvider is not initialized');
    }

    var generation = requestGeneration;
    while (_active?.id == expectedActiveId && _committedIdentityGeneration == expectedCommittedGeneration) {
      if (generation != null && generation != _identityMutationGeneration) {
        // A newer request may still be preparing before it enters the queue
        // (for example, clearing its former shelf owner). Do not reclaim
        // ownership until that request has finished. If it fails without
        // committing, the genuinely current failed identity can still be
        // restored on the next pass.
        await _awaitIdentityWorkAfter(generation);
        if (_active?.id != expectedActiveId || _committedIdentityGeneration != expectedCommittedGeneration) {
          return null;
        }
        generation = null;
      }

      late int attemptedGeneration;
      Future<int?> restore(int ownedGeneration) {
        attemptedGeneration = ownedGeneration;
        return _restoreFailedActivation(
          storage,
          profile,
          expectedActiveId,
          expectedCommittedGeneration,
          ownedGeneration,
        );
      }

      final restoredGeneration = generation == null
          ? await _serializeIdentityMutation<int?>(restore)
          : await _queueIdentityMutation<int?>(generation, restore);
      if (restoredGeneration != null) return restoredGeneration;
      if (_active?.id != expectedActiveId || _committedIdentityGeneration != expectedCommittedGeneration) {
        return null;
      }

      await _awaitIdentityWorkAfter(attemptedGeneration);
      generation = null;
    }
    return null;
  }

  Future<int?> _restoreFailedActivation(
    StorageService storage,
    Profile profile,
    String expectedActiveId,
    int expectedCommittedGeneration,
    int generation,
  ) async {
    if (_active?.id != expectedActiveId ||
        _committedIdentityGeneration != expectedCommittedGeneration ||
        generation != _identityMutationGeneration) {
      return null;
    }
    final previousActiveProfileId = storage.getActiveProfileId();
    try {
      await _writeActiveProfileId(storage, profile.id);
    } catch (_) {
      await _restoreActiveProfileId(storage, previousActiveProfileId);
      rethrow;
    }
    if (generation != _identityMutationGeneration) {
      await _restoreActiveProfileId(storage, previousActiveProfileId);
      return null;
    }

    _committedIdentityGeneration = generation;
    _active = profile;
    _profiles = sortProfilesByLastUsed([
      for (final candidate in _profiles) candidate.id == profile.id ? profile : candidate,
    ]);
    safeNotifyListeners();
    appLogger.i('ActiveProfileProvider: restored ${profile.displayName} (${profile.id}) after failed activation');
    return generation;
  }

  /// Clear the selected profile in both storage and memory so the picker
  /// can force an explicit choice on the next screen.
  Future<void> clearActiveProfile() async {
    final generation = beginIdentityMutationRequest();
    try {
      final storage = _storage ??= await StorageService.getInstance();
      if (!isIdentityMutationRequestCurrent(generation)) return;
      await _queueIdentityMutation<void>(generation, (ownedGeneration) async {
        if (ownedGeneration != _identityMutationGeneration) return;
        final previousActiveProfileId = storage.getActiveProfileId();
        await storage.clearActiveProfileId();
        if (ownedGeneration != _identityMutationGeneration) {
          await _restoreActiveProfileId(storage, previousActiveProfileId);
          return;
        }
        _committedIdentityGeneration = ownedGeneration;
        _active = null;
        safeNotifyListeners();
      });
    } finally {
      finishIdentityMutationRequest(generation);
    }
  }

  Future<void> _writeActiveProfileId(StorageService storage, String profileId) {
    return _activeProfileIdWriter?.call(profileId) ?? storage.setActiveProfileId(profileId);
  }

  Future<void> _restoreActiveProfileId(StorageService storage, String? profileId) {
    if (profileId == null) return storage.clearActiveProfileId();
    return _writeActiveProfileId(storage, profileId);
  }

  Future<T> _serializeIdentityMutation<T>(Future<T> Function(int generation) mutation) {
    final generation = ++_identityMutationGeneration;
    return _queueIdentityMutation(generation, mutation);
  }

  Future<T> _queueIdentityMutation<T>(int generation, Future<T> Function(int generation) mutation) {
    final previous = _identityMutationQueue;
    _pendingIdentityMutations++;
    final operation = () async {
      if (previous != null) await previous;
      try {
        return await mutation(generation);
      } finally {
        _pendingIdentityMutations--;
      }
    }();
    _identityMutationQueue = operation.then<void>((_) {}).catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _awaitIdentityWorkAfter(int generation) async {
    while (true) {
      final reservations = [
        for (final entry in _identityMutationReservations.entries)
          if (entry.key > generation) entry.value.future,
      ];
      final queue = _identityMutationQueue;
      if (reservations.isNotEmpty) await Future.wait(reservations);
      if (queue != null) await queue;

      final hasNewerReservation = _identityMutationReservations.keys.any((candidate) => candidate > generation);
      if (!hasNewerReservation && identical(queue, _identityMutationQueue)) return;
    }
  }

  @visibleForTesting
  Future<void> resetForTesting() async {
    await _connSub?.cancel();
    await _householdSub?.cancel();
    _connSub = null;
    _householdSub = null;
    _profiles = const [];
    _householdsByConnection = const {};
    _connectionsById = const {};
    _active = null;
    _initializeFuture = null;
    _initialized = false;
    _isBinding = false;
    _lastBindingSucceeded = true;
    for (final c in _bindingSettleWaiters) {
      if (!c.isCompleted) c.complete(_lastBindingSucceeded);
    }
    _bindingSettleWaiters.clear();
    for (final reservation in _identityMutationReservations.values) {
      if (!reservation.isCompleted) reservation.complete();
    }
    _identityMutationReservations.clear();
  }

  @override
  void dispose() {
    // Settle anyone awaiting binding before the listeners go away — leaving
    // them pending traps callers in a forever-await on app teardown.
    for (final c in _bindingSettleWaiters) {
      if (!c.isCompleted) c.complete(_lastBindingSucceeded);
    }
    _bindingSettleWaiters.clear();
    for (final reservation in _identityMutationReservations.values) {
      if (!reservation.isCompleted) reservation.complete();
    }
    _identityMutationReservations.clear();
    _initializeFuture = null;
    _connSub?.cancel();
    _householdSub?.cancel();
    super.dispose();
  }
}

/// Most recently used first; never-used profiles keep their input order.
List<Profile> sortProfilesByLastUsed(List<Profile> profiles) {
  final indexed = profiles.indexed.toList();
  indexed.sort((a, b) {
    final aLastUsed = a.$2.lastUsedAt;
    final bLastUsed = b.$2.lastUsedAt;
    if (aLastUsed == null && bLastUsed == null) return a.$1.compareTo(b.$1);
    if (aLastUsed == null) return 1;
    if (bLastUsed == null) return -1;
    final byLastUsed = bLastUsed.compareTo(aLastUsed);
    if (byLastUsed != 0) return byLastUsed;
    return a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}
