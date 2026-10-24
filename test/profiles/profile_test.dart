import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/silo/silo_profiles.dart';

void main() {
  group('Profile', () {
    test('a Silo profile is identified by its client scope', () {
      final profile = Profile.fromSilo(
        serverId: 'srv-a',
        profile: const SiloProfile(id: 'p-2', name: 'Kids', hasPin: true, isChild: true),
        sortOrder: 1,
      );

      expect(profile.id, 'silo:srv-a/p-2');
      expect(profile.connectionId, 'silo:srv-a');
      expect(
        (profile.displayName, profile.isPinProtected, profile.isChild, profile.isPrimary),
        ('Kids', true, true, false),
      );
      expect(profile.sortOrder, 1);
    });

    test('copyWith keeps identity and equality follows every field', () {
      const profile = Profile(serverId: 'srv-a', siloProfileId: 'p-1', displayName: 'Owner');
      final used = profile.copyWith(lastUsedAt: DateTime(2026, 10, 22));

      expect(used.id, profile.id);
      expect(used, isNot(profile));
      expect(used.copyWith(), used);
      expect(used.copyWith().hashCode, used.hashCode);
    });

    test('profile-scoped preference keys carry the scope, or none when signed out', () {
      expect(profileScopedPrefsKey('silo:srv-a/p-1', 'seerr_session'), 'user_silo:srv-a/p-1_seerr_session');
      expect(profileScopedPrefsKey('', 'seerr_session'), 'seerr_session');
    });
  });
}
