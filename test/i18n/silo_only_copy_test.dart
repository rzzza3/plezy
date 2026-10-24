import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';

void main() {
  test('the add connection subtitle offers Silo only in every locale', () async {
    final retired = RegExp('Plex|Jellyfin|Emby|another profile');

    for (final locale in AppLocale.values) {
      final connections = (await locale.build()).connections;

      expect(connections.addConnectionSubtitle, isNot(contains(retired)), reason: locale.name);
    }
  });
}
