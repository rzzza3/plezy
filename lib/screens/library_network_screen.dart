import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/hub_vertical_navigation.dart';
import '../focus/key_event_utils.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_filter.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_sort.dart';
import '../mixins/grid_focus_node_mixin.dart';
import '../providers/multi_server_provider.dart';
import '../services/library_network_browse.dart';
import '../services/library_networks.dart';
import '../services/settings_service.dart';
import '../services/silo_client.dart';
import '../services/tmdb/tmdb_client.dart';
import '../utils/app_logger.dart';
import '../utils/desktop_window_padding.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../widgets/anchored_option_menus.dart';
import '../widgets/app_bar_back_button.dart';
import '../widgets/app_icon.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/hub_section.dart';
import '../widgets/media_card.dart';
import '../widgets/media_card_sliver_layout.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/options_chips_bar.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/settings_builder.dart';
import '../widgets/tv_browse_rail.dart';
import 'libraries/filters_bottom_sheet.dart';
import 'libraries/sort_bottom_sheet.dart';

/// The network and genre pages' display face: Big Shoulders Display, heavy
/// and tight, for a genre's name (or a network's without a logo) in place of
/// a logo, on the pages and on the Library's tiles.
abstract final class LibraryDisplayType {
  static TextStyle style(double size) => TextStyle(
    fontFamily: 'Big Shoulders Display',
    fontSize: size,
    height: 0.9,
    fontWeight: FontWeight.w800,
    fontVariations: const [FontVariation('wght', 800)],
    color: Colors.white,
  );
}

/// A network's or genre's page, opened from its tile in the Library's
/// Networks or Genres row (or that row's last card): a title card over the
/// backdrop of its most popular title, with its logo (or name), how many
/// titles the library has and how many are in progress, and Browse all; then
/// a rail per row, stacked like the Library tab's: Continue Watching (only
/// these titles), Trending (these titles trending on TMDB this week), Top
/// Movies and Top TV. A row with nothing in it is left out. On TV the page
/// scrolls as focus moves between the rails.
/// Browse all opens every title in a grid like a row's View All, A–Z unless
/// sorted otherwise, and filterable ([LibraryNetworkBrowseScreen]).
///
/// [items] are the network's or genre's library titles, most popular first;
/// every card opens its Silo page. The rails show as a skeleton while
/// Continue Watching (`GET /api/v2/home`, per connected Silo server) and
/// Trending ([LibraryNetworks.trending]) load.
class LibraryNetworkScreen extends StatefulWidget {
  /// Most titles a Top row shows.
  static const int rowLimit = 20;

  final String name;

  /// The network's logo, shown in place of [name].
  final String? logoUrl;
  final List<MediaItem> items;

  const LibraryNetworkScreen({super.key, required this.name, this.logoUrl, required this.items});

  @override
  State<LibraryNetworkScreen> createState() => _LibraryNetworkScreenState();
}

class _LibraryNetworkScreenState extends State<LibraryNetworkScreen> {
  final _focusMemory = HubFocusMemory();
  final Map<String, GlobalKey<TvBrowseRailState>> _tvRailKeys = {};
  final Map<String, GlobalKey<HubSectionState>> _hubKeys = {};

  /// Each TV rail's wrapper, which scrolls the page to it when it takes focus.
  final Map<String, GlobalKey> _tvRowKeys = {};

  /// Each rail's one-hub list, kept so rebuilds hand the rail the same list
  /// and it keeps its position.
  final Map<String, List<MediaHub>> _railHubs = {};
  final _browseNode = FocusNode(debugLabel: 'library_network_browse');

  /// TV scrolls the page itself as focus moves between the title card and
  /// the rails.
  final _tvScroll = ScrollController();

  /// The network's titles in progress; null while loading.
  List<MediaItem>? _continueWatching;

  /// The network's titles trending on TMDB; null while loading.
  List<MediaItem>? _trending;

