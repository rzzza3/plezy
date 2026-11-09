import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../providers/multi_server_provider.dart';
import '../services/silo_client.dart';
import '../utils/app_logger.dart';
import '../utils/formatters.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/hub_section.dart';
import '../widgets/tv_browse_rail.dart';

/// A runtime range the section filters movies by, in minutes (inclusive;
/// null leaves that end open).
enum LibraryRuntimeFilter {
  under60(null, 59),
  under150(null, 149),
  allNight(120, null);

  final int? minMinutes;
  final int? maxMinutes;

  const LibraryRuntimeFilter(this.minMinutes, this.maxMinutes);

  String get label => switch (this) {
    under60 => t.libraryHome.runtimeUnder60,
    under150 => t.libraryHome.runtimeUnder150,
    allNight => t.libraryHome.runtimeAllNight,
  };
}

/// The Library tab's "How much time you got?": a strip of runtime filters
/// over a row of movies that fit. Moving through the strip switches the
/// filter, like the calendar's days. A small caps label over the title names
/// the focused movie and its runtime, like Seasonal Picks' label. Cards open the movie's page rather than
/// playing it.
///
/// One `POST /api/v2/catalog/query` per connected Silo server per filter,
/// read once a filter is first shown.
class LibraryRuntimeSection extends StatefulWidget {
  /// Most movies a filter shows.
  static const int maxItems = 40;

  /// UP from the strip.
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateToSidebar;

  /// DOWN from the row, or from the strip when the row has no cards.
  final VoidCallback? onNavigateDown;

  /// Focus entered the section, so the page can scroll it into view.
  final VoidCallback? onFocusEntered;

  const LibraryRuntimeSection({
    super.key,
    required this.onNavigateUp,
    required this.onNavigateToSidebar,
    this.onNavigateDown,
    this.onFocusEntered,
  });

  @override
  State<LibraryRuntimeSection> createState() => LibraryRuntimeSectionState();
}

class LibraryRuntimeSectionState extends State<LibraryRuntimeSection> {
  final _tvRailKey = GlobalKey<TvBrowseRailState>();
  final _hubKey = GlobalKey<HubSectionState>();
  final _focusMemory = HubFocusMemory();
  late final List<FocusNode> _filterNodes = [
    for (final filter in LibraryRuntimeFilter.values) FocusNode(debugLabel: 'runtime_${filter.name}'),
  ];

  LibraryRuntimeFilter _selected = LibraryRuntimeFilter.values.first;
  bool _hasSilo = true;

  /// The movie last focused in the row; null after a filter switch, when the
  /// label names the row's first movie.
  MediaItem? _focusedItem;

  /// Movies per filter, once read.
  final Map<LibraryRuntimeFilter, List<MediaItem>> _items = {};
  final Set<LibraryRuntimeFilter> _requested = {};
  final Set<LibraryRuntimeFilter> _failed = {};

  // Memoized on its inputs so rebuilds hand the rails the same hub list and
  // they keep their scroll position.
  List<MediaHub>? _hubs;
  Object? _hubsKey;

  @override
  void initState() {
    super.initState();
    for (final (index, filter) in LibraryRuntimeFilter.values.indexed) {
      _filterNodes[index].addListener(() {
        if (_filterNodes[index].hasFocus) _select(filter);
      });
    }
    unawaited(_load(_selected));
  }

