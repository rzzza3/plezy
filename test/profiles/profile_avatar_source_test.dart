import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/models/plex/plex_home_user.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/profiles/profile_avatar_source.dart';
import 'package:plezy/profiles/profile_connection.dart';

SiloConnection _silo(String serverId, {required DateTime createdAt}) {
  return SiloConnection(
    origin: 'https://silo.example',
    serverId: serverId,
    serverName: 'Silo',
    username: 'Agent',
    createdAt: createdAt,
  );
}

PlexAccountConnection _plex(String id, {required DateTime createdAt}) {
  return PlexAccountConnection(
    id: id,
    accountToken: 'token-$id',
    clientIdentifier: 'client-$id',
    accountLabel: 'Plex',
    createdAt: createdAt,
  );
}

PlexHomeUser _homeUser(String uuid, {String thumb = ''}) {
  return PlexHomeUser(
    id: 1,
    uuid: uuid,
    title: 'Home $uuid',
    thumb: thumb,
    hasPassword: false,
    restricted: false,
    updatedAt: null,
    admin: false,
    guest: false,
    protected: false,
  );
}

/// One home user, `home-a`, carrying [thumb]: what a link to [_plex] borrows.
List<PlexHomeUser> _avatarHome(String thumb) => [_homeUser('home-a', thumb: thumb)];

ProfileConnection _link(String connectionId, {String profileId = 'local-1', String userIdentifier = 'home-a'}) {
  return ProfileConnection(profileId: profileId, connectionId: connectionId, userIdentifier: userIdentifier);
}

Profile _local([String id = 'local-1']) => Profile.local(id: id, displayName: 'Owner', createdAt: DateTime(2026, 1, 1));

String? _resolve({
  required List<Profile> profiles,
  required Map<String, List<ProfileConnection>> links,
  required Map<String, Connection> connections,
  Map<String, List<PlexHomeUser>> plexHome = const {},
  String profileId = 'local-1',
}) {
  return resolveProfileAvatarUrls(
    profiles: profiles,
    connectionsByProfile: links,
    connectionsById: connections,
    plexHomeByConnectionId: plexHome,
  )[profileId];
}

