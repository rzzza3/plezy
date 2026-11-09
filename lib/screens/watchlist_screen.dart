import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/key_event_utils.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../navigation/main_screen_scope.dart';
import '../providers/multi_server_provider.dart';
import '../services/settings_service.dart';
import '../services/silo_client.dart';
import '../silo/silo_catalog.dart';
import '../utils/app_logger.dart';
import '../utils/formatters.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../utils/snackbar_helper.dart';
import '../utils/video_player_navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_menu.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/focusable_tab_chip.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/media_card_sliver_layout.dart';
import '../widgets/settings_builder.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/tv_browse_rail.dart';

/// The Watchlist tab: the profile's Silo Watchlist and Favorites, one at a
/// time behind a pair of tabs. Each list is laid out as a small home page: a
/// rotating hero of its first titles, up to four category tiles (a fan of
/// each category's posters; selecting one filters the grid to it), then the
/// whole list as a poster grid with type, genre, watch-state and sort
/// filters, applied on the device.
///
/// Reads `GET /api/v2/catalog?source=watchlist` and `source=favorites` from
/// every connected Silo server ([SiloClient.fetchPersonalList]), again each
/// time the tab is shown.
class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});

  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

/// One list as read: its titles (merged across servers) and the servers'
/// total, which can exceed what was read.
class _ListState {
  final List<MediaItem> items;
  final int total;

  const _ListState(this.items, this.total);
}

/// A category tile: a label, its titles, and the posters its fan shows.
class _Category {
  final String id;
  final String label;
  final List<MediaItem> items;

  const _Category(this.id, this.label, this.items);
}

/// What the grid shows by kind.
enum _TypeFilter { all, movies, shows }

/// The grid's order. [listOrder] keeps the server's stored order.
enum _SortOrder { listOrder, title, year, rating, added }

class _WatchlistScreenState extends State<WatchlistScreen> with TabVisibilityAware, FocusableTab, Refreshable {
  /// How many titles the hero rotates through.
  static const _heroCount = 5;
  static const _heroInterval = Duration(seconds: 8);

  SiloPersonalList _tab = SiloPersonalList.watchlist;
  final Map<SiloPersonalList, _ListState> _lists = {};
  bool _loading = false;
  bool _failed = false;

  // The grid's filters; reset when the tab changes.
  _TypeFilter _type = _TypeFilter.all;
  String? _genre;
  String? _status;
  _SortOrder _sort = _SortOrder.listOrder;

  final _tabNodes = {
    for (final list in SiloPersonalList.values) list: FocusNode(debugLabel: 'watchlist_tab_${list.name}'),
  };
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _filterBarKey = GlobalKey<FocusableActionBarState>();
  final _typeMenuKey = GlobalKey<AppMenuButtonState<_TypeFilter>>();
  final _genreMenuKey = GlobalKey<AppMenuButtonState<String>>();
  final _statusMenuKey = GlobalKey<AppMenuButtonState<String>>();
  final _sortMenuKey = GlobalKey<AppMenuButtonState<_SortOrder>>();
  final _tilesKey = GlobalKey<_CategoryTilesState>();
  final _tilesBoxKey = GlobalKey();
  final _filterBoxKey = GlobalKey();
  final _scroll = ScrollController();

  /// One focus node per grid card, by item, so a re-filter keeps focus on
  /// the same title.
  final Map<String, FocusNode> _gridNodes = {};

  int _heroIndex = 0;
  bool _heroFocused = false;
  Timer? _heroTimer;

  // Memoized on its inputs so rebuilds don't re-sort the grid.
  List<MediaItem>? _filtered;
  Object? _filteredKey;

  late final MultiServerProvider _servers = context.read<MultiServerProvider>();

  @override
  void initState() {
    super.initState();
    _servers.addOnlineServersListener(_onOnlineServersChanged);
    unawaited(_load());
    _startHeroTimer();
  }

  @override
  void dispose() {
    _servers.removeOnlineServersListener(_onOnlineServersChanged);
    _heroTimer?.cancel();
    for (final node in [..._tabNodes.values, ..._gridNodes.values]) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _onOnlineServersChanged(Set<String> _) {
    if (mounted && (_lists.isEmpty || _failed)) unawaited(_load());
  }

  @override
  void onTabShown() {
    // A title may have been saved or removed elsewhere since the last read.
    unawaited(_load());
    _startHeroTimer();
  }

  @override
  void onTabHidden() => _heroTimer?.cancel();

  @override
  void refresh() => unawaited(_load());

  @override
  void focusActiveTabIfReady() => _tabNodes[_tab]!.requestFocus();

  List<SiloClient> get _clients =>
      _servers.serverManager.visibleOnlineClients.values.whereType<SiloClient>().toList(growable: false);

  Future<void> _load() async {
    if (_loading) return;
    final clients = _clients;
    if (clients.isEmpty) return;
    _loading = true;

    Future<_ListState?> read(SiloPersonalList list) async {
      var failures = 0;
      final results = await Future.wait([
        for (final client in clients)
          client.fetchPersonalList(list).catchError((Object error) {
            failures++;
            appLogger.w('Watchlist: ${list.source} read failed for ${client.serverId} (${error.runtimeType})');
            return (items: const <MediaItem>[], total: 0);
          }),
      ]);
      if (failures == clients.length) return null;
      return _ListState([
        for (final result in results) ...result.items,
      ], results.fold<int>(0, (sum, result) => sum + result.total));
    }

    final watchlist = read(SiloPersonalList.watchlist);
    final favorites = read(SiloPersonalList.favorites);
    final results = {SiloPersonalList.watchlist: await watchlist, SiloPersonalList.favorites: await favorites};
    _loading = false;
    if (!mounted) return;
    setState(() {
      // Keep what was on screen for a list every server failed to read.
      for (final MapEntry(:key, :value) in results.entries) {
        if (value != null) _lists[key] = value;
      }
      _failed = results.values.every((value) => value == null) && _lists.isEmpty;
      _heroIndex = _heroIndex.clamp(0, math.max(0, _heroItems.length - 1));
      _dropMissingFilters();
    });
    _pruneGridNodes();
  }

  List<MediaItem> get _items => _lists[_tab]?.items ?? const [];
  List<MediaItem> get _heroItems => _items.take(_heroCount).toList(growable: false);

  void _selectTab(SiloPersonalList tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      _heroIndex = 0;
      _resetFilters();
    });
    _startHeroTimer();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  // Hero rotation: advances while the hero is not focused.
  void _startHeroTimer() {
    _heroTimer?.cancel();
    _heroTimer = Timer.periodic(_heroInterval, (_) {
      if (!mounted || _heroFocused) return;
      final count = _heroItems.length;
      if (count > 1) setState(() => _heroIndex = (_heroIndex + 1) % count);
    });
  }

