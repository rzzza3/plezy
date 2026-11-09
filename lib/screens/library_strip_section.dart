import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../focus/focus_theme.dart';
import '../focus/focusable_action_bar.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../providers/multi_server_provider.dart';
import '../services/library_networks.dart';
import '../services/settings_service.dart';
import '../services/silo_api_cache.dart';
import '../services/silo_client.dart';
import '../utils/app_logger.dart';
import '../utils/media_image_helper.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/hub_section.dart';
import '../widgets/media_card.dart';
import '../widgets/media_grid_delegate.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/settings_builder.dart';
import '../widgets/skeleton_media_card.dart';
import '../widgets/tv_browse_rail.dart';
import 'library_home_screen.dart';
import 'library_network_screen.dart';

/// One entry of a [LibraryStripSection]'s strip: its name, and the logo
/// shown in its place once known.
typedef LibraryStripChoice = ({String name, String? logoUrl});

/// A Library tab section of choices (networks, genres): a row of tiles, each
/// over the backdrop of its most popular title, above a row of the library's
/// titles for the picked one, newest added first. Moving through the tiles
/// switches the row and the section's backdrop; OK on a tile, or the row's
/// last card, opens the choice's page.
///
/// The choices are a [StringListPref], narrowed by the header filter; one
/// with fewer than [LibraryNetworks.minimumCount] titles is left out. Matches
/// each choice not cached within [cacheMaxAge]. Until the first choices are
/// matched it shows a placeholder of itself, which focus passes over; nothing
/// without a Silo server, or once no choice has enough titles.
abstract class LibraryStripSection extends StatefulWidget {
  /// Most titles a choice's row shows.
  static const int maxItems = 10;

  /// Choices matched at once.
  static const int concurrentMatches = 3;

  /// How long a choice's cached matches stand before they are matched again,
  /// as Silo keeps its network results for a day. Older ones still show
  /// while that runs.
  static const Duration cacheMaxAge = Duration(days: 1);

  final LibraryHomeFilter filter;

  /// UP from the strip.
  final VoidCallback onNavigateUp;

  /// DOWN from the row.
  final VoidCallback? onNavigateDown;
  final VoidCallback onNavigateToSidebar;

  /// Focus entered the section, so the page can scroll it into view.
  final VoidCallback? onFocusEntered;

  const LibraryStripSection({
    super.key,
    required this.filter,
    required this.onNavigateUp,
    this.onNavigateDown,
    required this.onNavigateToSidebar,
    this.onFocusEntered,
  });
}

abstract class LibraryStripSectionState<W extends LibraryStripSection> extends State<W> {
  // Replaced on every pick, so a new choice's row starts on its first card
  // rather than where the last one was left.
  var _tvRailKey = GlobalKey<TvBrowseRailState>();
  var _hubKey = GlobalKey<HubSectionState>();
  var _focusMemory = HubFocusMemory();
  final Map<String, FocusNode> _nodes = {};
  late final ValueNotifier<List<String>> _pref = SettingsService.instance.listenable(pref);

  /// The setting listing the chosen ids.
  StringListPref get pref;

  /// The section's heading, and its row's title before a choice is named.
  String get title;
  IconData get icon;

  /// Names the section in logs.
  String get logLabel;

  /// Names the section in focus labels, hub ids and the API cache.
  String get sectionKey;

  /// Whether the section can match anything (it may need TMDB).
  bool get canLoad => true;

  /// [ids] (as stored) that the catalogue knows, in the stored order: the
  /// Edit Library page sets it.
  List<String> choicesIn(List<String> ids);

  /// The strip's name and logo for [id].
  LibraryStripChoice describe(String id);

  /// Called as a load starts, for whatever the strip shows besides matches.
  void onLoadStarted(List<String> ids) {}

  /// Called once per load before the first [match], as the clients to read
  /// are known (for whatever every match shares, such as the library).
  Future<void> prepare(List<SiloClient> clients) async {}

  /// [id]'s library titles on [clients], most popular first.
  Future<List<MediaItem>> match(String id, List<SiloClient> clients);

  /// [id]'s page, with all its library titles (not just the header filter's).
  Widget pageFor(String id, List<MediaItem> items);

