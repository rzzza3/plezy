import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/focusable_button.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/exceptions/media_server_exceptions.dart';
import 'package:plezy/media/library_filter_result.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/media_sort.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/state_messages.dart';
import 'package:plezy/screens/libraries/tabs/library_browse_tab.dart';
import 'package:plezy/services/storage_service.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/focusable_filter_chip.dart';
import 'package:plezy/widgets/media_card.dart';

import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

final _musicLibrary = MediaLibrary(
  id: 'music-library',
  backend: MediaBackend.silo,
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
  late final _MusicBrowseClient client;
  late final MultiServerManager manager;
  late final MultiServerProvider provider;

  int get browseRequestCount => client.browseRequestCount;
  int get requestCount => client.requestCount;

  _MusicBrowseHarness({bool failFirstBrowse = false}) {
    client = _MusicBrowseClient(failFirstBrowse: failFirstBrowse);
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    provider = testMultiServerProvider(manager);
  }

  Future<void> dispose() async {
    provider.dispose();
    manager.dispose();
  }
}

/// A Silo music server holding one artist. Counts every call, and the item
/// reads separately as browse requests.
class _MusicBrowseClient implements MediaServerClient {
  _MusicBrowseClient({required this.failFirstBrowse});

  final bool failFirstBrowse;
  var browseRequestCount = 0;
  var requestCount = 0;

  @override
  ServerId get serverId => ServerId('music-server');

  @override
  String get serverName => 'Music Server';

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.silo;

  @override
  Future<List<MediaSort>> fetchSortOptions(String libraryId, {String? libraryType}) async {
    requestCount++;
    return const [];
  }

  @override
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId, {MediaKind? libraryKind}) async {
    requestCount++;
    return LibraryFilterResult.empty;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    requestCount++;
    browseRequestCount++;
    if (failFirstBrowse && browseRequestCount == 1) {
      throw MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 504);
    }
    return LibraryPage<MediaItem>(
      items: [
        testMediaItem(
          id: 'artist-1',
          backend: MediaBackend.silo,
          kind: MediaKind.artist,
          title: 'Artist One',
          libraryId: libraryId,
          serverId: serverId.value,
        ),
      ],
      totalCount: 1,
    );
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) {
    requestCount++;
    return super.noSuchMethod(invocation);
  }
}