  void _showHero(int index) {
    final count = _heroItems.length;
    if (count == 0) return;
    setState(() => _heroIndex = index % count);
    _startHeroTimer();
  }

  // ---- Categories and filters ----

  static bool _inProgress(MediaItem item) => item.hasActiveProgress || item.isPartiallyWatched;

  /// Whether [item] is in the watch state named [status] (a category id).
  static bool _hasStatus(String status, MediaItem item) => switch (status) {
    'in_progress' => _inProgress(item),
    'not_started' => !item.isWatched && !_inProgress(item),
    'unwatched' => !item.isWatched,
    _ => true,
  };

  /// The watch states this list offers, each only when it splits the list
  /// (Silo's list cards can arrive without progress, which would put every
  /// title in "Not Started").
  List<_Category> _statusCategories() {
    final s = t.watchlistPage;
    final items = _items;
    final ids = _tab == SiloPersonalList.watchlist ? const ['in_progress', 'not_started'] : const ['unwatched'];
    String label(String id) => switch (id) {
      'in_progress' => s.inProgress,
      'not_started' => s.notStarted,
      _ => s.unwatched,
    };
    return [
      for (final id in ids)
        if (items.where((item) => _hasStatus(id, item)).toList() case final matching
            when matching.isNotEmpty && matching.length < items.length)
          _Category(id, label(id), matching),
    ];
  }

  /// Every genre in the list, most common first.
  List<(String, int)> _genres() {
    final counts = <String, int>{};
    for (final item in _items) {
      for (final genre in item.genres ?? const <String>[]) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    return [for (final entry in counts.entries) (entry.key, entry.value)]
      ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.compareTo(b.$1));
  }

  /// Up to four category tiles: Movies and TV Shows, then watch states,
  /// then the genres most of the list shares, each only when it splits the
  /// list. Selecting one filters the grid to it.
  List<_Category> _categories() {
    final s = t.watchlistPage;
    final items = _items;
    bool splits(_Category category) => category.items.isNotEmpty && category.items.length < items.length;
    return [
      _Category('movies', s.movies, [...items.where((item) => item.kind == MediaKind.movie)]),
      _Category('shows', s.shows, [...items.where((item) => item.kind == MediaKind.show)]),
      ..._statusCategories(),
      for (final (genre, count) in _genres())
        if (count > 1)
          _Category('genre:$genre', genre, [...items.where((item) => item.genres?.contains(genre) ?? false)]),
    ].where(splits).take(4).toList(growable: false);
  }

  bool get _filtersActive => _type != _TypeFilter.all || _genre != null || _status != null;

  void _resetFilters() {
    _type = _TypeFilter.all;
    _genre = null;
    _status = null;
    _sort = _SortOrder.listOrder;
  }

  /// Drop a genre or status filter the list no longer has (after a reload or
  /// a removal), so the grid never sits empty behind a stale filter.
  void _dropMissingFilters() {
    if (_genre != null && !_genres().any((entry) => entry.$1 == _genre)) _genre = null;
    if (_status != null && !_statusCategories().any((category) => category.id == _status)) _status = null;
  }

  List<MediaItem> _filteredItems() {
    final items = _items;
    final key = (items, _type, _genre, _status, _sort);
    if (key == _filteredKey && _filtered != null) return _filtered!;
    _filteredKey = key;
    final filtered = [
      for (final item in items)
        if (switch (_type) {
              _TypeFilter.all => true,
              _TypeFilter.movies => item.kind == MediaKind.movie,
              _TypeFilter.shows => item.kind == MediaKind.show,
            } &&
            (_genre == null || (item.genres?.contains(_genre) ?? false)) &&
            (_status == null || _hasStatus(_status!, item)))
          item,
    ];
    int compare(Comparable<Object> a, Comparable<Object> b) => a.compareTo(b);
    switch (_sort) {
      case _SortOrder.listOrder:
        break;
      case _SortOrder.title:
        filtered.sort(
          (a, b) => compare((a.titleSort ?? a.title ?? '').toLowerCase(), (b.titleSort ?? b.title ?? '').toLowerCase()),
        );
      case _SortOrder.year:
        filtered.sort((a, b) => compare(b.year ?? 0, a.year ?? 0));
      case _SortOrder.rating:
        filtered.sort((a, b) => compare(b.rating ?? 0, a.rating ?? 0));
      case _SortOrder.added:
        filtered.sort((a, b) => compare(b.addedAt ?? 0, a.addedAt ?? 0));
    }
    return _filtered = filtered;
  }

