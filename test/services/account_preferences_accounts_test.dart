import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/media/account_ref.dart';
import 'package:plezy/models/plex/plex_home_user.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_connection.dart';
import 'package:plezy/services/account_preferences_accounts.dart';

void main() {
  final home = PlexHomeProfile(
    id: 'home',
    displayName: 'Home user',
    parentConnectionId: 'parent',
    plexHomeUserUuid: 'home-user',
    createdAt: DateTime(2026),
  );
  final parent = PlexAccountConnection(
    id: 'parent',
    accountToken: 'owner-token',
    clientIdentifier: 'client',
    accountLabel: 'Plex parent',
    createdAt: DateTime(2026),
  );
  final borrowed = SiloConnection(
    origin: 'https://silo.example.com',
    serverId: 'silo-server',
    serverName: 'Silo',
    username: 'alice',
    createdAt: DateTime(2026),
  );
  final borrowedRow = ProfileConnection(
    profileId: home.id,
    connectionId: borrowed.id,
    userIdentifier: borrowed.username,
    isDefault: true,
  );
  final parentRow = ProfileConnection(
    profileId: home.id,
    connectionId: parent.id,
    userIdentifier: 'home-user',
    userToken: 'switched-token',
  );

  test('a persisted borrowed default does not take Home authority from its exact parent', () {
    final resolution = resolveAccountPreferenceAccounts(
      profile: home,
      profileConnections: [borrowedRow, parentRow],
      connections: [borrowed, parent],
    );
    expect(resolution.playbackRef, const AccountRef.plex(accountConnectionId: 'parent', homeUserUuid: 'home-user'));
    expect(resolution.accounts.last.plexToken, 'switched-token');
  });

  test('missing Home parent, row, principal or token never selects the borrowed default or owner', () {
    for (final (profile, rows, connections) in <(Profile, List<ProfileConnection>, List<Connection>)>[
      (home, [borrowedRow, parentRow], [borrowed]),
      (home, [borrowedRow], [borrowed, parent]),
      (home, [borrowedRow, parentRow.copyWith(userToken: null)], [borrowed, parent]),
      (home, [borrowedRow, parentRow.copyWith(userToken: '')], [borrowed, parent]),
      (home, [borrowedRow, parentRow.copyWith(userIdentifier: 'someone-else')], [borrowed, parent]),
      (home.copyWith(plexHomeUserUuid: null), [borrowedRow, parentRow], [borrowed, parent]),
      (home.copyWith(parentConnectionId: null), [borrowedRow, parentRow], [borrowed, parent]),
    ]) {
      final resolution = resolveAccountPreferenceAccounts(
        profile: profile,
        profileConnections: rows,
        connections: connections,
      );
      expect(resolution.playbackRef, isNull);
      expect(resolution.accounts, isEmpty);
    }
  });

  test('local switched principals come from each row rather than account activeProfile metadata', () {
    final local = Profile.local(id: 'local', displayName: 'Local', createdAt: DateTime(2026));
    final account = parent.copyWith(
      activeProfile: PlexHomeUser(
        id: 2,
        uuid: 'account-wide-user',
        title: 'Other user',
        thumb: '',
        hasPassword: false,
        restricted: false,
        updatedAt: null,
        admin: false,
        guest: false,
        protected: false,
      ),
    );
    final resolution = resolveAccountPreferenceAccounts(
      profile: local,
      profileConnections: [parentRow.copyWith(profileId: local.id, isDefault: true)],
      connections: [account],
    );
    expect(resolution.playbackRef, const AccountRef.plex(accountConnectionId: 'parent', homeUserUuid: 'home-user'));
    expect(resolution.accounts.single.plexToken, 'switched-token');
  });

  test('a missing local designated account does not promote another editable account', () {
    final local = Profile.local(id: 'local', displayName: 'Local', createdAt: DateTime(2026));
    final other = PlexAccountConnection(
      id: 'other',
      accountToken: 'other-token',
      clientIdentifier: 'client',
      accountLabel: 'Plex other',
      createdAt: DateTime(2026),
    );
    final resolution = resolveAccountPreferenceAccounts(
      profile: local,
      profileConnections: [
        parentRow.copyWith(profileId: local.id, isDefault: true),
        ProfileConnection(profileId: local.id, connectionId: other.id, userIdentifier: 'other-user'),
      ],
      connections: [other],
    );
    expect(resolution.playbackRef, isNull);
    expect(resolution.accounts.single.ref.connectionId, other.id);
  });

}
