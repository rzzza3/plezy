import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/card_focus_scope.dart';
import '../focus/dpad_navigator.dart';
import '../focus/dpad_select_long_press_controller.dart';
import '../focus/focus_theme.dart';
import '../focus/key_event_utils.dart';
import '../focus/focus_navigation_intent.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../navigation/main_screen_scope.dart';
import '../screens/hub_detail_screen.dart';
import '../services/device_performance.dart';
import '../services/settings_service.dart';
import '../theme/mono_tokens.dart';
import '../utils/layout_constants.dart';
import '../utils/media_image_helper.dart';
import '../utils/formatters.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/provider_extensions.dart';
import 'animated_dim_scrim.dart';
import 'app_icon.dart';
import 'clickable_cursor.dart';
import 'focus_builders.dart';
import 'horizontal_scroll_with_arrows.dart';
import 'listenable_selector.dart';
import 'media_card.dart';
import 'media_context_menu.dart';
import 'media_progress_bar.dart';
import 'optimized_media_image.dart';
import 'person_avatar.dart';
import 'rasterized_gradient.dart';
import 'settings_builder.dart';

const _inactiveArtworkDimAlpha = 0.3;

class TvBrowseRailLayoutMetrics {
  final bool isPersonHub;
  final bool isMixedHub;
  final bool useWideLayout;
  final double focusExtra;
  final double railEdgePadding;
  final double itemGap;

  /// Whether the hub has a leading options card in the negative-offset region
  /// before the row's scroll anchor (see [TvBrowseRailLayout.minScrollExtentFor]).
  final bool hasLeading;
  final double cardWidth;
  final double posterWidth;
  final double posterHeight;
  final double containerHeight;
  final double height;

  const TvBrowseRailLayoutMetrics({
    required this.isPersonHub,
    required this.isMixedHub,
    required this.useWideLayout,
    required this.focusExtra,
    required this.railEdgePadding,
    required this.itemGap,
    this.hasLeading = false,
    required this.cardWidth,
    required this.posterWidth,
    required this.posterHeight,
    required this.containerHeight,
    required this.height,
  });
}

/// Silo's TV row heading (TvSectionHeader): plain title over its rail.
abstract final class TvSectionHeaderTokens {
  static const TextStyle title = TextStyle(fontSize: 18, height: 22 / 18, fontWeight: FontWeight.w600);
  static const double titleHeight = 22;

  /// The header's bottom padding plus the row's spacing down to its cards.
  static const double railGap = 16;
  static const double height = titleHeight + railGap;

  static const double chevronSize = 16;
  static const double chevronGap = 4;
  static const double chevronAlpha = 0.75;
}

class TvBrowseRailLayout {
  static const double compactTallPosterScale = 0.8;
  static const double compactEpisodeThumbnailScale = compactTallPosterScale;
  static const double fullCardFocusScale = FocusTheme.fullCardFocusScale;

  static double scaleForSize(Size size) => TvLayoutConstants.scaleForSize(size);

  static double horizontalInsetForScale(double scale) => (24 * scale).clamp(18, 40).toDouble();

  static double railTopPaddingForScale(double scale) => 12 * scale;

  static double railBottomPaddingForScale(double scale) => 8 * scale;

  static double railInteractionExpansionForScale(double scale) => (12 * scale).clamp(8, 18).toDouble();

  static double fullCardItemGapForScale(double scale) => (12 * scale).clamp(8, 18).toDouble();

  static double nextHubPeekHeightForScale(double scale) => 20 * scale;

  static double hubSectionHeightFor({required double scale, required double activeRailHeight}) {
    return TvSectionHeaderTokens.height + activeRailHeight;
  }

  static double viewportHeightFor({required int hubCount, required double scale, required double sectionHeight}) {
    final peekHeight = hubCount > 1 ? nextHubPeekHeightForScale(scale) : 0.0;
    return sectionHeight + peekHeight;
  }

  static bool isPersonHub(MediaHub hub) => hub.type == 'person';

  static double cardWidthFor({
    required double availableWidth,
    required int density,
    required bool useWideLayout,
    required double scale,
    required double horizontalPadding,
    required double itemGap,
  }) {
    final f = LibraryDensity.factor(density);
    final minWidth = (useWideLayout ? 280 : 170) * scale;
    final maxWidth = (useWideLayout ? 420 : 250) * scale;
    final targetCards = useWideLayout ? 4.2 - (f * 1.4) : 7.0 - (f * 2.0);
    final usableWidth = (availableWidth - horizontalPadding).clamp(1.0, double.infinity).toDouble();
    final gapCount = targetCards > 1 ? targetCards - 1 : 0.0;
    final fittedWidth = (usableWidth - (itemGap * gapCount)) / targetCards;
    return fittedWidth.clamp(minWidth, maxWidth).toDouble();
  }

  static TvBrowseRailLayoutMetrics metricsForHub({
    required MediaHub hub,
    required double availableWidth,
    required int density,
    required EpisodePosterMode episodePosterMode,
    required double scale,
    bool fullCardLayout = false,
    GridSpacing gridSpacing = GridSpacing.tight,
    double tallPosterScale = 1.0,
    double widePosterScale = 1.0,
    double extraItemGap = 0,
    bool hasLeading = false,
  }) {
    final focusExtra = FocusTheme.focusBorderWidth * 2 * scale;
    final railEdgePadding = focusExtra + (12 * scale);
    // Full-card rails keep their own scale-derived gutter, like full-bleed
    // grids; every other rail follows the user's grid-spacing setting, scaled
    // with the rest of the rail metrics (#2226).
    final itemGap =
        (fullCardLayout ? fullCardItemGapForScale(scale) : gridSpacing.gridGap * scale) + extraItemGap * scale;
    final isPersonHub = TvBrowseRailLayout.isPersonHub(hub);
    final emptyEpisodeThumbnailHub =
        hub.items.isEmpty && hub.type == 'episode' && episodePosterMode == EpisodePosterMode.episodeThumbnail;
    final hasWide =
        !isPersonHub &&
        (emptyEpisodeThumbnailHub || hub.items.any((item) => item.usesWideAspectRatio(episodePosterMode)));
    final hasTall = !isPersonHub && hub.items.any((item) => !item.usesWideAspectRatio(episodePosterMode));
    final isMixedHub = hasWide && hasTall;
    final useWideLayout = hasWide && (!hasTall || episodePosterMode == EpisodePosterMode.episodeThumbnail);
    // Music hubs render square album/artist artwork (person hubs are already square).
    final isSquareHub =
        !isPersonHub &&
        hub.items.isNotEmpty &&
        hub.items.every((item) => item.cardShape(episodePosterMode) == CardShape.square);
    final baseCardWidth = cardWidthFor(
      availableWidth: availableWidth,
      density: density,
      useWideLayout: useWideLayout,
      scale: scale,
      horizontalPadding: railEdgePadding * 2,
      itemGap: itemGap,
    );
    final cardWidth = baseCardWidth * (useWideLayout ? widePosterScale : tallPosterScale);
    final posterWidth = fullCardLayout ? cardWidth : cardWidth - (6 * scale);
    final posterHeight = (isPersonHub || isSquareHub)
        ? posterWidth
        : (useWideLayout ? posterWidth * 9 / 16 : posterWidth * 1.5);
    final labelHeight = fullCardLayout ? 0.0 : ((isPersonHub ? 52 : 36) * scale);
    final containerHeight = (posterHeight + labelHeight).ceilToDouble();
    final height = containerHeight + focusExtra + (10 * scale);

    return TvBrowseRailLayoutMetrics(
      isPersonHub: isPersonHub,
      isMixedHub: isMixedHub,
      useWideLayout: useWideLayout,
      focusExtra: focusExtra,
      railEdgePadding: railEdgePadding,
      itemGap: itemGap,
      hasLeading: hasLeading,
      cardWidth: cardWidth,
      posterWidth: posterWidth,
      posterHeight: posterHeight,
      containerHeight: containerHeight,
      height: height,
    );
  }

  static double maxActiveRailHeight({
    required List<MediaHub> hubs,
    required double availableWidth,
    required int density,
    required EpisodePosterMode episodePosterMode,
    EpisodePosterMode Function(MediaHub hub)? episodePosterModeForHub,
    double Function(MediaHub hub)? widePosterScaleForHub,
    required double scale,
    bool fullCardLayout = false,
    GridSpacing gridSpacing = GridSpacing.tight,
    double tallPosterScale = 1.0,
    double widePosterScale = 1.0,
  }) {
    var maxHeight = 0.0;
    for (final hub in hubs) {
      final metrics = metricsForHub(
        hub: hub,
        availableWidth: availableWidth,
        density: density,
        episodePosterMode: episodePosterModeForHub?.call(hub) ?? episodePosterMode,
        scale: scale,
        fullCardLayout: fullCardLayout,
        gridSpacing: gridSpacing,
        tallPosterScale: tallPosterScale,
        widePosterScale: widePosterScaleForHub?.call(hub) ?? widePosterScale,
      );
      if (metrics.height > maxHeight) maxHeight = metrics.height;
    }
    return maxHeight;
  }

  static double estimatedMaxScrollExtent({
    required MediaHub hub,
    required TvBrowseRailLayoutMetrics metrics,
    required double viewportWidth,
    bool? hasTrailing,
  }) {
    final showTrailing = hasTrailing ?? hub.more;
    final itemCount = hub.items.length + (showTrailing ? 1 : 0);
    // The leading options card lives BEFORE the scroll anchor (negative
    // offsets, see [minScrollExtentFor]); it never contributes here.
    final contentWidth = (metrics.railEdgePadding * 2) + (itemCount * (metrics.cardWidth + metrics.itemGap));
    return (contentWidth - viewportWidth).clamp(0.0, double.infinity).toDouble();
  }

  /// Scroll extent of the region before the anchor: the hub's leading options
  /// card plus its edge padding. Zero for hubs without a leading slot, so the
  /// row rests with its first item at the rail start and the options card
  /// sits off-screen until focus (or a drag) reveals it.
  static double minScrollExtentFor(TvBrowseRailLayoutMetrics metrics) =>
      metrics.hasLeading ? -(metrics.railEdgePadding + metrics.cardWidth) : 0.0;

  /// Whether a hub's row morphs its focused poster into a wide backdrop card
  /// (see [TvBrowseRail.expandFocusedPosters]): rows of 2:3 posters only, and
  /// none with a leading options slot, whose negative scroll region the
  /// pinned-to-start scrolling does not model.
  static bool usesPosterMorph(MediaHub hub, TvBrowseRailLayoutMetrics metrics) =>
      hub.items.isNotEmpty &&
      !metrics.isPersonHub &&
      !metrics.useWideLayout &&
      !metrics.isMixedHub &&
      !metrics.hasLeading &&
      (metrics.posterHeight - metrics.posterWidth * 1.5).abs() < 0.5;

  /// How much wider the focused card of a morphing row is than a poster: it
  /// grows to 16:9 at the poster's height.
  static double posterMorphExtraWidth(TvBrowseRailLayoutMetrics metrics) =>
      metrics.posterHeight * 16 / 9 - metrics.posterWidth;

  static double itemExtentForIndex({required int index, required TvBrowseRailLayoutMetrics metrics}) {
    assert(index >= 0);
    return metrics.cardWidth + metrics.itemGap;
  }

  static double scrollOffsetForIndex({
    required MediaHub hub,
    required int index,
    required TvBrowseRailLayoutMetrics metrics,
    required double viewportWidth,
    required double maxScrollExtent,
    bool? hasTrailing,
  }) {
    final showTrailing = hasTrailing ?? hub.more;
    final leadingCount = metrics.hasLeading ? 1 : 0;
    final totalCount = leadingCount + hub.items.length + (showTrailing ? 1 : 0);
    if (totalCount == 0) return 0;

    final clampedIndex = index.clamp(0, totalCount - 1).toInt();
    if (metrics.hasLeading && clampedIndex == 0) return minScrollExtentFor(metrics);
    final itemExtent = metrics.cardWidth + metrics.itemGap;
    final targetCenter = metrics.railEdgePadding + ((clampedIndex - leadingCount + 0.5) * itemExtent);
    return (targetCenter - (viewportWidth / 2)).clamp(0.0, maxScrollExtent).toDouble();
  }

