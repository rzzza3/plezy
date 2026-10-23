import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/external_ids.dart';

void main() {
  group('ExternalIds', () {
    test('round-trips through JSON, keeping absent ids absent', () {
      const ids = ExternalIds(imdb: 'tt123', tmdb: 456, anidb: 11905);

      final json = ids.toJson();
      final decoded = ExternalIds.fromJson(json);

      expect(json, {'imdb': 'tt123', 'tmdb': 456, 'anidb': 11905});
      expect(decoded.tvdb, isNull);
      expect(decoded.intersects(ids), isTrue);
    });

    test('an AniDB-only set has ids but none a title database can query', () {
      const ids = ExternalIds(anidb: 11905);

      expect(ids.hasAny, isTrue);
      expect(ids.hasCatalogIds, isFalse);
    });

    test('intersects matches any shared id and never an absent one', () {
      expect(const ExternalIds(imdb: 'tt1', tmdb: 2).intersects(const ExternalIds(tmdb: 2)), isTrue);
      expect(const ExternalIds(imdb: 'tt1').intersects(const ExternalIds(tmdb: 2)), isFalse);
      expect(const ExternalIds().intersects(const ExternalIds()), isFalse);
    });
  });
}
