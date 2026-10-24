import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import '../connection/connection.dart';
import '../media/ids.dart';
import '../media/media_server_client.dart';
import '../utils/active_client_scope.dart';
import '../utils/app_logger.dart';
import 'connectivity_probe.dart';
import 'silo_client.dart';

/// Holds the signed-in Silo servers' clients and their health.
///
/// The map and public accessors are typed against the [MediaServerClient]
/// interface so consumers don't depend on the concrete client.
class MultiServerManager {
  MultiServerManager({
    Stream<List<ConnectivityResult>> Function()? connectivityChanges,
    this._connectivityDebounceDuration = const Duration(seconds: 2),
  }) : _connectivityChanges = connectivityChanges ?? _defaultConnectivityChanges;

  static Stream<List<ConnectivityResult>> _defaultConnectivityChanges() => ConnectivityProbe.changes;

  final Stream<List<ConnectivityResult>> Function() _connectivityChanges;
  final Duration _connectivityDebounceDuration;

  final Map<String, MediaServerClient> _clients = {};

  final Map<String, bool> _serverStatus = {};

  /// Servers whose last probe was answered with a refusal, and which one:
  /// [HealthStatus.authError] (HTTP 401 — the token is expired or revoked, and
  /// a new sign-in fixes it) or [HealthStatus.accessDenied] (HTTP 403 — the
  /// server knows the account and refuses it, and a new sign-in does not).
  /// Holds no other status. These rows also have `_serverStatus[serverId] ==
  /// false` — a refusal is a *kind* of offline.
  final Map<String, HealthStatus> _refusedServers = {};

  final _statusController = StreamController<Map<String, bool>>.broadcast();

  Stream<Map<String, bool>> get statusStream => _statusController.stream;

  /// Publish a snapshot of the per-server online map — subscribers must never
  /// receive the live [_serverStatus] instance. A no-op once [shutdown] or
  /// [dispose] closed the controller, so a health probe or reconnect landing
  /// mid-exit cannot throw into a closed stream.
  void _emitStatus() {
    if (_statusController.isClosed) return;
    _statusController.add(Map.from(_serverStatus));
  }

  /// Per-server connect progress during a bind. Unlike [statusStream] — whose
  /// first emission means "the binder's first connect pass finished" and which
  /// triggers libraries/live-tv work per emission — this fires as each
  /// individual server lands so the startup splash can flip its checkmarks
  /// incrementally without disturbing those contracts.
  final _connectProgressController = StreamController<({String serverId, bool online})>.broadcast();

  Stream<({String serverId, bool online})> get connectProgressStream => _connectProgressController.stream;

  /// Servers whose token was rejected (HTTP 401). A re-auth flow should be
  /// offered for these — they remain "offline" until the user signs in again.
  /// Cleared once a probe succeeds.
  Set<String> get authErrorServerIds => _refusedServerIdsOf(HealthStatus.authError);

  /// Servers that know this account and refuse it (HTTP 403), such as a
  /// user denied remote access or outside their parental schedule. A
  /// new sign-in cannot help; the server owner or the network the device is on
  /// can. Cleared once a probe succeeds.
  Set<String> get accessDeniedServerIds => _refusedServerIdsOf(HealthStatus.accessDenied);

  /// Servers that answered and refuse this account, for either reason:
  /// reachable, so never a connectivity failure, and unusable until the
  /// refusal clears.
  Set<String> get refusedServerIds => Set.unmodifiable(_refusedServers.keys.toSet());

  Set<String> _refusedServerIdsOf(HealthStatus kind) => Set.unmodifiable({
    for (final MapEntry(:key, :value) in _refusedServers.entries)
      if (value == kind) key,
  });

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _connectivityDebounce;
  Future<void>? _activeHealthCheck;

  /// Ids of the servers with a client.
  List<String> get serverIds => _clients.keys.toList();

  /// Every server id the manager holds state for: live clients plus status
  /// left by one. Profile clean-up walks this set rather than [serverIds].
  List<String> get registeredServerIds => {..._clients.keys, ..._serverStatus.keys}.toList();

  /// Whether the client registered under [serverId] belongs to a profile
  /// other than [profileId] (a client scope `silo:<server_id>/<profile_id>`).
  bool isRegisteredForOtherProfile(ServerId serverId, {required String profileId}) {
    final client = _clients[serverId];
    return client is SiloClient && client.cacheServerId != profileId;
  }

