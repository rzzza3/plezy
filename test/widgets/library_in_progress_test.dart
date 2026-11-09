import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/poster_wall_hero.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

/// The Library tab's spotlight on what is in progress: time left on the
/// Continue Watching cards, and the in-progress posters lit on the wall.
void main() {
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  const minute = 60 * 1000;
  String left(int ms) => t.libraryHome.timeLeft(duration: formatDurationTextual(ms));

  MediaItem movie({int? viewOffsetMs, String id = 'movie-1'}) => testMediaItem(
    id: id,
    kind: MediaKind.movie,
    title: 'Supergirl',
    year: 2026,
    durationMs: 108 * minute,
    viewOffsetMs: viewOffsetMs,
    thumbPath: '/poster/$id.jpg',
  );

  MediaItem episode({int? viewOffsetMs}) => testMediaItem(
    id: 'ep-1',
    kind: MediaKind.episode,
    title: 'Chickenpox',
    grandparentTitle: 'South Park',
    parentId: 'season-2',
    parentIndex: 2,
    index: 10,
    durationMs: 23 * minute,
    viewOffsetMs: viewOffsetMs,
  );

  Future<void> pumpCard(WidgetTester tester, MediaItem item, {bool showTimeLeft = true}) => tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            child: MediaCard(
              item: item,
              width: 400,
              height: 225,
              viewModeOverride: ViewMode.grid,
              showTimeLeft: showTimeLeft,
            ),
          ),
        ),
      ),
    ),
  );

  group('Continue Watching cards', () {
    testWidgets("a part-watched movie shows the time left in place of its year", (tester) async {
      await pumpCard(tester, movie(viewOffsetMs: 9 * minute));
      expect(find.text(left(99 * minute)), findsOneWidget);
      expect(find.text('2026'), findsNothing);
    });

    testWidgets('a part-watched episode keeps its number and title, then the time left', (tester) async {
      await pumpCard(tester, episode(viewOffsetMs: 3 * minute));
      expect(find.text(' · ${left(20 * minute)}'), findsOneWidget);
      expect(find.text('Chickenpox'), findsOneWidget);
    });

    testWidgets('an unstarted movie, or a card without the option, keeps its year', (tester) async {
      await pumpCard(tester, movie());
      expect(find.text('2026'), findsOneWidget);

      await pumpCard(tester, movie(viewOffsetMs: 9 * minute), showTimeLeft: false);
      expect(find.text('2026'), findsOneWidget);
      expect(find.textContaining('left'), findsNothing);
    });
  });

  group('poster wall', () {
    final items = [for (var i = 0; i < 8; i++) movie(id: 'm$i', viewOffsetMs: i < 6 ? (i + 1) * minute : null)];

    Future<void> pumpWall(WidgetTester tester, {Map<String, double>? highlights}) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 1200,
            height: 600,
            child: PosterWall(items: items, highlights: highlights),
          ),
        ),
      ),
    );

    /// The lit posters' progress fills, by how full each is.
    List<double> litProgress(WidgetTester tester) => [
      for (final box in tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))) box.widthFactor!,
    ];

    testWidgets('lights what is in progress, with its progress, and greys the rest', (tester) async {
      await pumpWall(tester, highlights: {'/poster/m0.jpg': 0.25, '/poster/m1.jpg': 0.5});
      expect(litProgress(tester), unorderedEquals([0.25, 0.5]));
      expect(find.byType(ColorFiltered), findsOneWidget);
    });

    testWidgets('lights at most one poster per slot', (tester) async {
      await pumpWall(tester, highlights: {for (var i = 0; i < 6; i++) '/poster/m$i.jpg': 0.1 * (i + 1)});
      expect(litProgress(tester), hasLength(PosterWall.highlightSlots.length));
    });

    testWidgets('without highlights, or with nothing in progress, the wall is unchanged', (tester) async {
      await pumpWall(tester);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(litProgress(tester), isEmpty);

      await pumpWall(tester, highlights: const {});
      expect(find.byType(ColorFiltered), findsNothing);
    });
  });
}
