import 'dart:async';
import 'dart:convert';

import '../connection/connection.dart';
import '../connection/connection_registry.dart';
import '../services/base_shared_preferences_service.dart';
import '../silo/silo_app.dart';
import '../silo/silo_profiles.dart';
import '../utils/app_logger.dart';

/// Reads the household of one signed-in server. Null when the identity moved
/// during the read.
typedef SiloHouseholdLoader = Future<SiloHousehold?> Function(SiloConnection connection);

/// The profile a server's session has selected, or null when it has none.
typedef SiloSessionProfileReader = Future<String?> Function(SiloConnection connection);

Future<SiloHousehold?> _loadHousehold(SiloConnection connection) async {
  final http = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
  return SiloProfiles(http).load();
}

Future<String?> _sessionProfileId(SiloConnection connection) async =>
    (await SiloApp.session(connection.serverId)).session?.profileId;

/// Live source of truth for Silo profiles. Silo owns the household, so the
/// app never stores profiles as rows: this service keeps the last
/// `/api/v2/account/me` + `/api/v2/profiles` read per signed-in server,
/// caches it in shared preferences for cold and offline starts, and emits
/// `connectionId -> household` snapshots that [ActiveProfileProvider] turns
/// into [Profile]s.
///
/// A read also backfills [SiloConnection.accountId] for connections saved
/// before the companion remote needed it.
class SiloHouseholdService {
  SiloHouseholdService({
    required this._connections,
    SiloHouseholdLoader? loader,
    SiloSessionProfileReader? sessionProfile,
  }) : _load = loader ?? _loadHousehold,
       _readSessionProfile = sessionProfile ?? _sessionProfileId;

  static const _keyPrefix = 'silo_household_';

  final ConnectionRegistry _connections;
  final SiloHouseholdLoader _load;
  final SiloSessionProfileReader _readSessionProfile;

  final Map<String, SiloHousehold> _byConnection = {};
  final _controller = StreamController<Map<String, SiloHousehold>>.broadcast();
  final Map<String, Future<SiloHousehold?>> _refreshes = {};
  StreamSubscription<List<Connection>>? _connSub;
  Future<void>? _hydrateFuture;
  int _epoch = 0;
  bool _disposed = false;

  /// Snapshot of the cache (immutable view).
  Map<String, SiloHousehold> get current => Map.unmodifiable(_byConnection);

  /// Emits the current snapshot on subscribe, then every change.
  Stream<Map<String, SiloHousehold>> get stream {
    late StreamController<Map<String, SiloHousehold>> ctrl;
    StreamSubscription<Map<String, SiloHousehold>>? sub;
    ctrl = StreamController<Map<String, SiloHousehold>>(
      onListen: () {
        ctrl.add(current);
        sub = _controller.stream.listen(ctrl.add, onError: ctrl.addError, onDone: ctrl.close);
      },
      onPause: () => sub?.pause(),
      onResume: () => sub?.resume(),
      onCancel: () => sub?.cancel(),
    );
    return ctrl.stream;
  }

  /// The profile [connection]'s session has selected.
  Future<String?> sessionProfileId(SiloConnection connection) async {
    try {
      return await _readSessionProfile(connection);
    } on Exception catch (error) {
      appLogger.w('Silo: reading the session profile failed (${error.runtimeType})');
      return null;
    }
  }

