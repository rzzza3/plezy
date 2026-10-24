import '../media/ids.dart';

const _plexProfileScopeMarker = '/~plex-profile/';

const _plexTransferScopeSuffix = '/~plex-transfer';

/// Typed private cache namespace for one Plezy profile on a public Plex
/// server. The value is never a public media identity.
extension type const PlexProfileScopeId._(String value) implements String {
  factory PlexProfileScopeId({required ServerId serverId, required String profileId}) {
    if (profileId.isEmpty) {
      throw ArgumentError.value(profileId, 'profileId', 'must not be empty');
    }
    return PlexProfileScopeId._('$serverId$_plexProfileScopeMarker${Uri.encodeComponent(profileId)}');
  }

  static PlexProfileScopeId? tryParse(String value) {
    final markerIndex = value.indexOf(_plexProfileScopeMarker);
    if (markerIndex <= 0) return null;
    final serverId = ServerId.tryParse(value.substring(0, markerIndex));
    if (serverId == null) return null;
    final encodedProfileId = value.substring(markerIndex + _plexProfileScopeMarker.length);
    if (encodedProfileId.isEmpty || encodedProfileId.contains('/')) return null;
    try {
      if (Uri.decodeComponent(encodedProfileId).isEmpty) return null;
    } on FormatException {
      return null;
    }
    return PlexProfileScopeId._(value);
  }

  ServerId get publicServerId => ServerId(value.substring(0, value.indexOf(_plexProfileScopeMarker)));
  String get profileId =>
      Uri.decodeComponent(value.substring(value.indexOf(_plexProfileScopeMarker) + _plexProfileScopeMarker.length));
  ServerId get cacheServerId => ServerId(value);
}

/// Device-local namespace used only while a full logout has no profile owner.
///
/// Metadata copied here is stripped of profile-private watch/rating fields.
/// The next profile that adopts the physical download moves it into its own
/// [PlexProfileScopeId] before exposing it.
extension type const PlexTransferScopeId._(String value) implements String {
  factory PlexTransferScopeId(ServerId serverId) => PlexTransferScopeId._('$serverId$_plexTransferScopeSuffix');

  static PlexTransferScopeId? tryParse(String value) {
    if (!value.endsWith(_plexTransferScopeSuffix)) return null;
    final serverId = ServerId.tryParse(value.substring(0, value.length - _plexTransferScopeSuffix.length));
    return serverId == null ? null : PlexTransferScopeId._(value);
  }

  ServerId get publicServerId => ServerId(value.substring(0, value.length - _plexTransferScopeSuffix.length));
  ServerId get cacheServerId => ServerId(value);
}

PlexTransferScopeId buildPlexTransferScopeId(ServerId serverId) => PlexTransferScopeId(serverId);

PlexProfileScopeId buildPlexProfileScopeId({required ServerId serverId, required String profileId}) =>
    PlexProfileScopeId(serverId: serverId, profileId: profileId);

ServerId? publicPlexServerIdFromScope(String cacheServerId) =>
    PlexProfileScopeId.tryParse(cacheServerId)?.publicServerId;

ServerId? publicPlexServerIdFromCacheScope(String cacheServerId) =>
    publicPlexServerIdFromScope(cacheServerId) ?? PlexTransferScopeId.tryParse(cacheServerId)?.publicServerId;

bool isPlexProfileScopeId(String cacheServerId) => PlexProfileScopeId.tryParse(cacheServerId) != null;

const _siloScopePrefix = 'silo:';

/// Private namespace for one Silo profile on one Silo server, the
/// [SiloClient]'s `silo:<server_id>/<profile_id>` cache scope. Downloads,
/// their metadata and offline progress written under it are invisible to
/// every other profile.
extension type const SiloProfileScopeId._(String value) implements String {
  factory SiloProfileScopeId({required ServerId serverId, required String profileId}) {
    final scope = tryParse('$_siloScopePrefix$serverId/$profileId');
    if (scope == null) throw ArgumentError.value(profileId, 'profileId', 'is not a valid Silo profile id');
    return scope;
  }

  static SiloProfileScopeId? tryParse(String value) {
    if (!value.startsWith(_siloScopePrefix)) return null;
    final rest = value.substring(_siloScopePrefix.length);
    final slash = rest.indexOf('/');
    if (slash <= 0 || slash == rest.length - 1 || rest.indexOf('/', slash + 1) >= 0) return null;
    return ServerId.tryParse(rest.substring(0, slash)) == null ? null : SiloProfileScopeId._(value);
  }

  ServerId get publicServerId => ServerId(value.substring(_siloScopePrefix.length, value.indexOf('/')));
  String get profileId => value.substring(value.indexOf('/') + 1);
}

/// Returns the user-specific active client scope, or `null` when the client is
/// absent or only exposes the public server namespace.
String? resolveActiveClientScopeId({required ServerId serverId, required String? cacheServerId}) {
  if (cacheServerId == null) return null;
  final plexScope = PlexProfileScopeId.tryParse(cacheServerId);
  if (plexScope != null) return plexScope.publicServerId == serverId ? plexScope : null;
  if (PlexTransferScopeId.tryParse(cacheServerId) != null) return null;
  final siloScope = SiloProfileScopeId.tryParse(cacheServerId);
  if (siloScope != null) return siloScope.publicServerId == serverId ? siloScope : null;
  return null;
}