  /// A tile narrows the grid to its category and moves focus to the grid.
  void _applyCategory(_Category category) {
    setState(() {
      _type = switch (category.id) {
        'movies' => _TypeFilter.movies,
        'shows' => _TypeFilter.shows,
        _ => _TypeFilter.all,
      };
      _genre = category.id.startsWith('genre:') ? category.id.substring('genre:'.length) : null;
      _status = _statusCategories().any((status) => status.id == category.id) ? category.id : null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusGrid();
    });
  }

  void _setFilter(VoidCallback change) {
    setState(change);
    // Keep the grid in view under the filter bar while the filters change.
    if (PlatformDetector.isTV()) _revealTv(_filterBoxKey.currentContext, alignment: 0.05);
  }

  static String _typeLabel(_TypeFilter type) => switch (type) {
    _TypeFilter.all => t.watchlistPage.allTypes,
    _TypeFilter.movies => t.watchlistPage.movies,
    _TypeFilter.shows => t.watchlistPage.shows,
  };

  static String _sortLabel(_SortOrder sort) => switch (sort) {
    _SortOrder.listOrder => t.watchlistPage.listOrder,
    _SortOrder.title => t.hubDetail.title,
    _SortOrder.year => t.hubDetail.releaseYear,
    _SortOrder.rating => t.hubDetail.rating,
    _SortOrder.added => t.hubDetail.dateAdded,
  };

  FocusNode _gridNode(MediaItem item) =>
      _gridNodes.putIfAbsent(item.globalKey, () => FocusNode(debugLabel: 'watchlist_grid_${item.globalKey}'));

