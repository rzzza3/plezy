import 'media_backend.dart';

/// Identity of one media-server *account* whose preferences are stored on the
/// server (or on plex.tv) rather than on this device.
///
/// This is deliberately **not** [MediaServerClient.cacheServerId] /
/// `clientScopeId`. That value names a scoped client on one server, so a single
/// Plex account reachable through three servers would produce three of them —
/// while plex.tv stores exactly one preference set for that account's Home
/// user. The account is the unit of storage, so it is the unit of identity
/// here:
///
/// - Plex: one account per ([PlexAccountConnection], Home user) pair. Every
///   Home user has its own plex.tv profile, and the owner's token must never
///   be used to read or write a managed user's preferences.
class AccountRef {
  const AccountRef._(this.backend, this.connectionId, this.plexHomeUserUuid);

  /// A Plex account. [homeUserUuid] names the Home user whose profile is being
  /// read or written; null means the account owner signed in without Home.
  const AccountRef.plex({required String accountConnectionId, String? homeUserUuid})
    : this._(MediaBackend.plex, accountConnectionId, homeUserUuid);

  final MediaBackend backend;

  /// The owning [Connection.id]: `plex.<accountUuid>`.
  final String connectionId;

  /// Plex Home user uuid, when the account is used through a managed user.
  final String? plexHomeUserUuid;

  /// Stable cache/storage key. Contains no credentials — connection ids and
  /// Home uuids are identifiers, not secrets — so it is safe to log.
  String get key {
    final uuid = plexHomeUserUuid;
    return uuid == null || uuid.isEmpty ? connectionId : '$connectionId/~home/$uuid';
  }

  @override
  bool operator ==(Object other) =>
      other is AccountRef &&
      other.backend == backend &&
      other.connectionId == connectionId &&
      other.plexHomeUserUuid == plexHomeUserUuid;

  @override
  int get hashCode => Object.hash(backend, connectionId, plexHomeUserUuid);

  @override
  String toString() => 'AccountRef(${backend.id}, $key)';
}