  static double estimateHeight({
    required Size size,
    required List<MediaHub> hubs,
    required int density,
    required EpisodePosterMode episodePosterMode,
    EpisodePosterMode Function(MediaHub hub)? episodePosterModeForHub,
    double Function(MediaHub hub)? widePosterScaleForHub,
    bool fullCardLayout = false,
    GridSpacing gridSpacing = GridSpacing.tight,
    double tallPosterScale = 1.0,
    double widePosterScale = 1.0,
  }) {
    if (hubs.isEmpty) return 0;

    final scale = scaleForSize(size);
    final availableWidth = size.width - horizontalInsetForScale(scale);
    if (availableWidth <= 0) return 0;

    final railHeight = maxActiveRailHeight(
      hubs: hubs,
      availableWidth: availableWidth,
      density: density,
      episodePosterMode: episodePosterMode,
      episodePosterModeForHub: episodePosterModeForHub,
      widePosterScaleForHub: widePosterScaleForHub,
      scale: scale,
      fullCardLayout: fullCardLayout,
      gridSpacing: gridSpacing,
      tallPosterScale: tallPosterScale,
      widePosterScale: widePosterScale,
    );

    final sectionHeight = hubSectionHeightFor(scale: scale, activeRailHeight: railHeight);

    return railTopPaddingForScale(scale) +
        viewportHeightFor(hubCount: hubs.length, scale: scale, sectionHeight: sectionHeight) +
        railBottomPaddingForScale(scale);
  }
}

/// What [TvBrowseRail] renders in a hub's trailing slot (after the last item).
enum TvRailTrailing { none, loading, error, viewAll }

class TvBrowseRail extends StatefulWidget {
  final List<MediaHub> hubs;
  final HubFocusMemory focusMemory;

  /// Whether to show each hub's originating server name in its header. Used when
  /// the loaded hubs span more than one connected server so their origin stays
  /// clear, mirroring the mobile [HubSection] behavior.
  final bool showServerName;
  final ValueChanged<MediaItem>? onFocusedItemChanged;
  final void Function(MediaHub hub, MediaItem item)? onFocusedHubItemChanged;
  final void Function(MediaItem source)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;
  final bool Function(MediaHub hub)? isContinueWatchingHub;
  final bool Function(MediaHub hub)? usesContinueWatchingAction;

  /// The full-list loader a hub's View All screen uses instead of paging the
  /// hub from its server, or null — for the whole rail or for one hub — to let
  /// that screen page it itself. Only hubs the server cannot list in full
  /// (Continue Watching, catalog rows) need one.
  final Future<List<MediaItem>> Function()? Function(MediaHub hub)? loadMoreItems;

  /// Optional per-hub trailing-slot state (loading/error/viewAll). When null the
  /// rail keeps the legacy "[MediaHub.more] → View All" behavior.
  final TvRailTrailing Function(MediaHub hub)? trailingForHub;

  /// Optional per-hub leading slot: a compact options button before the first
  /// item that opens the context menu for the returned [MediaItem] (the media
  /// detail screen returns each episode hub's season). Presence must be stable
  /// per hub key across rebuilds — slot indices are not remapped when a hub
  /// gains or loses its leading slot.
  final MediaItem? Function(MediaHub hub)? leadingItemForHub;

  /// Invoked when the user activates a hub's trailing retry tile.
  final void Function(MediaHub hub)? onRetryHub;

  /// Overrides the View All screen a hub's trailing tile opens.
  final void Function(MediaHub hub)? onViewAll;
  final void Function(MediaHub hub, int index)? onActiveHubChanged;
  final VoidCallback? onNavigateUp;

  /// DOWN on the last hub, for a rail with content below it. Null keeps
  /// DOWN inside the rail.
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateToSidebar;

  /// LEFT on a hub's first slot (-1) or RIGHT on its last slot (1). Return
  /// true when handled — e.g. by moving into the neighbouring season with
  /// [TvBrowseRailState.enterHubAtEdge]; false falls back to the default.
  final bool Function(MediaHub hub, int direction)? onHorizontalEdge;
  final VoidCallback? onBack;
  final FutureOr<bool> Function(MediaHub hub, MediaItem item)? onActivateItem;
  final double tallPosterScale;
  final double widePosterScale;

  /// Added to the gap between cards (before the TV scale), on top of the
  /// user's grid spacing.
  final double extraItemGap;
  final String? initialHubId;
  final String? initialItemId;
  final bool autofocus;

  /// False drops the title row above each hub, for a rail whose section
  /// already names it.
  final bool showHubHeaders;
  final EpisodePosterMode Function(MediaHub hub)? episodePosterModeForHub;
  final double Function(MediaHub hub)? widePosterScaleForHub;

  /// Hubs whose episode cards belong to the show this rail sits under, so
  /// cards headline the episode title instead of the show name
  /// ([MediaCard.showTitleImplied]).
  final bool Function(MediaHub hub)? showTitleImpliedForHub;

  /// Explicit background bleed override. When null, the bleed target is read
  /// from [MainScreenFocusScope] (offset aspect) inside the bleed widget
  /// itself, so sidebar flips never rebuild the rail — only the bleed layer.
  final double? backgroundBleedLeft;

  /// Height to give the hub list instead of one hub plus the next one's peek,
  /// so several hubs show stacked at once. The list then ends at its last hub
  /// rather than letting that hub scroll to the top.
  final double? viewportHeight;

  /// Space above the first hub inside the scrolling list. The first hub sits
  /// below it; every later hub scrolls it away and lands at the list's top, so
  /// a header over the rail can scroll off without leaving a gap.
  final double leadingInset;

  /// False keeps the rail at full brightness while focus is elsewhere on the
  /// page, for a row that should stay readable from the hero above it.
  final bool dimWhenUnfocused;

  /// Cards lead their subtitle with the time left on part-watched items
  /// ([MediaCard.showTimeLeft]).
  final bool showTimeLeft;

  /// Overrides the user's full-card layout setting for this rail: true always
  /// renders image-only full-bleed cards, false always captioned cards.
  final bool? fullCardLayout;

  /// Person hubs draw round photos (or initials) with the name and role
  /// centered underneath, instead of square photos.
  final bool circularPersonCards;

  /// Rows of posters show image-only cards, and the focused one grows into a
  /// wide backdrop with its logo, pinned at the row's start, while the row
  /// slides past it (see [TvBrowseRailLayout.usesPosterMorph]).
  final bool expandFocusedPosters;

  const TvBrowseRail({
    super.key,
    required this.hubs,
    required this.focusMemory,
    this.showServerName = false,
    this.onFocusedItemChanged,
    this.onFocusedHubItemChanged,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
    this.isContinueWatchingHub,
    this.usesContinueWatchingAction,
    this.loadMoreItems,
    this.trailingForHub,
    this.leadingItemForHub,
    this.onRetryHub,
    this.onViewAll,
    this.onActiveHubChanged,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateToSidebar,
    this.onHorizontalEdge,
    this.onBack,
    this.onActivateItem,
    this.tallPosterScale = 1.0,
    this.widePosterScale = 1.0,
    this.extraItemGap = 0,
    this.initialHubId,
    this.initialItemId,
    this.autofocus = false,
    this.showHubHeaders = true,
    this.episodePosterModeForHub,
    this.widePosterScaleForHub,
    this.showTitleImpliedForHub,
    this.backgroundBleedLeft,
    this.viewportHeight,
    this.leadingInset = 0,
    this.dimWhenUnfocused = true,
    this.showTimeLeft = false,
    this.fullCardLayout,
    this.circularPersonCards = false,
    this.expandFocusedPosters = true,
  });

  @override
  State<TvBrowseRail> createState() => TvBrowseRailState();
}

class TvBrowseRailState extends State<TvBrowseRail> with TickerProviderStateMixin {
  // Per-step scroll glide; platform-specific, see
  // FocusTheme.navigationScrollDuration. Successive steps — including
  // hold-repeats — retarget the animation from the row's current offset, so a
  // sustained drag trails the focused index slightly and catches up in one
  // continuous glide on release.
  static Duration get _navigationScrollDuration => FocusTheme.navigationScrollDuration();
  static const _scrollCatchUpViewportDistance = 2.5;
  // Equivalent to the former whole-rail Opacity(0.6) without keeping a
  // full-viewport saveLayer alive.
  static const _unfocusedRailDimAlpha = 0.4;

  late final FocusNode _focusNode = LockedFocusRowNode(debugLabel: 'tv_browse_rail', focusedItemRect: _focusedCardRect);
  final Map<String, ScrollController> _scrollControllers = {};
  final ScrollController _verticalController = ScrollController();
  final SnapshotController _verticalScrollSnapshotController = SnapshotController();
  final Map<int, GlobalKey> _hubSectionKeys = {};
  final Map<String, GlobalKey<MediaCardState>> _mediaCardKeys = {};
  final Map<String, TvBrowseRailLayoutMetrics> _metricsByHub = {};
  final Map<String, TvRailTrailing> _lastTrailingByHubKey = {};
  final Map<String, GlobalKey<MediaContextMenuState>> _leadingMenuKeys = {};
  final Map<int, _HubArtworkDim> _artworkDims = {};

  /// Per-hub morph state of the rows that expand their focused poster.
  final Map<String, _PosterMorph> _posterMorphs = {};

  int _hubIndex = 0;
  int _itemIndex = 0;

  /// Mirrors (_hubIndex, _itemIndex) plus the rail's focus state for the
  /// per-card/header/artwork-dim selectors, so d-pad moves and focus flips repaint
  /// only the affected subtrees instead of setState-rebuilding every visible
  /// row (expensive on low-end TVs).
  final _RailFocusModel _focusModel = _RailFocusModel();
  List<double> _sectionOffsets = const [];
  double _sectionMaxScrollExtent = 0;
  final _selectLongPress = DpadSelectLongPressController();
  bool _hasUserInteracted = false;
  bool _hasUserChangedHub = false;
  int _verticalScrollGeneration = 0;
  bool _hasUserChangedItem = false;

  /// Hub key whose leading slot took focus only because the hub had no items
  /// yet (the clamp in [_moveHub]); when items arrive, focus advances to the
  /// first item so entering a not-yet-fetched hub still lands on item 1.
  String? _pendingLeadingAutoAdvanceHubKey;

  /// Set by [enterHubAtEdge]: the hub (by `hub.id`) to land on at its first or
  /// last item once it is in [TvBrowseRail.hubs] with items.
  ({String hubId, bool atEnd})? _pendingEdgeEntry;

  /// On the next hub update that brings [hubId] into the rail with items,
  /// focus its last item ([atEnd]) or its first, skipping the leading slot.
  /// Call before the owner rebuilds the rail with the new hub.
  void enterHubAtEdge(String hubId, {required bool atEnd}) {
    _pendingEdgeEntry = (hubId: hubId, atEnd: atEnd);
  }

  MediaHub? get _activeHub => widget.hubs.isEmpty ? null : widget.hubs[_hubIndex.clamp(0, widget.hubs.length - 1)];

  void requestFocus() {
    _notifyFocusedItem();
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    final startHub = _activeHub;
    if (startHub != null) _itemIndex = _defaultSlotFor(startHub);
    _selectInitialHubIfPossible();
    final selectedInitialItem = _selectInitialItemIfPossible();
    _focusModel.set(_hubIndex, _itemIndex, notify: false);
    _rememberTrailingStates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.hubs.isEmpty) return;
      if (selectedInitialItem) _scrollToItem(animate: false);
      _scrollActiveHubToTop(animate: false);
      _notifyActiveHubChanged();
      _notifyFocusedItem();
      if (widget.autofocus) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(covariant TvBrowseRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hubs.length < oldWidget.hubs.length) {
      _artworkDims.removeWhere((index, dim) {
        if (index < widget.hubs.length) return false;
        dim.dispose();
        return true;
      });
    }
    final trailingStateChanged = _hasTrailingStateChanged(widget.hubs);
    final hubStateChanged = trailingStateChanged || !_hasSameHubState(oldWidget.hubs, widget.hubs);
    final initialSelectionChanged =
        oldWidget.initialHubId != widget.initialHubId || oldWidget.initialItemId != widget.initialItemId;