  /// Dispose the nodes of titles no longer on either list, after the frame
  /// that stops showing them.
  void _pruneGridNodes() {
    final keep = {
      for (final list in _lists.values)
        for (final item in list.items) item.globalKey,
    };
    final stale = [
      for (final MapEntry(:key, :value) in _gridNodes.entries)
        if (!keep.contains(key)) (key, value),
    ];
    if (stale.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final (key, node) in stale) {
        if (identical(_gridNodes[key], node)) _gridNodes.remove(key);
        node.dispose();
      }
    });
  }

  // ---- Focus flow, top to bottom: tabs, hero actions, tiles, filters, grid ----

  void _focusSidebar() => MainScreenFocusScope.focusSidebarOf(context);
  void _focusTabs() => _tabNodes[_tab]!.requestFocus();

  void _focusHero() {
    if (_heroItems.isEmpty) return;
    _actionBarKey.currentState?.requestFocusOnFirst();
  }

  void _focusTiles() {
    final tiles = _tilesKey.currentState;
    if (tiles != null) {
      tiles.requestFocus();
    } else {
      _focusFilters();
    }
  }

  void _focusFilters() => _filterBarKey.currentState?.requestFocusOnFirst();

  void _focusAboveFilters() => _tilesKey.currentState != null ? _focusTiles() : _focusHero();

  void _focusGrid() {
    final first = _filteredItems().firstOrNull;
    if (first == null) return _focusFilters();
    _gridNode(first).requestFocus();
  }

  /// TV: scroll the page so [section] sits at [alignment] of the viewport.
  void _revealTv(BuildContext? section, {double alignment = 1}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = section?.findRenderObject();
      if (!mounted || box == null || !box.attached || !_scroll.hasClients) return;
      final position = _scroll.position;
      final target = RenderAbstractViewport.of(
        box,
      ).getOffsetToReveal(box, alignment).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
      unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
    });
  }

  void _revealTop() {
    if (!_scroll.hasClients) return;
    unawaited(_scroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
  }

  SiloClient? _clientFor(MediaItem item) {
    final client = _servers.serverManager.visibleOnlineClients[item.serverId];
    return client is SiloClient ? client : null;
  }

  Future<void> _play(MediaItem item) async {
    if (item.kind != MediaKind.show) {
      await navigateToVideoPlayer(context, metadata: item);
      return;
    }
    // A show plays its next-up episode; the detail page when there is none.
    final client = _clientFor(item);
    MediaItem? episode;
    try {
      episode = (await client?.fetchItemWithOnDeck(item.id))?.onDeckEpisode;
    } catch (error) {
      appLogger.w('Watchlist: next-up read failed (${error.runtimeType})');
    }
    if (!mounted) return;
    if (episode != null) {
      await navigateToVideoPlayer(context, metadata: episode);
    } else {
      await navigateToMediaItemDetails(context, item);
    }
  }

  Future<void> _remove(MediaItem item) async {
    final client = _clientFor(item);
    if (client == null) return;
    final list = _tab;
    final previous = _lists[list];
    // Take it off screen straight away; put it back if the write fails.
    if (previous != null) {
      setState(() {
        _lists[list] = _ListState([
          for (final other in previous.items)
            if (other.globalKey != item.globalKey) other,
        ], math.max(0, previous.total - 1));
        _heroIndex = _heroIndex.clamp(0, math.max(0, _heroItems.length - 1));
        _dropMissingFilters();
      });
    }
    try {
      if (list == SiloPersonalList.watchlist) {
        await client.setWatchlisted(item, false);
      } else {
        await client.setFavorite(item, false);
      }
      if (!mounted) return;
      showAppSnackBar(
        context,
        list == SiloPersonalList.watchlist
            ? t.watchlistPage.removedFromWatchlist
            : t.watchlistPage.removedFromFavorites,
      );
    } catch (error) {
      appLogger.w('Watchlist: ${list.source} removal failed (${error.runtimeType})');
      if (!mounted) return;
      if (previous != null) setState(() => _lists[list] = previous);
      showErrorSnackBar(context, t.watchlistPage.updateFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTv = PlatformDetector.isTV();
    final size = MediaQuery.sizeOf(context);
    final scale = isTv ? TvBrowseRailLayout.scaleForSize(size) : 1.0;
    final inset = isTv ? TvBrowseRailLayout.horizontalInsetForScale(scale) : 16.0;
    final topInset = MediaQuery.paddingOf(context).top;
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    final heroHeight = isTv ? size.height * 0.42 : (useSideNav ? math.max(size.height * 0.46, 320.0) : 360.0);

    final tabs = Padding(
      padding: EdgeInsets.fromLTRB(inset, (isTv ? 20 : 12) + (useSideNav ? 0 : topInset), inset, isTv ? 16 : 12),
      child: TabChipStrip(
        children: [
          for (final list in SiloPersonalList.values) ...[
            if (list != SiloPersonalList.values.first) const SizedBox(width: 8),
            FocusableTabChip(
              focusNode: _tabNodes[list],
              label: _tabLabel(list),
              isSelected: list == _tab,
              onSelect: () => _selectTab(list),
              onNavigateLeft: list == SiloPersonalList.values.first
                  ? _focusSidebar
                  : () => _tabNodes[SiloPersonalList.values[list.index - 1]]!.requestFocus(),
              onNavigateRight: list == SiloPersonalList.values.last
                  ? null
                  : () => _tabNodes[SiloPersonalList.values[list.index + 1]]!.requestFocus(),
              onNavigateDown: _focusHero,
              onBack: _focusSidebar,
            ),
          ],
        ],
      ),
    );

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (hasFocus && isTv && _tabNodes.values.any((node) => node.hasFocus)) _revealTop();
        },
        child: _items.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabs,
                  Expanded(
                    child: _EmptyState(
                      loading: _lists[_tab] == null && !_failed,
                      failed: _failed,
                      title: _tab == SiloPersonalList.watchlist
                          ? t.watchlistPage.emptyWatchlist
                          : t.watchlistPage.emptyFavorites,
                    ),
                  ),
                ],
              )
            : CustomScrollView(
                controller: _scroll,
                physics: isTv ? const NeverScrollableScrollPhysics() : null,
                slivers: [
                  SliverToBoxAdapter(child: tabs),
                  ..._buildContent(context, isTv: isTv, inset: inset, heroHeight: heroHeight),
                ],
              ),
      ),
    );
  }

  String _tabLabel(SiloPersonalList list) {
    final name = list == SiloPersonalList.watchlist ? t.watchlistPage.watchlist : t.watchlistPage.favorites;
    final total = _lists[list]?.total;
    return total == null ? name : '$name  $total';
  }

  List<Widget> _buildContent(
    BuildContext context, {
    required bool isTv,
    required double inset,
    required double heroHeight,
  }) {
    final theme = Theme.of(context);
    final heroItems = _heroItems;
    final heroItem = heroItems[_heroIndex.clamp(0, heroItems.length - 1)];
    final categories = _categories();
    final filtered = _filteredItems();
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    final hero = Padding(
      padding: EdgeInsets.symmetric(horizontal: inset),
      child: SizedBox(
        height: heroHeight,
        child: _Hero(
          item: heroItem,
          index: _heroIndex,
          count: heroItems.length,
          list: _tab,
          actionBarKey: _actionBarKey,
          onDot: _showHero,
          onPlay: () => unawaited(_play(heroItem)),
          onRemove: () => unawaited(_remove(heroItem)),
          onInfo: () => unawaited(navigateToMediaItemDetails(context, heroItem)),
          onNavigateUp: _focusTabs,
          onNavigateDown: _focusTiles,
          onNavigateLeft: _focusSidebar,
          // RIGHT past the last action shows the next title.
          onNavigateRight: heroItems.length > 1 ? () => _showHero(_heroIndex + 1) : null,
          onBack: _focusSidebar,
          onFocusChange: (hasFocus) {
            _heroFocused = hasFocus;
            if (hasFocus && isTv) _revealTop();
          },
        ),
      ),
    );

    final tiles = categories.isEmpty
        ? null
        : Padding(
            key: _tilesBoxKey,
            padding: EdgeInsets.fromLTRB(inset, isTv ? 20 : 16, inset, 0),
            child: _CategoryTiles(
              key: _tilesKey,
              categories: categories,
              onOpen: _applyCategory,
              onNavigateUp: _focusHero,
              onNavigateDown: _focusFilters,
              onNavigateToSidebar: _focusSidebar,
              onFocusEntered: isTv ? () => _revealTv(_tilesBoxKey.currentContext, alignment: 0.5) : null,
            ),
          );

    final heading = Padding(
      key: _filterBoxKey,
      padding: EdgeInsets.fromLTRB(inset, isTv ? 28 : 24, inset, isTv ? 8 : 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _tab == SiloPersonalList.watchlist
                      ? t.watchlistPage.allWatchlist
                      : t.watchlistPage.allFavorites,
                ),
                TextSpan(
                  text: '   ${t.discover.titleCount(n: filtered.length)}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w500,
                    fontSize: isTv ? 15 : 14,
                  ),
                ),
              ],
            ),
            style: isTv
                ? TvSectionHeaderTokens.title.copyWith(color: theme.colorScheme.onSurface)
                : theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _buildFilterBar(isTv: isTv),
        ],
      ),
    );

    return [
      SliverToBoxAdapter(child: hero),
      if (tiles != null) SliverToBoxAdapter(child: tiles),
      SliverToBoxAdapter(child: heading),
      if (filtered.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                t.watchlistPage.noMatches,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
          ),
        )
      else
        _buildGrid(filtered, isTv: isTv, inset: inset),
      SliverToBoxAdapter(child: SizedBox(height: isTv ? 48 : 24 + bottomPadding)),
    ];
  }

  Widget _buildFilterBar({required bool isTv}) {
    final genres = _genres();
    final statuses = _statusCategories();

    FocusableAction menu<T>({
      required String debugLabel,
      required GlobalKey<AppMenuButtonState<T>> menuKey,
      required String label,
      required IconData icon,
      required bool active,
      required List<AppMenuItem<T>> Function() entries,
      required ValueChanged<T> onSelected,
    }) => FocusableAction(
      debugLabel: debugLabel,
      onPressed: () => menuKey.currentState?.showButtonMenu(focusFirstItem: true),
      builder: (context, state) => AppMenuButton<T>(
        key: menuKey,
        onSelected: onSelected,
        entriesBuilder: (context) => entries(),
        child: _FilterPill(
          label: label,
          icon: icon,
          active: active,
          focused: state.showFocus,
          duration: state.animationDuration,
        ),
      ),
    );

    final bar = FocusableActionBar(
      key: _filterBarKey,
      spacing: 10,
      revealFocusedAction: true,
      onNavigateUp: _focusAboveFilters,
      onNavigateDown: _focusGrid,
      onNavigateLeft: _focusSidebar,
      onBack: _focusSidebar,
      onFocusChange: (hasFocus) {
        if (hasFocus && isTv) _revealTv(_filterBoxKey.currentContext, alignment: 0.05);
      },
      actions: [
        menu<_TypeFilter>(
          debugLabel: 'watchlist_filter_type',
          menuKey: _typeMenuKey,
          label: _typeLabel(_type),
          icon: Symbols.movie_rounded,
          active: _type != _TypeFilter.all,
          entries: () => [
            for (final type in _TypeFilter.values)
              AppMenuItem(value: type, label: _typeLabel(type), selected: type == _type),
          ],
          onSelected: (type) => _setFilter(() => _type = type),
        ),
        if (genres.isNotEmpty)
          menu<String>(
            debugLabel: 'watchlist_filter_genre',
            menuKey: _genreMenuKey,
            label: _genre ?? t.watchlistPage.allGenres,
            icon: Symbols.theater_comedy_rounded,
            active: _genre != null,
            entries: () => [
              AppMenuItem(value: '', label: t.watchlistPage.allGenres, selected: _genre == null),
              for (final (genre, count) in genres)
                AppMenuItem(value: genre, label: '$genre  ($count)', selected: genre == _genre),
            ],
            onSelected: (genre) => _setFilter(() => _genre = genre.isEmpty ? null : genre),
          ),
        if (statuses.isNotEmpty)
          menu<String>(
            debugLabel: 'watchlist_filter_status',
            menuKey: _statusMenuKey,
            label: statuses.where((status) => status.id == _status).firstOrNull?.label ?? t.watchlistPage.anyStatus,
            icon: Symbols.visibility_rounded,
            active: _status != null,
            entries: () => [
              AppMenuItem(value: '', label: t.watchlistPage.anyStatus, selected: _status == null),
              for (final status in statuses)
                AppMenuItem(value: status.id, label: status.label, selected: status.id == _status),
            ],
            onSelected: (status) => _setFilter(() => _status = status.isEmpty ? null : status),
          ),
        menu<_SortOrder>(
          debugLabel: 'watchlist_sort',
          menuKey: _sortMenuKey,
          label: _sortLabel(_sort),
          icon: Symbols.swap_vert_rounded,
          active: _sort != _SortOrder.listOrder,
          entries: () => [
            for (final sort in _SortOrder.values)
              AppMenuItem(value: sort, label: _sortLabel(sort), selected: sort == _sort),
          ],
          onSelected: (sort) => _setFilter(() => _sort = sort),
        ),
        if (_filtersActive || _sort != _SortOrder.listOrder)
          FocusableAction(
            debugLabel: 'watchlist_filter_clear',
            onPressed: () => _setFilter(_resetFilters),
            builder: (context, state) => _FilterPill(
              label: t.watchlistPage.clearFilters,
              icon: Symbols.close_rounded,
              active: false,
              focused: state.showFocus,
              duration: state.animationDuration,
              onTap: () => _setFilter(_resetFilters),
            ),
          ),
      ],
    );
    return SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: bar);
  }

  /// Every title that passes the filters, as poster cards in the library
  /// grid layout at the user's grid density.
  Widget _buildGrid(List<MediaItem> items, {required bool isTv, required double inset}) {
    return SettingsBuilder(
      prefs: const [SettingsService.libraryDensity, SettingsService.tvFullCardLayout],
      builder: (context) {
        final svc = SettingsService.instance;
        final fullCardLayout = isTv && svc.read(SettingsService.tvFullCardLayout);
        return MediaCardSliverLayout(
          viewMode: ViewMode.grid,
          itemCount: items.length,
          findChildIndexCallback: (key) {
            final id = (key as ValueKey<String>).value;
            final index = items.indexWhere((item) => item.globalKey == id);
            return index < 0 ? null : index;
          },
          density: svc.read(SettingsService.libraryDensity),
          padding: EdgeInsets.fromLTRB(inset - 8, 8, inset - 8, 8),
          fullBleedImage: fullCardLayout,
          itemBuilder: (context, position) {
            final item = items[position.index];
            final node = _gridNode(item);
            return FocusableMediaCard(
              // Keyed by item so a re-filter or re-sort moves the card with
              // its title.
              key: Key(item.globalKey),
              focusNode: node,
              item: item,
              viewModeOverride: ViewMode.grid,
              disableScale: position.disableScale,
              fullBleedImage: fullCardLayout,
              onRefresh: (_) => unawaited(_load()),
              onListRefresh: () => unawaited(_load()),
              onNavigateUp: position.isFirstRow ? _focusFilters : null,
              onNavigateLeft: position.isFirstColumn ? _focusSidebar : null,
              onBack: _focusSidebar,
              onFocusChange: (hasFocus) {
                if (hasFocus && isTv) _revealTv(node.context, alignment: 0.5);
              },
            );
          },
        );
      },
    );
  }
}