  /// The most popular title with a backdrop, behind the title card.
  late final MediaItem? _backdrop = widget.items.where((item) => item.resolvedBackdropPaths.isNotEmpty).firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(_loadContinueWatching());
    unawaited(_loadTrending());
  }

  @override
  void dispose() {
    _browseNode.dispose();
    _tvScroll.dispose();
    super.dispose();
  }

  /// Every Silo server's Continue Watching, kept to this network's titles:
  /// its movies, and episodes of its series.
  Future<void> _loadContinueWatching() async {
    final clients = context
        .read<MultiServerProvider>()
        .serverManager
        .visibleOnlineClients
        .values
        .whereType<SiloClient>()
        .toList();
    final titles = {for (final item in widget.items) '${item.serverId}:${item.id}'};
    final lists = await Future.wait([
      for (final client in clients)
        client.fetchContinueWatching(count: null).catchError((Object error) {
          // The row is left out; the rest of the page still shows.
          appLogger.w('Library network: continue watching failed (${error.runtimeType})');
          return const <MediaItem>[];
        }),
    ]);
    if (!mounted) return;
    setState(() {
      _continueWatching = [
        for (final item in lists.expand((list) => list))
          if (titles.contains('${item.serverId}:${item.grandparentId ?? item.id}')) item,
      ];
    });
  }

  Future<void> _loadTrending() async {
    final tmdb = context.read<TmdbClient?>();
    var trending = const <MediaItem>[];
    if (tmdb != null && tmdb.isConfigured) {
      try {
        trending = await LibraryNetworks(tmdb).trending(widget.items);
      } catch (error) {
        // The row is left out; the rest of the page still shows.
        appLogger.w('Library network: trending failed (${error.runtimeType})');
      }
    }
    if (mounted) setState(() => _trending = trending);
  }

  // Memoized so rebuilds hand the rail the same hubs and it keeps its
  // position.
  List<MediaHub>? _hubs;

  List<MediaHub> get _builtHubs => _hubs ??= [
    // First, as on the Library tab.
    if (_continueWatching case final items?) _hub('continue', t.discover.continueWatching, items),
    if (_trending case final items?) _hub('trending', t.libraryHome.networkTabTrending, items),
    _hub('movies', t.libraryHome.networkTopMovies, [
      for (final item in widget.items)
        if (item.kind == MediaKind.movie) item,
    ]),
    _hub('shows', t.libraryHome.networkTopShows, [
      for (final item in widget.items)
        if (item.kind != MediaKind.movie) item,
    ]),
  ].nonNulls.toList();

  /// A row of at most [LibraryNetworkScreen.rowLimit] of [items], or null
  /// without any.
  MediaHub? _hub(String id, String title, List<MediaItem> items) {
    if (items.isEmpty) return null;
    final shown = id == 'continue' ? items : items.take(LibraryNetworkScreen.rowLimit).toList();
    return MediaHub(
      id: 'library_network_$id',
      identifier: 'library_network_$id',
      title: title,
      type: 'mixed',
      size: shown.length,
      items: shown,
    );
  }

  Future<void> _open(MediaItem item) => navigateToMediaItemDetails(context, item);

  void _pop() => Navigator.pop(context);

  void _browseAll() => unawaited(
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LibraryNetworkBrowseScreen(name: widget.name, logoUrl: widget.logoUrl, items: widget.items),
      ),
    ),
  );

  List<MediaHub> _railOf(MediaHub hub) => _railHubs.putIfAbsent(hub.id, () => [hub]);

  /// Focus the rail for [hub], coming from above or below.
  void _focusRow(MediaHub hub) {
    if (PlatformDetector.isTV()) {
      _tvRailKeys[hub.id]?.currentState?.requestFocus();
    } else {
      _hubKeys[hub.id]?.currentState?.requestFocusFromMemory();
    }
  }

  /// DOWN from the title card: the first rail.
  void _focusFirstRow() {
    if (_hubs?.firstOrNull case final hub?) _focusRow(hub);
  }

  void _revealTvTop() {
    if (!_tvScroll.hasClients) return;
    unawaited(_tvScroll.animateTo(0, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
  }

  /// Scroll a TV rail into view: the first bottom-aligned, so the title card
  /// still shows above it; the rest centred, with the rails around them
  /// peeking in. Runs after the frame, so it replaces the focused card's own
  /// minimal `showOnScreen` scroll.
  void _revealTv(GlobalKey row, {required double alignment}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final box = row.currentContext?.findRenderObject();
      if (!mounted || box == null || !box.attached || !_tvScroll.hasClients) return;
      final position = _tvScroll.position;
      final target = RenderAbstractViewport.of(
        box,
      ).getOffsetToReveal(box, alignment).offset.clamp(position.minScrollExtent, position.maxScrollExtent);
      unawaited(_tvScroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTv = PlatformDetector.isTV();
    final loading = _continueWatching == null || _trending == null;
    final hubs = loading ? const <MediaHub>[] : _builtHubs;

    // A system back pops, unless it repeats a Back key a row already handled.
    // canPop keeps the iOS swipe-back.
    final body = isTv ? _buildTv(hubs, loading: loading) : _buildTouch(hubs, loading: loading);
    return OverlaySheetHost(
      canPop: PlatformDetector.isHandheldIOS(context),
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        _pop();
      },
      child: Scaffold(backgroundColor: theme.scaffoldBackgroundColor, body: body),
    );
  }

  /// The title card over a backdrop on its right, then the rails, in one
  /// page that scrolls by focus.
  Widget _buildTv(List<MediaHub> hubs, {required bool loading}) {
    final size = MediaQuery.sizeOf(context);
    final scale = TvBrowseRailLayout.scaleForSize(size);
    // Lines the title up with the rails' first poster.
    final inset = TvBrowseRailLayout.horizontalInsetForScale(scale) + 8;
    return SingleChildScrollView(
      controller: _tvScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: size.height * 0.6,
            child: Stack(
              // The backdrop fades out below the title card, behind the first rail.
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  width: size.width * 0.7,
                  height: size.height * 0.74,
                  child: _Backdrop(item: _backdrop),
                ),
                Positioned.fill(
                  child: _TitleCard(
                    name: widget.name,
                    logoUrl: widget.logoUrl,
                    backdrop: _backdrop,
                    titleCount: widget.items.length,
                    inProgress: _continueWatching?.length ?? 0,
                    inset: inset,
                    actions: FocusableActionBar(
                      spacing: 12,
                      onNavigateDown: _focusFirstRow,
                      onBack: _pop,
                      onFocusChange: (hasFocus) {
                        if (hasFocus) _revealTvTop();
                      },
                      actions: [
                        FocusableAction(
                          debugLabel: 'library_network_browse',
                          focusNode: _browseNode,
                          autofocus: true,
                          onPressed: _browseAll,
                          builder: (context, state) => _PillButton(
                            icon: Symbols.grid_view_rounded,
                            label: t.libraryHome.networkBrowseAll(count: widget.items.length),
                            focused: state.showFocus,
                            primary: true,
                            duration: state.animationDuration,
                            onTap: _browseAll,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (loading)
            _TvShelfSkeleton(items: widget.items, inset: inset)
          else
            for (final (index, hub) in hubs.indexed) _buildTvRow(hubs, index, hub),
          // Room for the last rail to scroll up to the centre.
          SizedBox(height: math.max(48, size.height / 2)),
        ],
      ),
    );
  }

  Widget _buildTvRow(List<MediaHub> hubs, int index, MediaHub hub) {
    final rowKey = _tvRowKeys.putIfAbsent(hub.id, GlobalKey.new);
    return Focus(
      key: rowKey,
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) _revealTv(rowKey, alignment: index == 0 ? 1 : 0.5);
      },
      child: TvBrowseRail(
        key: _tvRailKeys.putIfAbsent(hub.id, GlobalKey<TvBrowseRailState>.new),
        hubs: _railOf(hub),
        focusMemory: _focusMemory,
        onNavigateUp: index == 0 ? _browseNode.requestFocus : () => _focusRow(hubs[index - 1]),
        // The last rail keeps DOWN to itself.
        onNavigateDown: index == hubs.length - 1 ? null : () => _focusRow(hubs[index + 1]),
        onBack: _pop,
        // Full-size posters with room between them, as on the Library tab.
        extraItemGap: 16,
        onActivateItem: (hub, item) {
          unawaited(_open(item));
          return true;
        },
      ),
    );
  }

  Widget _buildTouch(List<MediaHub> hubs, {required bool loading}) {
    final size = MediaQuery.sizeOf(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final useSideNav = PlatformDetector.shouldUseSideNavigation(context);
    final heroHeight = useSideNav ? math.max(size.height * 0.55, 360.0) : 380 + topInset;
    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: heroHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _Backdrop(item: _backdrop),
                    _TitleCard(
                      name: widget.name,
                      logoUrl: widget.logoUrl,
                      backdrop: _backdrop,
                      titleCount: widget.items.length,
                      inProgress: _continueWatching?.length ?? 0,
                      inset: 16,
                      actions: _PillButton(
                        icon: Symbols.grid_view_rounded,
                        label: t.libraryHome.networkBrowseAll(count: widget.items.length),
                        focused: false,
                        primary: true,
                        duration: FocusTheme.getAnimationDuration(context),
                        onTap: _browseAll,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (loading)
              const SliverToBoxAdapter(child: _SkeletonRow())
            else
              for (final (index, hub) in hubs.indexed)
                SliverToBoxAdapter(
                  key: ValueKey(hub.id),
                  child: HubSection(
                    key: _hubKeys.putIfAbsent(hub.id, GlobalKey<HubSectionState>.new),
                    hub: hub,
                    focusMemory: _focusMemory,
                    icon: _iconFor(hub),
                    onItemTap: (item) => unawaited(_open(item)),
                    onVerticalNavigation: (isUp) => navigateVerticalHubRows(
                      hubCount: hubs.length,
                      hubIndex: index,
                      isUp: isUp,
                      requestFocus: (target) => _focusRow(hubs[target]),
                    ),
                    onBack: _pop,
                  ),
                ),
            SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPadding)),
          ],
        ),
        Positioned(
          top: 0,
          left: 0,
          child: DesktopAppBarHelper.buildAdjustedLeading(
            AppBarBackButton(style: BackButtonStyle.circular, onPressed: _pop),
            context: context,
          )!,
        ),
      ],
    );
  }

  static IconData _iconFor(MediaHub hub) => switch (hub.id) {
    'library_network_trending' => Symbols.trending_up_rounded,
    'library_network_shows' => Symbols.tv_rounded,
    'library_network_continue' => Symbols.play_circle_rounded,
    _ => Symbols.movie_rounded,
  };
}