  List<String> get onlineServerIds => _serverStatus.entries.where((e) => e.value).map((e) => e.key).toList();

  List<String> get offlineServerIds => _serverStatus.entries.where((e) => !e.value).map((e) => e.key).toList();

  MediaServerClient? getClient(ServerId serverId) => _clients[serverId];

  /// Resolve an exact private client namespace without falling back to a
  /// different active user on the same public server.
  MediaServerClient? getClientByScope(String clientScopeId) {
    final siloScope = SiloProfileScopeId.tryParse(clientScopeId);
    if (siloScope == null) return null;
    final client = _clients[siloScope.publicServerId];
    return client is SiloClient && client.cacheServerId == clientScopeId ? client : null;
  }

  /// Server ids visible to the active profile; `null` means no restriction.
  /// Owned here rather than on `MultiServerProvider` so non-UI consumers
  /// (the download client resolver) apply the same filter the UI does —
  /// the provider delegates its filter state to this field.
  Set<String>? _visibleServerIds;

  Set<String>? get visibleServerIds => _visibleServerIds;

  final _visibilityController = StreamController<void>.broadcast();

  /// Fires when [visibleServerIds] changes. Kept off [statusStream], whose
  /// emissions mean "a connect pass settled" to the startup splash and the
  /// offline-mode detector.
  Stream<void> get visibilityChanges => _visibilityController.stream;

  void setVisibleServerIds(Set<String>? ids) {
    if (setEquals(_visibleServerIds, ids)) return;
    _visibleServerIds = ids;
    if (!_visibilityController.isClosed) _visibilityController.add(null);
  }

  bool isServerVisible(ServerId serverId) => _visibleServerIds?.contains(serverId) ?? true;

  /// Resolve the client for a queued download. A supplied private namespace
  /// must match exactly; falling back to another active user would run work
  /// under the wrong authenticated identity.
  MediaServerClient? resolveDownloadClient(ServerId serverId, {String? clientScopeId}) {
    if (!isServerVisible(serverId)) return null;
    if (clientScopeId != null && clientScopeId.isNotEmpty) {
      final scoped = getClientByScope(clientScopeId);
      return scoped?.serverId == serverId ? scoped : null;
    }
    return getClient(serverId);
  }

  @visibleForTesting
  void debugRegisterClientForTesting(MediaServerClient client, {bool online = true}) {
    _clients[client.serverId] = client;
    _serverStatus[client.serverId] = online;
  }

  @visibleForTesting
  void debugMarkAuthErrorForTesting(ServerId serverId) {
    _serverStatus[serverId] = false;
    _refusedServers[serverId] = HealthStatus.authError;
    _emitStatus();
  }

  @visibleForTesting
  void debugMarkAccessDeniedForTesting(ServerId serverId) {
    _serverStatus[serverId] = false;
    _refusedServers[serverId] = HealthStatus.accessDenied;
    _emitStatus();
  }

  /// Re-publish the current status snapshot so tests can drive
  /// [statusStream]-reactive services after `debugRegister*ForTesting`.
  @visibleForTesting
  void debugEmitStatusForTesting() => _emitStatus();

  String serverDisplayName(ServerId serverId) => _clients[serverId]?.serverName ?? serverId;

  Map<String, MediaServerClient> get onlineClients {
    final result = <String, MediaServerClient>{};
    for (final serverId in onlineServerIds) {
      final client = _clients[serverId];
      if (client != null) {
        result[serverId] = client;
      }
    }
    return result;
  }

  /// [onlineClients] restricted to the active profile's visibility filter —
  /// what cross-server readers (hubs, search, push channels, shelves) fan out
  /// to, so a registration the profile does not own is never queried.
  Map<String, MediaServerClient> get visibleOnlineClients => {
    for (final entry in onlineClients.entries)
      if (isServerVisible(ServerId(entry.key))) entry.key: entry.value,
  };

  bool isServerOnline(ServerId serverId) => _serverStatus[serverId] ?? false;

  /// Check whether the active or exact scoped client for [serverId] is online.
  bool isClientOnline(ServerId serverId, {String? clientScopeId}) {
    if (clientScopeId != null && clientScopeId.isNotEmpty) {
      final client = getClientByScope(clientScopeId);
      if (client == null || client.serverId != serverId) return false;
    }
    return isServerOnline(serverId);
  }