  /// Chosen ids, in the order the setting lists them.
  List<String> _choices = const [];

  /// The choice picked in the strip; the first shown one stands in while it
  /// is null or left out.
  String? _picked;

  /// The choice whose tile has focus, which the "OK Open …" hint names.
  String? _focusedChoice;

  bool _loading = false;

  /// The choice changed during a load, which then runs again.
  bool _rerun = false;

  /// Library titles per choice, once matched or read from the cache.
  final Map<String, List<MediaItem>> _matches = {};

  /// Choices matched this session or cached within
  /// [LibraryStripSection.cacheMaxAge]; the rest are matched (again) on the
  /// next load.
  final Set<String> _upToDate = {};

  /// Whether the first matching finished, so the strip doesn't grow choice
  /// by choice on first show.
  bool _settled = false;

  // Memoized on its inputs so rebuilds hand the rails the same hub list and
  // they keep their scroll position.
  List<MediaHub>? _hubs;
  Object? _hubsKey;

  @override
  void initState() {
    super.initState();
    _pref.addListener(_onChoicesChanged);
    _applyChoices();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pref.removeListener(_onChoicesChanged);
    for (final node in _nodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Whether the section is on screen to take focus.
  bool get isShown => _shownChoices().isNotEmpty;

  /// Focus the selected choice.
  void requestFocus() {
    final selected = _selectedIn(_shownChoices());
    if (selected == null) return widget.onNavigateUp();
    _nodes[selected]?.requestFocus();
  }

  /// Focus the row, coming UP from below.
  void requestFocusFromBelow() {
    if (isShown) _focusRow();
  }

  /// Read again whatever failed or found no server: the library, or a
  /// chosen entry.
  void retryIfUnavailable() {
    if (!_choices.every(_upToDate.contains)) unawaited(_load());
  }

  void _onChoicesChanged() {
    setState(_applyChoices);
    unawaited(_load());
  }

  /// Follow the chosen entries, with a focus node each.
  void _applyChoices() {
    _choices = choicesIn(_pref.value);
    for (final id in [..._nodes.keys]) {
      if (!_choices.contains(id)) _nodes.remove(id)!.dispose();
    }
    for (final id in _choices) {
      _nodes.putIfAbsent(id, () {
        final node = FocusNode(debugLabel: '${sectionKey}_$id');
        node.addListener(() {
          if (node.hasFocus) {
            _select(id);
            _reveal(node);
            if (_focusedChoice != id) setState(() => _focusedChoice = id);
          } else if (_focusedChoice == id) {
            setState(() => _focusedChoice = null);
          }
        });
        return node;
      });
    }
  }

  /// Scroll [node]'s tile into view with the row's inset beside it, so the
  /// first and last tiles stop where they rest rather than at the screen edge.
  void _reveal(FocusNode node) {
    final box = node.context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final margin = TvBrowseRailLayout.horizontalInsetForScale(
      TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)),
    );
    box.showOnScreen(
      rect: Rect.fromLTRB(-margin, 0, box.size.width + margin, box.size.height),
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
    );
  }

  /// Read the library if not yet read, then match every chosen entry not yet
  /// matched, [LibraryStripSection.concurrentMatches] at a time.
  Future<void> _load() async {
    if (_loading) {
      _rerun = true;
      return;
    }
    if (!canLoad) return;
    final clients = context
        .read<MultiServerProvider>()
        .serverManager
        .visibleOnlineClients
        .values
        .whereType<SiloClient>()
        .toList();
    if (clients.isEmpty) return;
    // Shows the placeholder on first load.
    setState(() => _loading = true);
    final cache = _StripCache(clients, key: sectionKey, logLabel: logLabel);
    try {
      onLoadStarted(_choices);
      await _readCached(cache);
      final pending = [
        for (final id in _choices)
          if (!_upToDate.contains(id)) id,
      ];
      if (pending.isNotEmpty) {
        // Cached rows show while the rest are matched, which takes a while
        // when the whole library is read (100 titles a request).
        if (!_settled && _matches.isNotEmpty) setState(() => _settled = true);
        await prepare(clients);
        Future<void> worker() async {
          while (pending.isNotEmpty && mounted) {
            final id = pending.removeAt(0);
            try {
              final items = await match(id, clients);
              if (!mounted) return;
              _matches[id] = items;
              _upToDate.add(id);
              unawaited(cache.write(id, items));
              // Shown as they land once the section is on screen.
              if (_settled) setState(() {});
            } catch (error) {
              // Left unmatched; the next visit to the tab asks again.
              appLogger.w('$logLabel: matching failed for $id (${error.runtimeType})');
            }
          }
        }

        await Future.wait([for (var i = 0; i < LibraryStripSection.concurrentMatches; i++) worker()]);
      }
    } catch (error) {
      appLogger.w('$logLabel: library read failed (${error.runtimeType})');
    } finally {
      _loading = false;
    }
    if (!mounted) return;
    setState(() => _settled = true);
    // The choice changed while this ran; match what it added.
    if (_rerun) {
      _rerun = false;
      unawaited(_load());
    }
  }