/// The backdrop behind the title card, faded into the page on its left and
/// bottom so the title and the rails sit on the page's colour.
class _Backdrop extends StatelessWidget {
  final MediaItem? item;

  const _Backdrop({required this.item});

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    if (item == null) return const SizedBox.shrink();
    final background = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          OptimizedMediaImage(
            client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
            imagePath: item.resolvedBackdropPaths.first,
            imageType: ImageType.art,
            alignment: Alignment.topCenter,
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [background, background.withValues(alpha: 0.55), background.withValues(alpha: 0)],
                stops: const [0, 0.3, 0.65],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [background.withValues(alpha: 0), background.withValues(alpha: 0.6), background],
                stops: const [0.45, 0.8, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The page's title card: the logo (or the name, large in
/// [LibraryDisplayType]), the library's count and the titles in progress,
/// then [actions]; the backdrop's title captioned at the bottom right.
class _TitleCard extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final MediaItem? backdrop;
  final int titleCount;
  final int inProgress;
  final double inset;
  final Widget actions;

  const _TitleCard({
    required this.name,
    required this.logoUrl,
    required this.backdrop,
    required this.titleCount,
    required this.inProgress,
    required this.inset,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final isTv = PlatformDetector.isTV();
    final short = math.min(size.height, size.width * 0.75);
    final nameSize = (short * (isTv ? 0.2 : 0.16)).clamp(56.0, 140.0);
    final nameText = Text(name.toUpperCase(), maxLines: 1, style: LibraryDisplayType.style(nameSize));
    final logoHeight = (short * 0.09).clamp(40.0, 72.0);

    final Widget title = logoUrl == null
        ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: nameText)
        : Align(
            alignment: Alignment.bottomLeft,
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: OptimizedMediaImage(
                imagePath: logoUrl,
                width: logoHeight * 4,
                height: logoHeight,
                fit: BoxFit.contain,
                alignment: Alignment.bottomLeft,
                imageType: ImageType.heroLogo,
                placeholder: (context, _) => SizedBox(width: logoHeight * 4, height: logoHeight),
                errorWidget: (context, _, _) =>
                    FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.bottomLeft, child: nameText),
              ),
            ),
          );

    final statsStyle = theme.textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.82));
    final caption = backdrop == null
        ? null
        : [backdrop!.displayTitle, if (backdrop!.year case final year?) '$year'].join(' · ');

    return Stack(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, isTv ? 24 : 0, inset, isTv ? 20 : 16),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: size.width * 0.55),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  title,
                  SizedBox(height: isTv ? 14 : 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: t.libraryHome.networkTitleCount(n: titleCount)),
                        if (inProgress > 0) ...[
                          TextSpan(
                            text: '  ·  ',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                          ),
                          TextSpan(text: t.libraryHome.networkInProgress(count: inProgress)),
                        ],
                      ],
                    ),
                    style: statsStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isTv ? 18 : 16),
                  actions,
                ],
              ),
            ),
          ),
        ),
        if (caption != null && isTv)
          Positioned(
            right: inset,
            bottom: 24,
            child: Text(
              caption,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.75),
                shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1))],
              ),
            ),
          ),
      ],
    );
  }
}