/// A filter or sort pill: translucent, outlined while its filter is set,
/// solid white on D-pad focus.
class _FilterPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final bool focused;
  final Duration duration;

  /// Null when an ancestor (an [AppMenuButton]) handles taps.
  final VoidCallback? onTap;

  const _FilterPill({
    required this.label,
    required this.icon,
    required this.active,
    required this.focused,
    required this.duration,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final foreground = focused ? Colors.black : Colors.white;
    final pill = AnimatedContainer(
      duration: duration,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.white.withValues(alpha: active ? 0.2 : 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withValues(alpha: focused ? 0 : (active ? 0.7 : 0.12)),
          width: active ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIcon(icon, size: 18, color: foreground),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: foreground, fontSize: isTv ? 15 : 14, fontWeight: FontWeight.w600),
          ),
          if (onTap == null) ...[
            const SizedBox(width: 4),
            AppIcon(Symbols.arrow_drop_down_rounded, size: 20, color: foreground),
          ],
        ],
      ),
    );
    if (onTap == null) return pill;
    return ClickableCursor(
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}

/// The rotating hero: the title's backdrop, faded to the left behind its
/// name, facts and actions (play, take off this list, details), with a dot
/// per title in the corner.
class _Hero extends StatelessWidget {
  final MediaItem item;
  final int index;
  final int count;
  final SiloPersonalList list;
  final GlobalKey<FocusableActionBarState> actionBarKey;
  final ValueChanged<int> onDot;
  final VoidCallback onPlay;
  final VoidCallback onRemove;
  final VoidCallback onInfo;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback onBack;
  final ValueChanged<bool> onFocusChange;