  /// Cached matches for chosen entries not yet read this session.
  Future<void> _readCached(_StripCache cache) async {
    for (final id in _choices) {
      if (_matches.containsKey(id)) continue;
      final cached = await cache.read(id);
      if (cached == null || !mounted) continue;
      _matches[id] = cached.items;
      if (cached.fresh) _upToDate.add(id);
    }
  }

  /// A choice's titles under the header filter.
  List<MediaItem> _itemsFor(String id) => [
    for (final item in _matches[id] ?? const <MediaItem>[])
      if (widget.filter.accepts(item.kind)) item,
  ];

  /// Chosen entries with enough titles under the header filter to show.
  List<String> _shownChoices() {
    if (!_settled) return const [];
    return [
      for (final id in _choices)
        if (_itemsFor(id).length >= LibraryNetworks.minimumCount) id,
    ];
  }

  String? _selectedIn(List<String> shown) {
    if (shown.isEmpty) return null;
    return shown.contains(_picked) ? _picked : shown.first;
  }

  void _select(String id) {
    if (id == _picked) return;
    setState(() {
      _picked = id;
      _tvRailKey = GlobalKey<TvBrowseRailState>();
      _hubKey = GlobalKey<HubSectionState>();
      _focusMemory = HubFocusMemory();
    });
  }

  /// Each shown choice's most popular title with a backdrop that no tile
  /// before it shows, for its tile and the section's backdrop: one film is
  /// often in several genres.
  Map<String, MediaItem> _artFor(List<String> shown) {
    final art = <String, MediaItem>{};
    final used = <String>{};
    for (final id in shown) {
      for (final item in _itemsFor(id)) {
        if (item.resolvedBackdropPaths.isEmpty || !used.add(item.globalKey)) continue;
        art[id] = item;
        break;
      }
    }
    return art;
  }

  Future<void> _open(MediaItem item) => navigateToMediaItemDetails(context, item);