/// A rounded button: white when [primary] or focused, else outlined.
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool focused;
  final bool primary;
  final Duration duration;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.focused,
    required this.primary,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = primary || focused;
    final foreground = filled ? Colors.black : Colors.white;
    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: focused ? 1.05 : 1,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: filled ? Colors.white : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: filled ? 0 : 0.2)),
              boxShadow: focused
                  ? const [BoxShadow(color: Color(0x80000000), blurRadius: 16, offset: Offset(0, 6))]
                  : null,
            ),
            // The focused button carries a dark ring inside the white, as
            // the primary one is white whether focused or not.
            foregroundDecoration: focused && primary
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.black, width: 2),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, fill: 1, size: 20, color: foreground),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(color: foreground, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every title of a network or genre, opened from its page's Browse all: a
/// grid laid out and focused like a View All page, which scrolls each
/// focused card into view, under the network's logo (or name), the count,
/// and Filters and Sort. A–Z unless sorted otherwise ([LibraryNetworkBrowse]).
class LibraryNetworkBrowseScreen extends StatefulWidget {
  final String name;
  final String? logoUrl;
  final List<MediaItem> items;

  const LibraryNetworkBrowseScreen({super.key, required this.name, this.logoUrl, required this.items});

  @override
  State<LibraryNetworkBrowseScreen> createState() => _LibraryNetworkBrowseScreenState();
}

class _LibraryNetworkBrowseScreenState extends State<LibraryNetworkBrowseScreen> with GridFocusNodeMixin {
  /// Below [OverlaySheetHost], for opening the sort and filter sheets.
  final _overlayChildKey = GlobalKey();
  final _filtersChipKey = GlobalKey();
  final _sortChipKey = GlobalKey();
  final _filtersChipFocusNode = FocusNode(debugLabel: 'library_network_filters');
  final _sortChipFocusNode = FocusNode(debugLabel: 'library_network_sort');

  late final _filterOptions = LibraryNetworkBrowse.filtersFor(widget.items);
  late final _sortOptions = LibraryNetworkBrowse.sortOptions();
  List<LibraryFilter> _filters = const [];
  MediaSort? _sort;
  bool _descending = false;

  /// The titles, filtered and sorted.
  late List<MediaItem> _allContent = _browse();

  List<MediaItem> _browse() =>
      LibraryNetworkBrowse.apply(widget.items, filters: _filters, sort: _sort, descending: _descending);

  @override
  void initState() {
    super.initState();
    // The grid takes focus as the page opens, or the chips without titles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !PlatformDetector.isTV()) return;
      if (_allContent.isEmpty) {
        _focusChips();
      } else {
        _focusGrid();
      }
    });
  }

  @override
  void dispose() {
    _filtersChipFocusNode.dispose();
    _sortChipFocusNode.dispose();
    disposeGridFocusNodes();
    super.dispose();
  }

  void _pop() => Navigator.pop(context);

  static const _gridPrefix = 'library_network_all';

  /// A little more room around each poster than the shared grid gutter.
  static const _gridCellPadding = 4.0;

  FocusNode _gridNode(int index) => focusNodeForIndex(
    index,
    getGridItemFocusNode(0, prefix: _gridPrefix),
    prefix: _gridPrefix,
    itemIdentity: _allContent[index].globalKey,
  );

  void _focusGrid() {
    if (_allContent.isNotEmpty) getGridItemFocusNode(0, prefix: _gridPrefix).requestFocus();
  }

  void _focusChips() => (_filterOptions.filters.isEmpty ? _sortChipFocusNode : _filtersChipFocusNode).requestFocus();

  /// Re-derives the grid after a sort or filter [change]; each card keeps
  /// its focus node wherever it moves.
  void _updateAllContent(VoidCallback change) {
    setState(() {
      change();
      _allContent = _browse();
    });
    reconcileGridFocusNodes({for (final (index, item) in _allContent.indexed) item.globalKey: index});
  }

  // The editor keys its staged values by owner; this page has one.
  String get _filterOwner => 'library_network:${widget.name}';

  static Future<List<MediaFilterValue>> _noFilterValues(MediaFilter filter) async => const [];

  /// Opens the filter editor and applies its edits once, when it closes —
  /// as the Library's browse tab does.
  void _showFilters() {
    var pending = _filters;
    void commit() {
      if (!mounted || listEquals(pending, _filters)) return;
      _updateAllContent(() => _filters = List<LibraryFilter>.unmodifiable(pending));
    }

    final anchorRect = useAnchoredChipMenus(context) ? chipAnchorRect(_filtersChipKey) : null;
    if (anchorRect != null) {
      unawaited(
        showAnchoredFilterPanel(
          context,
          anchorRect: anchorRect,
          filters: _filterOptions.filters,
          selectedFilters: _filters,
          onFiltersChanged: (filters) => pending = filters,
          serverId: _filterOwner,
          libraryKey: _filterOwner,
          loadFilterValues: _noFilterValues,
          cachedValues: _filterOptions.cachedValues,
        ).then((_) => commit()),
      );
      return;
    }
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    unawaited(
      OverlaySheetController.of(_overlayChildKey.currentContext ?? context)
          .show(
            builder: (_) => FiltersBottomSheet(
              filters: _filterOptions.filters,
              selectedFilters: _filters,
              serverId: _filterOwner,
              libraryKey: _filterOwner,
              loadFilterValues: _noFilterValues,
              cachedValues: _filterOptions.cachedValues,
              onFiltersChanged: (filters) => pending = filters,
            ),
          )
          // Post-frame, so the regrid doesn't take focus from the closing sheet.
          .then((_) => WidgetsBinding.instance.addPostFrameCallback((_) => commit())),
    );
  }

  void _showSort() {
    final anchorRect = useAnchoredChipMenus(context) ? chipAnchorRect(_sortChipKey) : null;
    if (anchorRect != null) {
      unawaited(
        showAnchoredSortMenu(
          context,
          anchorRect: anchorRect,
          sortOptions: _sortOptions,
          selectedSort: _sort,
          isSortDescending: _descending,
          clearLabel: t.common.clear,
        ).then((result) {
          if (mounted && result != null) _applySort(result.sort, result.descending, cleared: result.cleared);
        }),
      );
      return;
    }
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    var pendingSort = _sort;
    var pendingDescending = _descending;
    var pendingCleared = false;
    unawaited(
      OverlaySheetController.of(_overlayChildKey.currentContext ?? context)
          .show(
            builder: (_) => SortBottomSheet(
              sortOptions: _sortOptions,
              selectedSort: _sort,
              isSortDescending: _descending,
              onSortChanged: (sort, descending) {
                pendingSort = sort;
                pendingDescending = descending;
                pendingCleared = false;
              },
              onClear: () {
                pendingSort = null;
                pendingDescending = false;
                pendingCleared = true;
              },
            ),
          )
          .then(
            (_) => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _applySort(pendingSort, pendingDescending, cleared: pendingCleared);
            }),
          ),
    );
  }

  /// A cleared sort is back to A–Z.
  void _applySort(MediaSort? sort, bool descending, {required bool cleared}) {
    final next = cleared ? null : sort;
    final nextDescending = cleared ? false : descending;
    if (next?.key == _sort?.key && nextDescending == _descending) return;
    _updateAllContent(() {
      _sort = next;
      _descending = nextDescending;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTv = PlatformDetector.isTV();
    final topInset = isTv ? 0.0 : MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final inset = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;

    // A system back with a sheet open closes the sheet; otherwise it pops,
    // unless it repeats a Back key a sheet or card already handled. canPop
    // keeps the iOS swipe-back.
    return OverlaySheetHost(
      canPop: PlatformDetector.isHandheldIOS(context),
      onSystemBack: () {
        if (BackKeyCoordinator.consumeIfHandled()) return;
        _pop();
      },
      child: Scaffold(
        key: _overlayChildKey,
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Stack(
          children: [
            CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    // Room for the back button off TV.
                    padding: EdgeInsets.fromLTRB(isTv ? inset : 56, topInset + (isTv ? 20 : 12), 8, 8),
                    child: _buildHeader(theme, isTv: isTv),
                  ),
                ),
                if (_allContent.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(inset, 24, inset, 24),
                      child: Text(
                        t.libraryHome.networkNoMatches,
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  _buildGrid(isTv: isTv, inset: inset),
                SliverToBoxAdapter(child: SizedBox(height: 24 + bottomPadding)),
              ],
            ),
            if (!isTv)
              Positioned(
                top: 0,
                left: 0,
                child: DesktopAppBarHelper.buildAdjustedLeading(
                  AppBarBackButton(style: BackButtonStyle.circular, onPressed: _pop),
                  context: context,
                )!,
              ),
          ],
        ),
      ),
    );
  }

  /// The logo (or name), "212 titles in your library", and the sort once
  /// sorted, then Filters and Sort.
  Widget _buildHeader(ThemeData theme, {required bool isTv}) {
    final titleHeight = isTv ? 30.0 : 28.0;
    final nameText = Text(widget.name.toUpperCase(), maxLines: 1, style: LibraryDisplayType.style(titleHeight * 1.15));
    final logoUrl = widget.logoUrl;
    final title = logoUrl == null
        ? nameText
        : ColorFiltered(
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
            child: OptimizedMediaImage(
              imagePath: logoUrl,
              width: titleHeight * 4,
              height: titleHeight,
              fit: BoxFit.contain,
              alignment: Alignment.centerLeft,
              imageType: ImageType.logo,
              placeholder: (context, _) => SizedBox(width: titleHeight * 4, height: titleHeight),
              errorWidget: (context, _, _) => nameText,
            ),
          );
    return Row(
      children: [
        if (!isTv) ...[const AppIcon(Symbols.grid_view_rounded, fill: 1), const SizedBox(width: 8)],
        Expanded(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              title,
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  [
                    t.libraryHome.networkTitleCount(n: _allContent.length),
                    if (_sort case final sort?) sort.title,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        OptionsChipsBar(
          chips: [
            if (_filterOptions.filters.isNotEmpty)
              OptionsChipDescriptor(
                anchorKey: _filtersChipKey,
                focusNode: _filtersChipFocusNode,
                icon: Symbols.filter_alt_rounded,
                label: _filters.isEmpty
                    ? t.libraries.filters
                    : t.libraries.filtersWithCount(count: _filters.map((clause) => clause.field).toSet().length),
                onPressed: _showFilters,
              ),
            OptionsChipDescriptor(
              anchorKey: _sortChipKey,
              focusNode: _sortChipFocusNode,
              icon: Symbols.sort_rounded,
              label: _sort?.title ?? t.libraries.sort,
              onPressed: _showSort,
            ),
          ],
          onNavigateDown: _focusGrid,
          onBack: _pop,
        ),
      ],
    );
  }

  Widget _buildGrid({required bool isTv, required double inset}) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.viewMode,
        SettingsService.episodePosterMode,
        SettingsService.libraryDensity,
        SettingsService.tvFullCardLayout,
      ],
      builder: (context) {
        final svc = SettingsService.instance;
        final fullCardLayout = isTv && svc.read(SettingsService.tvFullCardLayout);
        return MediaCardSliverLayout(
          viewMode: svc.read(SettingsService.viewMode),
          itemCount: _allContent.length,
          density: svc.read(SettingsService.libraryDensity),
          // Less the cell padding below, so posters line up with the header.
          padding: EdgeInsets.symmetric(
            horizontal: isTv ? inset - _gridCellPadding : 8 - _gridCellPadding,
            vertical: 8,
          ),
          fullBleedImage: fullCardLayout,
          itemBuilder: (context, position) {
            final index = position.index;
            final item = _allContent[index];
            final card = FocusableMediaCard(
              key: Key(item.globalKey),
              focusNode: _gridNode(index),
              item: item,
              disableScale: position.disableScale,
              onNavigateUp: position.isFirstRow ? _focusChips : null,
              onNavigateLeft: position.isGrid && position.isFirstColumn ? () {} : null,
              onBack: _pop,
              onFocusChange: (hasFocus) => trackGridItemFocus(index, hasFocus),
              fullBleedImage: fullCardLayout && position.isGrid,
            );
            return position.isGrid ? Padding(padding: const EdgeInsets.all(_gridCellPadding), child: card) : card;
          },
        );
      },
    );
  }
}

