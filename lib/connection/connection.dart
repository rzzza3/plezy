import '../media/media_backend.dart';
import '../models/plex/plex_home_user.dart';
import '../services/plex_auth_service.dart';

/// A media server connection — a unit of authentication the user added.
///
/// A `PlexAccountConnection` carries one Plex account + its discovered servers + an
/// optional active Home profile. A `SiloConnection` is one Silo server the
/// person signed in to. Most users only ever add one connection.
sealed class Connection {
  String get id;
  MediaBackend get kind;
  String get displayName;
  DateTime get createdAt;
  DateTime? get lastAuthenticatedAt;

  /// Alias for [kind] kept for UI call sites that read "backend"
  /// (badges, etc.).
  MediaBackend get backend => kind;

  /// Primary label shown in connection-list UIs. Plex shows the active
  /// profile/account name; Silo shows the server name.
  String get displayLabel;

  /// Secondary line shown beneath [displayLabel] in connection-list UIs.
  /// Plex: server count; Silo: `username · origin`. May be null when
  /// no useful subtitle exists.
  String? get displaySubtitle;

  /// Backend-specific config payload, persisted as JSON. Each subclass
  /// defines the schema.
  Map<String, Object?> toConfigJson();
}

/// A Plex account connection.
///
/// Fields here mirror what [PlexAuthService] gathers during PIN OAuth: an
/// account token (long-lived), the per-device client identifier (so plex.tv
/// doesn't see a "new device" each launch), and the optional Home user the
/// user has switched into.
class PlexAccountConnection extends Connection {
  @override
  final String id;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// plex.tv account access token.
  final String accountToken;

  /// Per-device client identifier. Stable across launches.
  final String clientIdentifier;

  /// Display name shown for this connection (typically the Plex account email
  /// or username, fallback "Plex").
  final String accountLabel;

  /// Active Home user, or `null` for the main account.
  final PlexHomeUser? activeProfile;

  /// Servers discovered for this account (cached). Populated by the auth
  /// flow and refreshed periodically.
  final List<PlexServer> servers;

  PlexAccountConnection({
    required this.id,
    required this.accountToken,
    required this.clientIdentifier,
    required this.accountLabel,
    this.activeProfile,
    this.servers = const [],
    required this.createdAt,
    this.lastAuthenticatedAt,
  });

  @override
  MediaBackend get kind => MediaBackend.plex;

  @override
  String get displayName => activeProfile != null && activeProfile!.title.isNotEmpty
      ? '${activeProfile!.title} · $accountLabel'
      : accountLabel;

  @override
  String get displayLabel => displayName;

  @override
  String? get displaySubtitle => servers.length == 1 ? '1 Plex server' : '${servers.length} Plex servers';

  PlexAccountConnection copyWith({
    String? id,
    String? accountToken,
    String? clientIdentifier,
    String? accountLabel,
    PlexHomeUser? activeProfile,
    bool clearActiveProfile = false,
    List<PlexServer>? servers,
    DateTime? createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    return PlexAccountConnection(
      id: id ?? this.id,
      accountToken: accountToken ?? this.accountToken,
      clientIdentifier: clientIdentifier ?? this.clientIdentifier,
      accountLabel: accountLabel ?? this.accountLabel,
      activeProfile: clearActiveProfile ? null : (activeProfile ?? this.activeProfile),
      servers: servers ?? this.servers,
      createdAt: createdAt ?? this.createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
    );
  }

  @override
  Map<String, Object?> toConfigJson() {
    return {
      'accountToken': accountToken,
      'clientIdentifier': clientIdentifier,
      'accountLabel': accountLabel,
      'activeProfile': activeProfile?.toJson(),
      'servers': servers.map((s) => s.toJson()).toList(),
    };
  }

  factory PlexAccountConnection.fromConfigJson({
    required String id,
    required Map<String, Object?> json,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    final profileJson = json['activeProfile'];
    final activeProfile = profileJson is Map<String, dynamic> ? PlexHomeUser.fromJson(profileJson) : null;
    final serversJson = json['servers'];
    final servers = serversJson is List
        ? serversJson.whereType<Map<String, dynamic>>().map(PlexServer.fromJson).toList()
        : <PlexServer>[];
    return PlexAccountConnection(
      id: id,
      accountToken: json['accountToken'] as String? ?? '',
      clientIdentifier: json['clientIdentifier'] as String? ?? '',
      accountLabel: json['accountLabel'] as String? ?? 'Plex',
      activeProfile: activeProfile,
      servers: servers,
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}

/// A Silo server the person signed in to. Holds no credential: the tokens and
/// the selected profile's token live in the server's vault-protected session
/// slot, and the join row names the profile.
class SiloConnection extends Connection {
  @override
  final String id;

  @override
  final DateTime createdAt;

  @override
  final DateTime? lastAuthenticatedAt;

  /// Canonical origin, e.g. `https://silo.example.com`.
  final String origin;

  /// `server_id` from `/api/v2/system/identity`.
  final String serverId;

  final String serverName;

  /// The account's username, for display.
  final String username;

  SiloConnection({
    required this.origin,
    required this.serverId,
    required this.serverName,
    required this.username,
    required this.createdAt,
    this.lastAuthenticatedAt,
  }) : id = idFor(serverId);

  /// One account per server per device, like Silo's own per-server slot.
  static String idFor(String serverId) => 'silo:$serverId';

  @override
  MediaBackend get kind => MediaBackend.silo;

  @override
  String get displayName => username.isEmpty ? serverName : '$username · $serverName';

  @override
  String get displayLabel => serverName;

  @override
  String? get displaySubtitle => username.isEmpty ? origin : '$username · $origin';

  @override
  Map<String, Object?> toConfigJson() => {
    'origin': origin,
    'serverId': serverId,
    'serverName': serverName,
    'username': username,
  };

  /// Null when the row lacks the origin or server id, so the registry drops
  /// it like any other undecodable row.
  static SiloConnection? fromConfigJson({
    required Map<String, Object?> json,
    required DateTime createdAt,
    DateTime? lastAuthenticatedAt,
  }) {
    final origin = json['origin'];
    final serverId = json['serverId'];
    if (origin is! String || origin.isEmpty || serverId is! String || serverId.isEmpty) return null;
    return SiloConnection(
      origin: origin,
      serverId: serverId,
      serverName: json['serverName'] as String? ?? 'Silo',
      username: json['username'] as String? ?? '',
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}