void main() {
  group('resolveProfileAvatarUrls', () {
    test('uses the picture of the oldest linked connection', () {
      final older = _plex('plex-older', createdAt: DateTime(2026, 1, 1));
      final newer = _plex('plex-newer', createdAt: DateTime(2026, 6, 1));

      final url = _resolve(
        profiles: [_local()],
        // Deliberately newest-first: the registry stream has no ordering
        // guarantee, so resolution must sort rather than take the head.
        links: {
          'local-1': [_link('plex-newer'), _link('plex-older')],
        },
        connections: {'plex-older': older, 'plex-newer': newer},
        plexHome: {'plex-older': _avatarHome('older-avatar'), 'plex-newer': _avatarHome('newer-avatar')},
      );

      expect(url, 'older-avatar');
    });

    test('falls back to initials when the first connection has no picture', () {
      final first = _silo('silo-first', createdAt: DateTime(2026, 1, 1));
      final second = _plex('plex-second', createdAt: DateTime(2026, 6, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link(first.id), _link('plex-second')],
        },
        connections: {first.id: first, 'plex-second': second},
        plexHome: {'plex-second': _avatarHome('second-avatar')},
      );

      // "First wins" is literal: we do not skip ahead to a later connection
      // that happens to have an image.
      expect(url, isNull);
    });

    test('breaks a createdAt tie on connection id so the choice is stable', () {
      final sameInstant = DateTime(2026, 1, 1);
      final b = _plex('plex-b', createdAt: sameInstant);
      final a = _plex('plex-a', createdAt: sameInstant);

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link('plex-b'), _link('plex-a')],
        },
        connections: {'plex-b': b, 'plex-a': a},
        plexHome: {'plex-b': _avatarHome('b-avatar'), 'plex-a': _avatarHome('a-avatar')},
      );

      expect(url, 'a-avatar');
    });

    test('ignores links whose connection is gone, including for ordering', () {
      final survivor = _plex('plex-survivor', createdAt: DateTime(2026, 6, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link('plex-removed'), _link('plex-survivor')],
        },
        connections: {'plex-survivor': survivor},
        plexHome: {'plex-survivor': _avatarHome('survivor-avatar')},
      );

      expect(url, 'survivor-avatar');
    });

    test('resolves a Plex link through the home user the link points at', () {
      final plex = _plex('plex-1', createdAt: DateTime(2026, 1, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link('plex-1', userIdentifier: 'home-b')],
        },
        connections: {'plex-1': plex},
        plexHome: {
          'plex-1': [
            _homeUser('home-a', thumb: 'https://plex.tv/users/home-a/avatar'),
            _homeUser('home-b', thumb: 'https://plex.tv/users/home-b/avatar'),
          ],
        },
      );

      expect(url, 'https://plex.tv/users/home-b/avatar');
    });

    test('gives no picture for a Plex link with no home user selected', () {
      final plex = _plex('plex-1', createdAt: DateTime(2026, 1, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link('plex-1', userIdentifier: '')],
        },
        connections: {'plex-1': plex},
        plexHome: {
          'plex-1': [_homeUser('home-a', thumb: 'https://plex.tv/users/home-a/avatar')],
        },
      );

      expect(url, isNull);
    });

    test('gives no picture when the selected home user has a blank thumb', () {
      final plex = _plex('plex-1', createdAt: DateTime(2026, 1, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link('plex-1', userIdentifier: 'home-a')],
        },
        connections: {'plex-1': plex},
        plexHome: {
          'plex-1': [_homeUser('home-a')],
        },
      );

      expect(url, isNull);
    });

    test('mixed Silo and Plex links still resolve by creation order', () {
      final plexFirst = _plex('plex-1', createdAt: DateTime(2026, 1, 1));
      final siloSecond = _silo('silo-1', createdAt: DateTime(2026, 6, 1));

      final url = _resolve(
        profiles: [_local()],
        links: {
          'local-1': [_link(siloSecond.id), _link('plex-1', userIdentifier: 'home-a')],
        },
        connections: {'plex-1': plexFirst, siloSecond.id: siloSecond},
        plexHome: {
          'plex-1': [_homeUser('home-a', thumb: 'https://plex.tv/users/home-a/avatar')],
        },
      );

      expect(url, 'https://plex.tv/users/home-a/avatar');
    });

    test('leaves a Plex Home profile on its own thumb', () {
      final plexHomeProfile = Profile.virtualPlexHome(
        connectionId: 'plex-1',
        homeUser: _homeUser('home-a', thumb: 'https://plex.tv/users/home-a/avatar'),
      );
      final borrowed = _plex('plex-2', createdAt: DateTime(2026, 1, 1));

      final url = _resolve(
        profiles: [plexHomeProfile],
        links: {
          plexHomeProfile.id: [_link('plex-2', profileId: plexHomeProfile.id)],
        },
        connections: {'plex-2': borrowed},
        plexHome: {'plex-2': _avatarHome('borrowed-avatar')},
        profileId: plexHomeProfile.id,
      );

      expect(url, 'https://plex.tv/users/home-a/avatar');
    });

    test('a Plex Home profile with no avatar keeps its initials rather than borrowing one', () {
      final plexHomeProfile = Profile.virtualPlexHome(connectionId: 'plex-1', homeUser: _homeUser('home-a'));
      final borrowed = _plex('plex-2', createdAt: DateTime(2026, 1, 1));

      final url = _resolve(
        profiles: [plexHomeProfile],
        links: {
          plexHomeProfile.id: [_link('plex-2', profileId: plexHomeProfile.id)],
        },
        connections: {'plex-2': borrowed},
        plexHome: {'plex-2': _avatarHome('borrowed-avatar')},
        profileId: plexHomeProfile.id,
      );

      // Plex owns this identity end to end; "nothing changes" for Plex Home
      // profiles means a blank thumb stays blank, not that it picks up the
      // picture of a lent connection.
      expect(url, isNull);
    });

    test('gives no picture to a profile with no links', () {
      expect(_resolve(profiles: [_local()], links: const {}, connections: const {}), isNull);
    });

    test('covers every profile so callers can look up by id', () {
      final map = resolveProfileAvatarUrls(
        profiles: [_local('local-1'), _local('local-2')],
        connectionsByProfile: const {},
        connectionsById: const {},
        plexHomeByConnectionId: const {},
      );

      expect(map.keys, containsAll(['local-1', 'local-2']));
    });
  });
}
