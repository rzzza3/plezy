import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/libraries/folder_tree_view.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  testWidgets('refresh reports whether the root listing landed', (tester) async {
    final client = _FolderClient([
      testMediaItem(id: 'f1', backend: MediaBackend.silo, kind: MediaKind.folder, title: 'Folder One', serverId: 'srv'),
    ]);
    final provider = testMultiServer(clients: [client]).provider;
    final key = GlobalKey<FolderTreeViewState>();

    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: InputModeTracker(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: CustomScrollView(
                slivers: [FolderTreeView(key: key, libraryKey: 'lib', serverId: 'srv', libraryKind: MediaKind.movie)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Folder One'), findsOneWidget);

    final refreshed = key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(await refreshed, isTrue);

    client.failNext = true;
    final failed = key.currentState!.refresh();
    await tester.pumpAndSettle();
    expect(await failed, isFalse);
  });
}

/// Serves one root listing, or throws once [failNext] is set.
class _FolderClient implements MediaServerClient {
  _FolderClient(this.rootFolders);

  final List<MediaItem> rootFolders;
  bool failNext = false;

  @override
  ServerId get serverId => ServerId('srv');

  @override
  MediaBackend get backend => MediaBackend.silo;

  @override
  Future<List<MediaItem>> fetchLibraryFolders(
    String libraryId, {
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async {
    if (failNext) throw Exception('down');
    return rootFolders;
  }

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