  /// Connect [connection] as the Silo profile [profileId]. True when the
  /// server answered as online.
  Future<bool> addSiloConnection(SiloConnection connection, {required String profileId}) async {
    try {
      final client = await SiloClient.create(connection, profileId: profileId);
      final serverId = client.serverId;
      final oldClient = _clients[serverId];
      _clients[serverId] = client;
      if (oldClient != null) unawaited(_closeClientGracefully(oldClient));

      final health = await client.checkHealth();
      if (!identical(_clients[serverId], client)) return health == HealthStatus.online;
      _applyHealth(serverId, health);
      appLogger.i('Added Silo server: ${connection.serverName} (${health.name})');
      return health == HealthStatus.online;
    } catch (e, stackTrace) {
      appLogger.e('Failed to add Silo server ${connection.serverName}', error: e, stackTrace: stackTrace);
      return false;
    }
  }

  void removeServer(ServerId serverId) {
    final activeClient = _forgetServer(serverId);
    if (activeClient != null) unawaited(_closeClientGracefully(activeClient));
    _emitStatus();
    appLogger.i('Removed server: $serverId');
  }

  MediaServerClient? _forgetServer(String serverId) {
    final client = _clients.remove(serverId);
    _serverStatus.remove(serverId);
    _refusedServers.remove(serverId);
    return client;
  }

  /// Close [client], draining in-flight requests when it supports it. Callers
  /// that do not need to wait wrap the call in `unawaited(...)`.
  Future<void> _closeClientGracefully(
    MediaServerClient client, {
    Duration drainTimeout = const Duration(seconds: 2),
  }) async {
    if (client case final GracefullyCloseable graceful) {
      await graceful.closeGracefully(drainTimeout: drainTimeout);
    } else {
      client.close();
    }
  }

  /// Update server status (used for health monitoring).
  ///
  /// Clears the auth-error flag — callers that observed an auth failure
  /// should use [_applyHealth] instead.
  void updateServerStatus(ServerId serverId, bool isOnline) =>
      _applyHealth(serverId, isOnline ? HealthStatus.online : HealthStatus.offline);

  /// Apply a health-probe outcome to both online state and auth-error
  /// tracking. Used by the manager's own health checks; external callers
  /// without an auth-distinct signal should use [updateServerStatus].
  void _applyHealth(ServerId serverId, HealthStatus status) {
    final isOnline = status == HealthStatus.online;
    final refusal = status == HealthStatus.authError || status == HealthStatus.accessDenied ? status : null;
    final prevOnline = _serverStatus[serverId];
    final prevRefusal = _refusedServers[serverId];

    _serverStatus[serverId] = isOnline;
    if (refusal != null) {
      _refusedServers[serverId] = refusal;
    } else {
      _refusedServers.remove(serverId);
    }

    final changed = prevOnline != isOnline || prevRefusal != refusal;
    if (changed) {
      _emitStatus();
      switch (refusal) {
        case HealthStatus.authError:
          appLogger.w('Server $serverId auth rejected — token expired or revoked');
        case HealthStatus.accessDenied:
          appLogger.w('Server $serverId refused this account (HTTP 403)');
        case _:
          appLogger.d('Server $serverId status changed to: $isOnline');
      }
    }

    // The offline verdict rests on connectivity changes re-probing every
    // server, so monitoring must run whenever a server is online — including
    // one that came online through a reconnect or health probe after a
    // session that started with everything unreachable (#2505).
    if (isOnline && _connectivitySubscription == null && _clients.containsKey(serverId)) {
      _startNetworkMonitoring();
    }
  }

  /// Test connection health for all servers. The probe reads the signed-in
  /// session, so a revoked token is reported as a refusal.
  Future<void> checkServerHealth() async {
    // Coalesce concurrent calls — return the in-flight future if one exists
    if (_activeHealthCheck != null) return _activeHealthCheck!;

    _activeHealthCheck = _doCheckServerHealth();
    try {
      await _activeHealthCheck;
    } finally {
      _activeHealthCheck = null;
    }
  }

  Future<void> _doCheckServerHealth() async {
    appLogger.d('Checking health for ${_clients.length} servers');

    final healthChecks = _clients.entries.map((entry) async {
      final serverId = entry.key;
      final client = entry.value;

      final status = await client.checkHealth();
      // A profile switch or reconnect can replace (or remove) the client
      // while its probe is in flight; the old client's verdict says nothing
      // about the new one, which may run under a different token.
      if (!identical(_clients[serverId], client)) {
        appLogger.d('Ignoring stale health result for $serverId');
        return;
      }
      _applyHealth(ServerId(serverId), status);
      if (status != HealthStatus.online) {
        appLogger.w('Server $serverId health check failed: ${status.name}');
      }
    });

    await Future.wait(healthChecks);
  }

