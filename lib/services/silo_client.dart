import '../connection/connection.dart';
import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_server_client.dart';
import '../media/server_capabilities.dart';
import '../silo/silo_app.dart';
import '../silo/silo_http.dart';
import '../utils/app_logger.dart';

/// A Silo server bound to one profile. Carries the identity members only:
/// every catalog, playback and download member throws [UnsupportedError]
/// until the step that implements it lands (S3 onwards).
class SiloClient extends MediaServerClient implements ScopedMediaServerClient {
  final SiloConnection connection;
  final String profileId;
  final SiloHttp http;

  int _sessionGeneration = -1;
  Object _sessionIdentity = Object();
  bool _offline = false;

  SiloClient({required this.connection, required this.profileId, required this.http});

  /// Binds the server's session slot to [profileId]. A profile other than
  /// the one the slot holds is selected without a token; a PIN profile then
  /// needs the picker again.
  static Future<SiloClient> create(SiloConnection connection, {required String profileId}) async {
    final silo = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
    final session = silo.session.session;
    if (session != null && session.profileId != profileId) await silo.session.selectProfile(profileId, null);
    return SiloClient(connection: connection, profileId: profileId, http: silo);
  }

  @override
  ServerId get serverId => ServerId(connection.serverId);

  @override
  String? get serverName => connection.serverName;

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  String get scopedServerId => 'silo:${connection.serverId}/$profileId';

  @override
  Object get authenticationSessionId {
    final generation = http.session.generation;
    if (generation != _sessionGeneration) {
      _sessionGeneration = generation;
      _sessionIdentity = Object();
    }
    return _sessionIdentity;
  }

  @override
  bool get isOfflineMode => _offline;

  @override
  void setOfflineMode(bool offline) => _offline = offline;

  @override
  void close() => http.close();

  /// `GET /api/v2/account/me`, the lightest call that proves the bearer.
  @override
  Future<HealthStatus> checkHealth() async {
    try {
      final response = await http.send(const SiloRequest.get('/api/v2/account/me'));
      return switch (response.statusCode) {
        200 => HealthStatus.online,
        401 => HealthStatus.authError,
        403 => HealthStatus.accessDenied,
        _ => HealthStatus.offline,
      };
    } on SiloCredentialsRepudiatedException {
      return HealthStatus.authError;
    } on Exception {
      return HealthStatus.offline;
    }
  }

  @override
  Future<String?> getMachineIdentifier() async {
    try {
      final response = await http.send(const SiloRequest.get('/api/v2/system/identity', auth: SiloAuth.none));
      final json = response.statusCode == 200 ? response.json() : null;
      final id = json is Map ? json['server_id'] : null;
      return id is String && id.trim().isNotEmpty ? id.trim() : null;
    } on Exception {
      return null;
    }
  }

  /// Members the later steps implement fail as a rejected future, so an
  /// awaiting caller sees an ordinary error instead of a synchronous throw.
  @override
  dynamic noSuchMethod(Invocation invocation) {
    final error = UnsupportedError('SiloClient does not implement ${invocation.memberName} yet');
    if (invocation.isMethod) return Future<Never>.error(error);
    throw error;
  }
}

/// `POST /api/v2/auth/logout`, bounded, then the slot is wiped.
Future<void> signOutSiloSession(SiloHttp silo) async {
  if (silo.session.session != null) {
    try {
      final response = await silo
          .send(const SiloRequest.post('/api/v2/auth/logout', single: true, timeout: Duration(seconds: 10)))
          .timeout(const Duration(seconds: 10));
      appLogger.i('Silo: logout status ${response.statusCode}');
    } on Object catch (error) {
      // The local wipe below is what signs this device out.
      appLogger.i('Silo: logout failed (${error.runtimeType})');
    }
  }
  await silo.session.signOut();
}

Future<void> signOutSiloConnection(SiloConnection connection) async {
  final silo = await SiloApp.http(origin: Uri.parse(connection.origin), serverId: connection.serverId);
  try {
    await signOutSiloSession(silo);
  } finally {
    silo.close();
  }
}
