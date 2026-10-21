import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/video_controls/widgets/video_controls_header.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  testWidgets('title-less movie builds with localized fallback in both layouts', (tester) async {
    final item = testMediaItem(id: 'movie-without-name');

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      expect(find.text(t.common.unknown), findsOneWidget, reason: style.name);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('title-less episode keeps series identity and uses fallback in both layouts', (tester) async {
    final item = testMediaItem(
      id: 'episode-without-name',
      kind: MediaKind.episode,
      grandparentTitle: 'Mapped Series',
      parentIndex: 2,
      index: 3,
    );

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      final expectedEpisodeLine = switch (style) {
        VideoHeaderStyle.singleLine => 'Mapped Series · S2E3 · ${t.common.unknown}',
        VideoHeaderStyle.multiLine => 'S2 · E3 · ${t.common.unknown}',
      };
      expect(find.text(expectedEpisodeLine), findsOneWidget, reason: style.name);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('ordinary episode wording remains unchanged in both layouts', (tester) async {
    final item = testMediaItem(
      id: 'titled-episode',
      kind: MediaKind.episode,
      title: 'The Arrival',
      grandparentTitle: 'Mapped Series',
      parentIndex: 1,
      index: 4,
    );

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      final expectedEpisodeLine = switch (style) {
        VideoHeaderStyle.singleLine => 'Mapped Series · S1E4 · The Arrival',
        VideoHeaderStyle.multiLine => 'S1 · E4 · The Arrival',
      };
      expect(find.text(expectedEpisodeLine), findsOneWidget, reason: style.name);
      expect(find.text(t.common.unknown), findsNothing, reason: style.name);
    }
  });
}

Future<void> _pumpHeader(WidgetTester tester, {required MediaItem metadata, required VideoHeaderStyle style}) async {
  final watchTogether = WatchTogetherProvider();
  addTearDown(watchTogether.dispose);

  await tester.pumpWidget(
    TranslationProvider(
      child: ChangeNotifierProvider<WatchTogetherProvider>.value(
        value: watchTogether,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 900,
              child: VideoControlsHeader(metadata: metadata, style: style, onBack: () {}),
            ),
          ),
        ),
      ),
    ),
  );
}
