import '../media/media_backend.dart';

/// A media server connection — a unit of authentication the user added.
///
/// A [SiloConnection] is one Silo server the person signed in to. Most users
/// only ever add one connection.
sealed class Connection {
  String get id;
  MediaBackend get kind;
  String get displayName;
  DateTime get createdAt;
  DateTime? get lastAuthenticatedAt;

  /// Alias for [kind] kept for UI call sites that read "backend"
  /// (badges, etc.).
  MediaBackend get backend => kind;

  /// Primary label shown in connection-list UIs: the server name.
  String get displayLabel;

  /// Secondary line shown beneath [displayLabel] in connection-list UIs:
  /// `username · origin`. May be null when no useful subtitle exists.
  String? get displaySubtitle;

  /// Backend-specific config payload, persisted as JSON. Each subclass
  /// defines the schema.
  Map<String, Object?> toConfigJson();
}

/// A Silo server the person signed in to. Holds no credential: the tokens and
/// the selected profile's token live in the server's vault-protected session
/// slot.
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

  /// `id` from `/api/v2/account/me`. With [serverId] it keys the companion
  /// remote's shared secret. Empty for connections persisted before S9 until
  /// the next household read fills it in.
  final String accountId;

  SiloConnection({
    required this.origin,
    required this.serverId,
    required this.serverName,
    required this.username,
    this.accountId = '',
    required this.createdAt,
    this.lastAuthenticatedAt,
  }) : id = idFor(serverId);

  SiloConnection copyWith({String? username, String? accountId, DateTime? lastAuthenticatedAt}) => SiloConnection(
    origin: origin,
    serverId: serverId,
    serverName: serverName,
    username: username ?? this.username,
    accountId: accountId ?? this.accountId,
    createdAt: createdAt,
    lastAuthenticatedAt: lastAuthenticatedAt ?? this.lastAuthenticatedAt,
  );

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
    if (accountId.isNotEmpty) 'accountId': accountId,
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
      accountId: json['accountId'] as String? ?? '',
      createdAt: createdAt,
      lastAuthenticatedAt: lastAuthenticatedAt,
    );
  }
}
