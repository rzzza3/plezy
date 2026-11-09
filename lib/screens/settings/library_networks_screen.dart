import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/card_focus_scope.dart';
import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../services/library_rows.dart';
import '../../services/settings_service.dart';
import '../../services/tmdb/tmdb_client.dart';
import '../../services/tmdb/tmdb_genres.dart';
import '../../services/tmdb/tmdb_models.dart';
import '../../services/tmdb/tmdb_networks.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_image_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/clickable_cursor.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/settings_builder.dart';
import '../library_network_screen.dart';

/// The rail's entries: the Library's rows as a whole, then the two rows
/// whose tiles this page picks.
enum _Tab { rows, networks, genres }

/// One pickable network or genre: its stored id, name and (networks only)
/// logo.
typedef _Choice = ({String id, String name, String? logoUrl});

/// The Library hero's Edit page: which rows the Library tab shows and in what
/// order, and which networks and genres its Networks and Genres rows show.
///
/// A rail picks what to edit. Rows lists every [LibraryRow]: OK on one (or a
/// touch drag on its handle) moves it up or down, and its Shown/Hidden
/// toggle hides it from the Library while keeping its place.
///
/// For Networks and Genres, above the grid, "Your … row" shows that row's tiles
/// as the Library lays them out; OK on one (or a touch drag) moves it. OK on
/// a grid tile adds it to the end of the row, or takes it out. Tiles look
/// like the Library's own: a white logo, or the name in the pages' display
/// face, on a dark tile with a white focus ring.
///
/// Writes [SettingsService.libraryRowOrder], [SettingsService.libraryRowsHidden],
/// [SettingsService.libraryNetworks] and [SettingsService.libraryGenres];
/// network logos come from TMDB as they
/// load.
class LibraryNetworksScreen extends StatefulWidget {
  const LibraryNetworksScreen({super.key});

  /// Below this width the rail turns into a row of buttons above the page.
  static const double railBreakpoint = 720;

  @override
  State<LibraryNetworksScreen> createState() => _LibraryNetworksScreenState();
}

class _LibraryNetworksScreenState extends State<LibraryNetworksScreen> {
  static const double _gap = 12;
  static const double _railWidth = 200;

  /// Tiles sit this far inside the content's clip, so a focused tile's
  /// scale and ring are never cut off.
  static const double _inset = 10;

  /// TMDB's logo per network, once read.
  final Map<int, String> _logos = {};
  final Map<int, TmdbNetworkBrand> _brands = {for (final network in TmdbNetworks.all) network.id: network};
  final Map<String, LibraryGenre> _genres = {for (final genre in TmdbGenres.all) genre.id: genre};

  /// Focus per row tile, so a tile keeps focus while it moves.
  final Map<String, FocusNode> _rowNodes = {};

  /// The rail's Rows, Networks and Genres entries, so LEFT from the content lands
  /// on the row being edited rather than whichever entry is nearest.
  final Map<_Tab, FocusNode> _railNodes = {
    for (final row in _Tab.values) row: FocusNode(debugLabel: 'edit_library_rail_${row.name}'),
  };
  final _resetNode = FocusNode(debugLabel: 'edit_library_reset');

  /// The row strip and grid. Its own scope keeps D-pad moves inside it, and
  /// remembers the last tile for RIGHT from the rail.
  final _contentScope = FocusScopeNode(debugLabel: 'edit_library_content');

  _Tab _tab = _Tab.rows;

  /// The row's order while a tile is being moved with the remote, and the
  /// tile; written when it is put down, dropped on BACK.
  List<String>? _draft;
  String? _moving;

  @override
  void initState() {
    super.initState();
    final tmdb = context.read<TmdbClient>();
    if (!tmdb.isConfigured) return;
    for (final network in TmdbNetworks.all) {
      if (!network.usesWordmark) unawaited(_loadLogo(tmdb, network.id));
    }
  }