  void _openPage(String id) => unawaited(
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => pageFor(id, _matches[id] ?? const []))),
  );

  List<MediaHub> _hubsFor(String id) {
    final items = LibraryNetworks.newestFirst(_itemsFor(id)).take(LibraryStripSection.maxItems).toList();
    final name = describe(id).name;
    final hubKey = (id, _matches[id], widget.filter, name);
    if (_hubs != null && hubKey == _hubsKey) return _hubs!;
    _hubsKey = hubKey;
    return _hubs = [
      MediaHub(
        id: '${sectionKey}_$id',
        identifier: sectionKey,
        title: name,
        type: 'mixed',
        size: items.length,
        // The trailing card opens the choice's page.
        more: true,
        items: items,
      ),
    ];
  }

  void _focusRow() {
    final tvRail = _tvRailKey.currentState;
    final hub = _hubKey.currentState;
    if (tvRail != null) {
      tvRail.requestFocus();
    } else if (hub != null) {
      hub.requestFocusFromMemory();
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shownChoices();
    final selected = _selectedIn(shown);
    if (selected == null) {
      return !_settled && _loading && _choices.isNotEmpty ? _buildPlaceholder() : const SizedBox.shrink();
    }
    final isTv = PlatformDetector.isTV();
    final hubs = _hubsFor(selected);
    final hinted = isTv ? _focusedChoice : null;
    final art = _artFor(shown);

    final Widget row;
    if (isTv) {
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
        onActivateItem: (hub, item) {
          unawaited(_open(item));
          return true;
        },
        onViewAll: (_) => _openPage(selected),
      );
    } else {
      row = HubSection(
        key: _hubKey,
        hub: hubs.first,
        focusMemory: _focusMemory,
        icon: icon,
        showHeader: false,
        onItemTap: (item) => unawaited(_open(item)),
        onViewAll: () => _openPage(selected),
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
      child: Stack(
        children: [
          Positioned.fill(child: _SectionBackdrop(item: art[selected])),
          _layout(
            hint: hinted == null ? null : _OpenHint(name: describe(hinted).name),
            tiles: _buildTiles(shown, art, selected: selected, isTv: isTv),
            row: row,
          ),
        ],
      ),
    );
  }

  /// The heading with [hint] beside it, over the strip's [tiles] and the
  /// picked choice's [row].
  Widget _layout({required Widget? hint, required Widget tiles, required Widget row}) {
    final isTv = PlatformDetector.isTV();
    // Line up with the titles of the TV rails above.
    final inset = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(inset, isTv ? 24 : 16, inset, isTv ? 14 : 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: isTv
                      ? TvSectionHeaderTokens.title.copyWith(color: theme.colorScheme.onSurface)
                      : theme.textTheme.titleLarge,
                ),
              ),
              ?hint,
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: tiles,
        ),
        SizedBox(height: isTv ? 20 : 12),
        row,
        SizedBox(height: isTv ? 16 : 8),
      ],
    );
  }

  /// The section as it will show, while the first choices are matched (the
  /// whole library is read first, which takes a while): the chosen tiles
  /// without art, over skeleton cards, out of focus's way.
  Widget _buildPlaceholder() {
    final isTv = PlatformDetector.isTV();
    final scale = isTv ? TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)) : 1.0;
    final tileWidth = isTv ? 176 * scale : 152.0;
    return ExcludeFocus(
      child: IgnorePointer(
        child: _layout(
          hint: const _LoadingHint(),
          tiles: Row(
            spacing: isTv ? 12 * scale : 10,
            children: [
              for (final id in _choices)
                _ChoiceTile(
                  name: describe(id).name,
                  logoUrl: describe(id).logoUrl,
                  art: null,
                  width: tileWidth,
                  selected: false,
                  focused: false,
                  duration: Duration.zero,
                  onTap: () {},
                ),
            ],
          ),
          row: const _RowSkeleton(),
        ),
      ),
    );
  }

  Widget _buildTiles(List<String> shown, Map<String, MediaItem> art, {required String selected, required bool isTv}) {
    final scale = isTv ? TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)) : 1.0;
    final tileWidth = isTv ? 176 * scale : 152.0;
    return FocusableActionBar(
      spacing: isTv ? 12 * scale : 10,
      onNavigateLeft: widget.onNavigateToSidebar,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: _focusRow,
      onBack: widget.onNavigateToSidebar,
      actions: [
        for (final id in shown)
          FocusableAction(
            debugLabel: '${sectionKey}_$id',
            focusNode: _nodes[id],
            onPressed: () => _openPage(id),
            builder: (context, state) {
              final choice = describe(id);
              return _ChoiceTile(
                name: choice.name,
                logoUrl: choice.logoUrl,
                art: art[id],
                width: tileWidth,
                selected: id == selected,
                focused: state.showFocus,
                duration: state.animationDuration,
                // A touch picks a tile first, then opens it.
                onTap: () => id == selected ? _openPage(id) : _select(id),
              );
            },
          ),
      ],
    );
  }
}

/// "OK Open Netflix": what the remote's OK does on the focused tile.
class _OpenHint extends StatelessWidget {
  final String name;