  const _Hero({
    required this.item,
    required this.index,
    required this.count,
    required this.list,
    required this.actionBarKey,
    required this.onDot,
    required this.onPlay,
    required this.onRemove,
    required this.onInfo,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onBack,
    required this.onFocusChange,
  });

  String _facts() {
    final parts = <String>[
      item.kind == MediaKind.show ? t.discover.tvShow : t.discover.movie,
      if (item.year != null) '${item.year}',
      if (item.kind == MediaKind.show && (item.childCount ?? 0) > 0)
        t.watchlistPage.seasons(n: item.childCount!)
      else if (item.kind != MediaKind.show && (item.durationMs ?? 0) > 0)
        formatDurationTextual(item.durationMs!),
      if (item.genres case final genres? when genres.isNotEmpty) genres.take(2).join(', '),
    ];
    return parts.join('  ·  ');
  }

  ({String label, double? progress}) _playLabel() {
    if (item.hasActiveProgress) {
      return (label: t.watchlistPage.resume, progress: item.viewOffsetMs! / item.durationMs!);
    }
    if (item.isPartiallyWatched) return (label: t.watchlistPage.resume, progress: item.leafWatchFraction);
    if (item.isWatched) return (label: t.watchlistPage.watchAgain, progress: null);
    return (label: t.common.play, progress: null);
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final background = Theme.of(context).scaffoldBackgroundColor;
    final radius = BorderRadius.circular(isTv ? 16 : 14);
    final backdrop = item.heroBackdropPaths.firstOrNull ?? item.artPath;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final play = _playLabel();
    final isWatchlist = list == SiloPersonalList.watchlist;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        final pad = compact ? 20.0 : (isTv ? 32.0 : 36.0);
        final titleStyle =
            (compact ? Theme.of(context).textTheme.headlineMedium : Theme.of(context).textTheme.displaySmall)?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.05,
            );

