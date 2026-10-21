import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';

void main() {
  test('the add connection subtitles offer Silo only in every locale', () async {
    final retired = RegExp('Plex|Jellyfin|Emby');

    for (final locale in AppLocale.values) {
      final connections = (await locale.build()).connections;
      final subtitles = [
        connections.addConnectionSubtitleNoProfile,
        connections.addConnectionSubtitleScoped(displayName: 'Silo A'),
      ];

      expect(subtitles, everyElement(isNot(contains(retired))), reason: locale.name);
    }
  });
}
