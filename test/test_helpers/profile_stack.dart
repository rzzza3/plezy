import 'package:drift/native.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/connection/connection_registry.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/profiles/active_profile_provider.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/silo_household_service.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/silo/silo_profiles.dart';

/// A household with one account and [profiles] (id, name) pairs; the first
/// is the primary profile.
SiloHousehold testHousehold(
  List<(String, String)> profiles, {
  String accountId = 'acct-1',
  String username = 'alice',
}) => SiloHousehold(SiloAccount(id: accountId, username: username, role: 'admin'), [
  for (final (index, (id, name)) in profiles.indexed) SiloProfile(id: id, name: name, isPrimary: index == 0),
]);

/// A signed-in Silo server, as sign-in stores it.
SiloConnection testSiloConnection(String serverId, {String? serverName, String accountId = 'acct-1'}) => SiloConnection(
  origin: 'https://$serverId.example',
  serverId: serverId,
  serverName: serverName ?? serverId,
  username: 'alice',
  accountId: accountId,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

/// The profile dependency graph wired the way production wires it: database →
/// [ConnectionRegistry] → [SiloHouseholdService] → [ActiveProfileProvider].
///
/// Households come from [households] (keyed by connection id) instead of the
/// network; [sessionProfiles] stands in for each server's session profile.
class ProfileStack {
  ProfileStack._({
    required this.db,
    required this.connections,
    required this.households,
    required this.active,
    required this.serverHouseholds,
    required this.sessionProfiles,
    required this._storage,
    required this._ownsDatabase,
  });

  final AppDatabase db;
  final ConnectionRegistry connections;
  final SiloHouseholdService households;
  final ActiveProfileProvider active;

  /// What each server's `/account/me` + `/profiles` read returns, by
  /// connection id. Mutable so a test can change the server's answer.
  final Map<String, SiloHousehold> serverHouseholds;

  /// The profile id each server's session has selected, by connection id.
  final Map<String, String> sessionProfiles;

  final StorageService? _storage;
  final bool _ownsDatabase;

  /// Only wired when the stack was created with `withStorage: true`.
  StorageService get storage => _storage!;

  /// Pass [db] when the test also needs the database for caches or downloads;
  /// the caller then owns closing it.
  static Future<ProfileStack> create({AppDatabase? db, bool withStorage = true}) async {
    final database = db ?? AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(database);
    final storage = withStorage ? await StorageService.getInstance() : null;
    final serverHouseholds = <String, SiloHousehold>{};
    final sessionProfiles = <String, String>{};
    final households = SiloHouseholdService(
      connections: connections,
      loader: (connection) async => serverHouseholds[connection.id],
      sessionProfile: (connection) async => sessionProfiles[connection.id],
    );
    return ProfileStack._(
      db: database,
      connections: connections,
      households: households,
      active: ActiveProfileProvider(households: households, connections: connections, storage: storage),
      serverHouseholds: serverHouseholds,
      sessionProfiles: sessionProfiles,
      storage: storage,
      ownsDatabase: db == null,
    );
  }

  /// Sign in to [serverId] with [household] cached, the way sign-in leaves
  /// it, and return the stored connection.
  Future<SiloConnection> addServer(String serverId, SiloHousehold household, {String? serverName}) async {
    final connection = testSiloConnection(serverId, serverName: serverName, accountId: household.account.id);
    serverHouseholds[connection.id] = household;
    await connections.upsert(connection);
    await households.put(connection, household);
    await active.reloadFromStorage();
    return connection;
  }

  /// The [Profile] for [siloProfileId] on [serverId] as the provider lists it.
  Profile profile(String serverId, String siloProfileId) =>
      active.profiles.firstWhere((p) => p.serverId == serverId && p.siloProfileId == siloProfileId);

  Future<void> dispose() async {
    await active.resetForTesting();
    active.dispose();
    households.dispose();
    if (_ownsDatabase) await db.close();
  }
}