        return ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 450),
                child: KeyedSubtree(
                  key: ValueKey(item.globalKey),
                  child: backdrop == null
                      ? const SizedBox.expand()
                      : OptimizedMediaImage(
                          client: client,
                          imagePath: backdrop,
                          width: constraints.maxWidth,
                          height: constraints.maxHeight,
                          imageType: ImageType.art,
                          alignment: const Alignment(0, -0.2),
                        ),
                ),
              ),
              // Fade the art toward the copy: left, then the bottom on phones.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      background.withValues(alpha: 0.9),
                      background.withValues(alpha: 0.55),
                      background.withValues(alpha: 0),
                    ],
                    stops: compact ? const [0, 0.6, 1] : const [0, 0.34, 0.62],
                  ),
                ),
              ),
              if (compact)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [background.withValues(alpha: 0), background.withValues(alpha: 0.85)],
                      stops: const [0.35, 1],
                    ),
                  ),
                ),
              Positioned(
                left: pad,
                right: pad,
                bottom: pad,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: compact ? double.infinity : constraints.maxWidth * 0.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.displayTitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
                      const SizedBox(height: 8),
                      Text(
                        _facts(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: isTv ? 15 : 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: isTv ? 18 : 16),
                      FocusableActionBar(
                        key: actionBarKey,
                        spacing: 12,
                        onNavigateUp: onNavigateUp,
                        onNavigateDown: onNavigateDown,
                        onNavigateLeft: onNavigateLeft,
                        onNavigateRight: onNavigateRight,
                        onBack: onBack,
                        onFocusChange: onFocusChange,
                        actions: [
                          FocusableAction(
                            debugLabel: 'watchlist_hero_play',
                            onPressed: onPlay,
                            builder: (context, state) => _PlayPill(
                              label: play.label,
                              progress: play.progress,
                              focused: state.showFocus,
                              duration: state.animationDuration,
                              onTap: onPlay,
                            ),
                          ),
                          FocusableAction(
                            debugLabel: 'watchlist_hero_remove',
                            onPressed: onRemove,
                            builder: (context, state) => _CircleButton(
                              icon: isWatchlist ? Symbols.bookmark_rounded : Symbols.favorite_rounded,
                              filled: true,
                              tooltip: isWatchlist
                                  ? t.watchlistPage.removeFromWatchlist
                                  : t.watchlistPage.removeFromFavorites,
                              focused: state.showFocus,
                              duration: state.animationDuration,
                              onTap: onRemove,
                            ),
                          ),
                          FocusableAction(
                            debugLabel: 'watchlist_hero_info',
                            onPressed: onInfo,
                            builder: (context, state) => _CircleButton(
                              icon: Symbols.info_rounded,
                              tooltip: t.discover.overview,
                              focused: state.showFocus,
                              duration: state.animationDuration,
                              onTap: onInfo,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (count > 1)
                Positioned(
                  right: pad,
                  bottom: pad,
                  child: _Dots(count: count, index: index, onTap: onDot),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The white Play pill; resumable titles show their progress in it.
class _PlayPill extends StatelessWidget {
  final String label;
  final double? progress;
  final bool focused;
  final Duration duration;
  final VoidCallback onTap;

  const _PlayPill({
    required this.label,
    required this.progress,
    required this.focused,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final height = isTv ? 44.0 : 48.0;
    const foreground = Colors.black;
    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: focused ? FocusTheme.focusScale : 1,
          duration: duration,
          child: AnimatedContainer(
            duration: duration,
            height: height,
            padding: EdgeInsets.symmetric(horizontal: isTv ? 22 : 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(height / 2),
              boxShadow: focused ? [BoxShadow(color: Colors.white.withValues(alpha: 0.3), blurRadius: 18)] : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const AppIcon(Symbols.play_arrow_rounded, fill: 1, size: 24, color: foreground),
                const SizedBox(width: 8),
                if (progress case final progress?) ...[
                  Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        decoration: BoxDecoration(color: foreground, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(color: foreground, fontSize: isTv ? 16 : 15, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An outlined round icon button; solid white when focused.
class _CircleButton extends StatelessWidget {
  final IconData icon;
  final bool filled;
  final String tooltip;
  final bool focused;
  final Duration duration;
  final VoidCallback onTap;

  const _CircleButton({
    required this.icon,
    this.filled = false,
    required this.tooltip,
    required this.focused,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = PlatformDetector.isTV() ? 44.0 : 48.0;
    final foreground = focused ? Colors.black : Colors.white;
    return Tooltip(
      message: tooltip,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedScale(
            scale: focused ? FocusTheme.focusScale : 1,
            duration: duration,
            child: AnimatedContainer(
              duration: duration,
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: focused ? Colors.white : Colors.white.withValues(alpha: 0.14),
                border: Border.all(color: Colors.white.withValues(alpha: focused ? 0 : 0.4), width: 1.5),
              ),
              child: Center(
                child: AppIcon(icon, fill: filled ? 1 : 0, size: 22, color: foreground),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A dot per hero title, the shown one stretched into a bar.
class _Dots extends StatelessWidget {
  final int count;
  final int index;
  final ValueChanged<int> onTap;

  const _Dots({required this.count, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          ExcludeFocus(
            child: ClickableCursor(
              child: GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: i == index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == index ? Colors.white : Colors.white.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The category tiles: one row of up to four (two by two on phones), each
/// a name, a count and a fan of three of its posters.
class _CategoryTiles extends StatefulWidget {
  final List<_Category> categories;
  final ValueChanged<_Category> onOpen;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback onNavigateToSidebar;
  final VoidCallback? onFocusEntered;

  const _CategoryTiles({
    super.key,
    required this.categories,
    required this.onOpen,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateToSidebar,
    this.onFocusEntered,
  });

  @override
  State<_CategoryTiles> createState() => _CategoryTilesState();
}

class _CategoryTilesState extends State<_CategoryTiles> {
  final List<FocusNode> _nodes = [for (var i = 0; i < 4; i++) FocusNode(debugLabel: 'watchlist_tile_$i')];
  int _focused = 0;

  /// Columns in the last layout: four, or two on narrow screens.
  int _columns = 4;

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _count => math.min(widget.categories.length, _nodes.length);

  void requestFocus() => _nodes[_focused.clamp(0, _count - 1)].requestFocus();

  KeyEventResult _onKey(int i, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isSelectKey) return handleOneShotSelect(event, () => widget.onOpen(widget.categories[i]));
    final back = handleBackKeyAction(event, widget.onNavigateToSidebar);
    if (back != KeyEventResult.ignored) return back;
    if (!key.isDpadDirection) return KeyEventResult.ignored;
    if (!event.isActionable) return KeyEventResult.handled;

    final column = i % _columns;
    if (key.isLeftKey) {
      column == 0 ? widget.onNavigateToSidebar() : _nodes[i - 1].requestFocus();
    } else if (key.isRightKey) {
      if (column < _columns - 1 && i + 1 < _count) _nodes[i + 1].requestFocus();
    } else if (key.isUpKey) {
      i - _columns >= 0 ? _nodes[i - _columns].requestFocus() : widget.onNavigateUp();
    } else if (key.isDownKey) {
      i + _columns < _count ? _nodes[i + _columns].requestFocus() : widget.onNavigateDown();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    const gap = 12.0;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocusEntered?.call();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          _columns = constraints.maxWidth < 700 ? 2 : 4;
          final width = (constraints.maxWidth - gap * (_columns - 1)) / _columns;
          final height = isTv ? 92.0 : (_columns == 2 ? 104.0 : 112.0);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < _count; i++)
                _CategoryTile(
                  category: widget.categories[i],
                  width: width,
                  height: height,
                  focusNode: _nodes[i],
                  onKey: (event) => _onKey(i, event),
                  onFocusChange: (hasFocus) {
                    if (hasFocus) _focused = i;
                  },
                  onTap: () => widget.onOpen(widget.categories[i]),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatefulWidget {
  final _Category category;
  final double width;
  final double height;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.category,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onKey,
    required this.onFocusChange,
    required this.onTap,
  });

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = FocusTheme.getAnimationDuration(context);
    final radius = BorderRadius.circular(12);
    final category = widget.category;
    final posters = category.items.take(3).toList(growable: false);
    final posterHeight = widget.height * 0.86;
    final posterWidth = posterHeight * 2 / 3;

    Widget poster(MediaItem item, {required double angle, required double right, required double bottom}) {
      return Positioned(
        right: right,
        bottom: bottom,
        child: Transform.rotate(
          angle: angle,
          child: Container(
            width: posterWidth,
            height: posterHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: OptimizedMediaImage.poster(
                client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                imagePath: item.posterThumb(),
                width: posterWidth,
                height: posterHeight,
                placeholder: (context, _) => ColoredBox(color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
          ),
        ),
      );
    }

    // Back to front: the left poster under the middle, the right on top.
    final fan = <Widget>[
      if (posters.length > 2) poster(posters[2], angle: -0.16, right: posterWidth * 0.95, bottom: -posterHeight * 0.3),
      if (posters.length > 1) poster(posters[1], angle: -0.03, right: posterWidth * 0.48, bottom: -posterHeight * 0.2),
      poster(posters[0], angle: 0.12, right: 8, bottom: -posterHeight * 0.28),
    ];

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: (_, event) => widget.onKey(event),
      onFocusChange: (hasFocus) {
        setState(() => _focused = hasFocus);
        widget.onFocusChange(hasFocus);
      },
      child: ClickableCursor(
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _focused ? FocusTheme.focusScale : 1,
            duration: duration,
            child: AnimatedContainer(
              duration: duration,
              width: widget.width,
              height: widget.height,
              foregroundDecoration: FocusTheme.focusDecoration(
                context,
                isFocused: _focused,
                radii: radius,
                borderStrokeAlign: BorderSide.strokeAlignOutside,
              ),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2A2D34), Color(0xFF17191E)],
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(
                  children: [
                    ...fan,
                    Positioned(
                      left: 16,
                      top: 14,
                      right: posterWidth * 1.6,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category.label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.discover.titleCount(n: category.items.length),
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown while a list loads, when it is empty, or when it could not be read.
class _EmptyState extends StatelessWidget {
  final bool loading;
  final bool failed;
  final String title;

  const _EmptyState({required this.loading, required this.failed, required this.title});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(
              failed ? Symbols.cloud_off_rounded : Symbols.bookmark_rounded,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              failed ? t.watchlistPage.loadFailed : title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (!failed) ...[
              const SizedBox(height: 8),
              Text(
                t.watchlistPage.emptyHint,
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