  const _OpenHint({required this.name});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            child: Text(
              'OK',
              style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          t.libraryHome.networkOpen(name: name),
          style: theme.textTheme.labelMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

/// "Loading…" where the "OK Open …" hint goes, while the section matches.
class _LoadingHint extends StatelessWidget {
  const _LoadingHint();

  @override
  Widget build(BuildContext context) {
    // Static, like the app's skeletons.
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface.withValues(alpha: 0.72);
    return Text(t.common.loading, style: theme.textTheme.labelMedium?.copyWith(color: color));
  }
}

/// Skeleton cards the size of the row's, so the section keeps its height
/// as the titles land.
class _RowSkeleton extends StatelessWidget {
  const _RowSkeleton();

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
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
          if (!isTv) {
            // As HubSection sizes its poster cards.
            final cardWidth = MediaGridDelegate.cellWidth(
              context: context,
              availableWidth: constraints.maxWidth,
              density: svc.read(SettingsService.libraryDensity),
            );
            final cardGap = math.max(4.0, svc.read(SettingsService.gridSpacing).gridGap);
            return SizedBox(
              height: (cardWidth - 6) * 1.5 + 33 + FocusTheme.focusBorderWidth * 2 + 4,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                itemCount: LibraryStripSection.maxItems,
                separatorBuilder: (_, _) => SizedBox(width: cardGap),
                itemBuilder: (_, _) => SizedBox(width: cardWidth, child: const SkeletonMediaCard()),
              ),
            );
          }
          final railInset = TvBrowseRailLayout.horizontalInsetForScale(scale);
          // What the rail measures for poster cards.
          final metrics = TvBrowseRailLayout.metricsForHub(
            hub: const MediaHub(id: 'skeleton', identifier: 'skeleton', title: '', type: 'mixed', size: 0, items: []),
            availableWidth: (constraints.maxWidth - railInset).clamp(1.0, double.infinity).toDouble(),
            density: svc.read(SettingsService.libraryDensity),
            episodePosterMode: svc.read(SettingsService.episodePosterMode),
            scale: scale,
            fullCardLayout: svc.read(SettingsService.tvFullCardLayout),
            gridSpacing: svc.read(SettingsService.gridSpacing),
            extraItemGap: 16,
          );
          return SizedBox(
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
              itemCount: LibraryStripSection.maxItems,
              separatorBuilder: (_, _) => SizedBox(width: metrics.itemGap),
              itemBuilder: (_, _) => Align(
                alignment: Alignment.topCenter,
                child: SkeletonLoader(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  child: SizedBox(width: metrics.posterWidth, height: metrics.posterHeight),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The picked choice's backdrop, faded into the page on every side, so the
/// section takes on its colour. Crossfades as the pick changes.
class _SectionBackdrop extends StatelessWidget {
  final MediaItem? item;

  const _SectionBackdrop({required this.item});

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final item = this.item;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        child: item == null
            ? const SizedBox.expand()
            : Stack(
                key: ValueKey(item.globalKey),
                fit: StackFit.expand,
                children: [
                  OptimizedMediaImage(
                    client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                    imagePath: item.resolvedBackdropPaths.first,
                    imageType: ImageType.art,
                    alignment: Alignment.topCenter,
                  ),
                  // Dims the art without a saveLayer, then fades its edges.
                  ColoredBox(color: background.withValues(alpha: 0.78)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [background.withValues(alpha: 0.85), background.withValues(alpha: 0)],
                        stops: const [0.05, 0.6],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          background,
                          background.withValues(alpha: 0),
                          background.withValues(alpha: 0),
                          background,
                        ],
                        stops: const [0, 0.25, 0.7, 1],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A choice's tile: its most popular title's backdrop, darkened, under the
/// choice's logo in white, or its name in the pages' display face. The
/// focused tile is ringed in white; the picked one keeps a fainter ring
/// while focus is in its row.
class _ChoiceTile extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final MediaItem? art;
  final double width;
  final bool selected;
  final bool focused;
  final Duration duration;
  final VoidCallback onTap;

  const _ChoiceTile({
    required this.name,
    required this.logoUrl,
    required this.art,
    required this.width,
    required this.selected,
    required this.focused,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final height = width / 2;
    final radius = BorderRadius.circular(10);
    final art = this.art;
    final nameText = Text(name.toUpperCase(), maxLines: 1, style: LibraryDisplayType.style(height * 0.36));
    final Widget label = logoUrl == null
        ? Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: height * 0.14),
              child: FittedBox(fit: BoxFit.scaleDown, child: nameText),
            ),
          )
        : Center(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: OptimizedMediaImage(
                imagePath: logoUrl,
                width: width * 0.56,
                height: height * 0.36,
                fit: BoxFit.contain,
                imageType: ImageType.logo,
                placeholder: (context, _) => SizedBox(width: width * 0.56, height: height * 0.36),
                errorWidget: (context, _, _) => FittedBox(fit: BoxFit.scaleDown, child: nameText),
              ),
            ),
          );

    return Semantics(
      label: name,
      selected: selected,
      button: true,
      excludeSemantics: true,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: focused ? 1.06 : 1,
                duration: duration,
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  width: width,
                  height: height,
                  foregroundDecoration: BoxDecoration(
                    borderRadius: radius,
                    border: Border.all(
                      color: focused ? Colors.white : Colors.white.withValues(alpha: selected ? 0.8 : 0.08),
                      width: focused || selected ? FocusTheme.focusBorderWidth : 1,
                    ),
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1C),
                    borderRadius: radius,
                    boxShadow: focused
                        ? const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (art != null)
                          OptimizedMediaImage(
                            client: context.tryGetMediaClientWithFallback(serverIdOrNull(art.serverId)),
                            imagePath: art.resolvedBackdropPaths.first,
                            width: width,
                            height: height,
                            imageType: ImageType.art,
                          ),
                        // Keeps the white logo legible on any art.
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x73000000), Color(0xB3000000)],
                            ),
                          ),
                        ),
                        label,
                        // Recedes the other choices behind the one whose titles
                        // the row below shows.
                        AnimatedOpacity(
                          opacity: selected || focused ? 0 : 1,
                          duration: duration,
                          child: const ColoredBox(color: Color(0x80000000)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SizedBox(height: height * 0.1),
              // Marks the shown choice while focus is down in the row.
              AnimatedContainer(
                duration: duration,
                curve: Curves.easeOutCubic,
                width: selected ? width * 0.2 : 0,
                height: 3,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A choice's matches in the app's API cache, under the first Silo server's
/// profile scope and keyed by every server read, so a different set of
/// servers never reads another's rows. Inert without the cache (tests).
class _StripCache {
  final ServerId? _scope;
  final String _servers;

  /// The section's [LibraryStripSectionState.sectionKey]: `library_networks` keeps
  /// the `/plezy/library-networks/` rows cached before genres were added.
  final String key;
  final String logLabel;

  _StripCache(List<SiloClient> clients, {required this.key, required this.logLabel})
    : _scope = clients.isEmpty ? null : ServerId(clients.first.cacheServerId),
      _servers = ([for (final client in clients) client.cacheServerId]..sort()).join(',');

  /// How the cached items are ordered.
  static const _order = 'popularity';

  String _endpoint(String id) => '/plezy/${key.replaceAll('_', '-')}/$id?servers=${Uri.encodeComponent(_servers)}';

  Future<({List<MediaItem> items, bool fresh})?> read(String id) async {
    final cache = SiloApiCache.instanceOrNull;
    final scope = _scope;
    if (cache == null || scope == null) return null;
    try {
      final endpoint = _endpoint(id);
      final fresh = await cache.getIfFresh(scope, endpoint, maxAge: LibraryStripSection.cacheMaxAge);
      final row = fresh ?? await cache.get(scope, endpoint);
      final items = row?['items'];
      if (items is! List) return null;
      return (
        items: [for (final item in items.whereType<Map<String, dynamic>>()) MediaItem.fromJson(item)],
        // Rows cached newest first, before the network page's Top rows
        // needed TMDB's order, are matched again.
        fresh: fresh != null && row?['order'] == _order,
      );
    } catch (error) {
      appLogger.w('$logLabel: cache read failed for $id (${error.runtimeType})');
      return null;
    }
  }

  Future<void> write(String id, List<MediaItem> items) async {
    final cache = SiloApiCache.instanceOrNull;
    final scope = _scope;
    if (cache == null || scope == null) return;
    try {
      await cache.put(scope, _endpoint(id), {
        'order': _order,
        'items': [for (final item in items) item.toJson()],
      });
    } catch (error) {
      appLogger.w('$logLabel: cache write failed for $id (${error.runtimeType})');
    }
  }
}