/// The TV rails' placeholder while the page loads: a header bar over a row
/// of posters the size the first rail's will be.
class _TvShelfSkeleton extends StatelessWidget {
  final List<MediaItem> items;
  final double inset;

  const _TvShelfSkeleton({required this.items, required this.inset});

  @override
  Widget build(BuildContext context) {
    final scale = TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context));
    return SettingsBuilder(
      prefs: const [
        SettingsService.libraryDensity,
        SettingsService.episodePosterMode,
        SettingsService.tvFullCardLayout,
        SettingsService.gridSpacing,
      ],
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          final svc = SettingsService.instance;
          final railInset = TvBrowseRailLayout.horizontalInsetForScale(scale);
          // What the rail measures for the same titles.
          final metrics = TvBrowseRailLayout.metricsForHub(
            hub: MediaHub(id: 'skeleton', identifier: 'skeleton', title: '', type: 'mixed', size: 0, items: items),
            availableWidth: (constraints.maxWidth - railInset).clamp(1.0, double.infinity).toDouble(),
            density: svc.read(SettingsService.libraryDensity),
            episodePosterMode: svc.read(SettingsService.episodePosterMode),
            scale: scale,
            fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
            gridSpacing: svc.read(SettingsService.gridSpacing),
            extraItemGap: 16,
          );
          const bar = SkeletonLoader(
            borderRadius: BorderRadius.all(Radius.circular(999)),
            child: SizedBox(width: 220, height: 22),
          );
          return ExcludeFocus(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(left: inset, top: 8 * scale, bottom: 4 * scale),
                  child: bar,
                ),
                SizedBox(
                  height:
                      TvBrowseRailLayout.railTopPaddingForScale(scale) +
                      metrics.height +
                      TvBrowseRailLayout.railBottomPaddingForScale(scale),
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                      railInset + metrics.railEdgePadding,
                      TvBrowseRailLayout.railTopPaddingForScale(scale) + metrics.focusExtra / 2,
                      0,
                      0,
                    ),
                    itemCount: 12,
                    separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
                    itemBuilder: (_, _) => Align(
                      alignment: Alignment.topCenter,
                      child: SkeletonLoader(
                        borderRadius: const BorderRadius.all(Radius.circular(8)),
                        child: SizedBox(width: metrics.posterWidth, height: metrics.posterHeight),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final inset = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;
    final posterWidth = isTv ? 150.0 : 120.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonLoader(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: SizedBox(width: 320, height: 20),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: posterWidth * 1.5,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 12,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, _) => SizedBox(
                width: posterWidth,
                child: const SkeletonLoader(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  child: SizedBox.expand(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
