import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../exceptions/media_server_exceptions.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_item_merge.dart';
import '../media/media_person.dart';
import '../media/search_hit.dart';
import '../mixins/debounced_media_search.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/data_aggregation_service.dart';
import '../services/settings_service.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../utils/media_server_http_client.dart';
import '../utils/search_relevance.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/loading_indicator_box.dart';
import '../widgets/search_input_field.dart';
import '../widgets/app_icon.dart';
import '../widgets/hub_section.dart';
import '../widgets/media_grid_delegate.dart';
import '../widgets/settings_builder.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/person_search_row.dart';
import '../utils/focus_utils.dart';
import '../utils/media_navigation_helper.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/locked_hub_controller.dart';
import '../media/media_hub.dart';
import 'libraries/state_messages.dart';
import 'main_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with
        Refreshable,
        ManualRefreshable,
        FullRefreshable,
        SearchInputFocusable,
        FocusableTab,
        MountedSetStateMixin,
        DebouncedMediaSearch<SearchScreen, SearchHit> {
  String? _focusResultsForQuery;
  final _tvTextInputController = TvTextInputController();
  AbortController? _activeSearchAbort;
  ({String query, SearchAggregationResult result})? _pendingSearchOutcome;

  /// The pre-rank pools behind the ranked [searchResults]. The rails derive
  /// from them, so every result a server returned gets a place on screen.
  List<MediaItem> _searchCandidates = const [];
  List<MediaPerson> _searchPeople = const [];

  /// Movies, TV Shows, Cast & Crew, then any other kinds found.
  List<MediaHub> _rails = const [];

  /// The person behind each Cast & Crew rail item, by [MediaItem.id].
  Map<String, MediaPerson> _railPeople = const {};

  final _focusMemory = HubFocusMemory();
  final Map<String, GlobalKey<TvBrowseRailState>> _tvRailKeys = {};
  final Map<String, GlobalKey<HubSectionState>> _hubKeys = {};
  final Map<String, List<MediaHub>> _railHubLists = {};
  late final FocusNode _firstPersonFocusNode = FocusNode(debugLabel: 'SearchFirstPerson');

  HiddenLibrariesProvider? _hiddenLibraries;
  Set<String> _lastSeenHiddenKeys = const {};

  @override
  void initState() {
    super.initState();
    FocusUtils.requestFocusAfterBuild(this, searchFocusNode);
    unawaited(_bindHiddenLibraries());
  }

  @override
  void dispose() {
    _hiddenLibraries?.removeListener(_onHiddenLibrariesChanged);
    _firstPersonFocusNode.dispose();
    super.dispose();
  }

  /// Re-run the visible query when a library is hidden or unhidden while
  /// results are on screen. The listener is attached only after the provider
  /// has hydrated, so its initial load notification cannot race the first
  /// query — which awaits that same hydration — into running twice.
  Future<void> _bindHiddenLibraries() async {
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    await hiddenLibraries.ensureInitialized();
    if (!mounted) return;
    _lastSeenHiddenKeys = Set.of(hiddenLibraries.hiddenLibraryKeys);
    _hiddenLibraries = hiddenLibraries..addListener(_onHiddenLibrariesChanged);
  }

  void _onHiddenLibrariesChanged() {
    final hiddenLibraries = _hiddenLibraries;
    if (hiddenLibraries == null || !mounted) return;
    final currentKeys = hiddenLibraries.hiddenLibraryKeys;
    if (currentKeys.length == _lastSeenHiddenKeys.length && currentKeys.containsAll(_lastSeenHiddenKeys)) {
      return;
    }
    _lastSeenHiddenKeys = Set.of(currentKeys);
    final query = searchController.text.trim();
    if (query.isEmpty || !hasSearched) return;
    unawaited(runSearch(query));
  }

  @override
  String get searchDebugLabel => 'Search';

  @override
  Future<List<SearchHit>> performSearchQuery(String query) async {
    final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);
    if (!multiServerProvider.hasConnectedServers) {
      throw const _SearchUnavailableException();
    }

    // Hidden-library keys must be hydrated before the first query, or a cold
    // start would filter nothing. Read before any await: the profile subtree
    // can be torn down mid-search.
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    await hiddenLibraries.ensureInitialized();
    if (!mounted) return const [];

    final abort = AbortController();
    _activeSearchAbort = abort;
    try {
      final result = await multiServerProvider.aggregationService.searchAcrossServers(
        query,
        hiddenLibraryKeys: hiddenLibraries.hiddenLibraryKeys,
        abort: abort,
      );
      abort.throwIfAborted();
      if (result.succeededServerIds.isEmpty && result.failedServerIds.isNotEmpty) {
        throw const _SearchUnavailableException();
      }
      if (result.succeededServerIds.isEmpty && result.cancelledServerIds.isNotEmpty) {
        throw MediaServerHttpException(
          type: MediaServerHttpErrorType.cancelled,
          message: 'Search was cancelled before any server completed',
        );
      }
      _pendingSearchOutcome = (query: query, result: result);
      return result.hits;
    } finally {
      if (identical(_activeSearchAbort, abort)) _activeSearchAbort = null;
    }
  }

  @override
  void onSearchInvalidated() {
    _activeSearchAbort?.abort();
    _activeSearchAbort = null;
    _pendingSearchOutcome = null;
  }

  @override
  void onSearchError(Object error) {
    _focusResultsForQuery = null;
    _pendingSearchOutcome = null;
    _resetRails();
    final message = error is _SearchUnavailableException
        ? t.errors.searchUnavailable
        : t.errors.searchFailed(error: error);
    showErrorSnackBar(context, message);
  }

  @override
  void onSearchCleared() {
    _focusResultsForQuery = null;
    _pendingSearchOutcome = null;
    _resetRails();
  }

  @override
  void onSearchCompleted(String query, List<SearchHit> results) {
    final outcome = _pendingSearchOutcome;
    _pendingSearchOutcome = null;
    final matched = outcome != null && outcome.query == query ? outcome.result : null;

    // Committed alongside the results the pending setState renders (build has
    // not run yet).
    _searchCandidates =
        matched?.candidates ??
        [
          for (final hit in results)
            if (hit case MediaSearchHit(:final item)) item,
        ];
    _searchPeople =
        matched?.people ??
        [
          for (final hit in results)
            if (hit case PersonSearchHit(:final person)) person,
        ];
    _rebuildRails(query);

    if (matched != null && matched.failedServerIds.isNotEmpty) {
      showAppSnackBar(context, t.messages.searchPartialResults);
    }

    if (_focusResultsForQuery == null || _focusResultsForQuery != query) return;
    _focusResultsForQuery = null;
    if (results.isEmpty) return;
    if (searchController.text.trim() != query) return; // user kept editing
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusFirstResult();
    });
  }

  /// OSK "Search" / hardware Enter on TV additionally focuses the results
  /// when the forced search lands.
  @override
  void handleSearchSubmit() {
    final query = searchController.text.trim();
    if (query.isEmpty) return;
    if (searchResults.isEmpty || isSearching || query != lastSearchedQuery) {
      _focusResultsForQuery = query;
    }
    super.handleSearchSubmit();
  }

  @override
  void focusFirstResult() {
    if (_rails.isNotEmpty) _focusRail(0);
  }

  @override
  void refresh() {
    if (!mounted) return;
    runSearch(searchController.text.trim());
  }

  /// Cmd+R / Ctrl+R re-runs the query currently on screen; `runSearch` no-ops
  /// on an empty field.
  @override
  void manualRefresh() => refresh();

  /// Focus the search input field
  @override
  void focusSearchInput() {
    if (!mounted) return;
    searchFocusNode.requestFocus();
  }

  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    searchFocusNode.requestFocus();
  }

  /// Apply a complete query submitted from the Plezy companion remote: set the
  /// text, dismiss any open on-screen keyboard, land focus on the input without
  /// (re)opening the OSK, and run the search now — the first result takes focus
  /// when it lands (via onSearchCompleted). The user already typed the query on
  /// their phone, so the TV keyboard must never be up afterwards.
  @override
  void submitSearchQuery(String query) {
    if (!mounted) return;
    final trimmed = query.trim();
    searchController.text = trimmed; // listener arms the debounce / resets state

    // Focusing the field normally auto-opens the OSK; a remote search must not
    // show it, and must dismiss one the TV user already had open (the phone's
    // Search chip sends tabSearch before the query arrives).
    _tvTextInputController.closeTextInput();
    if (trimmed.isEmpty) return;

    // Land focus on the (visible) input immediately so the D-pad remote is
    // never stranded on the hidden previous tab — while the search is in
    // flight, when it fails, and when it returns nothing.
    _tvTextInputController.focusInputWithoutOpening();

    // Same path as the OSK Search key: jumps straight to already-matching
    // results, or cancels the debounce and runs now; the screen override arms
    // _focusResultsForQuery so results take focus when they land.
    handleSearchSubmit();
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    if (!mounted) return;
    appLogger.d('SearchScreen.fullRefresh() called - clearing search and reloading');
    // Clearing the field resets the search state through the text listener.
    _focusResultsForQuery = null;
    searchController.clear();
  }

  Future<void> updateItem(MediaItem source) async {
    if (!mounted) return;
    final serverId = source.serverId;
    if (serverId == null) return;

    try {
      final multiServer = context.read<MultiServerProvider>();
      final updated = await multiServer.getClientForServer(ServerId(serverId))?.fetchItem(source.id);
      if (!mounted || updated == null) return;
      // A fresh `fetchItem` may carry no library field, and a
      // library-less row would lose its label (#1970); keep the identity
      // and library context the search stamped on the original row.
      final merged = mergeFetchedMediaItem(fetched: updated, fallbackServerId: ServerId(serverId), existing: source);
      // Refresh every copy so a later rebuild cannot resurrect the stale row.
      // The rails swap the item where it stands rather than re-ranking, so a
      // changed title never moves the card out from under focus.
      var replaced = _replaceHitByGlobalKey(searchResults, source.globalKey, merged);
      replaced = _replaceByGlobalKey(_searchCandidates, source.globalKey, merged) || replaced;
      replaced = _replaceInRails(source.globalKey, merged) || replaced;
      if (replaced) setState(() {});
    } catch (e) {
      appLogger.d('Search item refresh skipped for ${source.globalKey}', error: e);
    }
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.focusSidebarOf(context);
  }

  /// Rail order after Movies, TV Shows and Cast & Crew. Episodes get no rail:
  /// their show's rail covers them. `folder`/`unknown` are never search kinds.
  static const List<MediaKind> _otherRailKinds = [
    MediaKind.season,
    MediaKind.artist,
    MediaKind.album,
    MediaKind.track,
    MediaKind.collection,
    MediaKind.playlist,
    MediaKind.clip,
    MediaKind.photo,
  ];

  static const String _peopleRailId = 'search_people';

  void _rebuildRails(String query) {
    MediaHub? kindRail(MediaKind kind) {
      final ofKind = [
        for (final candidate in _searchCandidates)
          if (candidate.kind == kind) candidate,
      ];
      if (ofKind.isEmpty) return null;
      final ranked = rankMediaSearchResults(ofKind, query);
      return MediaHub(
        id: 'search_${kind.id}',
        title: _kindRailLabel(kind),
        type: kind.id,
        items: ranked,
        size: ranked.length,
      );
    }

    final people = rankPeopleSearchResults(_searchPeople, query);
    final personItems = <String, MediaPerson>{};
    final peopleItems = [for (final person in people) _personRailItem(person, (id) => personItems[id] = person)];
    _railPeople = personItems;
    _rails = [
      ?kindRail(MediaKind.movie),
      ?kindRail(MediaKind.show),
      if (peopleItems.isNotEmpty)
        MediaHub(
          id: _peopleRailId,
          title: t.search.castAndCrew,
          type: 'person',
          items: peopleItems,
          size: peopleItems.length,
        ),
      for (final kind in _otherRailKinds) ?kindRail(kind),
    ];
  }

  /// A person as a TV rail item: name as title, credit as the second line.
  MediaItem _personRailItem(MediaPerson person, void Function(String id) register) {
    final id = person.globalKey;
    register(id);
    return MediaItem(
      id: id,
      backend: person.backend,
      kind: MediaKind.unknown,
      title: person.name,
      parentTitle: switch (person.credit) {
        PersonCredit.actor => t.explore.creditRole.actor,
        PersonCredit.director => t.explore.creditRole.director,
        null => null,
      },
      thumbPath: person.thumbPath,
      serverId: person.serverId,
      serverName: person.serverName,
    );
  }

  void _resetRails() {
    _searchCandidates = const [];
    _searchPeople = const [];
    _rails = const [];
    _railPeople = const {};
  }

  static bool _replaceByGlobalKey(List<MediaItem> items, String globalKey, MediaItem replacement) {
    final index = items.indexWhere((item) => item.globalKey == globalKey);
    if (index == -1) return false;
    items[index] = replacement;
    return true;
  }

  bool _replaceInRails(String globalKey, MediaItem replacement) {
    final rails = [..._rails];
    var replaced = false;
    for (var i = 0; i < rails.length; i++) {
      final hub = rails[i];
      final index = hub.items.indexWhere((item) => item.globalKey == globalKey);
      if (index == -1) continue;
      final items = [...hub.items]..[index] = replacement;
      rails[i] = MediaHub(id: hub.id, title: hub.title, type: hub.type, items: items, size: items.length);
      replaced = true;
    }
    if (replaced) _rails = rails;
    return replaced;
  }

  static bool _replaceHitByGlobalKey(List<SearchHit> hits, String globalKey, MediaItem replacement) {
    final index = hits.indexWhere((hit) => hit is MediaSearchHit && hit.globalKey == globalKey);
    if (index == -1) return false;
    hits[index] = MediaSearchHit(replacement);
    return true;
  }

  String _kindRailLabel(MediaKind kind) => switch (kind) {
    MediaKind.movie => t.libraries.groupings.movies,
    MediaKind.show => t.libraries.groupings.shows,
    MediaKind.season => t.libraries.groupings.seasons,
    MediaKind.episode => t.libraries.groupings.episodes,
    MediaKind.artist => t.libraries.groupings.artists,
    MediaKind.album => t.libraries.groupings.albums,
    MediaKind.track => t.libraries.groupings.tracks,
    MediaKind.collection => t.libraries.tabs.collections,
    MediaKind.playlist => t.libraries.tabs.playlists,
    MediaKind.clip => t.discover.extras,
    MediaKind.photo || MediaKind.folder || MediaKind.unknown => kind.id,
  };

  static IconData _railIcon(MediaHub hub) => switch (hub.type) {
    'movie' => Symbols.movie_rounded,
    'show' || 'season' || 'episode' => Symbols.tv_rounded,
    'artist' || 'album' || 'track' => Symbols.music_note_rounded,
    'collection' || 'playlist' => Symbols.video_library_rounded,
    _ => Symbols.search_rounded,
  };

  /// Focus rail [index]: its remembered card, or the first person.
  void _focusRail(int index) {
    if (index < 0 || index >= _rails.length) return;
    final hub = _rails[index];
    if (PlatformDetector.isTV()) {
      _tvRailKeys[hub.id]?.currentState?.requestFocus();
    } else if (hub.id == _peopleRailId) {
      _firstPersonFocusNode.requestFocus();
    } else {
      _hubKeys[hub.id]?.currentState?.requestFocusFromMemory();
    }
  }

  /// UP from rail [index]: the rail above, or the search field from the first.
  void _focusAbove(int index) => index == 0 ? focusSearchInput() : _focusRail(index - 1);

  /// The single-hub list a TV rail renders, kept identical while its hub is.
  List<MediaHub> _railOf(MediaHub hub) {
    final cached = _railHubLists[hub.id];
    if (cached != null && identical(cached.single, hub)) return cached;
    return _railHubLists[hub.id] = [hub];
  }

  void _openPerson(MediaPerson person) => unawaited(
    navigateToPersonMedia(
      context,
      personId: person.id,
      name: person.name,
      thumbPath: person.thumbPath,
      serverId: person.serverId,
      serverName: person.serverName,
      backend: person.backend,
    ),
  );

  Widget _buildRail(BuildContext context, int index) {
    final hub = _rails[index];
    final isLast = index == _rails.length - 1;
    if (PlatformDetector.isTV()) {
      return Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (hasFocus) {
          if (!hasFocus) return;
          // Center the rail, with its neighbors peeking in.
          final rowContext = context;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !rowContext.mounted) return;
            unawaited(
              Scrollable.ensureVisible(
                rowContext,
                alignment: index == 0 ? 0.6 : 0.5,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
              ),
            );
          });
        },
        child: Builder(
          builder: (context) => TvBrowseRail(
            key: _tvRailKeys.putIfAbsent(hub.id, GlobalKey<TvBrowseRailState>.new),
            hubs: _railOf(hub),
            focusMemory: _focusMemory,
            // Image-only posters with their own gutter; people as round
            // photos with names underneath.
            fullCardLayout: hub.id != _peopleRailId,
            circularPersonCards: true,
            extraItemGap: 16,
            onRefresh: updateItem,
            onNavigateUp: () => _focusAbove(index),
            onNavigateDown: isLast ? null : () => _focusRail(index + 1),
            onNavigateToSidebar: _navigateToSidebar,
            onBack: focusSearchInput,
            onActivateItem: (hub, item) {
              final person = _railPeople[item.id];
              if (person == null) return false;
              _openPerson(person);
              return true;
            },
          ),
        ),
      );
    }

    if (hub.id == _peopleRailId) {
      return _PeopleRail(
        title: hub.title,
        people: [for (final item in hub.items) ?_railPeople[item.id]],
        firstFocusNode: _firstPersonFocusNode,
        showServerName: context.watch<MultiServerProvider>().totalServerCount > 1,
        onNavigateUp: () => _focusAbove(index),
        onNavigateDown: isLast ? null : () => _focusRail(index + 1),
        onNavigateToSidebar: _navigateToSidebar,
      );
    }

    return HubSection(
      key: _hubKeys.putIfAbsent(hub.id, GlobalKey<HubSectionState>.new),
      hub: hub,
      focusMemory: _focusMemory,
      icon: _railIcon(hub),
      onRefresh: updateItem,
      onVerticalNavigation: (isUp) => navigateVerticalHubRows(
        hubCount: _rails.length,
        hubIndex: index,
        isUp: isUp,
        requestFocus: _focusRail,
        onTopBoundary: focusSearchInput,
      ),
      onNavigateToSidebar: _navigateToSidebar,
      onBack: focusSearchInput,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          primary: false,
          slivers: [
            DesktopSliverAppBar(title: Text(t.common.search), floating: true),
            SliverToBoxAdapter(
              child: SearchInputField(
                controller: searchController,
                focusNode: searchFocusNode,
                debugLabel: searchDebugLabel,
                hintText: t.search.hint,
                tvTextInputController: _tvTextInputController,
                onNavigateLeft: _navigateToSidebar,
                onNavigateDown: _rails.isNotEmpty && !isSearching ? () => _focusRail(0) : null,
                onEditingComplete: PlatformDetector.isTV() ? handleSearchSubmit : null,
                onBack: () {
                  if (searchController.text.isNotEmpty) {
                    searchController.clear();
                  } else {
                    _navigateToSidebar();
                  }
                },
              ),
            ),
            if (isSearching)
              LoadingIndicatorBox.sliver
            else if (!hasSearched)
              SliverFillRemaining(
                child: StateMessageWidget(
                  message: t.search.searchYourMedia,
                  subtitle: t.search.enterTitleActorOrKeyword,
                  icon: Symbols.search_rounded,
                  iconSize: 80,
                ),
              )
            else if (lastSearchFailed)
              SliverFillRemaining(
                child: StateMessageWidget(message: t.explore.searchFailed, icon: Symbols.error_rounded, iconSize: 80),
              )
            else if (_rails.isEmpty)
              SliverFillRemaining(
                child: StateMessageWidget(
                  message: t.messages.noResultsFound,
                  subtitle: t.search.tryDifferentTerm,
                  icon: Symbols.search_off_rounded,
                  iconSize: 80,
                ),
              )
            else ...[
              for (var index = 0; index < _rails.length; index++)
                SliverToBoxAdapter(
                  key: ValueKey(_rails[index].id),
                  child: Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 8 : (PlatformDetector.isTV() ? 0 : 16)),
                    child: Builder(builder: (context) => _buildRail(context, index)),
                  ),
                ),
              // Room for the last rail to scroll up toward the middle.
              SliverToBoxAdapter(child: SizedBox(height: PlatformDetector.isTV() ? 160 : 24)),
            ],
          ],
        ),
      ),
    );
  }
}

