import '../media/ids.dart';

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
  final siloScope = SiloProfileScopeId.tryParse(cacheServerId);
  if (siloScope != null) return siloScope.publicServerId == serverId ? siloScope : null;
  return null;
}