  /// Load the cached households of the current connections. No network.
  Future<void> hydrate() {
    if (_disposed) return Future.value();
    return _hydrateFuture ??= _hydrate().catchError((Object error, StackTrace stackTrace) {
      _hydrateFuture = null;
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> _hydrate() async {
    final epoch = _epoch;
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final connections = await _connections.list();
    if (epoch != _epoch) return;
    _byConnection.clear();
    for (final connection in connections.whereType<SiloConnection>()) {
      final cached = _decode(prefs.getString('$_keyPrefix${connection.id}'));
      if (cached != null) _byConnection[connection.id] = cached;
    }
    _emit();
  }

  /// Re-read the cache, for callers that changed connections in storage.
  Future<void> reloadFromStorage() async {
    _hydrateFuture = null;
    await hydrate();
  }

  /// Follow connection changes and refresh every household once.
  Future<void> start() async {
    if (_disposed || _connSub != null) return;
    await hydrate();
    if (_disposed) return;
    _connSub = _connections.watchConnections().listen((connections) => unawaited(_onConnections(connections)));
  }

  Future<void> _onConnections(List<Connection> connections) async {
    final silo = connections.whereType<SiloConnection>().toList();
    final ids = {for (final connection in silo) connection.id};
    var changed = false;
    for (final id in _byConnection.keys.toList()) {
      if (ids.contains(id)) continue;
      _byConnection.remove(id);
      changed = true;
      unawaited(_remove(id));
    }
    if (changed) _emit();
    for (final connection in silo) {
      if (!_byConnection.containsKey(connection.id)) unawaited(refresh(connection));
    }
  }

  /// Read [connection]'s household from the server and cache it. Returns
  /// null, keeping the cached copy, when the read fails or the identity
  /// moved during it. Concurrent calls for one connection share a read.
  Future<SiloHousehold?> refresh(SiloConnection connection) {
    if (_disposed) return Future.value();
    // The callback must not return the removed future: whenComplete would
    // wait on it, and it is this very refresh.
    return _refreshes[connection.id] ??= _refresh(connection).whenComplete(() {
      _refreshes.remove(connection.id);
    });
  }

  Future<SiloHousehold?> _refresh(SiloConnection connection) async {
    final epoch = _epoch;
    final SiloHousehold? household;
    try {
      household = await _load(connection);
    } on Exception catch (error) {
      appLogger.w('Silo: household read failed (${error.runtimeType})');
      return null;
    }
    if (household == null || epoch != _epoch || _disposed) return null;
    await put(connection, household);
    return household;
  }

  /// Cache a household read elsewhere (the sign-in picker) and backfill the
  /// connection's account id.
  Future<void> put(SiloConnection connection, SiloHousehold household) async {
    if (_disposed) return;
    _byConnection[connection.id] = household;
    _emit();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString('$_keyPrefix${connection.id}', _encode(household));
    final stored = await _connections.get(connection.id);
    if (stored is SiloConnection &&
        (stored.accountId != household.account.id || stored.username != household.account.username)) {
      await _connections.upsert(stored.copyWith(accountId: household.account.id, username: household.account.username));
    }
  }

  Future<void> _remove(String connectionId) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove('$_keyPrefix$connectionId');
  }

  /// Forget every household, for a full logout.
  Future<void> clearAll() async {
    _epoch++;
    final ids = _byConnection.keys.toList();
    _byConnection.clear();
    _emit();
    final prefs = await BaseSharedPreferencesService.sharedCache();
    for (final key in prefs.keys.where((key) => key.startsWith(_keyPrefix)).toList()) {
      await prefs.remove(key);
    }
    appLogger.d('SiloHouseholdService: cleared ${ids.length} households');
  }

  void _emit() {
    if (!_disposed) _controller.add(current);
  }

  static String _encode(SiloHousehold household) => jsonEncode({
    'account': {'id': household.account.id, 'username': household.account.username, 'role': household.account.role},
    'profiles': [
      for (final profile in household.profiles)
        {
          'id': profile.id,
          'name': profile.name,
          'avatar_url': ?profile.avatarUrl,
          'has_pin': profile.hasPin,
          'is_child': profile.isChild,
          'is_primary': profile.isPrimary,
        },
    ],
  });

  static SiloHousehold? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final account = SiloAccount.fromJson(json['account']);
      final profiles = json['profiles'];
      if (account == null || profiles is! List) return null;
      return SiloHousehold(account, [for (final profile in profiles) ?SiloProfile.fromJson(profile)]);
    } on FormatException {
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _epoch++;
    unawaited(_connSub?.cancel());
    _connSub = null;
    unawaited(_controller.close());
  }
}
