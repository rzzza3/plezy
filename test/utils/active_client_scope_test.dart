import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/utils/active_client_scope.dart';

void main() {
  final serverId = ServerId('media-machine');

  group('resolveActiveClientScopeId', () {
    test('returns null before a client is bound', () {
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: null), isNull);
    });

    test('rejects an empty cache scope', () {
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: ''), isNull);
    });

    test('rejects the bare server scope', () {
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: 'media-machine'), isNull);
    });

    test('rejects empty and foreign compound scopes', () {
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: 'media-machine/'), isNull);
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: 'other-machine/user-a'), isNull);
    });
  });

  group('Silo profile scopes', () {
    test('are typed, deterministic, profile-specific, and publicly projected', () {
      final profileA = SiloProfileScopeId(serverId: serverId, profileId: 'profile-a');
      final profileB = SiloProfileScopeId(serverId: serverId, profileId: 'profile-b');

      expect(profileA, 'silo:media-machine/profile-a');
      expect(profileA, SiloProfileScopeId(serverId: serverId, profileId: 'profile-a'));
      expect(profileA, isNot(profileB));
      expect(profileA.publicServerId, serverId);
      expect(profileA.profileId, 'profile-a');
      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: profileA), profileA);
    });

    test('a scope of another server does not resolve', () {
      final foreign = SiloProfileScopeId(serverId: ServerId('other-machine'), profileId: 'profile-a');

      expect(resolveActiveClientScopeId(serverId: serverId, cacheServerId: foreign), isNull);
    });

    test('rejects malformed persisted scopes before getters can throw', () {
      for (final malformed in ['silo:', 'silo:/profile-a', 'silo:media-machine/', 'silo:a/b/c', 'media-machine/a']) {
        expect(SiloProfileScopeId.tryParse(malformed), isNull, reason: malformed);
        expect(
          resolveActiveClientScopeId(serverId: serverId, cacheServerId: malformed),
          isNull,
          reason: malformed,
        );
      }
    });
  });
}
