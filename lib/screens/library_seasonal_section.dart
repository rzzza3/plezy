import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../focus/focus_theme.dart';
import '../focus/key_event_utils.dart';
import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/optimized_media_image.dart';
import '../widgets/tv_browse_rail.dart';

/// The Library tab's Seasonal Picks: the Silo home section of type
/// `seasonal_themed` (this season's "Halloween Favorites", say), laid out in
/// pages of one large poster and a two-row grid of smaller ones. The section
/// is one screen tall and each page one screen wide, so revealing the section
/// or turning a page fills the screen. A small caps label over the title names
/// the focused card. [LibraryForYouSection] reuses the layout for its row.
class LibrarySeasonalSection extends StatefulWidget {
  /// Silo's section type for the seasonal row.
  static const sectionType = 'seasonal_themed';

  final MediaHub hub;

  /// UP from the top row.
  final VoidCallback onNavigateUp;

  /// LEFT from the first card, and BACK.
  final VoidCallback onNavigateToSidebar;

  /// DOWN from the bottom row (or the large card).
  final VoidCallback? onNavigateDown;

  /// Focus moved into the section (TV scrolls the page to it).
  final VoidCallback? onFocusEntered;

  const LibrarySeasonalSection({
    super.key,
    required this.hub,
    required this.onNavigateUp,
    required this.onNavigateToSidebar,
    this.onNavigateDown,
    this.onFocusEntered,
  });

  @override
  State<LibrarySeasonalSection> createState() => LibrarySeasonalSectionState();
}

class LibrarySeasonalSectionState extends State<LibrarySeasonalSection> {
  /// Room around the cards for the focused card's scale and ring.
  static const _focusSlack = 8.0;

  final _scroll = ScrollController();
  List<FocusNode> _nodes = [];
  int _focused = 0;

  /// Small-card columns per page, as many as the screen width fits; set by
  /// the last layout.
  int _columns = 4;
  int get _perPage => 1 + _columns * 2;

  /// One page's width: a page scroll moves exactly one screen.
  double _pageStride = 0;

  List<MediaItem> get _items => widget.hub.items;

  @override
  void initState() {
    super.initState();
    _syncNodes();
  }