  @override
  void dispose() {
    for (final node in [..._rowNodes.values, ..._railNodes.values, _resetNode, _contentScope]) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLogo(TmdbClient tmdb, int id) async {
    final TmdbNetwork network;
    try {
      network = await tmdb.network(id);
    } catch (error) {
      appLogger.w('Library networks settings: details failed for $id (${error.runtimeType})');
      return;
    }
    final url = network.logoUrl('w185');
    if (mounted && url != null) setState(() => _logos[id] = url);
  }

  StringListPref get _pref => switch (_tab) {
    _Tab.rows => SettingsService.libraryRowOrder,
    _Tab.networks => SettingsService.libraryNetworks,
    _Tab.genres => SettingsService.libraryGenres,
  };

  /// [row]'s stored ids that its catalogue knows, in the stored order. For
  /// Rows, every row's name, hidden ones included.
  List<String> _chosen(_Tab row) {
    if (row == _Tab.rows) return [for (final libraryRow in LibraryRow.savedOrder()) libraryRow.name];
    final pref = row == _Tab.networks ? SettingsService.libraryNetworks : SettingsService.libraryGenres;
    return [
      for (final id in SettingsService.instance.read(pref).toSet())
        if (row == _Tab.networks ? _brands.containsKey(int.tryParse(id)) : _genres.containsKey(id)) id,
    ];
  }

  _Choice _choice(String id) {
    if (_tab == _Tab.genres) return (id: id, name: _genres[id]!.name, logoUrl: null);
    final network = _brands[int.parse(id)]!;
    return (id: id, name: network.name, logoUrl: network.usesWordmark ? null : _logos[network.id]);
  }

  int _total(_Tab row) => switch (row) {
    _Tab.rows => LibraryRow.values.length,
    _Tab.networks => TmdbNetworks.all.length,
    _Tab.genres => TmdbGenres.all.length,
  };

  /// How many of [row]'s entries the Library shows.
  int _shownCount(_Tab row) => row == _Tab.rows ? LibraryRow.shown().length : _chosen(row).length;

  FocusNode _rowNode(String id) =>
      _rowNodes.putIfAbsent('${_tab.name}-$id', () => FocusNode(debugLabel: 'edit_library_row_$id'));

  // ── Focus ────────────────────────────────────────────────────────────────

  void _focusRail() => _jumpTo(_railNodes[_tab]!);

  /// RIGHT from the rail: back to the tile last focused in the content, or
  /// its first tile.
  void _focusContent() {
    final remembered = _contentScope.focusedChild;
    if (remembered != null && (remembered.context?.mounted ?? false)) {
      _jumpTo(remembered);
      return;
    }
    _contentScope.requestFocus();
    _contentScope.nextFocus();
    _forgetMoves();
  }

  /// Focus set by hand, not by an arrow, so the traversal's memory of recent
  /// moves no longer applies. Left in place, DOWN to Reset then UP after
  /// Reset hands focus to Genres would "return" to Genres and do nothing.
  void _jumpTo(FocusNode node) {
    node.requestFocus();
    _forgetMoves();
  }

  void _forgetMoves() {
    // Each scope's memory lives in the policy its own nodes traverse with.
    for (final node in [_railNodes[_tab]!, _contentScope]) {
      final nodeContext = node.context;
      final scope = node is FocusScopeNode ? node : node.nearestScope;
      if (nodeContext == null || scope == null) continue;
      FocusTraversalGroup.maybeOf(nodeContext)?.invalidateScopeData(scope);
    }
  }

  /// Keeps a row tile in the middle of the strip, clear of its clipped
  /// edges, when it gains focus or moves.
  void _centreRowTile(String id) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final tileContext = _rowNodes['${_tab.name}-$id']?.context;
      if (tileContext == null || !tileContext.mounted) return;
      unawaited(
        Scrollable.ensureVisible(
          tileContext,
          alignment: 0.5,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  // ── Changes ──────────────────────────────────────────────────────────────

  Future<void> _write(List<String> ids) {
    // The default row order is stored as the default (empty), so moving rows
    // back where they started leaves Reset with nothing to do.
    if (_tab == _Tab.rows && _listEquals(ids, LibraryRow.defaultOrder)) {
      return SettingsService.instance.reset(SettingsService.libraryRowOrder);
    }
    return SettingsService.instance.write(_pref, ids);
  }

  /// Shows [row] on the Library, or hides it there; it keeps its place here.
  void _toggleHidden(LibraryRow row) {
    _putDown();
    final hidden = LibraryRow.savedHidden();
    if (!hidden.remove(row)) hidden.add(row);
    final names = [
      for (final row in LibraryRow.values)
        if (hidden.contains(row)) row.name,
    ];
    final pref = SettingsService.libraryRowsHidden;
    unawaited(names.isEmpty ? SettingsService.instance.reset(pref) : SettingsService.instance.write(pref, names));
  }

  void _selectRow(_Tab row) {
    if (row == _tab) return;
    _putDown();
    setState(() => _tab = row);
  }

  /// Adds [id] to the end of the row, or takes it out.
  void _toggle(String id) {
    _putDown();
    final chosen = _chosen(_tab);
    if (!chosen.remove(id)) chosen.add(id);
    unawaited(_write(chosen));
  }

  static const _prefs = [
    SettingsService.libraryRowOrder,
    SettingsService.libraryRowsHidden,
    SettingsService.libraryNetworks,
    SettingsService.libraryGenres,
  ];

  /// Everything back to its defaults. One button for every tab, since the
  /// rail follows focus: a per-tab reset below Genres could never be reached
  /// with Rows shown.
  void _reset() {
    _putDown();
    for (final pref in _prefs) {
      unawaited(SettingsService.instance.reset(pref));
    }
    // Reset turns itself off, so hand focus to the row being edited rather
    // than wherever the framework drops it.
    if (_resetNode.hasFocus) _focusRail();
  }

  /// OK on a row tile: picks it up, or puts it down where it now sits.
  void _onRowTileSelect(String id) {
    if (_moving == id) {
      _putDown();
    } else {
      _putDown();
      setState(() {
        _moving = id;
        _draft = _chosen(_tab);
      });
    }
  }

  void _putDown() {
    final draft = _draft;
    if (draft == null) return;
    setState(() {
      _moving = null;
      _draft = null;
    });
    unawaited(_write(draft));
  }

  void _cancelMove() => setState(() {
    _moving = null;
    _draft = null;
  });

  /// LEFT/RIGHT move the picked-up tile (UP/DOWN a picked-up row, on Rows);
  /// the other arrows stay put, so it is put down (OK) or dropped (BACK)
  /// where the user can see it.
  KeyEventResult _onRowTileKey(String id, KeyEvent event) {
    if (_moving != id) return KeyEventResult.ignored;
    final backResult = handleBackKeyAction(event, _cancelMove);
    if (backResult != KeyEventResult.ignored) return backResult;
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final vertical = _tab == _Tab.rows;
    final back = vertical ? key.isUpKey : key.isLeftKey;
    final forward = vertical ? key.isDownKey : key.isRightKey;
    if (back || forward) {
      final draft = _draft!;
      final from = draft.indexOf(id);
      final to = back ? from - 1 : from + 1;
      if (to >= 0 && to < draft.length) {
        setState(() {
          draft.removeAt(from);
          draft.insert(to, id);
        });
        _centreRowTile(id);
      }
      return KeyEventResult.handled;
    }
    if (key.isUpKey || key.isDownKey || key.isLeftKey || key.isRightKey) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  void _onReorder(int from, int to) {
    _putDown();
    final chosen = _chosen(_tab);
    final id = chosen.removeAt(from);
    chosen.insert(to, id);
    unawaited(_write(chosen));
  }

  // ── Layout ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: _prefs,
      builder: (context) {
        // On an Android remote the key handlers own BACK (a picked-up tile
        // drops its move; otherwise the page closes), so the system's own back
        // must not pop the page as well.
        return PopScope(
          canPop: _moving == null && !InputModeTracker.shouldBlockSystemBack(context),
          onPopInvokedWithResult: (didPop, _) {
            if (didPop || BackKeyCoordinator.consumeIfHandled()) return;
            if (_moving != null) {
              // Android TV sends this just before the press's KeyUp, which
              // would otherwise reach the page's BACK and close it.
              if (BackKeyPressTracker.isBackKeyDown) BackKeyUpSuppressor.suppressBackUntilKeyUp();
              _cancelMove();
            } else {
              Navigator.pop(context);
            }
          },
          child: FocusedScrollScaffold(
            title: Text(t.libraryHome.editLibrary),
            slivers: [
              SliverFillRemaining(
                hasScrollBody: true,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= LibraryNetworksScreen.railBreakpoint;
                    final padding = wide ? 24.0 : 16.0;
                    // The rail and its gutter, when beside the content.
                    final contentWidth = constraints.maxWidth - padding * 2 - (wide ? _railWidth + 32 : 0);
                    final columns = ((contentWidth + _gap) / (104 + _gap)).floor().clamp(3, 8);
                    // Floored, so rounding never wraps a row's last tile.
                    final tileWidth = ((contentWidth - _gap * (columns - 1)) / columns).floorToDouble();
                    final content = _tab == _Tab.rows
                        ? _buildRowsContent(context, padding: padding, wide: wide)
                        : _buildContent(context, tileWidth: tileWidth, columns: columns, padding: padding, wide: wide);
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.fromLTRB(padding, 4, padding, 8),
                            child: _buildRail(context, vertical: false),
                          ),
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(left: padding - _inset),
                              child: content,
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(padding, 8, 32 - _inset, 0),
                          child: SizedBox(width: _railWidth, child: _buildRail(context, vertical: true)),
                        ),
                        Expanded(child: content),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRail(BuildContext context, {required bool vertical}) {
    final isDefault = _prefs.every((pref) => _listEquals(SettingsService.instance.read(pref), pref.defaultValue));
    final items = [
      for (final row in _Tab.values)
        _RailButton(
          key: ValueKey('edit-library-${row.name}'),
          label: switch (row) {
            _Tab.rows => t.libraryHome.editLibraryRows,
            _Tab.networks => t.libraryHome.networks,
            _Tab.genres => t.libraryHome.genres,
          },
          detail: t.libraryHome.editLibraryShown(count: _shownCount(row), total: _total(row)),
          focusNode: _railNodes[row]!,
          selected: row == _tab,
          // On a remote the rail follows focus, like the Library's tiles.
          onFocus: () => _selectRow(row),
          onSelect: () => _selectRow(row),
          onRight: vertical ? _focusContent : null,
          onDown: vertical ? null : _focusContent,
        ),
    ];
    final reset = _RailButton(
      key: const ValueKey('edit-library-reset'),
      label: t.libraryHome.editLibraryReset,
      icon: Symbols.restart_alt_rounded,
      focusNode: _resetNode,
      enabled: !isDefault,
      onSelect: _reset,
      onRight: vertical ? _focusContent : null,
      onDown: vertical ? null : _focusContent,
    );
    if (!vertical) {
      return Wrap(spacing: 8, runSpacing: 8, children: [...items, reset]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 6,
      children: [
        ...items,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12)),
        ),
        reset,
      ],
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required double tileWidth,
    required int columns,
    required double padding,
    required bool wide,
  }) {
    final theme = Theme.of(context);
    final chosen = _chosen(_tab);
    final shown = _draft ?? chosen;
    final heading = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final groupStyle = theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget grid(Iterable<String> ids) => Wrap(
      spacing: _gap,
      runSpacing: _gap,
      children: [
        for (final (index, id) in ids.indexed)
          _PickTile(
            key: ValueKey('library-${_tab == _Tab.networks ? 'network' : 'genre'}-$id'),
            choice: _choice(id),
            width: tileWidth,
            picked: chosen.contains(id),
            onSelect: () => _toggle(id),
            // The first column's LEFT goes to the rail.
            onLeft: wide && index % columns == 0 ? _focusRail : null,
          ),
      ],
    );

    final List<Widget> groups;
    if (_tab == _Tab.genres) {
      groups = [grid(TmdbGenres.all.map((genre) => genre.id))];
    } else {
      groups = [
        for (final group in TmdbNetworkGroup.values) ...[
          Padding(
            padding: const EdgeInsets.only(top: 20, bottom: 10),
            child: Text(_groupName(group), style: groupStyle),
          ),
          grid(TmdbNetworks.all.where((network) => network.group == group).map((network) => '${network.id}')),
        ],
      ];
    }

    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: _inset, right: padding, top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  _tab == _Tab.networks ? t.libraryHome.editLibraryNetworksRow : t.libraryHome.editLibraryGenresRow,
                  style: heading,
                ),
              ),
              if (shown.length > 1) _MoveHint(moving: _moving != null),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          // Room for a focused or lifted tile's scale, ring and lift.
          height: tileWidth / 2 + 28,
          child: shown.isEmpty
              ? _EmptyRow(width: tileWidth, rightPadding: padding)
              : _buildRowStrip(shown, tileWidth: tileWidth, rightPadding: padding, wide: wide),
        ),
        Expanded(
          // Scrolled tiles pass under the row strip, not over it; sideways
          // the focused tile's scale may still spill past the edge.
          child: ClipRect(
            clipper: const _ClipVertically(),
            child: Stack(
              children: [
                ListView(
                  key: ValueKey(_tab),
                  // Every tile built, so D-pad traversal can reach the last group.
                  scrollCacheExtent: const ScrollCacheExtent.pixels(4000),
                  padding: EdgeInsets.fromLTRB(_inset, 0, padding, 32),
                  clipBehavior: Clip.none,
                  children: [if (_tab == _Tab.genres) const SizedBox(height: 20), ...groups],
                ),
                // Tiles fade out under the strip instead of ending on a hard cut.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 20,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [theme.scaffoldBackgroundColor, theme.scaffoldBackgroundColor.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    // D-pad moves stay among the tiles; LEFT off the first column and RIGHT
    // from the rail are wired explicitly.
    return FocusScope(node: _contentScope, child: column);
  }

  /// Rows: every Library row, top to bottom in the Library's order, each with
  /// a Shown/Hidden toggle beside it.
  Widget _buildRowsContent(BuildContext context, {required double padding, required bool wide}) {
    final theme = Theme.of(context);
    final order = [for (final name in _draft ?? _chosen(_Tab.rows)) LibraryRow.fromName(name)!];
    final hidden = LibraryRow.savedHidden();
    final heading = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: _inset, right: padding, top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(child: Text(t.libraryHome.editLibraryRowsHeading, style: heading)),
              _MoveHint(moving: _moving != null, vertical: true),
            ],
          ),
        ),
        if (hidden.length == LibraryRow.values.length)
          Padding(
            padding: EdgeInsets.only(left: _inset, right: padding, top: 8),
            child: Text(
              t.libraryHome.editLibraryRowsAllHidden,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: EdgeInsets.fromLTRB(_inset, 6, padding, 32),
            itemCount: order.length,
            onReorderItem: _onReorder,
            proxyDecorator: (child, _, _) => Material(type: MaterialType.transparency, child: child),
            itemBuilder: (context, index) {
              final row = order[index];
              return Padding(
                key: ValueKey('library-rows-item-${row.name}'),
                padding: const EdgeInsets.only(bottom: 8),
                child: _LibraryRowLine(
                  row: row,
                  index: index,
                  shown: !hidden.contains(row),
                  focusNode: _rowNode(row.name),
                  moving: _moving == row.name,
                  canMoveUp: index > 0,
                  canMoveDown: index < order.length - 1,
                  onSelect: () => _onRowTileSelect(row.name),
                  onKeyEvent: (event) => _onRowTileKey(row.name, event),
                  onFocusChange: (focused) {
                    if (focused) {
                      if (InputModeTracker.isKeyboardMode(context, listen: false)) _centreRowTile(row.name);
                    } else if (_moving == row.name) {
                      _putDown();
                    }
                  },
                  onToggle: () => _toggleHidden(row),
                  onLeft: wide ? _focusRail : null,
                  onUp: !wide && index == 0 ? _focusRail : null,
                ),
              );
            },
          ),
        ),
      ],
    );
    return FocusScope(node: _contentScope, child: column);
  }

  Widget _buildRowStrip(
    List<String> shown, {
    required double tileWidth,
    required double rightPadding,
    required bool wide,
  }) {
    return ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      // Clipped, so a long row scrolls under the rail rather than over it.
      padding: EdgeInsets.fromLTRB(_inset, 14, rightPadding, 14),
      itemCount: shown.length,
      onReorderItem: _onReorder,
      proxyDecorator: (child, _, _) => Material(type: MaterialType.transparency, child: child),
      itemBuilder: (context, index) {
        final id = shown[index];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('library-row-${_tab.name}-$id'),
          index: index,
          child: Padding(
            padding: const EdgeInsets.only(right: _gap),
            child: _RowTile(
              choice: _choice(id),
              width: tileWidth,
              focusNode: _rowNode(id),
              moving: _moving == id,
              canMoveLeft: index > 0,
              canMoveRight: index < shown.length - 1,
              onSelect: () => _onRowTileSelect(id),
              onKeyEvent: (event) => _onRowTileKey(id, event),
              onFocusChange: (focused) {
                if (focused) {
                  if (InputModeTracker.isKeyboardMode(context, listen: false)) _centreRowTile(id);
                } else if (_moving == id) {
                  _putDown();
                }
              },
              onLeft: index == 0 && wide ? _focusRail : null,
              onUp: wide ? null : _focusRail,
            ),
          ),
        );
      },
    );
  }

  String _groupName(TmdbNetworkGroup group) => switch (group) {
    TmdbNetworkGroup.streaming => t.libraryHome.editLibraryStreaming,
    TmdbNetworkGroup.usChannels => t.libraryHome.editLibraryUsChannels,
    TmdbNetworkGroup.ukChannels => t.libraryHome.editLibraryUkChannels,
  };

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ── Pieces ─────────────────────────────────────────────────────────────────