  /// Start monitoring network connectivity for all servers
  void _startNetworkMonitoring() {
    if (_connectivitySubscription != null) {
      appLogger.d('Network monitoring already active');
      return;
    }

    appLogger.i('Starting network monitoring for all servers');
    try {
      _connectivitySubscription = _connectivityChanges().listen(
        (results) {
          final status = results.isNotEmpty ? results.first : ConnectivityResult.none;

          // `none` re-probes like any other change instead of pausing: it means
          // "no internet-capable adapter", not "no route to the server". The
          // health check drops servers that really became unreachable (the
          // offline verdict rests on exactly that) and keeps loopback or
          // LAN-without-WAN servers online (#2505).
          // Debounce rapid connectivity events (e.g. WiFi flapping) into a single trigger
          _connectivityDebounce?.cancel();
          _connectivityDebounce = Timer(_connectivityDebounceDuration, () {
            _connectivityDebounce = null;

            appLogger.d(
              'Connectivity change detected, re-probing all servers',
              error: {
                'status': status.name,
                'interfaces': results.map((r) => r.name).toList(),
                'serverCount': _clients.length,
              },
            );
            checkServerHealth();
          });
        },
        onError: (error, stackTrace) {
          appLogger.w('Connectivity listener error', error: error, stackTrace: stackTrace);
        },
      );
    } catch (e) {
      appLogger.w('Connectivity monitoring unavailable', error: e);
    }
  }

  /// Stop monitoring network connectivity
  void _stopNetworkMonitoring() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    _connectivityDebounce?.cancel();
    _connectivityDebounce = null;
    appLogger.i('Stopped network monitoring');
  }

  /// Re-probe every offline server. A Silo client reconnects on its next
  /// request, so a successful probe is the whole reconnect.
  Future<void> reconnectOfflineServers() async {
    if (offlineServerIds.isEmpty) return;
    await checkServerHealth();
  }

  /// Disconnect all servers, fire-and-forget.
  ///
  /// Registrations are dropped synchronously ([_detachAllClients] runs before
  /// the first await); only the socket drain is left running in the background.
  void disconnectAll() {
    unawaited(disconnectAllGracefully(drainTimeout: const Duration(seconds: 2)));
  }

  Future<void> disconnectAllGracefully({Duration drainTimeout = const Duration(seconds: 5)}) async {
    appLogger.i('Gracefully disconnecting all servers');
    final clients = _detachAllClients();
    await Future.wait(
      clients.map((client) => _closeClientGracefully(client, drainTimeout: drainTimeout)),
      eagerError: false,
    );
  }

  Set<MediaServerClient> _detachAllClients() {
    _stopNetworkMonitoring();
    _activeHealthCheck = null;
    final clients = <MediaServerClient>{..._clients.values};
    _clients.clear();
    _serverStatus.clear();
    _refusedServers.clear();
    if (!_statusController.isClosed) {
      _statusController.add({});
    }
    return clients;
  }

  /// Terminal app-exit teardown: closes the status streams first, then drains
  /// every client connection.
  ///
  /// Unlike [disconnectAllGracefully] — whose empty snapshot profile-switch
  /// and disconnect flows must observe — exit teardown must stay invisible:
  /// the widget tree is still mounted while the exit request is serviced, and
  /// an empty snapshot reads as "all servers gone", flipping the app into
  /// offline UI and dismantling screens mid-shutdown.
  Future<void> shutdown({Duration drainTimeout = const Duration(seconds: 5)}) async {
    if (!_statusController.isClosed) unawaited(_statusController.close());
    if (!_connectProgressController.isClosed) unawaited(_connectProgressController.close());
    if (!_visibilityController.isClosed) unawaited(_visibilityController.close());
    await disconnectAllGracefully(drainTimeout: drainTimeout);
  }

  void dispose() {
    disconnectAll();
    if (!_statusController.isClosed) {
      _statusController.close();
    }
    if (!_connectProgressController.isClosed) {
      _connectProgressController.close();
    }
    if (!_visibilityController.isClosed) {
      _visibilityController.close();
    }
  }
}
