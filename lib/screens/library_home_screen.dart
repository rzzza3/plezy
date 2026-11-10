import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../navigation/main_screen_scope.dart';
import '../navigation/navigation_tabs.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/discover_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/library_rows.dart';
import '../services/settings_service.dart';
import '../utils/formatters.dart';
import '../utils/hub_icons.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../widgets/app_icon.dart';
import '../widgets/app_menu.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/hub_section.dart';
import '../widgets/poster_wall_hero.dart';
import '../widgets/tv_browse_rail.dart';
import 'library_calendar_section.dart';
import 'library_for_you_section.dart';
import 'library_genres_section.dart';
import 'library_networks_section.dart';
import 'library_runtime_section.dart';
import 'library_seasonal_section.dart';
import 'settings/library_networks_screen.dart';

/// Which kinds of media the hero's poster wall draws from.
enum LibraryHomeFilter {
  moviesAndShows,
  movies,
  shows;

  bool accepts(MediaKind kind) {
    final isMovie = kind == MediaKind.movie;
    final isShow = kind == MediaKind.show || kind == MediaKind.season || kind == MediaKind.episode;
    return switch (this) {
      moviesAndShows => isMovie || isShow,
      movies => isMovie,
      shows => isShow,
    };
  }
}

/// The Library tab: a hero (a time-of-day greeting over a tilted wall of
/// posters, with a media-type filter and a Browse All shortcut) above the
/// [LibraryRow]s: Home's Continue Watching row, the [LibraryCalendarSection],
/// Seasonal Picks, the [LibraryRuntimeSection], [LibraryForYouSection],
/// [LibraryNetworksSection] and [LibraryGenresSection]. The user picks which
/// rows show and in what order on the Edit Library page.
///
/// The hero and Continue Watching come from what Home already loaded
/// ([DiscoverProvider]); the sections below them make requests of their own.
class LibraryHomeScreen extends StatefulWidget {
  const LibraryHomeScreen({super.key});