  @override
  void dispose() {
    for (final node in _filterNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Focus the selected filter, coming DOWN from above. With no Silo server
  /// the section isn't shown, so focus carries on down.
  void requestFocus() {
    if (!_hasSilo) return widget.onNavigateDown?.call();
    _filterNodes[_selected.index].requestFocus();
  }

  /// Focus the row's cards, else the strip: UP from the section below. With
  /// no Silo server, focus carries on up.
  void requestFocusFromBelow() {
    if (!_hasSilo) return widget.onNavigateUp();
    if (_tvRailKey.currentState == null && _hubKey.currentState == null) {
      return _filterNodes[_selected.index].requestFocus();
    }
    _focusRow();
  }

  /// Read the filters again, from the one on screen.
  void refresh() {
    _items.clear();
    _requested.clear();
    _failed.clear();
    unawaited(_load(_selected));
  }

  /// Retry the filter on screen when its read failed or found no server.
  void retryIfUnavailable() {
    if (_hasSilo && !_failed.contains(_selected)) return;
    unawaited(_load(_selected));
  }

  void _select(LibraryRuntimeFilter filter) {
    if (filter == _selected) return;
    setState(() {
      _selected = filter;
      _focusedItem = null;
    });
    unawaited(_load(filter));
  }

  Future<void> _load(LibraryRuntimeFilter filter) async {
    if (!_requested.add(filter)) return;
    final clients = context
        .read<MultiServerProvider>()
        .serverManager
        .visibleOnlineClients
        .values
        .whereType<SiloClient>()
        .toList();
    if (clients.isEmpty) {
      _requested.remove(filter);
      setState(() => _hasSilo = false);
      return;
    }
    if (!_hasSilo) setState(() => _hasSilo = true);

    var failures = 0;
    final results = await Future.wait([
      for (final client in clients)
        client
            .fetchMoviesByRuntime(
              minMinutes: filter.minMinutes,
              maxMinutes: filter.maxMinutes,
              limit: LibraryRuntimeSection.maxItems,
            )
            .catchError((Object error) {
              failures++;
              appLogger.w('Library runtime: read failed for ${client.serverId} (${error.runtimeType})');
              return const <MediaItem>[];
            }),
    ]);
    if (!mounted) return;

    // Servers each answer highest rated first; interleave them the same way.
    final items = [...results.expand((items) => items)]..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    setState(() {
      _items[filter] = items.take(LibraryRuntimeSection.maxItems).toList();
      if (failures == clients.length) {
        _failed.add(filter);
        // Let the next visit to this filter try again.
        _requested.remove(filter);
      } else {
        _failed.remove(filter);
      }
    });
  }

  Future<void> _open(MediaItem item) => navigateToMediaItemDetails(context, item);

  List<MediaHub> _hubsForSelected() {
    final filter = _selected;
    final items = _items[filter] ?? const <MediaItem>[];
    final key = (filter, items, t.libraryHome.runtimeTitle);
    if (_hubs != null && key == _hubsKey) return _hubs!;
    _hubsKey = key;
    return _hubs = items.isEmpty
        ? const []
        : [
            MediaHub(
              id: 'library_runtime_${filter.name}',
              identifier: 'library_runtime',
              title: filter.label,
              type: 'movie',
              size: items.length,
              more: false,
              items: items,
            ),
          ];
  }

  void _onFocusedItem(MediaItem item) {
    if (item != _focusedItem) setState(() => _focusedItem = item);
  }

  /// "Title · 1h 52m" for the focused movie, else the row's first.
  String? _label(List<MediaHub> hubs) {
    final item = _focusedItem ?? hubs.firstOrNull?.items.firstOrNull;
    if (item == null) return null;
    return [
      item.displayTitle,
      if (item.durationMs case final durationMs?) formatDurationTextual(durationMs),
    ].join(' · ');
  }

  /// DOWN from the filter strip: the movies. While the selected filter loads,
  /// focus stays on the strip instead of skipping past a row that is about to
  /// appear.
  void _focusRow() {
    final tvRail = _tvRailKey.currentState;
    final hub = _hubKey.currentState;
    if (tvRail != null) {
      tvRail.requestFocus();
    } else if (hub != null) {
      hub.requestFocusFromMemory();
    } else if (_items.containsKey(_selected)) {
      widget.onNavigateDown?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSilo) return const SizedBox.shrink();
    final isTv = PlatformDetector.isTV();
    // Line up with the titles of the TV rails above.
    final inset = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;
    final theme = Theme.of(context);
    final hubs = _hubsForSelected();
    final loaded = _items.containsKey(_selected);
    final label = _label(hubs);

    final Widget row;
    if (!loaded) {
      row = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else if (_failed.contains(_selected) || hubs.isEmpty) {
      row = Padding(
        padding: EdgeInsets.fromLTRB(inset, 24, inset, 48),
        child: Text(
          _failed.contains(_selected) ? t.libraryHome.runtimeFailed : t.libraryHome.runtimeEmpty,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    } else if (isTv) {
      row = TvBrowseRail(
        key: _tvRailKey,
        hubs: hubs,
        focusMemory: _focusMemory,
        onNavigateUp: requestFocus,
        onNavigateDown: widget.onNavigateDown,
        onNavigateToSidebar: widget.onNavigateToSidebar,
        onBack: widget.onNavigateToSidebar,
        extraItemGap: 16,
        showHubHeaders: false,
        onFocusedItemChanged: _onFocusedItem,
        onActivateItem: (hub, item) {
          unawaited(_open(item));
          return true;
        },
      );
    } else {
      row = HubSection(
        key: _hubKey,
        hub: hubs.first,
        focusMemory: _focusMemory,
        icon: Symbols.timer_rounded,
        showHeader: false,
        onFocusedItemChanged: _onFocusedItem,
        onItemTap: (item) => unawaited(_open(item)),
        onVerticalNavigation: (isUp) {
          if (isUp) {
            requestFocus();
          } else {
            widget.onNavigateDown?.call();
          }
          return true;
        },
        onNavigateUp: requestFocus,
        onNavigateToSidebar: widget.onNavigateToSidebar,
      );
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocusEntered?.call();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, isTv ? 24 : 16, inset, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Its room is kept without a movie, so the strip doesn't jump.
                Visibility.maintain(
                  visible: label != null,
                  child: Text(
                    (label ?? ' ').toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.libraryHome.runtimeTitle,
                  style: isTv
                      ? TvSectionHeaderTokens.title.copyWith(color: theme.colorScheme.onSurface)
                      : theme.textTheme.titleLarge,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: _buildStrip(isTv: isTv),
            ),
          ),
          SizedBox(height: isTv ? 24 : 12),
          row,
          SizedBox(height: isTv ? 16 : 8),
        ],
      ),
    );
  }

  Widget _buildStrip({required bool isTv}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FocusableActionBar(
          spacing: 4,
          revealFocusedAction: true,
          onNavigateLeft: widget.onNavigateToSidebar,
          onNavigateUp: widget.onNavigateUp,
          onNavigateDown: _focusRow,
          onBack: widget.onNavigateToSidebar,
          actions: [
            for (final filter in LibraryRuntimeFilter.values)
              FocusableAction(
                debugLabel: 'runtime_${filter.name}',
                focusNode: _filterNodes[filter.index],
                onPressed: () {
                  _select(filter);
                  _focusRow();
                },
                builder: (context, state) => _FilterChip(
                  label: filter.label,
                  selected: filter == _selected,
                  focused: state.showFocus,
                  duration: state.animationDuration,
                  large: isTv,
                  onTap: () => _select(filter),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool focused;
  final bool large;
  final Duration duration;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.focused,
    required this.large,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = focused ? Colors.black : Colors.white;
    final Color background = focused
        ? Colors.white
        : selected
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.transparent;

    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          padding: EdgeInsets.symmetric(horizontal: large ? 20 : 16, vertical: large ? 10 : 8),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
          child: Text(
            label,
            style: (large ? textTheme.titleMedium : textTheme.titleSmall)?.copyWith(
              color: foreground.withValues(alpha: focused || selected ? 1 : 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
