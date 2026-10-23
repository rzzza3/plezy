import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/services/base_shared_preferences_service.dart';
import 'package:plezy/services/trackers/tracker_account_store.dart';
import 'package:plezy/services/trackers/tracker_constants.dart';
import 'package:plezy/services/trackers/tracker_session.dart';

import '../../test_helpers/prefs.dart';

const _profileId = 'local-abc';

TrackerSession _session() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return TrackerSession(accessToken: 'a', refreshToken: 'r', expiresAt: now + 86400, createdAt: now);
}

void main() {
  setUp(resetSharedPreferencesForTest);

  group('profile user scoping', () {
    test('profileScopedPrefsKey prefixes the profile id, and an empty id stays global', () {
      expect(profileScopedPrefsKey(_profileId, 'trakt_session'), 'user_${_profileId}_trakt_session');
      expect(profileScopedPrefsKey('', 'trakt_session'), 'trakt_session');
    });

    test('store writes the profile-scoped key, loads it back and clears it', () async {
      final store = trackerAccountStore(TrackerService.trakt);
      await store.save(_profileId, _session());

      final prefs = await BaseSharedPreferencesService.sharedCache();
      expect(prefs.getString('user_${_profileId}_trakt_session'), isNotNull);
      expect(prefs.getString('trakt_session'), isNull);

      expect(await store.load(_profileId), isNotNull);
      expect(await store.load('local-other'), isNull);

      await store.clear(_profileId);
      expect(await store.load(_profileId), isNull);
    });
  });
}
