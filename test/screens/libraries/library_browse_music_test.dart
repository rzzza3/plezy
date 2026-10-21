import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/focus/focusable_button.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/state_messages.dart';
import 'package:plezy/screens/libraries/tabs/library_browse_tab.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_filter_chip.dart';
import 'package:plezy/widgets/media_card.dart';

import '../../test_helpers/backend_client_fixtures.dart';
import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

final _musicLibrary = MediaLibrary(
  id: 'music-library',
  backend: MediaBackend.plex,
  title: 'Music',
  kind: MediaKind.artist,
  serverId: ServerId('music-server'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('TV full-card preference keeps music browse captions visible', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    await SettingsService.instance.write(SettingsService.tvFullCardLayout, true);
    final harness = _MusicBrowseHarness();
    addTearDown(harness.dispose);

    await _pumpBrowseTab(tester, harness);

    expect(harness.browseRequestCount, 1);
    final card = tester.widget<MediaCard>(find.byType(MediaCard).first);
    expect(card.fullBleedImage, isFalse);
    expect(find.text('Artist One'), findsOneWidget);
    expect(find.descendant(of: find.byType(MediaCard), matching: find.byType(ClipOval)), findsOneWidget);
  });

  testWidgets('D-pad down focuses Retry and select reloads music browse', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    final harness = _MusicBrowseHarness(failFirstBrowse: true);
    addTearDown(harness.dispose);

    await _pumpBrowseTab(tester, harness);

    expect(find.byType(ErrorStateWidget), findsOneWidget);
    expect(harness.browseRequestCount, 1);

    final groupingChip = tester.widget<FocusableFilterChip>(find.byType(FocusableFilterChip).first);
    groupingChip.focusNode!.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    final retryFinder = find.descendant(of: find.byType(ErrorStateWidget), matching: find.byType(FocusableButton));
    final retry = tester.widget<FocusableButton>(retryFinder);
    expect(retry.focusNode, isNotNull);
    expect(retry.focusNode!.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await pumpRequestFrames(tester);

    expect(harness.browseRequestCount, 2);
    expect(find.byType(ErrorStateWidget), findsNothing);
    expect(find.text('Artist One'), findsOneWidget);
  });

  testWidgets('missing library owner shows an error without querying another online server', (tester) async {
    final harness = _MusicBrowseHarness();
    addTearDown(harness.dispose);
    final missingOwnerLibrary = MediaLibrary(
      id: _musicLibrary.id,
      backend: _musicLibrary.backend,
      title: _musicLibrary.title,
      kind: _musicLibrary.kind,
      serverId: 'missing-server',
    );

    await _pumpBrowseTab(tester, harness, library: missingOwnerLibrary);

    expect(find.byType(ErrorStateWidget), findsOneWidget);
    expect(harness.requestCount, 0);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpBrowseTab(WidgetTester tester, _MusicBrowseHarness harness, {MediaLibrary? library}) async {
  await pumpLibraryTab(
    tester,
    provider: harness.provider,
    tab: LibraryBrowseTab(
      library: library ?? _musicLibrary,
      canGroupByFolders: true,
      suppressAutoFocus: true,
      onBack: () {},
    ),
  );
  await pumpRequestFrames(tester);
}

class _MusicBrowseHarness {
  final bool failFirstBrowse;
  final AppDatabase database;
  var browseRequestCount = 0;
  var requestCount = 0;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  _MusicBrowseHarness({this.failFirstBrowse = false}) : database = AppDatabase.forTesting(NativeDatabase.memory()) {
    PlexApiCache.initialize(database);
    final client = testPlexClient(
      serverId: ServerId('music-server'),
      httpClient: MockClient((request) async {
        requestCount++;
        // Filter discovery reads the section endpoint with `includeMeta=1`;
        // only the item reads count as browse requests.
        if (request.url.path == '/library/sections/music-library/all' &&
            request.url.queryParameters['includeMeta'] != '1') {
          browseRequestCount++;
          if (failFirstBrowse && browseRequestCount == 1) {
            return http.Response('gateway timeout', 504);
          }
          return http.Response(
            jsonEncode({
              'MediaContainer': {
                'size': 1,
                'totalSize': 1,
                'offset': 0,
                'Metadata': const [
                  {'ratingKey': 'artist-1', 'type': 'artist', 'title': 'Artist One'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
    await database.close();
  }
}