  @override
  State<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends State<LibraryHomeScreen> with TabVisibilityAware, FocusableTab {
  final _actionBarKey = GlobalKey<FocusableActionBarState>();
  final _filterMenuKey = GlobalKey<AppMenuButtonState<LibraryHomeFilter>>();
  LibraryHomeFilter _filter = LibraryHomeFilter.moviesAndShows;

  final _continueWatchingKey = GlobalKey<HubSectionState>();
  final _tvBrowseRailKey = GlobalKey<TvBrowseRailState>();
  final _hubFocusMemory = HubFocusMemory();
  final _calendarKey = GlobalKey<LibraryCalendarSectionState>();
  final _tvContinueWatchingBoxKey = GlobalKey();
  final _seasonalKey = GlobalKey<LibrarySeasonalSectionState>();
  final _runtimeKey = GlobalKey<LibraryRuntimeSectionState>();
  final _forYouKey = GlobalKey<LibraryForYouSectionState>();
  final _networksKey = GlobalKey<LibraryNetworksSectionState>();
  final _genresKey = GlobalKey<LibraryGenresSectionState>();

  /// TV scrolls the page itself as focus moves between sections.
  final _tvScroll = ScrollController();

  /// The TV section focus last entered and how it aligns, so it can be put
  /// back when a section changes height (most often one above it finishing
  /// its first load). Null while focus is in the hero, which sits at the top.
  GlobalKey? _tvAnchor;
  double _tvAnchorAlignment = 1;
  bool _tvReanchorScheduled = false;

  // Memoized on the provider's list identity (it replaces onDeck on change,
  // never mutates it) so unrelated rebuilds hand TvBrowseRail the same hubs
  // list and it keeps its scroll and focus position.
  List<MediaHub>? _continueWatchingHubs;
  (List<MediaItem>, bool, String, LibraryHomeFilter)? _continueWatchingHubsKey;

  // Memoized like Continue Watching, so the seasonal row keeps its position.
  MediaHub? _seasonalHub;
  (MediaHub?, LibraryHomeFilter)? _seasonalHubKey;

  late final MultiServerProvider _servers = context.read<MultiServerProvider>();

  /// The rows below the hero, in order, as set on the Edit Library page.
  List<LibraryRow> _rows = LibraryRow.shown();
  late final Listenable _rowPrefs = SettingsService.instance.listenableOfAll(const [
    SettingsService.libraryRowOrder,
    SettingsService.libraryRowsHidden,
  ]);

  void _onRowsChanged() {
    if (mounted) setState(() => _rows = LibraryRow.shown());
  }

  @override
  void initState() {
    super.initState();
    // The tab can open before a Silo server is online (straight after
    // sign-in), when every section finds no server to read.
    _servers.addOnlineServersListener(_onOnlineServersChanged);
    _rowPrefs.addListener(_onRowsChanged);
    // Home owns the initial load; start it here only when Home never ran.
    final discover = context.read<DiscoverProvider>();
    if (discover.hubs.isEmpty && discover.onDeck.isEmpty && !discover.isLoadInFlight) {
      unawaited(discover.load());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimInitialFocus());
  }

  /// The hero button focus was given on a cold start, held so focus can move
  /// on to Resume when Continue Watching lands after it, unless the user has
  /// moved on by then.
  FocusNode? _initialFocus;

  /// On a cold start MainScreen focuses its content scope, not a control in
  /// it. Left there, the first D-pad press runs Flutter's directional search
  /// from nowhere, and LEFT lands on the page's right-most card (the end of
  /// For You) and scrolls down to it rather than opening the sidebar. So while
  /// focus is still nowhere (no node, or a bare scope), take it to the hero's
  /// first button, as Home does with its rail. Focus on a real control, such
  /// as the sidebar item that opened this tab, is left alone.
  void _claimInitialFocus() {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && focus is! FocusScopeNode) return;
    _actionBarKey.currentState?.requestFocusOnFirst();
    // Focus changes apply after this callback; read the result next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _initialFocus = FocusManager.instance.primaryFocus;
    });
  }

  /// Resume arrived after the initial claim: move focus to it if it is still
  /// where the claim put it.
  void _handInitialFocusToResume() {
    final held = _initialFocus;
    if (held == null) return;
    _initialFocus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(FocusManager.instance.primaryFocus, held)) {
        _actionBarKey.currentState?.requestFocusOnFirst();
      }
    });
  }

  @override
  void dispose() {
    _servers.removeOnlineServersListener(_onOnlineServersChanged);
    _rowPrefs.removeListener(_onRowsChanged);
    _tvScroll.dispose();
    super.dispose();
  }

  @override
  void onTabShown() {
    // The greeting follows the clock; pick up a period change since last visit.
    setState(() {});
    _retryUnavailable();
  }

  void _onOnlineServersChanged(Set<String> _) {
    if (mounted) _retryUnavailable();
  }

  /// Read again each section whose last read failed or found no server.
  void _retryUnavailable() {
    _calendarKey.currentState?.refreshIfStale();
    _runtimeKey.currentState?.retryIfUnavailable();
    _forYouKey.currentState?.retryIfUnavailable();
    _networksKey.currentState?.retryIfUnavailable();
    _genresKey.currentState?.retryIfUnavailable();
  }

  @override
  void onTabHidden() {}

  @override
  void focusActiveTabIfReady() {
    _actionBarKey.currentState?.requestFocusOnFirst();
  }

  void _focusSidebar() => MainScreenFocusScope.focusSidebarOf(context);

  void _focusActions() => _actionBarKey.currentState?.requestFocusOnFirst();

  /// Whether [row] is on screen to take focus. Rows that pass focus along
  /// themselves when empty (the calendar and runtime row before a server is
  /// online) count as shown once built.
  bool _canFocus(LibraryRow row) => switch (row) {
    LibraryRow.continueWatching => _tvBrowseRailKey.currentState != null || _continueWatchingKey.currentState != null,
    LibraryRow.calendar => _calendarKey.currentState != null,
    LibraryRow.seasonal => _seasonalKey.currentState != null,
    LibraryRow.runtime => _runtimeKey.currentState != null,
    LibraryRow.forYou => _forYouKey.currentState?.isShown ?? false,
    LibraryRow.networks => _networksKey.currentState?.isShown ?? false,
    LibraryRow.genres => _genresKey.currentState?.isShown ?? false,
  };

  /// Focus [row], coming DOWN from above it.
  void _enterFromAbove(LibraryRow row) {
    switch (row) {
      case LibraryRow.continueWatching:
        final tvRail = _tvBrowseRailKey.currentState;
        if (tvRail != null) {
          tvRail.requestFocus();
        } else {
          _continueWatchingKey.currentState?.requestFocusFromMemory();
        }
      case LibraryRow.calendar:
        _calendarKey.currentState?.requestFocus();
      case LibraryRow.seasonal:
        _seasonalKey.currentState?.requestFocus();
      case LibraryRow.runtime:
        _runtimeKey.currentState?.requestFocus();
      case LibraryRow.forYou:
        _forYouKey.currentState?.requestFocus();
      case LibraryRow.networks:
        _networksKey.currentState?.requestFocus();
      case LibraryRow.genres:
        _genresKey.currentState?.requestFocus();
    }
  }

  /// Focus [row], coming UP from below it: its cards where it has a strip
  /// above them.
  void _enterFromBelow(LibraryRow row) {
    switch (row) {
      case LibraryRow.calendar:
        _calendarKey.currentState?.requestFocusFromBelow();
      case LibraryRow.runtime:
        _runtimeKey.currentState?.requestFocusFromBelow();
      case LibraryRow.networks:
        _networksKey.currentState?.requestFocusFromBelow();
      case LibraryRow.genres:
        _genresKey.currentState?.requestFocusFromBelow();
      case LibraryRow.continueWatching || LibraryRow.seasonal || LibraryRow.forYou:
        _enterFromAbove(row);
    }
  }

  /// DOWN from [from], or from the hero when null: the next shown row that
  /// can take focus, in the user's order.
  void _focusBelow(LibraryRow? from) {
    final index = from == null ? -1 : _rows.indexOf(from);
    if (from != null && index < 0) return;
    for (final row in _rows.skip(index + 1)) {
      if (_canFocus(row)) return _enterFromAbove(row);
    }
  }

  /// UP from [from]: the nearest shown row above that can take focus, else
  /// the hero.
  void _focusAbove(LibraryRow from) {
    final index = _rows.indexOf(from);
    for (final row in _rows.take(math.max(0, index)).toList().reversed) {
      if (_canFocus(row)) return _enterFromBelow(row);
    }
    _focusActions();
  }

  void _revealTvTop() {
    _tvAnchor = null;
    if (!_tvScroll.hasClients) return;
    unawaited(_tvScroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
  }

  /// Scroll a TV section into view: bottom-aligned by default, so the one
  /// above still peeks in; the calendar top-aligns, since its rail only
  /// appears once the day's episodes load, Seasonal Picks, one screen
  /// tall, top-aligns to fill it, and the runtime, Networks and Genres rows center
  /// with a band of page above and below. Runs after the frame, so it
  /// replaces the focused child's own minimal `showOnScreen` scroll.
  ///
  /// The section becomes the page's anchor: [_reanchorTv] holds it at this
  /// alignment while the sections around it finish loading.
  void _revealTv(GlobalKey section, {double alignment = 1}) {
    _tvAnchor = section;
    _tvAnchorAlignment = alignment;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _tvAnchorOffset();
      if (target == null) return;
      unawaited(_tvScroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
    });
  }

  /// The page offset that shows the anchor section at its alignment.
  double? _tvAnchorOffset() {
    final box = _tvAnchor?.currentContext?.findRenderObject();
    if (!mounted || box == null || !box.attached || !_tvScroll.hasClients) return null;
    final position = _tvScroll.position;
    return RenderAbstractViewport.of(
      box,
    ).getOffsetToReveal(box, _tvAnchorAlignment).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
  }

  /// A TV section changed height (a row loaded, a filter emptied a section, a
  /// section appeared): put the anchor back where focus left it, rather than
  /// let the focused row slide down the screen or out of view. Runs once
  /// after the frame however many sections changed in it.
  bool _onTvSectionResized(SizeChangedLayoutNotification _) {
    if (_tvAnchor == null || _tvReanchorScheduled) return true;
    _tvReanchorScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tvReanchorScheduled = false;
      final target = _tvAnchorOffset();
      if (target == null) return;
      final position = _tvScroll.position;
      if ((target - position.pixels).abs() < 0.5) return;
      if (position.isScrollingNotifier.value) {
        // Still on its way from a focus move: aim the same scroll at the new spot.
        unawaited(_tvScroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
      } else {
        // At rest: snap back so the focused row looks like it never moved.
        _tvScroll.jumpTo(target);
      }
    });
    return true;
  }

  /// The same synthesized row Home renders, narrowed to the header's filter,
  /// as a one-hub list (empty when nothing matching is in progress).
  List<MediaHub> _continueWatching(DiscoverProvider discover) {
    final key = (discover.onDeck, discover.hasMoreContinueWatching, t.discover.continueWatching, _filter);
    if (_continueWatchingHubs != null && key == _continueWatchingHubsKey) return _continueWatchingHubs!;
    _continueWatchingHubsKey = key;
    final hub = discover.continueWatchingHub(t.discover.continueWatching);
    final items = [
      for (final item in hub.items)
        if (_accepts(_filter, item.kind)) item,
    ];
    return _continueWatchingHubs = items.isEmpty
        ? const []
        : [hub.copyWith(items: items, size: items.length + (hub.more ? 1 : 0))];
  }

  /// View All for the row: the full Continue Watching list, same filter.
  Future<List<MediaItem>> _loadAllContinueWatching() async {
    final filter = _filter;
    final items = await context.read<DiscoverProvider>().loadAllContinueWatching();
    return [
      for (final item in items)
        if (_accepts(filter, item.kind)) item,
    ];
  }

  String _greeting(String? name) {
    final hour = DateTime.now().hour;
    final hasName = name != null && name.trim().isNotEmpty;
    if (hour >= 5 && hour < 12) {
      return hasName ? t.libraryHome.greetingMorningNamed(name: name) : t.libraryHome.greetingMorning;
    }
    if (hour >= 12 && hour < 17) {
      return hasName ? t.libraryHome.greetingAfternoonNamed(name: name) : t.libraryHome.greetingAfternoon;
    }
    if (hour >= 17 && hour < 22) {
      return hasName ? t.libraryHome.greetingEveningNamed(name: name) : t.libraryHome.greetingEvening;
    }
    return hasName ? t.libraryHome.greetingNightNamed(name: name) : t.libraryHome.greetingNight;
  }

  static String _filterLabel(LibraryHomeFilter filter) => switch (filter) {
    LibraryHomeFilter.moviesAndShows => t.libraryHome.moviesAndShows,
    LibraryHomeFilter.movies => t.libraryHome.movies,
    LibraryHomeFilter.shows => t.libraryHome.shows,
  };

  /// The server's seasonal section (Home's "Halloween Favorites" this time of
  /// year), narrowed by the header filter like Continue Watching.
  MediaHub? _seasonal(DiscoverProvider discover) {
    final hub = discover.hubs.where((hub) => hub.identifier == LibrarySeasonalSection.sectionType).firstOrNull;
    final key = (hub, _filter);
    if (key == _seasonalHubKey) return _seasonalHub;
    _seasonalHubKey = key;
    if (hub == null) return _seasonalHub = null;
    final items = [
      for (final item in hub.items)
        if (_accepts(_filter, item.kind)) item,
    ];
    return _seasonalHub = items.isEmpty ? null : hub.copyWith(items: items, size: items.length);
  }

  static bool _accepts(LibraryHomeFilter filter, MediaKind kind) => filter.accepts(kind);

  // Memoized on the Continue Watching list, which is memoized itself.
  Map<String, double>? _wallHighlights;
  List<MediaHub>? _wallHighlightsKey;

  /// Watch progress by poster path for what is part-watched in Continue
  /// Watching, in its order, for the wall to light up. An episode lights its
  /// show's poster; the most recent episode of a show wins.
  Map<String, double> _highlights(List<MediaHub> continueWatching) {
    if (_wallHighlights != null && identical(continueWatching, _wallHighlightsKey)) return _wallHighlights!;
    _wallHighlightsKey = continueWatching;
    final highlights = <String, double>{};
    for (final item in continueWatching.firstOrNull?.items ?? const <MediaItem>[]) {
      final path = item.posterThumb();
      if (path == null || !item.hasActiveProgress) continue;
      highlights.putIfAbsent(path, () => item.viewOffsetMs! / item.durationMs!);
    }
    return _wallHighlights = highlights;
  }

  /// One poster per title across Continue Watching and every hub. Episodes and
  /// seasons resolve to their show's poster, so the dedupe is by poster path.
  List<MediaItem> _wallItems(DiscoverProvider discover) {
    final seen = <String>{};
    final items = <MediaItem>[];
    for (final item in [...discover.onDeck, for (final hub in discover.hubs) ...hub.items]) {
      if (!_accepts(_filter, item.kind)) continue;
      final path = item.posterThumb();
      if (path == null || !seen.add(path)) continue;
      items.add(item);
      if (items.length >= PosterWall.maxPosters) break;
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isTv = PlatformDetector.isTV();
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final heroHeight = isTv
        ? size.height * 0.56
        : useSideNav
        ? math.max(size.height * 0.62, 360.0)
        : 420 + topInset;

    final name = context.watch<ActiveProfileProvider>().active?.displayName;
    final discover = context.watch<DiscoverProvider>();
    final posters = _wallItems(discover);
    final continueWatching = _continueWatching(discover);
    final resumeItem = continueWatching.firstOrNull?.items.firstOrNull;
    if (resumeItem != null) _handInitialFocusToResume();
    final seasonalHub = _seasonal(discover);
    // The shown rows with something to build: Continue Watching and Seasonal
    // Picks go when they have nothing in them.
    final built = [
      for (final row in _rows)
        if (switch (row) {
          LibraryRow.continueWatching => continueWatching.isNotEmpty,
          LibraryRow.seasonal => seasonalHub != null,
          _ => true,
        })
          row,
    ];
    final hero = PosterWallHero(
      title: _greeting(name),
      posters: posters,
      highlights: _highlights(continueWatching),
      actions: _buildActions(context, resume: resumeItem),
      // Extra room above a row that is not Continue Watching's rail.
      bottomPadding: isTv && built.firstOrNull != LibraryRow.continueWatching ? 64 : 40,
    );

    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    // Each shown row, in the user's order (set on the Edit Library page).
    // Hidden rows are never built, so they make no requests.
    Widget buildRow(LibraryRow row) {
      VoidCallback? reveal(GlobalKey key, double alignment) => isTv ? () => _revealTv(key, alignment: alignment) : null;
      void up() => _focusAbove(row);
      // The last row keeps DOWN to itself.
      final VoidCallback? down = row == built.last ? null : () => _focusBelow(row);
      switch (row) {
        case LibraryRow.continueWatching:
          if (isTv) {
            return Focus(
              key: _tvContinueWatchingBoxKey,
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (hasFocus) {
                if (hasFocus) _revealTv(_tvContinueWatchingBoxKey);
              },
              child: TvBrowseRail(
                key: _tvBrowseRailKey,
                hubs: continueWatching,
                initialHubId: 'continue_watching',
                focusMemory: _hubFocusMemory,
                onRefresh: discover.updateItem,
                onRemoveFromContinueWatching: discover.refreshContinueWatching,
                isContinueWatchingHub: (hub) => hub.isContinueWatchingHub,
                usesContinueWatchingAction: (hub) => hub.usesContinueWatchingAction,
                loadMoreItems: (_) => _loadAllContinueWatching,
                onNavigateUp: up,
                onNavigateDown: down,
                onNavigateToSidebar: _focusSidebar,
                onBack: _focusSidebar,
                tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                extraItemGap: 16,
                // The hero spotlights this row: it stays lit while the
                // hero has focus, and says how long each title has left.
                dimWhenUnfocused: false,
                showTimeLeft: true,
              ),
            );
          }
          final hub = continueWatching.single;
          return HubSection(
            key: _continueWatchingKey,
            hub: hub,
            focusMemory: _hubFocusMemory,
            icon: hubIconFor(hub),
            onRefresh: discover.updateItem,
            onRemoveFromContinueWatching: discover.refreshContinueWatching,
            isInContinueWatching: true,
            loadMoreItems: _loadAllContinueWatching,
            onVerticalNavigation: (isUp) => navigateVerticalHubRows(
              hubCount: 1,
              hubIndex: 0,
              isUp: isUp,
              onTopBoundary: up,
              onBottomBoundary: down,
              requestFocus: (_) {},
            ),
            onNavigateUp: up,
            onNavigateToSidebar: _focusSidebar,
          );
        case LibraryRow.calendar:
          return LibraryCalendarSection(
            key: _calendarKey,
            onNavigateUp: up,
            onNavigateToSidebar: _focusSidebar,
            onNavigateDown: down,
            onFocusEntered: reveal(_calendarKey, 0),
          );
        case LibraryRow.seasonal:
          return LibrarySeasonalSection(
            key: _seasonalKey,
            hub: seasonalHub!,
            onNavigateUp: up,
            onNavigateToSidebar: _focusSidebar,
            onNavigateDown: down,
            onFocusEntered: reveal(_seasonalKey, 0),
          );
        case LibraryRow.runtime:
          return LibraryRuntimeSection(
            key: _runtimeKey,
            onNavigateUp: up,
            onNavigateToSidebar: _focusSidebar,
            onNavigateDown: down,
            onFocusEntered: reveal(_runtimeKey, 0.5),
          );
        case LibraryRow.forYou:
          return LibraryForYouSection(
            key: _forYouKey,
            filter: _filter,
            onNavigateUp: up,
            onNavigateToSidebar: _focusSidebar,
            onNavigateDown: down,
            onFocusEntered: reveal(_forYouKey, 0),
          );
        case LibraryRow.networks:
          return LibraryNetworksSection(
            key: _networksKey,
            filter: _filter,
            onNavigateUp: up,
            onNavigateDown: down,
            onNavigateToSidebar: _focusSidebar,
            onFocusEntered: reveal(_networksKey, 0.5),
          );
        case LibraryRow.genres:
          return LibraryGenresSection(
            key: _genresKey,
            filter: _filter,
            onNavigateUp: up,
            onNavigateDown: down,
            onNavigateToSidebar: _focusSidebar,
            onFocusEntered: reveal(_genresKey, 0.5),
          );
      }
    }

    final rows = [for (final row in built) buildRow(row)];

    // TV stacks the hero and the rows in one page it scrolls by focus.
    if (isTv) {
      // Keyed by the section's own key, so a section appearing above another
      // (or a row moved on the Edit page) never hands it a different wrapper.
      Widget tracked(Widget section) => SizeChangedLayoutNotifier(key: ValueKey(section.key), child: section);
      return Material(
        color: theme.scaffoldBackgroundColor,
        // Each section, and the page as a whole (for a section that appears
        // or goes), reports a change of height so the focused one stays put.
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: _onTvSectionResized,
          child: SingleChildScrollView(
            controller: _tvScroll,
            child: SizeChangedLayoutNotifier(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: heroHeight, child: hero),
                  for (final section in rows) tracked(section),
                  // Room for the last row to scroll up to the center.
                  SizedBox(height: math.max(48, size.height / 2)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: theme.scaffoldBackgroundColor,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: heroHeight, child: hero),
          ),
          for (final section in rows) SliverToBoxAdapter(key: ValueKey(section.key), child: section),
          SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPadding)),
        ],
      ),
    );
  }

  /// The hero's buttons: Resume (the first title in Continue Watching, and
  /// so where focus lands), Browse All, the media-type filter and Edit.
  Widget _buildActions(BuildContext context, {required MediaItem? resume}) {
    return FocusableActionBar(
      key: _actionBarKey,
      spacing: 16,
      onNavigateLeft: _focusSidebar,
      onNavigateDown: () => _focusBelow(null),
      onBack: _focusSidebar,
      onFocusChange: (hasFocus) {
        if (hasFocus && PlatformDetector.isTV()) _revealTvTop();
      },
      actions: [
        if (resume != null)
          FocusableAction(
            debugLabel: 'library_home_resume',
            onPressed: () => _resume(resume),
            builder: (context, state) => _HeroPillButton(
              label: t.libraryHome.resumeTitle(title: resume.displayTitle),
              detail: resume.hasActiveProgress
                  ? t.libraryHome.timeLeft(duration: formatDurationTextual(resume.durationMs! - resume.viewOffsetMs!))
                  : null,
              leadingIcon: Symbols.play_arrow_rounded,
              focused: state.showFocus,
              duration: state.animationDuration,
              onTap: () => _resume(resume),
            ),
          ),
        FocusableAction(
          debugLabel: 'library_home_browse_all',
          onPressed: _browseAll,
          builder: (context, state) => _HeroPillButton(
            label: t.libraryHome.browseAll,
            leadingIcon: Symbols.grid_view_rounded,
            focused: state.showFocus,
            duration: state.animationDuration,
            onTap: _browseAll,
          ),
        ),
        FocusableAction(
          debugLabel: 'library_home_filter',
          onPressed: () => _filterMenuKey.currentState?.showButtonMenu(focusFirstItem: true),
          builder: (context, state) => AppMenuButton<LibraryHomeFilter>(
            key: _filterMenuKey,
            onSelected: (filter) => setState(() => _filter = filter),
            entriesBuilder: (context) => [
              for (final filter in LibraryHomeFilter.values)
                AppMenuItem(value: filter, label: _filterLabel(filter), selected: filter == _filter),
            ],
            child: _HeroPillButton(
              label: _filterLabel(_filter),
              trailingIcon: Symbols.unfold_more_rounded,
              focused: state.showFocus,
              duration: state.animationDuration,
            ),
          ),
        ),
        FocusableAction(
          debugLabel: 'library_home_edit',
          onPressed: _editRows,
          builder: (context, state) => _HeroPillButton(
            label: t.common.edit,
            leadingIcon: Symbols.tune_rounded,
            focused: state.showFocus,
            duration: state.animationDuration,
            onTap: _editRows,
          ),
        ),
      ],
    );
  }

  /// Play [item] from where it was left, as its Continue Watching card does.
  void _resume(MediaItem item) => unawaited(
    navigateToMediaItem(context, item, onRefresh: context.read<DiscoverProvider>().updateItem, playDirectly: true),
  );

  void _browseAll() => MainScreenFocusScope.selectTabOf(context, NavigationTabId.libraries);

  void _editRows() =>
      unawaited(Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const LibraryNetworksScreen())));
}