final class _SearchUnavailableException implements Exception {
  const _SearchUnavailableException();
}

/// The Cast & Crew rail on touch and desktop: round photos with names, in a
/// row that scrolls sideways. Keyboard focus moves card to card; UP and DOWN
/// leave for the neighboring rails.
class _PeopleRail extends StatelessWidget {
  const _PeopleRail({
    required this.title,
    required this.people,
    required this.firstFocusNode,
    required this.showServerName,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateToSidebar,
  });

  final String title;
  final List<MediaPerson> people;
  final FocusNode firstFocusNode;
  final bool showServerName;
  final VoidCallback onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback onNavigateToSidebar;

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<int>(
      pref: SettingsService.libraryDensity,
      builder: (context, density, _) => _build(context, density),
    );
  }

  Widget _build(BuildContext context, int density) {
    return Column(
      crossAxisAlignment: .start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 8, 2),
          child: Row(
            children: [
              const AppIcon(Symbols.person_rounded, fill: 1),
              const SizedBox(width: 8),
              Flexible(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge, maxLines: 1, overflow: .ellipsis),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = MediaGridDelegate.cellWidth(
              context: context,
              availableWidth: constraints.maxWidth,
              density: density,
              useWideAspectRatio: false,
            );
            return SizedBox(
              // Round photo plus two caption lines and the focus scale room.
              height: cardWidth + 52,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                itemCount: people.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final person = people[index];
                  return SizedBox(
                    width: cardWidth,
                    child: PersonSearchRow(
                      key: Key(person.globalKey),
                      person: person,
                      viewMode: ViewMode.grid,
                      focusNode: index == 0 ? firstFocusNode : null,
                      showServerName: showServerName,
                      onNavigateLeft: index == 0 ? onNavigateToSidebar : null,
                      onNavigateUp: onNavigateUp,
                      onNavigateDown: onNavigateDown ?? () {},
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