/// What moves a tile in the row (or, [vertical], a row in the list), for
/// the input in use.
class _MoveHint extends StatelessWidget {
  final bool moving;
  final bool vertical;

  const _MoveHint({required this.moving, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboard = InputModeTracker.isKeyboardMode(context);
    final s = t.libraryHome;
    final text = moving
        ? (vertical ? s.editLibraryRowsMovingHint : s.editLibraryMovingHint)
        : keyboard
        ? (vertical ? s.editLibraryRowsMoveHint : s.editLibraryMoveHint)
        : (vertical ? s.editLibraryRowsDragHint : s.editLibraryDragHint);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: moving ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// Where the row's tiles go when none is picked.
class _EmptyRow extends StatelessWidget {
  final double width;
  final double rightPadding;

  const _EmptyRow({required this.width, required this.rightPadding});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(_LibraryNetworksScreenState._inset, 14, rightPadding, 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              t.libraryHome.editLibraryEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rail entry: Networks, Genres, or Reset. Selected entries sit on a
/// raised surface; a focused one turns white, like the Library hero's pills.
class _RailButton extends StatelessWidget {
  final String label;
  final String? detail;
  final IconData? icon;
  final FocusNode focusNode;
  final bool selected;
  final bool enabled;
  final VoidCallback? onFocus;
  final VoidCallback onSelect;
  final VoidCallback? onRight;
  final VoidCallback? onDown;

  const _RailButton({
    super.key,
    required this.label,
    this.detail,
    this.icon,
    required this.focusNode,
    this.selected = false,
    this.enabled = true,
    this.onFocus,
    required this.onSelect,
    this.onRight,
    this.onDown,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      focusNode: focusNode,
      canRequestFocus: enabled,
      semanticLabel: detail == null ? label : '$label, $detail',
      onNavigateRight: onRight,
      onNavigateDown: onDown,
      onSelect: enabled ? onSelect : null,
      onFocusChange: (focused) {
        if (focused && InputModeTracker.isKeyboardMode(context, listen: false)) onFocus?.call();
      },
      delegateFocusBorder: true,
      disableScale: true,
      borderRadius: 10,
      child: GestureDetector(
        onTap: enabled ? onSelect : null,
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final focused = CardFocusScope.maybeOf(context) ?? false;
            final background = focused
                ? Colors.white
                : selected
                ? theme.colorScheme.surfaceContainerHighest
                : Colors.transparent;
            final foreground = focused
                ? Colors.black
                : selected
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
              child: Opacity(
                opacity: enabled ? 1 : 0.4,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[AppIcon(icon!, size: 18, color: foreground), const SizedBox(width: 10)],
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(color: foreground, fontWeight: FontWeight.w500),
                      ),
                    ),
                    if (detail != null) ...[
                      const SizedBox(width: 12),
                      Text(
                        detail!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: foreground.withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A line in Rows: the row (OK picks it up to move; its handle drags) and
/// its Shown/Hidden toggle. A hidden row stays in place, dimmed.
class _LibraryRowLine extends StatelessWidget {
  final LibraryRow row;
  final int index;
  final bool shown;
  final FocusNode focusNode;
  final bool moving;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onSelect;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onToggle;
  final VoidCallback? onLeft;
  final VoidCallback? onUp;

  const _LibraryRowLine({
    required this.row,
    required this.index,
    required this.shown,
    required this.focusNode,
    required this.moving,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onSelect,
    required this.onKeyEvent,
    required this.onFocusChange,
    required this.onToggle,
    this.onLeft,
    this.onUp,
  });

  static const double _height = 60;

  (String, String?, IconData) get _face => switch (row) {
    LibraryRow.continueWatching => (t.discover.continueWatching, null, Symbols.play_circle_rounded),
    LibraryRow.calendar => (t.libraryHome.calendar, null, Symbols.calendar_month_rounded),
    LibraryRow.seasonal => (t.libraryHome.seasonalPicks, t.libraryHome.seasonalPicksDetail, Symbols.park_rounded),
    LibraryRow.runtime => (t.libraryHome.runtimeTitle, null, Symbols.timer_rounded),
    LibraryRow.forYou => (t.libraryHome.forYouTitle, null, Symbols.auto_awesome_rounded),
    LibraryRow.networks => (t.libraryHome.networks, null, Symbols.live_tv_rounded),
    LibraryRow.genres => (t.libraryHome.genres, null, Symbols.theater_comedy_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final (label, detail, icon) = _face;
    final state = shown ? t.libraryHome.editLibraryRowShown : t.libraryHome.editLibraryRowHidden;

    final body = FocusableWrapper(
      key: ValueKey('library-rows-${row.name}'),
      focusNode: focusNode,
      semanticLabel: '$label, $state',
      onSelect: onSelect,
      onKeyEvent: (_, event) => onKeyEvent(event),
      onNavigateLeft: onLeft,
      onNavigateUp: onUp,
      onFocusChange: onFocusChange,
      delegateFocusBorder: true,
      disableScale: true,
      borderRadius: 10,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final lit = moving || (CardFocusScope.maybeOf(context) ?? false);
          final foreground = lit ? Colors.black : theme.colorScheme.onSurface.withValues(alpha: shown ? 1 : 0.45);
          final handle = moving
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: canMoveUp ? 1 : 0.25,
                      child: AppIcon(Symbols.keyboard_arrow_up_rounded, size: 20, color: foreground),
                    ),
                    Opacity(
                      opacity: canMoveDown ? 1 : 0.25,
                      child: AppIcon(Symbols.keyboard_arrow_down_rounded, size: 20, color: foreground),
                    ),
                  ],
                )
              : ReorderableDragStartListener(
                  index: index,
                  child: ClickableCursor(
                    child: AppIcon(
                      Symbols.drag_indicator_rounded,
                      size: 22,
                      color: foreground.withValues(alpha: lit ? 0.6 : 0.5),
                    ),
                  ),
                );
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            height: _height,
            padding: const EdgeInsets.only(left: 10, right: 16),
            decoration: BoxDecoration(
              color: lit ? Colors.white : theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(10),
              boxShadow: moving
                  ? const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))]
                  : null,
            ),
            child: Row(
              children: [
                SizedBox(width: 28, child: Center(child: handle)),
                const SizedBox(width: 8),
                AppIcon(icon, size: 22, color: foreground),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge?.copyWith(color: foreground, fontWeight: FontWeight.w500),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: foreground.withValues(alpha: 0.7)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final toggle = FocusableWrapper(
      key: ValueKey('library-rows-${row.name}-toggle'),
      semanticLabel: label,
      checked: shown,
      onSelect: onToggle,
      onNavigateUp: onUp,
      delegateFocusBorder: true,
      disableScale: true,
      borderRadius: 10,
      child: GestureDetector(
        onTap: onToggle,
        child: Builder(
          builder: (context) {
            final theme = Theme.of(context);
            final focused = CardFocusScope.maybeOf(context) ?? false;
            final foreground = focused
                ? Colors.black
                : shown
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurfaceVariant;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: 132,
              height: _height,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: focused
                    ? Colors.white
                    : shown
                    ? theme.colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: focused || shown ? Colors.transparent : theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppIcon(
                    shown ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
                    size: 20,
                    color: foreground,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      state,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: foreground, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    // A long press anywhere on the line drags it too, as on the Networks row.
    return ReorderableDelayedDragStartListener(
      index: index,
      // Short of the full width on TV, so the toggle sits near its row.
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(child: body),
              const SizedBox(width: 10),
              toggle,
            ],
          ),
        ),
      ),
    );
  }
}

/// A grid tile: on (full strength, white check) or off (dimmed).
class _PickTile extends StatelessWidget {
  final _Choice choice;
  final double width;
  final bool picked;
  final VoidCallback onSelect;
  final VoidCallback? onLeft;

  const _PickTile({
    super.key,
    required this.choice,
    required this.width,
    required this.picked,
    required this.onSelect,
    this.onLeft,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      semanticLabel: choice.name,
      onNavigateLeft: onLeft,
      checked: picked,
      onSelect: onSelect,
      delegateFocusBorder: true,
      focusScale: 1.06,
      borderRadius: 10,
      child: GestureDetector(
        onTap: onSelect,
        child: Builder(
          builder: (context) {
            final focused = CardFocusScope.maybeOf(context) ?? false;
            return _TileFace(
              choice: choice,
              width: width,
              focused: focused,
              // Focus lifts an off tile only enough to read it.
              dim: picked ? 0 : (focused ? 0.3 : 0.6),
              badge: picked ? const _CheckBadge() : null,
            );
          },
        ),
      ),
    );
  }
}

/// A tile in "Your … row". Picked up, it lifts and shows which ways it can
/// move.
class _RowTile extends StatelessWidget {
  final _Choice choice;
  final double width;
  final FocusNode focusNode;
  final bool moving;
  final bool canMoveLeft;
  final bool canMoveRight;
  final VoidCallback onSelect;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback? onLeft;
  final VoidCallback? onUp;

  const _RowTile({
    required this.choice,
    required this.width,
    required this.focusNode,
    required this.moving,
    required this.canMoveLeft,
    required this.canMoveRight,
    required this.onSelect,
    required this.onKeyEvent,
    required this.onFocusChange,
    this.onLeft,
    this.onUp,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableWrapper(
      focusNode: focusNode,
      semanticLabel: choice.name,
      onSelect: onSelect,
      onKeyEvent: (_, event) => onKeyEvent(event),
      onNavigateLeft: onLeft,
      onNavigateUp: onUp,
      onFocusChange: onFocusChange,
      delegateFocusBorder: true,
      focusScale: 1.06,
      borderRadius: 10,
      child: Builder(
        builder: (context) {
          final focused = CardFocusScope.maybeOf(context) ?? false;
          return AnimatedSlide(
            offset: Offset(0, moving ? -0.06 : 0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: _TileFace(
              choice: choice,
              width: width,
              focused: focused || moving,
              lifted: moving,
              dim: 0,
              leading: moving && canMoveLeft ? const _MoveArrow(icon: Symbols.chevron_left_rounded) : null,
              trailing: moving && canMoveRight ? const _MoveArrow(icon: Symbols.chevron_right_rounded) : null,
            ),
          );
        },
      ),
    );
  }
}

/// The Library tile's look without its art: a white logo, or the name in
/// the pages' display face, on dark.
class _TileFace extends StatelessWidget {
  final _Choice choice;
  final double width;
  final bool focused;
  final bool lifted;

  /// Black over the tile, 0 to 1.
  final double dim;
  final Widget? badge;
  final Widget? leading;
  final Widget? trailing;

  const _TileFace({
    required this.choice,
    required this.width,
    required this.focused,
    required this.dim,
    this.lifted = false,
    this.badge,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final height = width / 2;
    final radius = BorderRadius.circular(10);
    final nameText = Text(choice.name.toUpperCase(), maxLines: 1, style: LibraryDisplayType.style(height * 0.32));
    final fallback = Center(
      child: Padding(
        // Clear of the check badge in the corner.
        padding: EdgeInsets.symmetric(horizontal: height * 0.4),
        child: FittedBox(fit: BoxFit.scaleDown, child: nameText),
      ),
    );
    final label = choice.logoUrl == null
        ? fallback
        : Center(
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: OptimizedMediaImage(
                imagePath: choice.logoUrl,
                width: width * 0.58,
                height: height * 0.4,
                fit: BoxFit.contain,
                imageType: ImageType.logo,
                placeholder: (context, _) => SizedBox(width: width * 0.58, height: height * 0.4),
                errorWidget: (context, _, _) => fallback,
              ),
            ),
          );

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: focused ? Colors.white : Colors.white.withValues(alpha: 0.08),
          width: focused ? 2.5 : 1,
        ),
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1C),
        borderRadius: radius,
        boxShadow: focused || lifted
            ? const [BoxShadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 8))]
            : null,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            label,
            AnimatedOpacity(
              opacity: dim,
              duration: const Duration(milliseconds: 150),
              child: const ColoredBox(color: Colors.black),
            ),
            if (badge != null) Positioned(top: 6, right: 6, child: badge!),
          ],
        ),
      ),
    );
    if (leading == null && trailing == null) return tile;
    // The move arrows sit on the tile's edges, clear of its logo.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        tile,
        if (leading != null) Positioned(left: -10, top: 0, bottom: 0, child: Center(child: leading)),
        if (trailing != null) Positioned(right: -10, top: 0, bottom: 0, child: Center(child: trailing)),
      ],
    );
  }
}

class _CheckBadge extends StatelessWidget {
  const _CheckBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const AppIcon(Symbols.check_rounded, size: 14, color: Colors.black, weight: 700),
    );
  }
}

class _MoveArrow extends StatelessWidget {
  final IconData icon;

  const _MoveArrow({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: AppIcon(icon, size: 18, color: Colors.black),
    );
  }
}

/// Clips above and below only, so a focused tile's scale can still spill
/// past the sides.
class _ClipVertically extends CustomClipper<Rect> {
  const _ClipVertically();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-40, 0, size.width + 40, size.height);

  @override
  bool shouldReclip(_ClipVertically oldClipper) => false;
}