/// Translucent pill used for the hero actions; turns solid white on D-pad focus.
class _HeroPillButton extends StatelessWidget {
  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  /// Quieter text after [label], such as the time left.
  final String? detail;
  final bool focused;
  final Duration duration;

  /// Null when an ancestor (the filter's [AppMenuButton]) handles taps.
  final VoidCallback? onTap;

  const _HeroPillButton({
    required this.label,
    this.leadingIcon,
    this.trailingIcon,
    this.detail,
    required this.focused,
    required this.duration,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = focused ? Colors.black : Colors.white;
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600);

    final pill = AnimatedContainer(
      duration: duration,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: focused ? Colors.white : Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: focused ? 0 : 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[AppIcon(leadingIcon!, size: 20, color: foreground), const SizedBox(width: 10)],
          // A long title gives way before the time left does. A cap, not a
          // Flexible: the action bar lays the pills out unbounded.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          if (detail != null) ...[
            const SizedBox(width: 10),
            Text(
              detail!,
              maxLines: 1,
              style: style?.copyWith(fontWeight: FontWeight.w500, color: foreground.withValues(alpha: 0.62)),
            ),
          ],
          if (trailingIcon != null) ...[const SizedBox(width: 8), AppIcon(trailingIcon!, size: 20, color: foreground)],
        ],
      ),
    );
    if (onTap == null) return pill;
    return ClickableCursor(
      child: GestureDetector(onTap: onTap, child: pill),
    );
  }
}
