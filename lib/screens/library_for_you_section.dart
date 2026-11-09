import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../providers/multi_server_provider.dart';
import '../services/silo_client.dart';
import '../utils/app_logger.dart';
import 'library_home_screen.dart';
import 'library_seasonal_section.dart';

/// The Library tab's "For You": the profile's main recommendation row
/// (`for-you-main`, the server's `/recommendations/section/for-you-main`),
/// laid out like Seasonal Picks and narrowed by the header filter. Shows
/// nothing until the row loads, or when the server has none for the profile.
///
/// One `GET /api/v2/recommendations/section/for-you-main` per connected Silo
/// server.
class LibraryForYouSection extends StatefulWidget {
  /// The server's maximum for one section.
  static const int maxItems = 60;

  final LibraryHomeFilter filter;

  /// UP from the top row.
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateToSidebar;

  /// DOWN from the bottom row.
  final VoidCallback? onNavigateDown;

  /// Focus entered the section, so the page can scroll it into view.
  final VoidCallback? onFocusEntered;

  const LibraryForYouSection({
    super.key,
    required this.filter,
    required this.onNavigateUp,
    required this.onNavigateToSidebar,
    this.onNavigateDown,
    this.onFocusEntered,
  });

  @override
  State<LibraryForYouSection> createState() => LibraryForYouSectionState();
}

class LibraryForYouSectionState extends State<LibraryForYouSection> {
  final _sectionKey = GlobalKey<LibrarySeasonalSectionState>();

  /// The row, once read; null while loading or after every server failed.
  List<MediaItem>? _items;
  bool _loading = false;

  // Memoized on its inputs so rebuilds hand the section the same hub and it
  // keeps its page.
  MediaHub? _hub;
  Object? _hubKey;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Whether the row is on screen to take focus.
  bool get isShown => _sectionKey.currentState != null;

  /// Focus the card last focused here, else the first.
  void requestFocus() => _sectionKey.currentState?.requestFocus();

  /// Read the row again.
  void refresh() => unawaited(_load());

  /// Read the row again if the last read failed or found no server.
  void retryIfUnavailable() {
    if (_items == null) unawaited(_load());
  }

  Future<void> _load() async {
    if (_loading) return;
    final clients = context
        .read<MultiServerProvider>()
        .serverManager
        .visibleOnlineClients
        .values
        .whereType<SiloClient>()
        .toList();
    if (clients.isEmpty) return;
    _loading = true;

    var failures = 0;
    final results = await Future.wait([
      for (final client in clients)
        client.fetchForYou(limit: LibraryForYouSection.maxItems).catchError((Object error) {
          failures++;
          appLogger.w('Library For You: read failed for ${client.serverId} (${error.runtimeType})');
          return const <MediaItem>[];
        }),
    ]);
    _loading = false;
    if (!mounted) return;
    // Keep what was on screen when every server failed.
    if (failures == clients.length) return;
    setState(() => _items = [...results.expand((items) => items)]);
  }

  MediaHub? _hubForFilter() {
    final items = _items;
    final key = (items, widget.filter, t.libraryHome.forYouTitle);
    if (key == _hubKey) return _hub;
    _hubKey = key;
    final shown = [
      for (final item in items ?? const <MediaItem>[])
        if (widget.filter.accepts(item.kind)) item,
    ];
    return _hub = shown.isEmpty
        ? null
        : MediaHub(
            id: 'library_for_you',
            identifier: 'for-you-main',
            title: t.libraryHome.forYouTitle,
            type: 'mixed',
            size: shown.length,
            more: false,
            items: shown,
          );
  }

  @override
  Widget build(BuildContext context) {
    final hub = _hubForFilter();
    if (hub == null) return const SizedBox.shrink();
    return LibrarySeasonalSection(
      key: _sectionKey,
      hub: hub,
      onNavigateUp: widget.onNavigateUp,
      onNavigateToSidebar: widget.onNavigateToSidebar,
      onNavigateDown: widget.onNavigateDown,
      onFocusEntered: widget.onFocusEntered,
    );
  }
}