    if (!hubStateChanged && !initialSelectionChanged) {
      _rememberTrailingStates();
      if (!oldWidget.autofocus && widget.autofocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
      return;
    }

    final oldActiveHub = oldWidget.hubs.isEmpty ? null : oldWidget.hubs[_hubIndex.clamp(0, oldWidget.hubs.length - 1)];
    final oldActiveHubKey = oldActiveHub == null ? null : _hubKey(oldActiveHub);
    final oldFocusedItem = oldActiveHub == null ? null : _itemAtSlot(oldActiveHub, _itemIndex);

    if (widget.hubs.isEmpty) {
      _hubIndex = 0;
      _itemIndex = 0;
      _focusModel.set(_hubIndex, _itemIndex, notify: false);
      _rememberTrailingStates();
      return;
    }

    final selectedInitialHub = _selectInitialHubIfPossible();
    if (!selectedInitialHub && oldActiveHubKey != null) {
      final preservedIndex = widget.hubs.indexWhere((hub) => _hubKey(hub) == oldActiveHubKey);
      if (preservedIndex != -1) {
        _hubIndex = preservedIndex;
      } else {
        _hubIndex = _hubIndex.clamp(0, widget.hubs.length - 1);
      }
    } else if (!selectedInitialHub) {
      _hubIndex = _hubIndex.clamp(0, widget.hubs.length - 1);
    }

    final hub = _activeHub;
    if (hub == null) return;
    var followedFocusedItem = false;
    if (_hasUserInteracted && oldFocusedItem != null && _hubKey(hub) == oldActiveHubKey) {
      // Keep the selection on the media it was on when the active hub's items
      // reorder underneath it — a Continue Watching refresh after playback
      // moves the just-played item to the front (#1987). When the exact item
      // left the list, follow its series' replacement entry (finished episode
      // → next episode); otherwise fall through to the positional clamp.
      final followedIndex = followItemIndex(hub.items, oldFocusedItem);
      final followedSlot = followedIndex == -1 ? -1 : followedIndex + _leadingCountFor(hub);
      if (followedSlot != -1 && followedSlot != _itemIndex) {
        _itemIndex = followedSlot;
        followedFocusedItem = true;
      }
    }
    _itemIndex = _itemIndex.clamp(0, _totalItemCount(hub) == 0 ? 0 : _totalItemCount(hub) - 1);
    var enteredAtEdge = false;
    final edgeEntry = _pendingEdgeEntry;
    if (edgeEntry != null && hub.id == edgeEntry.hubId) {
      final leading = _leadingCountFor(hub);
      if (hub.items.isNotEmpty) {
        _itemIndex = edgeEntry.atEnd ? leading + hub.items.length - 1 : leading;
        _pendingEdgeEntry = null;
        _pendingLeadingAutoAdvanceHubKey = null;
        _hasUserChangedItem = true;
        _rememberFocus(hub);
        enteredAtEdge = true;
      } else {
        // Still loading: wait on the leading slot rather than on the old
        // position's clamp (the trailing spinner).
        _itemIndex = 0;
      }
    }
    var autoAdvancedFromLeading = false;
    if (_pendingLeadingAutoAdvanceHubKey == _hubKey(hub) && hub.items.isNotEmpty) {
      if (_isLeadingSlot(hub, _itemIndex)) {
        _itemIndex = _defaultSlotFor(hub);
        widget.focusMemory.remapForHub(_hubKey(hub), _itemIndex);
        autoAdvancedFromLeading = true;
      }
      _pendingLeadingAutoAdvanceHubKey = null;
    }
    final selectedInitialItem = _selectInitialItemIfPossible();
    // notify:false — this runs during the build phase and the enclosing
    // rebuild already refreshes every selector.
    _focusModel.set(_hubIndex, _itemIndex, notify: false);
    final newActiveHub = _activeHub;
    final activeHubChanged = oldActiveHubKey != (newActiveHub == null ? null : _hubKey(newActiveHub));
    final activeHubStateChanged =
        _hubStateChanged(oldWidget.hubs, widget.hubs, _hubIndex) ||
        (_activeHub != null && _trailingStateChanged(_activeHub!));
    final shouldJumpAlignActiveHub = selectedInitialHub || activeHubChanged || !_hasUserChangedHub;
    final shouldAnimateAlignActiveHub = !shouldJumpAlignActiveHub && activeHubStateChanged;
    _rememberTrailingStates();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (selectedInitialItem || followedFocusedItem || autoAdvancedFromLeading || enteredAtEdge) {
        _scrollToItem(animate: false);
      }
      // Items came, went or moved: re-pin every morphing row in place.
      _updatePosterMorphs(animate: false);
      if (shouldJumpAlignActiveHub) {
        _scrollActiveHubToTop(animate: false);
      } else if (shouldAnimateAlignActiveHub) {
        _scrollActiveHubToTop();
      }
      if (!oldWidget.autofocus && widget.autofocus) _focusNode.requestFocus();
      if (activeHubChanged) _notifyActiveHubChanged();
      _notifyFocusedItem();
    });
  }

  bool _hasSameHubState(List<MediaHub> oldHubs, List<MediaHub> newHubs) {
    if (oldHubs.length != newHubs.length) return false;
    for (var i = 0; i < oldHubs.length; i++) {
      if (_hubStateChanged(oldHubs, newHubs, i)) return false;
    }
    return true;
  }

  bool _hubStateChanged(List<MediaHub> oldHubs, List<MediaHub> newHubs, int index) {
    if (index < 0 || index >= oldHubs.length || index >= newHubs.length) return true;
    final oldHub = oldHubs[index];
    final newHub = newHubs[index];
    if (_hubKey(oldHub) != _hubKey(newHub) ||
        oldHub.more != newHub.more ||
        oldHub.items.length != newHub.items.length) {
      return true;
    }
    for (var j = 0; j < oldHub.items.length; j++) {
      if (oldHub.items[j].globalKey != newHub.items[j].globalKey) return true;
    }
    return false;
  }

  bool _hasTrailingStateChanged(List<MediaHub> hubs) {
    for (final hub in hubs) {
      if (_trailingStateChanged(hub)) return true;
    }
    return false;
  }

  bool _trailingStateChanged(MediaHub hub) {
    final previous = _lastTrailingByHubKey[_hubKey(hub)];
    return previous != null && previous != _trailingFor(hub);
  }

  void _rememberTrailingStates() {
    _lastTrailingByHubKey
      ..clear()
      ..addEntries(widget.hubs.map((hub) => MapEntry(_hubKey(hub), _trailingFor(hub))));
  }

  @override
  void dispose() {
    _selectLongPress.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    for (final dim in _artworkDims.values) {
      dim.dispose();
    }
    _focusModel.dispose();
    for (final morph in _posterMorphs.values) {
      morph.dispose();
    }
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _verticalController.dispose();
    _verticalScrollGeneration++;
    _verticalScrollSnapshotController.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _resetLongPressState();
    if (_focusNode.hasFocus) _notifyFocusedItem();
    // No setState: rail focus is observed through _focusModel selectors
    // (per-card focus wrappers, headers and artwork dim), so a focus flip
    // repaints only those subtrees instead of rebuilding every visible row.
    _focusModel.setRailFocus(_focusNode.hasFocus);
    _updatePosterMorphs();
  }

  /// Points every morphing row at where it should rest: the active hub's
  /// focused slot pinned at its start and expanded while the rail has focus;
  /// every other row collapsed where it was left.
  void _updatePosterMorphs({bool animate = true}) {
    for (var i = 0; i < widget.hubs.length; i++) {
      final key = _hubKey(widget.hubs[i]);
      final morph = _posterMorphs[key];
      if (morph == null) continue;
      final active = i == _hubIndex;
      morph.retarget(
        position: active ? _itemIndex.toDouble() : morph.targetPosition,
        amount: active && _focusNode.hasFocus ? 1 : 0,
        animate: animate,
      );
      if (!animate) _syncPosterMorphScroll(key);
    }
  }

  /// Holds a morphing row's scroll at its pinned slot (see [_PosterMorph]).
  void _syncPosterMorphScroll(String hubKey) {
    final morph = _posterMorphs[hubKey];
    final controller = _scrollControllers[hubKey];
    final metrics = _metricsByHub[hubKey];
    if (morph == null || controller == null || metrics == null || controller.positions.length != 1) return;
    final position = controller.position;
    final target = math.max(0.0, morph.position * (metrics.cardWidth + metrics.itemGap));
    if ((position.pixels - target).abs() >= 0.01) position.jumpTo(target);
  }

  void _resetLongPressState() {
    _selectLongPress.reset();
  }

  bool _hasTrailingFor(MediaHub hub) => _trailingFor(hub) != TvRailTrailing.none;

  MediaItem? _leadingItemFor(MediaHub hub) => widget.leadingItemForHub?.call(hub);

  bool _hasLeadingFor(MediaHub hub) => _leadingItemFor(hub) != null;

  int _leadingCountFor(MediaHub hub) => _hasLeadingFor(hub) ? 1 : 0;

  bool _isLeadingSlot(MediaHub hub, int slot) => slot == 0 && _hasLeadingFor(hub);

  bool _isTrailingSlot(MediaHub hub, int slot) =>
      _hasTrailingFor(hub) && slot == _leadingCountFor(hub) + hub.items.length;

  /// The media item shown at [slot], or null for the leading/trailing slots.
  MediaItem? _itemAtSlot(MediaHub hub, int slot) {
    final index = slot - _leadingCountFor(hub);
    return index >= 0 && index < hub.items.length ? hub.items[index] : null;
  }

  /// Where focus lands in [hub] with no remembered position: the first media
  /// item, so a leading slot never adds a step to normal navigation.
  int _defaultSlotFor(MediaHub hub) {
    final total = _totalItemCount(hub);
    return total == 0 ? 0 : _leadingCountFor(hub).clamp(0, total - 1);
  }

  int _totalItemCount(MediaHub hub) => _leadingCountFor(hub) + hub.items.length + (_hasTrailingFor(hub) ? 1 : 0);

  bool _isPersonHub(MediaHub hub) => TvBrowseRailLayout.isPersonHub(hub);

  void _notifyFocusedItem() {
    final hub = _activeHub;
    if (hub == null) return;
    final item = _itemAtSlot(hub, _itemIndex);
    if (item == null) return;
    widget.onFocusedItemChanged?.call(item);
    widget.onFocusedHubItemChanged?.call(hub, item);
  }

  void _notifyActiveHubChanged() {
    final hub = _activeHub;
    if (hub == null) return;
    widget.onActiveHubChanged?.call(hub, _hubIndex);
  }

  bool _selectInitialHubIfPossible() {
    final initialHubId = widget.initialHubId;
    if (_hasUserInteracted ||
        _hasUserChangedHub ||
        _hasUserChangedItem ||
        initialHubId == null ||
        widget.hubs.isEmpty) {
      return false;
    }
    // External contract: `initialHubId` is a bare `hub.id` supplied by the
    // single-server media-detail caller, so match on `hub.id` (not `_hubKey`).
    final initialIndex = widget.hubs.indexWhere((hub) => hub.id == initialHubId);
    if (initialIndex == -1) return false;
    if (initialIndex != _hubIndex) {
      _hubIndex = initialIndex;
      _itemIndex = _defaultSlotFor(widget.hubs[initialIndex]);
    }
    return true;
  }

  bool _selectInitialItemIfPossible() {
    final initialItemId = widget.initialItemId;
    final hub = _activeHub;
    if (_hasUserInteracted || _hasUserChangedHub || _hasUserChangedItem || initialItemId == null || hub == null) {
      return false;
    }
    final initialIndex = hub.items.indexWhere((item) => item.id == initialItemId);
    if (initialIndex == -1) return false;
    final initialSlot = initialIndex + _leadingCountFor(hub);
    if (initialSlot != _itemIndex) _itemIndex = initialSlot;
    return true;
  }

  _HubArtworkDim _artworkDimForHub(BuildContext context, int hubIndex) => _artworkDims.putIfAbsent(
    hubIndex,
    () => _HubArtworkDim(_focusModel, hubIndex, vsync: this, duration: FocusTheme.getAnimationDuration(context)),
  );

  KeyEventResult _handleKeyEvent(FocusNode _, KeyEvent event) {
    final key = event.logicalKey;

    if (key.isSelectKey) {
      _hasUserInteracted = true;

      return _selectLongPress.handleKeyEvent(
        event,
        isOwnerActive: () => mounted,
        onShortPress: _activateCurrentItem,
        onLongPress: _showContextMenuForCurrentItem,
      );
    }

    if (widget.onBack != null) {
      final backResult = handleBackKeyAction(event, widget.onBack!);
      if (backResult != KeyEventResult.ignored) {
        _hasUserInteracted = true;
        return backResult;
      }
    }

    if (key.isDpadDirection && event is KeyUpEvent) return KeyEventResult.handled;

    if (!event.isActionable) return KeyEventResult.ignored;
    final hub = _activeHub;
    if (hub == null) return KeyEventResult.ignored;
    if (key.isDpadDirection || key.isContextMenuKey) _hasUserInteracted = true;

    if (key.isLeftKey) {
      if (_itemIndex > 0) {
        _moveItem(-1);
      } else if (widget.onHorizontalEdge?.call(hub, -1) != true) {
        widget.onNavigateToSidebar?.call();
      }
      return KeyEventResult.handled;
    }

    if (key.isRightKey) {
      if (_itemIndex < _totalItemCount(hub) - 1) {
        _moveItem(1);
      } else {
        widget.onHorizontalEdge?.call(hub, 1);
      }
      return KeyEventResult.handled;
    }

    if (key.isUpKey) {
      if (_hubIndex > 0) {
        _moveHub(-1);
      } else {
        widget.onNavigateUp?.call();
      }
      return KeyEventResult.handled;
    }

    if (key.isDownKey) {
      if (_hubIndex >= widget.hubs.length - 1 && widget.onNavigateDown != null) {
        widget.onNavigateDown!();
      } else {
        _moveHub(1);
      }
      return KeyEventResult.handled;
    }

    if (key.isContextMenuKey) {
      _showContextMenuForCurrentItem();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _moveItem(int delta) {
    final hub = _activeHub;
    if (hub == null) return;
    _hasUserInteracted = true;
    final next = (_itemIndex + delta).clamp(0, _totalItemCount(hub) - 1);
    if (next == _itemIndex) return;

    // No setState: the per-card focus selectors and the fixed semantics proxy
    // observe the selection through _focusModel.
    _itemIndex = next;
    _hasUserChangedItem = true;
    _pendingLeadingAutoAdvanceHubKey = null;
    _focusModel.set(_hubIndex, _itemIndex);
    _rememberFocus(hub);
    _notifyFocusedItem();
    _scrollToItem();
  }

  void _moveHub(int delta) {
    if (widget.hubs.isEmpty) return;
    _hasUserInteracted = true;
    final next = (_hubIndex + delta).clamp(0, widget.hubs.length - 1);
    if (next == _hubIndex) return;
    final currentHub = _activeHub;
    if (currentHub != null) _rememberFocus(currentHub);
    final nextHub = widget.hubs[next];
    final remembered = widget.focusMemory.getForHubOnly(
      _hubKey(nextHub),
      _totalItemCount(nextHub),
      fallback: _defaultSlotFor(nextHub),
    );
    // No setState: the active-hub change is observed through _focusModel
    // selectors (cards, headers, artwork dim), so a hub move repaints only the
    // two affected rows instead of rebuilding every visible card. Section
    // extents don't depend on the active hub, so no relayout is needed.
    _hubIndex = next;
    _itemIndex = remembered.clamp(0, _totalItemCount(nextHub) == 0 ? 0 : _totalItemCount(nextHub) - 1);
    // Landing on the leading slot only because the hub has no items yet is a
    // clamp artifact, not a choice: advance to the first item once they load.
    _pendingLeadingAutoAdvanceHubKey = nextHub.items.isEmpty && _isLeadingSlot(nextHub, _itemIndex)
        ? _hubKey(nextHub)
        : null;
    _hasUserChangedHub = true;
    _focusModel.set(_hubIndex, _itemIndex);
    _notifyFocusedItem();
    _notifyActiveHubChanged();
    // The row left collapses and the one entered expands, both animated; the
    // jump below then finds them already aimed and only aligns the scroll.
    _updatePosterMorphs();
    _scrollToItemAfterLayout(animate: false);
    // Section offsets are computed at build, so a laid-out list can start the
    // vertical glide in this frame instead of one frame later.
    if (!_alignActiveHubToTop(animate: true)) _scrollActiveHubToTop();
  }

  /// Scrolls the vertical list so the active hub sits at the top, using the
  /// build-time section offsets. Returns false when the list has no client yet
  /// or the offsets do not cover [_hubIndex]; callers then fall back to the
  /// section key path in [_scrollActiveHubToTop].
  bool _alignActiveHubToTop({required bool animate}) {
    if (!_verticalController.hasClients || _hubIndex < 0 || _hubIndex >= _sectionOffsets.length) return false;
    final target = _sectionOffsets[_hubIndex].clamp(0.0, _sectionMaxScrollExtent).toDouble();
    if (animate) {
      _startVerticalScrollAnimation(
        () => _verticalController.animateTo(target, duration: _navigationScrollDuration, curve: Curves.easeOutCubic),
      );
    } else {
      _verticalScrollGeneration++;
      _focusModel.verticalScrollActive = false;
      _verticalScrollSnapshotController.allowSnapshotting = false;
      _verticalController.jumpTo(target);
    }
    return true;
  }

  void _scrollActiveHubToTop({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_alignActiveHubToTop(animate: animate)) return;
      // ensureVisible would scroll the first hub past the leading inset.
      if (_hubIndex == 0 && widget.leadingInset > 0) {
        if (_verticalController.hasClients) _verticalController.jumpTo(0);
        return;
      }

      final key = _hubSectionKeys[_hubIndex];
      final context = key?.currentContext;
      if (context == null) return;
      if (animate) {
        _startVerticalScrollAnimation(
          () => Scrollable.ensureVisible(
            context,
            alignment: 0,
            duration: _navigationScrollDuration,
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _verticalScrollGeneration++;
        _focusModel.verticalScrollActive = false;
        _verticalScrollSnapshotController.allowSnapshotting = false;
        unawaited(Scrollable.ensureVisible(context, alignment: 0, duration: Duration.zero));
      }
    });
  }

  void _startVerticalScrollAnimation(Future<void> Function() animate) {
    final generation = ++_verticalScrollGeneration;
    // Suppress the focus glow while the rail animates vertically: the glow
    // paints in the root overlay, unclipped by the vertical viewport, so on UP
    // moves it would flash over the rows above while the target row is still
    // offscreen. Cleared in whenComplete (or by a non-animated jump) so the
    // glow fades back in once the row has settled.
    _focusModel.verticalScrollActive = true;
    // Full-tier row effects must stay live. The reduced tier has already
    // resolved those short effects to their final state before this snapshot.
    final useSnapshots = DevicePerformance.isReduced;
    if (useSnapshots) {
      _verticalScrollSnapshotController.allowSnapshotting = true;
    }
    unawaited(
      animate().whenComplete(() {
        if (!mounted || generation != _verticalScrollGeneration) return;
        _focusModel.verticalScrollActive = false;
        _verticalScrollSnapshotController.allowSnapshotting = false;
      }),
    );
  }

  void _setHoveredItem(MediaHub hub, int index) {
    final active = _activeHub;
    if (active == null || _hubKey(active) != _hubKey(hub) || _itemAtSlot(hub, index) == null || _itemIndex == index) {
      return;
    }
    // Expanding the hovered card would slide the row under the pointer onto
    // the next card, and on down the row.
    if (_posterMorphs.containsKey(_hubKey(hub))) return;
    _hasUserInteracted = true;
    _itemIndex = index;
    _hasUserChangedItem = true;
    _pendingLeadingAutoAdvanceHubKey = null;
    _focusModel.set(_hubIndex, _itemIndex);
    _rememberFocus(hub);
    _notifyFocusedItem();
  }

  void _selectHubItem(MediaHub hub, int hubIndex, int itemIndex) {
    final totalCount = _totalItemCount(hub);
    if (totalCount == 0) return;
    _hasUserInteracted = true;

    final clampedItemIndex = itemIndex.clamp(0, totalCount - 1).toInt();
    final hubChanged = _hubIndex != hubIndex;
    final previousHub = _activeHub;
    if (hubChanged && previousHub != null) _rememberFocus(previousHub);
    // No setState: observed through _focusModel selectors (see _moveHub).
    _hubIndex = hubIndex;
    _itemIndex = clampedItemIndex;
    _hasUserChangedHub = true;
    _hasUserChangedItem = true;
    _pendingLeadingAutoAdvanceHubKey = null;
    _focusModel.set(_hubIndex, _itemIndex);
    _rememberFocus(hub);
    _notifyFocusedItem();
    if (hubChanged) _notifyActiveHubChanged();
    _updatePosterMorphs();
    _scrollActiveHubToTop();
    _scrollToItemAfterLayout(animate: false);
  }

  void _rememberFocus(MediaHub hub) {
    widget.focusMemory.setForHub(_hubKey(hub), _itemIndex);
  }

  void _scrollToItem({bool animate = true}) {
    final hub = _activeHub;
    if (hub == null) return;
    if (_posterMorphs.containsKey(_hubKey(hub))) {
      _updatePosterMorphs(animate: animate);
      return;
    }
    final controller = _scrollControllers[_hubKey(hub)];
    if (controller == null) return;
    if (controller.positions.length != 1) return;
    final metrics = _metricsByHub[_hubKey(hub)];
    if (metrics == null) return;
    final position = controller.position;
    final viewportWidth = position.viewportDimension;
    final maxScrollExtent = position.maxScrollExtent;
    if (!viewportWidth.isFinite || !maxScrollExtent.isFinite) return;
    final target = TvBrowseRailLayout.scrollOffsetForIndex(
      hub: hub,
      index: _itemIndex,
      metrics: metrics,
      viewportWidth: viewportWidth,
      maxScrollExtent: maxScrollExtent,
      hasTrailing: _hasTrailingFor(hub),
    );

    final distance = (position.pixels - target).abs();
    if (distance < 0.5) return;
    if (!animate || distance > viewportWidth * _scrollCatchUpViewportDistance) {
      position.jumpTo(target);
    } else {
      unawaited(position.animateTo(target, duration: _navigationScrollDuration, curve: Curves.easeOutCubic));
    }
  }

  void _scrollToItemAfterLayout({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollToItem(animate: animate);
    });
  }

  ScrollController _scrollControllerForHub(
    MediaHub hub,
    TvBrowseRailLayoutMetrics metrics,
    double viewportWidth,
    int initialItemIndex, {
    required bool hasTrailing,
    required bool isActiveHub,
    bool posterMorph = false,
  }) {
    return _scrollControllers.putIfAbsent(_hubKey(hub), () {
      // A morphing row rests with its slot pinned at the start.
      if (posterMorph) {
        return ScrollController(
          initialScrollOffset: math.max(0, initialItemIndex) * (metrics.cardWidth + metrics.itemGap),
        );
      }
      final maxScrollExtent = TvBrowseRailLayout.estimatedMaxScrollExtent(
        hub: hub,
        metrics: metrics,
        viewportWidth: viewportWidth,
        hasTrailing: hasTrailing,
      );
      final initialScrollOffset = TvBrowseRailLayout.scrollOffsetForIndex(
        hub: hub,
        index: initialItemIndex,
        metrics: metrics,
        viewportWidth: viewportWidth,
        maxScrollExtent: maxScrollExtent,
        hasTrailing: hasTrailing,
      );
      // Only the active hub may rest in the negative region that reveals the
      // leading options card: an inactive row (e.g. a not-yet-fetched season
      // whose only slot IS the card) must still rest anchored on its first
      // item so the card stays off-screen.
      return ScrollController(
        initialScrollOffset: isActiveHub ? initialScrollOffset : math.max(0.0, initialScrollOffset),
      );
    });
  }

  /// The morph state of a hub's row when [enabled], created resting at [slot];
  /// null (dropping any earlier state) when the row does not morph.
  _PosterMorph? _posterMorphForHub(String hubKey, {required bool enabled, required int slot, required bool expanded}) {
    if (!enabled) {
      final stale = _posterMorphs.remove(hubKey);
      // Its listeners unsubscribe as this build replaces their subtree.
      if (stale != null) WidgetsBinding.instance.addPostFrameCallback((_) => stale.dispose());
      return null;
    }
    return _posterMorphs.putIfAbsent(hubKey, () {
      final morph = _PosterMorph(vsync: this, position: slot.toDouble(), amount: expanded ? 1 : 0);
      morph.addListener(() => _syncPosterMorphScroll(hubKey));
      return morph;
    });
  }

  /// Stable, collision-free per-hub key. `hub.id` (the backend hub key) is only
  /// unique within one server; Discover aggregates hubs from several servers, so
  /// prefix the server id to keep two same-id hubs from sharing rail state
  /// (scroll position, metrics, card GlobalKeys, focus memory).
  String _hubKey(MediaHub hub) => '${hub.serverId ?? ''}:${hub.id}';

  GlobalKey<MediaCardState> _cardKeyFor(MediaHub hub, int itemIndex) {
    return _mediaCardKeys.putIfAbsent('${_hubKey(hub)}:$itemIndex', () => GlobalKey<MediaCardState>());
  }

  /// Global rect of the active hub's selected card, pricing one swipe step by
  /// the card's geometry instead of the rail-wide focus node's (see
  /// [LockedFocusRowNode]).
  Rect? _focusedCardRect() {
    final hub = _activeHub;
    if (hub == null || _itemAtSlot(hub, _itemIndex) == null) return null;
    final context = _cardKeyFor(hub, _itemIndex).currentContext;
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  bool _isContinueWatchingHub(MediaHub hub) => widget.isContinueWatchingHub?.call(hub) ?? false;

  bool _usesContinueWatchingAction(MediaHub hub) {
    return widget.usesContinueWatchingAction?.call(hub) ?? _isContinueWatchingHub(hub);
  }

  GlobalKey<MediaContextMenuState> _leadingMenuKeyFor(MediaHub hub) {
    return _leadingMenuKeys.putIfAbsent(_hubKey(hub), () => GlobalKey<MediaContextMenuState>());
  }

  void _showLeadingContextMenu(MediaHub hub, {Offset? position}) {
    _leadingMenuKeyFor(hub).currentState?.showContextMenu(context, position: position);
  }

  void _showContextMenuForCurrentItem() {
    final hub = _activeHub;
    if (hub == null) return;
    if (_isLeadingSlot(hub, _itemIndex)) {
      _showLeadingContextMenu(hub);
      return;
    }
    if (_itemAtSlot(hub, _itemIndex) == null) return;
    if (_isPersonHub(hub)) return;
    _cardKeyFor(hub, _itemIndex).currentState?.showContextMenu();
  }

  Future<void> _activateCurrentItem() async {
    final hub = _activeHub;
    if (hub == null) return;
    if (_isLeadingSlot(hub, _itemIndex)) {
      _showLeadingContextMenu(hub);
      return;
    }
    if (_isTrailingSlot(hub, _itemIndex)) {
      switch (_trailingFor(hub)) {
        case TvRailTrailing.error:
          widget.onRetryHub?.call(hub);
          break;
        case TvRailTrailing.loading:
          break; // no-op while the page loads
        case TvRailTrailing.viewAll:
        case TvRailTrailing.none:
          _navigateToHubDetail(hub);
      }
      return;
    }
    final item = _itemAtSlot(hub, _itemIndex);
    if (item == null) return;
    final handled = await widget.onActivateItem?.call(hub, item);
    if (handled == true) return;
    if (!mounted) return;
    await navigateToMediaItem(
      context,
      item,
      onRefresh: widget.onRefresh,
      playDirectly: _usesContinueWatchingAction(hub),
    );
  }

  void _navigateToHubDetail(MediaHub hub) {
    if (widget.onViewAll case final onViewAll?) return onViewAll(hub);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HubDetailScreen(
          hub: hub,
          loadItems: widget.loadMoreItems?.call(hub),
          isInContinueWatching: _isContinueWatchingHub(hub),
          usesContinueWatchingAction: _usesContinueWatchingAction(hub),
          onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
        ),
      ),
    );
  }

  double _scale(BuildContext context) => TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context));

  double _horizontalInset(BuildContext context) => TvBrowseRailLayout.horizontalInsetForScale(_scale(context));

  @override
  Widget build(BuildContext context) {
    if (_activeHub == null) return const SizedBox.shrink();
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
          final theme = Theme.of(context);
          final scale = _scale(context);
          final horizontalInset = _horizontalInset(context);
          final interactionExpansion = TvBrowseRailLayout.railInteractionExpansionForScale(
            scale,
          ).clamp(0.0, horizontalInset).toDouble();
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : MediaQuery.sizeOf(context).width;
          final availableWidth = (width - horizontalInset).clamp(1.0, double.infinity).toDouble();
          final railViewportWidth = (availableWidth + interactionExpansion).clamp(1.0, double.infinity).toDouble();
          final density = svc.read(SettingsService.libraryDensity);
          final episodePosterMode = svc.read(SettingsService.episodePosterMode);
          final settingFullCardLayout = svc.read(SettingsService.tvFullCardLayout);
          final fullCardLayout = widget.fullCardLayout ?? settingFullCardLayout;
          final gridSpacing = svc.read(SettingsService.gridSpacing);
          final modes = [for (final hub in widget.hubs) widget.episodePosterModeForHub?.call(hub) ?? episodePosterMode];
          final wideScales = [
            for (final hub in widget.hubs) widget.widePosterScaleForHub?.call(hub) ?? widget.widePosterScale,
          ];
          final metricsByHub = [
            for (var i = 0; i < widget.hubs.length; i++)
              TvBrowseRailLayout.metricsForHub(
                hub: widget.hubs[i],
                availableWidth: availableWidth,
                density: density,
                episodePosterMode: modes[i],
                scale: scale,
                fullCardLayout: fullCardLayout,
                gridSpacing: gridSpacing,
                tallPosterScale: widget.tallPosterScale,
                widePosterScale: wideScales[i],
                extraItemGap: widget.extraItemGap,
                hasLeading: _hasLeadingFor(widget.hubs[i]),
              ),
          ];
          final sectionHeights = [
            for (final metrics in metricsByHub)
              widget.showHubHeaders
                  ? TvBrowseRailLayout.hubSectionHeightFor(scale: scale, activeRailHeight: metrics.height)
                  : metrics.height,
          ];
          // The first hub rests at 0 under the leading inset; later hubs align
          // past it.
          final offsets = <double>[];
          var nextOffset = widget.leadingInset;
          for (final height in sectionHeights) {
            offsets.add(offsets.isEmpty ? 0 : nextOffset);
            nextOffset += height;
          }
          _sectionOffsets = offsets;

          var viewportSectionHeight = 0.0;
          for (final height in sectionHeights) {
            if (height > viewportSectionHeight) viewportSectionHeight = height;
          }
          final fixedViewportHeight = widget.viewportHeight;
          final viewportHeight =
              fixedViewportHeight ??
              TvBrowseRailLayout.viewportHeightFor(
                hubCount: widget.hubs.length,
                scale: scale,
                sectionHeight: viewportSectionHeight,
              );
          final bottomPadding = fixedViewportHeight != null
              ? 0.0
              : (viewportHeight - sectionHeights.last).clamp(0.0, double.infinity).toDouble();
          _sectionMaxScrollExtent = (nextOffset + bottomPadding - viewportHeight)
              .clamp(0.0, double.infinity)
              .toDouble();
          final totalHeight =
              TvBrowseRailLayout.railTopPaddingForScale(scale) +
              viewportHeight +
              TvBrowseRailLayout.railBottomPaddingForScale(scale);
          return Focus(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: Align(
              alignment: .bottomCenter,
              heightFactor: 1,
              child: SizedBox(
                height: totalHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _RailBleedPositioned(
                      width: width,
                      targetBleedLeft: widget.backgroundBleedLeft,
                      child: RasterizedGradient(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, theme.scaffoldBackgroundColor.withValues(alpha: 0.7)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: .fromLTRB(
                        horizontalInset,
                        TvBrowseRailLayout.railTopPaddingForScale(scale),
                        0,
                        TvBrowseRailLayout.railBottomPaddingForScale(scale),
                      ),
                      child: ClipRect(
                        clipper: _RailClipper(leftOverflow: horizontalInset, rightOverflow: 0),
                        child: ExcludeSemantics(
                          // Both axes animate during D-pad navigation. Keeping
                          // the individual headers/cards in the semantics tree
                          // makes Android recompute every moving node's bounds
                          // on every frame when an accessibility service is
                          // active. A fixed proxy below exposes the same active
                          // selection and actions without tracking that motion.
                          child: SizedBox(
                            height: viewportHeight,
                            child: _buildHubSectionList(
                              modes: modes,
                              metricsByHub: metricsByHub,
                              sectionHeights: sectionHeights,
                              scale: scale,
                              fullCardLayout: fullCardLayout,
                              leftOverflow: horizontalInset,
                              interactionExpansion: interactionExpansion,
                              railViewportWidth: railViewportWidth,
                              bottomPadding: bottomPadding,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: horizontalInset,
                      top: TvBrowseRailLayout.railTopPaddingForScale(scale),
                      right: 0,
                      height: viewportHeight,
                      child: _buildSemanticSelectionProxy(context),
                    ),
                    // Unfocused-rail dim: a scrim quad on top instead of
                    // AnimatedOpacity, which would keep a full-viewport
                    // saveLayer alive every frame (see AnimatedDimScrim).
                    // Bled under the side nav like the background gradient,
                    // so its edge doesn't seam against the nav.
                    if (widget.dimWhenUnfocused)
                      _RailBleedPositioned(
                        width: width,
                        targetBleedLeft: widget.backgroundBleedLeft,
                        child: ListenableSelector<bool>(
                          listenable: _focusModel,
                          selector: () => _focusModel.railHasFocus,
                          builder: (context, railHasFocus, _) => AnimatedDimScrim(
                            dimmed: !railHasFocus,
                            color: theme.scaffoldBackgroundColor,
                            alpha: _unfocusedRailDimAlpha,
                            // The band's top edge cuts across the spotlight
                            // artwork; ramp the dim in instead.
                            fadeTop: 36 * scale,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHubSectionList({
    required List<EpisodePosterMode> modes,
    required List<TvBrowseRailLayoutMetrics> metricsByHub,
    required List<double> sectionHeights,
    required double scale,
    required bool fullCardLayout,
    required double leftOverflow,
    required double interactionExpansion,
    required double railViewportWidth,
    required double bottomPadding,
  }) {
    return ListView.builder(
      key: const ValueKey('tv_browse_rail_vertical'),
      controller: _verticalController,
      physics: const NeverScrollableScrollPhysics(),
      // Inert on media lists (no keep-alive clients): dropping the per-child
      // wrappers shrinks build + semantics work per item.
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      clipBehavior: Clip.none,
      padding: .only(top: widget.leadingInset, bottom: bottomPadding),
      itemExtentBuilder: (index, _) => sectionHeights[index],
      itemCount: widget.hubs.length,
      itemBuilder: (context, hubIndex) {
        final hub = widget.hubs[hubIndex];
        final metrics = metricsByHub[hubIndex];
        final sectionHeight = sectionHeights[hubIndex];
        // Active-hub state is observed through _focusModel so a hub move
        // repaints only the two affected headers/artwork tints; the row content
        // below is passed through as a stable child.
        bool isActiveHub() => _focusModel.hubIndex == hubIndex;

        return SnapshotWidget(
          controller: _verticalScrollSnapshotController,
          mode: SnapshotMode.permissive,
          autoresize: true,
          child: SizedBox(
            key: _hubSectionKeys.putIfAbsent(hubIndex, () => GlobalKey()),
            height: sectionHeight,
            child: Column(
              crossAxisAlignment: .stretch,
              children: [
                if (widget.showHubHeaders)
                  ListenableSelector<bool>(
                    listenable: _focusModel,
                    selector: isActiveHub,
                    builder: (context, isActive, _) =>
                        _buildHubHeader(context, hub: hub, isActive: isActive, scale: scale),
                  ),
                _buildHubRail(
                  hub: hub,
                  hubIndex: hubIndex,
                  episodePosterMode: modes[hubIndex],
                  metrics: metrics,
                  scale: scale,
                  fullCardLayout: fullCardLayout,
                  leftOverflow: leftOverflow,
                  interactionExpansion: interactionExpansion,
                  railViewportWidth: railViewportWidth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSemanticSelectionProxy(BuildContext context) {
    if (!MediaQuery.accessibleNavigationOf(context)) return const SizedBox.shrink();

    return ListenableSelector<(int, int)>(
      listenable: _focusModel,
      selector: () => _focusModel.position,
      builder: (context, position, _) {
        final hubIndex = position.$1;
        if (hubIndex < 0 || hubIndex >= widget.hubs.length) return const SizedBox.shrink();

        final hub = widget.hubs[hubIndex];
        final itemIndex = position.$2;
        final trailing = _trailingFor(hub);
        final totalCount = _totalItemCount(hub);
        final item = _itemAtSlot(hub, itemIndex);
        final isLeading = _isLeadingSlot(hub, itemIndex);
        final isTrailing = _isTrailingSlot(hub, itemIndex);
        final actionable = item != null || isLeading || (isTrailing && trailing != TvRailTrailing.loading);

        // The enclosing Focus publishes its focused state independently. Keeping
        // that state out of this selector avoids rebuilding the label and actions
        // when focus enters or leaves the rail.
        return Semantics(
          key: const ValueKey('tv_browse_rail_semantic_proxy'),
          identifier: 'tv_browse_rail_selection',
          container: true,
          focusable: true,
          button: actionable,
          label: _semanticSelectionLabel(hub, itemIndex, trailing),
          onTap: actionable ? () => unawaited(_activateCurrentItem()) : null,
          onLongPress: (item != null || isLeading) && !_isPersonHub(hub) ? _showContextMenuForCurrentItem : null,
          onScrollLeft: itemIndex > 0 ? () => _moveItem(-1) : null,
          onScrollRight: itemIndex < totalCount - 1 ? () => _moveItem(1) : null,
          onScrollUp: hubIndex > 0 ? () => _moveHub(-1) : null,
          onScrollDown: hubIndex < widget.hubs.length - 1 ? () => _moveHub(1) : null,
          child: const SizedBox.expand(),
        );
      },
    );
  }

  String _semanticSelectionLabel(MediaHub hub, int itemIndex, TvRailTrailing trailing) {
    String selection;
    final item = _itemAtSlot(hub, itemIndex);
    if (item != null) {
      if (_isPersonHub(hub)) {
        selection = [item.displayTitle, if (item.parentTitle?.isNotEmpty == true) item.parentTitle!].join(', ');
      } else {
        selection = mediaCardSemanticLabel(item);
      }
    } else if (_isLeadingSlot(hub, itemIndex)) {
      selection = t.common.options;
    } else {
      selection = switch (trailing) {
        TvRailTrailing.loading => t.common.loading,
        TvRailTrailing.error => t.common.retry,
        TvRailTrailing.viewAll => t.common.viewAll,
        TvRailTrailing.none => '',
      };
    }

    return [hub.title, if (selection.isNotEmpty) selection].join(', ');
  }

  Widget _buildHubHeader(BuildContext context, {required MediaHub hub, required bool isActive, required double scale}) {
    final colorScheme = Theme.of(context).colorScheme;
    final showServerName = widget.showServerName && hub.serverName != null;
    final serverColor = colorScheme.primary.withValues(alpha: isActive ? 0.7 : 0.4);
    final serverStyle = Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(color: serverColor, fontSize: 15 * scale, height: 1, fontWeight: FontWeight.w700);

    return SizedBox(
      height: TvSectionHeaderTokens.height,
      child: ExcludeFocus(
        child: Align(
          alignment: .topLeft,
          child: SizedBox(
            height: TvSectionHeaderTokens.titleHeight,
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          hub.title,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TvSectionHeaderTokens.title.copyWith(color: colorScheme.onSurface),
                        ),
                      ),
                      if (showServerName) ...[
                        SizedBox(width: 8 * scale),
                        Text('•', style: serverStyle),
                        SizedBox(width: 8 * scale),
                        Flexible(
                          child: Text(hub.serverName!, maxLines: 1, overflow: .ellipsis, style: serverStyle),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_trailingFor(hub) == TvRailTrailing.viewAll) ...[
                  const SizedBox(width: TvSectionHeaderTokens.chevronGap),
                  AppIcon(
                    Symbols.chevron_right_rounded,
                    fill: 1,
                    size: TvSectionHeaderTokens.chevronSize,
                    color: colorScheme.onSurface.withValues(alpha: TvSectionHeaderTokens.chevronAlpha),
                  ),
                  SizedBox(width: 30 * scale),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHubRail({
    required MediaHub hub,
    required int hubIndex,
    required EpisodePosterMode episodePosterMode,
    required TvBrowseRailLayoutMetrics metrics,
    required double scale,
    required bool fullCardLayout,
    required double leftOverflow,
    required double interactionExpansion,
    required double railViewportWidth,
  }) {
    final isActiveHub = hubIndex == _hubIndex;
    final hasTrailing = _hasTrailingFor(hub);
    final totalCount = _totalItemCount(hub);
    final inactiveIndex = widget.focusMemory.getForHubOnly(_hubKey(hub), totalCount, fallback: _defaultSlotFor(hub));
    final focusedIndex = isActiveHub ? _itemIndex : inactiveIndex;
    final hubKey = _hubKey(hub);
    final morph = _posterMorphForHub(
      hubKey,
      enabled: widget.expandFocusedPosters && TvBrowseRailLayout.usesPosterMorph(hub, metrics),
      slot: focusedIndex,
      expanded: isActiveHub && _focusNode.hasFocus,
    );
    final scrollController = _scrollControllerForHub(
      hub,
      metrics,
      railViewportWidth,
      focusedIndex,
      hasTrailing: hasTrailing,
      isActiveHub: isActiveHub,
      posterMorph: morph != null,
    );
    _metricsByHub[hubKey] = metrics;

    final rail = _buildHubRailList(
      hub: hub,
      hubIndex: hubIndex,
      episodePosterMode: episodePosterMode,
      metrics: metrics,
      scale: scale,
      fullCardLayout: fullCardLayout,
      scrollController: scrollController,
      totalCount: totalCount,
      morph: morph,
      railViewportWidth: railViewportWidth,
    );
    final rightOverflow = metrics.railEdgePadding + metrics.cardWidth + metrics.itemGap;

    return Transform.translate(
      offset: Offset(-interactionExpansion, 0),
      child: SizedBox(
        width: railViewportWidth,
        height: metrics.height,
        child: ClipRect(
          clipper: _RailClipper(
            leftOverflow: leftOverflow,
            rightOverflow: rightOverflow,
            verticalOverflow: metrics.focusExtra,
          ),
          child: rail,
        ),
      ),
    );
  }

  Widget _buildHubRailList({
    required MediaHub hub,
    required int hubIndex,
    required EpisodePosterMode episodePosterMode,
    required TvBrowseRailLayoutMetrics metrics,
    required double scale,
    required bool fullCardLayout,
    required ScrollController scrollController,
    required int totalCount,
    _PosterMorph? morph,
    double railViewportWidth = 0,
  }) {
    final leadingCount = _leadingCountFor(hub);
    final itemDelegate = SliverChildBuilderDelegate(
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      childCount: totalCount - leadingCount,
      (context, childIndex) => _buildRailSlot(
        context,
        hub: hub,
        hubIndex: hubIndex,
        itemIndex: childIndex + leadingCount,
        episodePosterMode: episodePosterMode,
        metrics: metrics,
        scale: scale,
        fullCardLayout: fullCardLayout,
        morph: morph,
      ),
    );
    const centerSliverKey = ValueKey('tv_browse_rail_row_center');
    return HorizontalScrollWithArrows(
      controller: scrollController,
      builder: (scrollController) => CustomScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        // The row anchors at its first media item. The leading options card
        // occupies the negative-offset region before the anchor, so at rest it
        // sits off-screen and never pushes the hub's content right; focusing
        // it (or dragging) scrolls it into view.
        center: centerSliverKey,
        slivers: [
          if (leadingCount > 0)
            SliverPadding(
              padding: .fromLTRB(metrics.railEdgePadding, 2 * scale, 0, 6 * scale),
              sliver: SliverToBoxAdapter(
                child: Align(
                  alignment: .topLeft,
                  child: ListenableSelector<bool>(
                    listenable: _focusModel,
                    selector: () => _focusModel.railHasFocus && _focusModel.position == (hubIndex, 0),
                    builder: (context, isFocused, _) =>
                        _buildLeadingSlot(context, hub, hubIndex, metrics: metrics, isFocused: isFocused, scale: scale),
                  ),
                ),
              ),
            ),
          SliverPadding(
            key: centerSliverKey,
            // A morphing row pins even its last card at the start, so it
            // runs a viewport on past it.
            padding: .fromLTRB(
              metrics.railEdgePadding,
              2 * scale,
              morph == null ? metrics.railEdgePadding : railViewportWidth,
              6 * scale,
            ),
            sliver: morph == null
                ? SliverFixedExtentList(
                    // A fixed extent keeps all sliver offset and child-index math O(1).
                    itemExtent: TvBrowseRailLayout.itemExtentForIndex(index: 0, metrics: metrics),
                    delegate: itemDelegate,
                  )
                // Card widths change as they morph.
                : SliverList(delegate: itemDelegate),
          ),
        ],
      ),
    );
  }

  Widget _buildRailSlot(
    BuildContext context, {
    required MediaHub hub,
    required int hubIndex,
    required int itemIndex,
    required EpisodePosterMode episodePosterMode,
    required TvBrowseRailLayoutMetrics metrics,
    required double scale,
    required bool fullCardLayout,
    required _PosterMorph? morph,
  }) {
    // Focus is observed through _focusModel so a d-pad move or a rail focus
    // flip rebuilds only the cheap wrapper of the two affected cards; the
    // card content below is passed through as a stable child.
    bool isItemFocused() => _focusModel.railHasFocus && _focusModel.position == (hubIndex, itemIndex);

    if (_isTrailingSlot(hub, itemIndex)) {
      return Padding(
        padding: .only(right: metrics.itemGap),
        child: Align(
          alignment: .topLeft,
          child: ListenableSelector<bool>(
            listenable: _focusModel,
            selector: isItemFocused,
            builder: (context, isFocused, _) => _buildTrailingSlot(
              context,
              hub,
              hubIndex,
              itemIndex,
              metrics: metrics,
              isFocused: isFocused,
              scale: scale,
            ),
          ),
        ),
      );
    }

    final item = hub.items[itemIndex - _leadingCountFor(hub)];
    final morphs = morph != null;
    Widget card = _buildHubCard(
      context,
      hub: hub,
      hubIndex: hubIndex,
      item: item,
      itemIndex: itemIndex,
      episodePosterMode: episodePosterMode,
      metrics: metrics,
      scale: scale,
      fullCardLayout: fullCardLayout || morphs,
    );
    if (morph != null) {
      // Only the slot's own expansion rebuilds it, so a move repaints the
      // two cards trading places; the poster card passes through untouched.
      card = ListenableSelector<(({double expansion, double artwork, double logo}), double, bool)>(
        listenable: morph,
        selector: () => (morph.appearanceOf(itemIndex), morph.visibilityOf(itemIndex), morph.isNearTarget(itemIndex)),
        builder: (context, state, poster) => _PosterMorphCard(
          item: item,
          expansion: state.$1.expansion,
          artwork: state.$1.artwork,
          logo: state.$1.logo,
          visibility: state.$2,
          prefetchBackdrop: state.$3,
          metrics: metrics,
          scale: scale,
          episodePosterMode: episodePosterMode,
          poster: poster!,
        ),
        child: card,
      );
    }

    // Record: (focused, glow shown). The glow is additionally gated on the
    // vertical scroll being idle — it paints in the root overlay, unclipped
    // by the rail's viewport, so on UP moves it would flash over the
    // spotlight while the target row is still offscreen. The selection
    // collapses to (false, false) for unfocused cards, so the flag flip
    // repaints only the focused card.
    final focusableCard = ListenableSelector<(bool, bool)>(
      listenable: _focusModel,
      selector: () {
        final isFocused = isItemFocused();
        return (isFocused, isFocused && !_focusModel.verticalScrollActive);
      },
      builder: (context, focus, child) => FocusBuilders.buildLockedFocusWrapper(
        context: context,
        isFocused: focus.$1,
        borderRadius: tokens(context).radiusSm,
        // A morphing card grows instead of scaling up.
        focusScale: morphs ? 1.0 : (fullCardLayout ? TvBrowseRailLayout.fullCardFocusScale : FocusTheme.focusScale),
        useFocusGlow: fullCardLayout && !morphs,
        showGlow: focus.$2,
        // The card draws the border itself (poster rect for standard cards,
        // whole card when full-bleed).
        delegateFocusBorder: true,
        glowSize: fullCardLayout && !morphs ? Size(metrics.cardWidth, metrics.posterHeight) : null,
        onTap: () {
          _selectHubItem(hub, hubIndex, itemIndex);
          unawaited(_activateCurrentItem());
        },
        onLongPress: metrics.isPersonHub
            ? null
            : () {
                _selectHubItem(hub, hubIndex, itemIndex);
                _cardKeyFor(hub, itemIndex).currentState?.showContextMenu();
              },
        child: child!,
      ),
      child: card,
    );

    return Padding(
      padding: .only(right: metrics.itemGap),
      child: MouseRegion(
        onEnter: (_) => _setHoveredItem(hub, itemIndex),
        child: Align(alignment: .topLeft, child: focusableCard),
      ),
    );
  }

  Widget _buildHubCard(
    BuildContext context, {
    required MediaHub hub,
    required int hubIndex,
    required MediaItem item,
    required int itemIndex,
    required EpisodePosterMode episodePosterMode,
    required TvBrowseRailLayoutMetrics metrics,
    required double scale,
    required bool fullCardLayout,
  }) {
    final artworkDim = _artworkDimForHub(context, hubIndex);
    return metrics.isPersonHub
        ? MergeSemantics(
            child: _buildPersonCard(
              context,
              item,
              cardWidth: metrics.cardWidth,
              imageSize: metrics.posterHeight,
              scale: scale,
              fullCardLayout: fullCardLayout,
              artworkDim: artworkDim,
            ),
          )
        : MediaCard(
            key: _cardKeyFor(hub, itemIndex),
            item: item,
            width: metrics.cardWidth,
            height: metrics.posterHeight,
            onRefresh: widget.onRefresh,
            onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
            viewModeOverride: ViewMode.grid,
            fullBleedImage: fullCardLayout,
            artworkDim: artworkDim,
            isInContinueWatching: _isContinueWatchingHub(hub),
            usesContinueWatchingAction: _usesContinueWatchingAction(hub),
            mixedHubContext: metrics.isMixedHub,
            episodePosterModeOverride: episodePosterMode,
            showTitleImplied: widget.showTitleImpliedForHub?.call(hub) ?? false,
            showTimeLeft: widget.showTimeLeft,
          );
  }

  Widget _buildPersonCard(
    BuildContext context,
    MediaItem item, {
    required double cardWidth,
    required double imageSize,
    required double scale,
    required bool fullCardLayout,
    required Animation<double>? artworkDim,
  }) {
    final theme = Theme.of(context);
    final characterName = item.parentTitle;

    if (widget.circularPersonCards) {
      return SizedBox(
        width: cardWidth,
        child: Padding(
          padding: .fromLTRB(3 * scale, 3 * scale, 3 * scale, scale),
          child: Column(
            mainAxisSize: .min,
            children: [
              PersonAvatar(
                name: item.displayTitle,
                imagePath: item.thumbPath,
                serverId: serverIdOrNull(item.serverId),
                size: imageSize,
              ),
              SizedBox(height: 8 * scale),
              Text(
                item.displayTitle,
                maxLines: 1,
                overflow: .ellipsis,
                textAlign: .center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens(context).text,
                  fontSize: 13 * scale,
                  height: 1.1,
                  fontWeight: .w600,
                ),
              ),
              if (characterName != null && characterName.isNotEmpty) ...[
                SizedBox(height: 2 * scale),
                Text(
                  characterName,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: tokens(context).textMuted,
                    fontSize: 11 * scale,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (fullCardLayout) {
      return SizedBox(
        width: cardWidth,
        height: imageSize,
        child: CardFocusBorder(
          borderRadius: tokens(context).radiusSm,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(tokens(context).radiusSm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                OptimizedMediaImage(
                  client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                  imagePath: item.thumbPath,
                  width: cardWidth,
                  height: imageSize,
                  fit: BoxFit.cover,
                  imageType: ImageType.square,
                  fallbackIcon: Symbols.person_rounded,
                  artworkDim: artworkDim,
                ),
                RasterizedGradient(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.78)],
                    stops: const [0.45, 1.0],
                  ),
                ),
                Positioned(
                  left: 10 * scale,
                  right: 10 * scale,
                  bottom: 9 * scale,
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: [
                      Text(
                        item.displayTitle,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 13 * scale, height: 1.1, fontWeight: .w800),
                      ),
                      if (characterName != null && characterName.isNotEmpty) ...[
                        SizedBox(height: 2 * scale),
                        Text(
                          characterName,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: 11 * scale,
                            height: 1.1,
                            fontWeight: .w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: cardWidth,
      child: Padding(
        padding: .fromLTRB(3 * scale, 3 * scale, 3 * scale, scale),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            CardFocusBorder(
              borderRadius: tokens(context).radiusSm,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                child: OptimizedMediaImage(
                  client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                  imagePath: item.thumbPath,
                  width: imageSize,
                  height: imageSize,
                  fit: BoxFit.cover,
                  imageType: ImageType.square,
                  fallbackIcon: Symbols.person_rounded,
                  artworkDim: artworkDim,
                ),
              ),
            ),
            SizedBox(height: 6 * scale),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens(context).text,
                fontSize: 13 * scale,
                height: 1.1,
                fontWeight: .w700,
              ),
            ),
            if (characterName != null && characterName.isNotEmpty) ...[
              SizedBox(height: 2 * scale),
              Text(
                characterName,
                maxLines: 1,
                overflow: .ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens(context).textMuted,
                  fontSize: 11 * scale,
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Resolve the trailing-slot state for [hub], defaulting to the legacy
  /// "[MediaHub.more] → View All" behavior when no resolver was supplied.
  TvRailTrailing _trailingFor(MediaHub hub) =>
      widget.trailingForHub?.call(hub) ?? (hub.more ? TvRailTrailing.viewAll : TvRailTrailing.none);

  /// The full-size options card occupying a hub's leading slot. Opens the
  /// context menu for the hub's leading item (e.g. the season an episode hub
  /// shows). Wrapped in the [MediaContextMenu] so keyboard/D-pad activation
  /// and pointer taps share one menu instance.
  Widget _buildLeadingSlot(
    BuildContext context,
    MediaHub hub,
    int hubIndex, {
    required TvBrowseRailLayoutMetrics metrics,
    required bool isFocused,
    required double scale,
  }) {
    final leadingItem = _leadingItemFor(hub);
    if (leadingItem == null) return const SizedBox.shrink();
    Offset? tapPosition;

    return MediaContextMenu(
      key: _leadingMenuKeyFor(hub),
      item: leadingItem,
      onRefresh: widget.onRefresh,
      child: ClickableCursor(
        child: GestureDetector(
          onTap: () {
            _selectHubItem(hub, hubIndex, 0);
            _showLeadingContextMenu(hub);
          },
          onSecondaryTapDown: (details) => tapPosition = details.globalPosition,
          onSecondaryTap: () {
            _selectHubItem(hub, hubIndex, 0);
            _showLeadingContextMenu(hub, position: tapPosition);
          },
          child: _buildActionCard(
            context,
            metrics: metrics,
            isFocused: isFocused,
            scale: scale,
            icon: Symbols.more_horiz_rounded,
            label: t.common.options,
          ),
        ),
      ),
    );
  }

  Widget _buildTrailingSlot(
    BuildContext context,
    MediaHub hub,
    int hubIndex,
    int itemIndex, {
    required TvBrowseRailLayoutMetrics metrics,
    required bool isFocused,
    required double scale,
  }) {
    switch (_trailingFor(hub)) {
      case TvRailTrailing.loading:
        return _buildActionCard(context, metrics: metrics, isFocused: isFocused, scale: scale, spinner: true);
      case TvRailTrailing.error:
        return ClickableCursor(
          child: GestureDetector(
            onTap: () {
              _selectHubItem(hub, hubIndex, itemIndex);
              widget.onRetryHub?.call(hub);
            },
            child: _buildActionCard(
              context,
              metrics: metrics,
              isFocused: isFocused,
              scale: scale,
              icon: Symbols.refresh_rounded,
              label: t.common.retry,
            ),
          ),
        );
      case TvRailTrailing.viewAll:
        return ClickableCursor(
          child: GestureDetector(
            onTap: () {
              _selectHubItem(hub, hubIndex, itemIndex);
              _navigateToHubDetail(hub);
            },
            child: _buildActionCard(
              context,
              metrics: metrics,
              isFocused: isFocused,
              scale: scale,
              icon: Symbols.arrow_forward_rounded,
              label: t.common.viewAll,
            ),
          ),
        );
      case TvRailTrailing.none:
        return const SizedBox.shrink();
    }
  }

  /// Shared full-size action card used by the leading options slot and the
  /// trailing View All / retry / loading slots: it matches the hub's card
  /// footprint so the row reads as cards end-to-end instead of mixing in
  /// compact pills.
  Widget _buildActionCard(
    BuildContext context, {
    required TvBrowseRailLayoutMetrics metrics,
    required bool isFocused,
    required double scale,
    IconData? icon,
    String? label,
    bool spinner = false,
  }) {
    final theme = Theme.of(context);
    final duration = FocusTheme.getAnimationDuration(context);
    final foreground = isFocused ? theme.colorScheme.primary : theme.colorScheme.onSurface.withValues(alpha: 0.78);
    final background = isFocused
        ? theme.colorScheme.primary.withValues(alpha: 0.2)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: spinner ? 0.18 : 0.42);

    return AnimatedScale(
      scale: isFocused ? FocusTheme.focusScale : 1.0,
      duration: duration,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: duration,
        curve: Curves.easeOutCubic,
        width: metrics.cardWidth,
        height: metrics.posterHeight,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          border: Border.all(
            color: isFocused ? theme.colorScheme.primary : Colors.transparent,
            width: FocusTheme.focusBorderWidth,
          ),
          boxShadow: isFocused
              ? [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 18, spreadRadius: 1)]
              : null,
        ),
        child: spinner
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
                ),
              )
            : Center(
                child: Column(
                  mainAxisSize: .min,
                  children: [
                    AppIcon(icon!, fill: 1, size: (26 * scale).clamp(22, 32).toDouble(), color: foreground),
                    SizedBox(height: (6 * scale).clamp(4, 9).toDouble()),
                    Padding(
                      padding: .symmetric(horizontal: (10 * scale).clamp(8, 14).toDouble()),
                      child: Text(
                        label!,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontSize: (13 * scale).clamp(12, 16).toDouble(),
                          fontWeight: .w800,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Positions [child] over the rail's full band, bled left under the side
/// navigation (animated with the nav's expansion). Full-width layers — the
/// background gradient and the unfocused-rail dim — must live here: anything
/// clipped to the rail's own footprint terminates in a visible vertical seam
/// at the nav edge, since the backdrop artwork continues behind the nav.
class _RailBleedPositioned extends StatelessWidget {
  final double width;

  /// Explicit target; when null the value comes from [MainScreenFocusScope]
  /// (offset aspect) so sidebar flips rebuild only this widget, not the rail.
  final double? targetBleedLeft;
  final Widget child;

  const _RailBleedPositioned({required this.width, required this.targetBleedLeft, required this.child});

  @override
  Widget build(BuildContext context) {
    final target = targetBleedLeft ?? MainScreenFocusScope.sideNavigationBleedOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: target),
      duration: FocusTheme.getAnimationDuration(context),
      curve: Curves.easeOutCubic,
      child: child,
      builder: (context, bleedLeft, child) {
        final backgroundWidth = math.max(width + bleedLeft, MediaQuery.sizeOf(context).width);
        return Positioned(top: 0, bottom: 0, left: -bleedLeft, width: backgroundWidth, child: child!);
      },
    );
  }
}

class _RailClipper extends CustomClipper<Rect> {
  final double leftOverflow;
  final double rightOverflow;
  final double topOverflow;
  final double bottomOverflow;

  const _RailClipper({
    this.leftOverflow = 0,
    required this.rightOverflow,
    double verticalOverflow = 0,
    double? topOverflow,
    double? bottomOverflow,
  }) : topOverflow = topOverflow ?? verticalOverflow,
       bottomOverflow = bottomOverflow ?? verticalOverflow;

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-leftOverflow, -topOverflow, size.width + rightOverflow, size.height + bottomOverflow);

  @override
  bool shouldReclip(covariant _RailClipper oldClipper) {
    return oldClipper.leftOverflow != leftOverflow ||
        oldClipper.rightOverflow != rightOverflow ||
        oldClipper.topOverflow != topOverflow ||
        oldClipper.bottomOverflow != bottomOverflow;
  }
}

/// Hot rail focus state — (hubIndex, itemIndex) position and whether the rail
/// itself holds focus — observed through [ListenableSelector]s so d-pad moves
/// and rail focus flips repaint only the affected cards/headers/dim effects
/// instead of setState-rebuilding every visible row (expensive on low-end
/// TVs). `notify: false` covers build-phase syncs (initState/didUpdateWidget),
/// where notifying would call setState on descendants mid-build and the
/// enclosing rebuild refreshes the selectors anyway.
class _RailFocusModel extends ChangeNotifier {
  (int, int) _position = (0, 0);
  bool _railHasFocus = false;
  bool _verticalScrollActive = false;

  (int, int) get position => _position;
  int get hubIndex => _position.$1;
  bool get railHasFocus => _railHasFocus;

  /// Whether the rail is animating a hub row into view vertically. Gates only
  /// the focus glow (root-overlay paint, unclipped by the vertical viewport);
  /// border and scale chrome stay tied to the position alone.
  bool get verticalScrollActive => _verticalScrollActive;

  set verticalScrollActive(bool value) {
    if (value == _verticalScrollActive) return;
    _verticalScrollActive = value;
    notifyListeners();
  }

  void set(int hubIndex, int itemIndex, {bool notify = true}) {
    final next = (hubIndex, itemIndex);
    if (next == _position) return;
    _position = next;
    if (notify) notifyListeners();
  }

  void setRailFocus(bool value) {
    if (value == _railHasFocus) return;
    _railHasFocus = value;
    notifyListeners();
  }
}

/// A card in a poster-morph row at [expansion] (0 a poster, 1 the focused
/// wide card). The poster [MediaCard] keeps its slot underneath, holding the
/// card's key, menu and watched badges; while expanded, a wider layer over
/// it cross-fades the poster into the backdrop with the logo on top. Each
/// image is decoded once at its final size and scaled to the frame, so the
/// morph never requests new sizes.
class _PosterMorphCard extends StatelessWidget {
  final MediaItem item;
  final double expansion;

  /// How far the backdrop has replaced the poster, and the logo's (and
  /// caption's) opacity; see [_PosterMorph.appearanceOf].
  final double artwork;
  final double logo;

  /// Fades a card out as it slides past the pinned slot (1 at or after it).
  final double visibility;

  /// Loads the backdrop ahead of the card expanding, so it never opens on an
  /// empty frame.
  final bool prefetchBackdrop;
  final TvBrowseRailLayoutMetrics metrics;
  final double scale;
  final EpisodePosterMode episodePosterMode;
  final Widget poster;

  const _PosterMorphCard({
    required this.item,
    required this.expansion,
    required this.artwork,
    required this.logo,
    required this.visibility,
    required this.prefetchBackdrop,
    required this.metrics,
    required this.scale,
    required this.episodePosterMode,
    required this.poster,
  });

  @override
  Widget build(BuildContext context) {
    final extra = TvBrowseRailLayout.posterMorphExtraWidth(metrics);
    final width = metrics.cardWidth + extra * expansion;
    final height = metrics.posterHeight;
    // Image-only cards would touch on a tight grid gap: inset each side so
    // the row keeps a visible gutter between cards.
    final inset = math.max(metrics.cardWidth - metrics.posterWidth, 10 * scale - metrics.itemGap).clamp(0.0, 24.0) / 2;
    final card = SizedBox(
      width: width,
      height: metrics.containerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: inset, top: 0, width: metrics.cardWidth - 2 * inset, height: height, child: poster),
          if (expansion == 0 && prefetchBackdrop)
            Offstage(
              child: Column(
                children: [
                  _backdropImage(context, metrics.cardWidth + extra),
                  _logo(context, (metrics.cardWidth + extra) * 0.5, height * 0.3),
                ],
              ),
            ),
          if (expansion > 0) ...[
            Positioned(
              left: inset,
              top: 0,
              width: width - 2 * inset,
              height: height,
              child: IgnorePointer(child: _buildExpandedArtwork(context, fullWidth: metrics.cardWidth + extra)),
            ),
            if (metrics.containerHeight - height >= 16 * scale)
              Positioned(
                left: inset + 2 * scale,
                right: 0,
                top: height + 8 * scale,
                child: Opacity(opacity: logo, child: _buildCaption(context)),
              ),
          ],
        ],
      ),
    );
    if (visibility >= 1) return card;
    return Opacity(opacity: visibility, child: card);
  }

  Widget _buildExpandedArtwork(BuildContext context, {required double fullWidth}) {
    final theme = Theme.of(context);
    final radius = tokens(context).radiusSm;
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final height = metrics.posterHeight;
    final backdrop = item.heroArtCandidates(containerAspectRatio: 16 / 9).firstOrNull;
    final posterPath = item.posterThumb(mode: episodePosterMode) ?? item.thumbPath;
    final logoWidth = fullWidth * 0.5;
    final logoHeight = height * 0.3;

    // Decoded at [w] × [h] and scaled to cover whatever frame the morph is at.
    Widget cover(String? path, double w, double h, ImageType type) => FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: w,
        height: h,
        child: OptimizedMediaImage(
          client: client,
          imagePath: path,
          width: w,
          height: h,
          fit: BoxFit.cover,
          imageType: type,
          fadeInDuration: Duration.zero,
        ),
      ),
    );

    return CardFocusBorder(
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
            // Stays under the backdrop until that has loaded.
            cover(posterPath, metrics.cardWidth, height, ImageType.poster),
            if (backdrop != null && artwork > 0)
              Opacity(
                opacity: artwork,
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: _backdropImage(context, fullWidth),
                ),
              ),
            Opacity(
              opacity: logo,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Darkens the corner under the logo, as Netflix does.
                  RasterizedGradient(
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
                      stops: const [0, 0.55],
                    ),
                  ),
                  Positioned(
                    left: 14 * scale,
                    bottom: 12 * scale,
                    // Sized for the full-width card so the logo never
                    // reflows while the card grows; the clip trims it.
                    width: logoWidth,
                    height: logoHeight,
                    child: _logo(context, logoWidth, logoHeight),
                  ),
                ],
              ),
            ),
            if (item.hasActiveProgress)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: MediaProgressBar(
                  viewOffset: item.viewOffsetMs!,
                  duration: item.durationMs!,
                  minHeight: 4 * scale,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The backdrop decoded at the fully expanded card's size, whether it is
  /// shown or only being loaded ahead.
  Widget _backdropImage(BuildContext context, double width) {
    final height = metrics.posterHeight;
    return SizedBox(
      width: width,
      height: height,
      child: OptimizedMediaImage(
        client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
        imagePath: item.heroArtCandidates(containerAspectRatio: 16 / 9).firstOrNull,
        width: width,
        height: height,
        fit: BoxFit.cover,
        imageType: ImageType.art,
        fadeInDuration: Duration.zero,
      ),
    );
  }

  /// The clear logo (or the title) in its slot of [width] × [height].
  Widget _logo(BuildContext context, double width, double height) => ClearLogoImage(
    client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
    logoPath: item.clearLogoPath,
    width: width,
    height: height,
    fallbackWidth: width,
    alignment: Alignment.bottomLeft,
    fadeInDuration: Duration.zero,
    fallbackBuilder: (context) => Align(
      alignment: Alignment.bottomLeft,
      child: Text(
        _title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white,
          fontSize: 22 * scale,
          height: 1.1,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black54, blurRadius: 8)],
        ),
      ),
    ),
  );

  String get _title => item.isEpisode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle;

  /// The title and what kind of title it is, under the wide card.
  Widget _buildCaption(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final details = [
      if (item.isEpisode && item.parentIndex != null && item.index != null) 'S${item.parentIndex} E${item.index}',
      if (!item.isEpisode && item.year != null) '${item.year}',
      if (item.durationMs != null && item.isMovie) formatDurationTextual(item.durationMs!),
    ].join('  •  ');
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: _title,
            style: TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface),
          ),
          if (details.isNotEmpty)
            TextSpan(
              text: '  •  $details',
              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7)),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 14 * scale, height: 1.2),
    );
  }
}

/// The animated state of a poster-morph row: which slot is pinned at the
/// row's start ([position], fractional mid-move) and how far its card is
/// expanded ([amount], 0 resting to 1 focused).
///
/// A slot's expansion is `amount * (1 - |slot - position|)`, so while focus
/// moves one step the outgoing card shrinks as the incoming one grows, and
/// every slot before the pinned one stays poster-wide. That makes the row's
/// scroll offset exactly `position * slotExtent` on every frame: the pinned
/// card holds its place at the start while the outgoing one slides out.
class _PosterMorph extends ChangeNotifier {
  _PosterMorph({required TickerProvider vsync, required double position, required double amount})
    : _position = position,
      _amount = amount,
      _fromPosition = position,
      _toPosition = position,
      _fromAmount = amount,
      _toAmount = amount {
    _controller = AnimationController(vsync: vsync, duration: _duration)..addListener(_tick);
  }

  /// A move from rest: focus (the border) lands on the next card at once and
  /// the row holds still for the first fifth, then the outgoing card shrinks
  /// out as the incoming one grows in, easing in and out.
  static const _fromRestDuration = Duration(milliseconds: 340);
  static const _fromRestCurve = Interval(0.2, 1, curve: Curves.easeInOutCubic);

  /// A move that lands mid-glide (a held D-pad): no hold, and no ease-in, so
  /// the row carries on at speed instead of stalling at each step.
  static const _retargetDuration = Duration(milliseconds: 260);
  static const _retargetCurve = Curves.easeOutCubic;

  /// Moves further than this many slots jump instead of sweeping the row.
  static const _maxAnimatedDistance = 3.0;

  static Duration get _duration => DevicePerformance.reducedDuration(_fromRestDuration);

  Curve _curve = _fromRestCurve;

  late final AnimationController _controller;
  double _position;
  double _amount;
  double _fromPosition;
  double _toPosition;
  double _fromAmount;
  double _toAmount;

  double get position => _position;
  double get targetPosition => _toPosition;

  /// Slots before the pinned one fade out as they slide past it.
  double visibilityOf(int slot) => slot >= _position ? 1 : (1 - (_position - slot)).clamp(0.0, 1.0);

  /// Slots within reach of the next few moves, whose backdrops load ahead.
  bool isNearTarget(int slot) => _toAmount > 0 && (slot - _toPosition).abs() <= 2;

  double expansionOf(int slot) {
    final distance = (slot - _position).abs();
    return distance >= 1 ? 0 : _amount * (1 - distance);
  }

  double _targetExpansionOf(int slot) {
    final distance = (slot - _toPosition).abs();
    return distance >= 1 ? 0 : _toAmount * (1 - distance);
  }

  /// How the slot's card is drawn: its width ([expansion]), how far the
  /// backdrop has replaced the poster ([artwork]) and the logo's opacity.
  ///
  /// As in the reference, a growing card keeps its poster (cropped to the
  /// widening frame) until it is mostly open, then fades to the backdrop, and
  /// its logo comes last. A shrinking card drops its logo at once and keeps
  /// its backdrop until it is nearly a poster again.
  ({double expansion, double artwork, double logo}) appearanceOf(int slot) {
    final expansion = expansionOf(slot);
    if (expansion <= 0) return (expansion: 0, artwork: 0, logo: 0);
    final target = _targetExpansionOf(slot);
    if (target >= expansion - 1e-6 && target > 0) {
      return (
        expansion: expansion,
        artwork: ((expansion - 0.55) / 0.4).clamp(0.0, 1.0),
        logo: ((expansion - 0.85) / 0.15).clamp(0.0, 1.0),
      );
    }
    return (expansion: expansion, artwork: (expansion / 0.35).clamp(0.0, 1.0), logo: 0);
  }

  void retarget({required double position, required double amount, required bool animate}) {
    if (position == _toPosition && amount == _toAmount) return;
    final snapPosition = !animate || (position - _position).abs() > _maxAnimatedDistance;
    _fromPosition = snapPosition ? position : _position;
    _fromAmount = animate ? _amount : amount;
    _toPosition = position;
    _toAmount = amount;
    final midGlide = _controller.isAnimating;
    if (_duration == Duration.zero || (_fromPosition == _toPosition && _fromAmount == _toAmount)) {
      _controller.stop();
      _position = position;
      _amount = amount;
      notifyListeners();
      return;
    }
    // Hold-repeat retargets from wherever the last step got to, so a held
    // D-pad glides continuously instead of restarting each step.
    _curve = midGlide ? _retargetCurve : _fromRestCurve;
    _controller.duration = DevicePerformance.reducedDuration(midGlide ? _retargetDuration : _fromRestDuration);
    unawaited(_controller.forward(from: 0));
  }

  void _tick() {
    final t = _curve.transform(_controller.value);
    _position = _fromPosition + (_toPosition - _fromPosition) * t;
    _amount = _fromAmount + (_toAmount - _fromAmount) * t;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// Paint-time dim animation shared by every artwork image in one hub.
///
/// A single controller avoids one ticker per card while each image repaints
/// through its own render object, without a row-sized overlay or save layer.
class _HubArtworkDim extends Animation<double> {
  _HubArtworkDim(this._focusModel, this._hubIndex, {required TickerProvider vsync, required Duration duration})
    : _duration = duration {
    _target = _resolveTarget();
    _controller = AnimationController(vsync: vsync, duration: duration, value: _target);
    _focusModel.addListener(_handleFocusChange);
  }

  final _RailFocusModel _focusModel;
  final int _hubIndex;
  final Duration _duration;
  late final AnimationController _controller;
  late double _target;

  double _resolveTarget() => _focusModel.railHasFocus && _focusModel.hubIndex != _hubIndex ? 1 : 0;

  void _handleFocusChange() {
    final next = _resolveTarget();
    if (next == _target) return;
    _target = next;
    if (_duration == Duration.zero) {
      _controller.value = next;
    } else {
      unawaited(_controller.animateTo(next, duration: _duration, curve: Curves.easeOutCubic));
    }
  }

  @override
  double get value => _controller.value * _inactiveArtworkDimAlpha;

  @override
  AnimationStatus get status => _controller.status;

  @override
  void addListener(VoidCallback listener) => _controller.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _controller.removeListener(listener);

  @override
  void addStatusListener(AnimationStatusListener listener) => _controller.addStatusListener(listener);

  @override
  void removeStatusListener(AnimationStatusListener listener) => _controller.removeStatusListener(listener);

  void dispose() {
    _focusModel.removeListener(_handleFocusChange);
    _controller.dispose();
  }
}