  @override
  void didUpdateWidget(LibrarySeasonalSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hub.items.length != _items.length) _syncNodes();
  }

  @override
  void dispose() {
    for (final node in _nodes) {
      node.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _syncNodes() {
    final length = _items.length;
    if (_nodes.length > length) {
      for (final node in _nodes.sublist(length)) {
        node.dispose();
      }
      _nodes = _nodes.sublist(0, length);
    } else {
      _nodes = [..._nodes, for (var i = _nodes.length; i < length; i++) FocusNode(debugLabel: 'seasonal_$i')];
    }
    _focused = _focused.clamp(0, math.max(0, length - 1));
  }

  /// Focus the card last focused here, else the first.
  void requestFocus() {
    if (_nodes.isEmpty) return widget.onNavigateUp();
    _nodes[_focused].requestFocus();
  }

  // Item [i] sits on page i ~/ _perPage, in slot i % _perPage: slot 0 is the
  // large card; slots 1.. fill the grid a column at a time, top then bottom.
  int _page(int i) => i ~/ _perPage;
  int _slot(int i) => i % _perPage;
  int _column(int i) => (_slot(i) - 1) ~/ 2;
  int _row(int i) => (_slot(i) - 1) % 2;
  int _index(int page, {int? column, int row = 0}) => page * _perPage + (column == null ? 0 : 1 + column * 2 + row);

  int? _target(int i, LogicalKeyboardKey key) {
    final last = _items.length - 1;
    int? within(int index) => index <= last ? index : null;
    final page = _page(i);
    final big = _slot(i) == 0;

    if (key.isRightKey) {
      if (big) return within(_index(page, column: 0));
      final column = _column(i) + 1;
      if (column < _columns) {
        // A column short its bottom card offers its top one instead.
        final next = within(_index(page, column: column, row: _row(i))) ?? within(_index(page, column: column));
        if (next != null) return next;
      }
      return within(_index(page + 1));
    }
    if (key.isLeftKey) {
      if (!big) {
        return _column(i) == 0 ? _index(page) : _index(page, column: _column(i) - 1, row: _row(i));
      }
      if (page == 0) return null;
      return _index(page - 1, column: _columns - 1);
    }
    if (key.isDownKey) return big || _row(i) == 1 ? i : (within(i + 1) ?? i);
    if (key.isUpKey) return big || _row(i) == 0 ? null : i - 1;
    return null;
  }

  KeyEventResult _onKey(int i, KeyEvent event) {
    final key = event.logicalKey;
    if (key.isSelectKey) return handleOneShotSelect(event, () => _open(i));
    final back = handleBackKeyAction(event, widget.onNavigateToSidebar);
    if (back != KeyEventResult.ignored) return back;
    if (!key.isDpadDirection) return KeyEventResult.ignored;
    if (!event.isActionable) return KeyEventResult.handled;

    final target = _target(i, key);
    if (key.isDownKey && target == i && widget.onNavigateDown != null) {
      widget.onNavigateDown!();
    } else if (target != null) {
      _nodes[target].requestFocus();
    } else if (key.isUpKey) {
      widget.onNavigateUp();
    } else if (key.isLeftKey) {
      widget.onNavigateToSidebar();
    }
    return KeyEventResult.handled;
  }

  /// Turn to the focused card's page: each page fills the row exactly.
  void _onFocusChange(int i, bool hasFocus) {
    if (!hasFocus) return;
    setState(() => _focused = i);
    if (_scroll.hasClients) {
      final position = _scroll.position;
      unawaited(
        _scroll.animateTo(
          (_page(i) * _pageStride).clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: FocusTheme.navigationScrollDuration(),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  Future<void> _open(int i) async {
    await navigateToMediaItem(context, _items[i]);
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final isTv = PlatformDetector.isTV();
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final scale = isTv ? TvBrowseRailLayout.scaleForSize(size) : 1.0;
    final inset = isTv ? TvBrowseRailLayout.horizontalInsetForScale(scale) : 16.0;
    // Where the TV rails above start their cards.
    final edge = isTv ? inset + (FocusTheme.focusBorderWidth * 2 + 12) * scale : inset;
    final gap = 12.0 * scale;
    final bottom = isTv ? 24.0 : 8.0;

    // The section is one screen tall, so revealing it fills the screen.
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus) widget.onFocusEntered?.call();
      },
      child: SizedBox(
        height: size.height - MediaQuery.paddingOf(context).vertical,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(inset, isTv ? 24 : 16, inset, (isTv ? 16 : 12) - _focusSlack),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The focused card, else the one last focused here.
                  Text(
                    _items[_focused].displayTitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.hub.title,
                    style: isTv
                        ? TvSectionHeaderTokens.title.copyWith(color: theme.colorScheme.onSurface)
                        : theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                // Clipped at the content edge, so earlier pages don't slide
                // under the sidebar; the slack keeps the focus ring.
                padding: EdgeInsets.only(left: edge - _focusSlack, bottom: bottom),
                child: LayoutBuilder(builder: (context, constraints) => _buildPages(constraints, gap, inset)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The pages for a [constraints]-sized row: posters fill its height (the
  /// large one both rows), and a page holds as many columns as fit across.
  Widget _buildPages(BoxConstraints constraints, double gap, double inset) {
    final gridHeight = math.max(0.0, constraints.maxHeight - _focusSlack * 2);
    final stride = math.max(1.0, constraints.maxWidth - _focusSlack);
    final across = stride - inset;
    // Posters as tall as the row fits, then the nearest whole number of
    // columns: shrink the posters a touch to fit one more, or spread a small
    // remainder across the gaps.
    final fullBig = gridHeight / 1.5;
    final fullSmall = math.max(0.0, (gridHeight - gap) / 2) / 1.5;
    _columns = math.max(1, ((across - fullBig) / (fullSmall + gap)).round());
    final fit = ((across - _columns * gap) / (fullBig + _columns * fullSmall)).clamp(0.0, 1.0);
    final bigWidth = fullBig * fit;
    final bigHeight = bigWidth * 1.5;
    final smallWidth = fullSmall * fit;
    final smallHeight = smallWidth * 1.5;
    final columnGap = math.max(gap, (across - bigWidth - _columns * smallWidth) / _columns);
    _pageStride = stride;
    final pages = (_items.length / _perPage).ceil();

    Widget card(int i, {required bool big}) => _SeasonalCard(
      item: _items[i],
      width: big ? bigWidth : smallWidth,
      height: big ? bigHeight : smallHeight,
      focusNode: _nodes[i],
      onKey: (event) => _onKey(i, event),
      onFocusChange: (hasFocus) => _onFocusChange(i, hasFocus),
      onTap: () => unawaited(_open(i)),
    );

    Widget page(int p) => SizedBox(
      width: stride,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          card(_index(p), big: true),
          for (var c = 0; c < _columns; c++)
            if (_index(p, column: c) < _items.length)
              Padding(
                padding: EdgeInsets.only(left: columnGap),
                child: Column(
                  children: [
                    card(_index(p, column: c), big: false),
                    SizedBox(height: gap),
                    if (_index(p, column: c, row: 1) < _items.length) card(_index(p, column: c, row: 1), big: false),
                  ],
                ),
              ),
        ],
      ),
    );

    return SingleChildScrollView(
      controller: _scroll,
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.hardEdge,
      physics: PlatformDetector.isTV() ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(_focusSlack, _focusSlack, 0, _focusSlack),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [for (var p = 0; p < pages; p++) page(p)]),
    );
  }
}

/// One seasonal card: the item's poster as the server has it.
class _SeasonalCard extends StatefulWidget {
  final MediaItem item;
  final double width;
  final double height;
  final FocusNode focusNode;
  final KeyEventResult Function(KeyEvent event) onKey;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onTap;

  const _SeasonalCard({
    required this.item,
    required this.width,
    required this.height,
    required this.focusNode,
    required this.onKey,
    required this.onFocusChange,
    required this.onTap,
  });

  @override
  State<_SeasonalCard> createState() => _SeasonalCardState();
}

class _SeasonalCardState extends State<_SeasonalCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final duration = FocusTheme.getAnimationDuration(context);
    final radius = BorderRadius.circular(widget.width > 200 ? 14 : 10);

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
              child: ClipRRect(
                borderRadius: radius,
                child: OptimizedMediaImage.poster(
                  client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                  imagePath: item.posterThumb(),
                  width: widget.width,
                  height: widget.height,
                  placeholder: (context, _) => ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
