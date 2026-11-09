import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focus_theme.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_library.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/content_utils.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/library_management_sheet.dart' show reconcileLibraryOrder;
import '../../widgets/system_bottom_inset.dart';

/// Settings → Libraries: which libraries the sidebar shows, and in what order.
///
/// Each row is a switch (shown in the sidebar) plus a move handle. Pointers
/// drag the handle. On a remote or keyboard, SELECT on the handle picks the
/// library up: UP/DOWN move it, SELECT places it, BACK puts it back. Rows are
/// ordinary focusables, so the settings pane's own traversal (LEFT back to the
/// category list) keeps working outside a move.
class LibrariesSettingsPane extends StatefulWidget {
  const LibrariesSettingsPane({super.key});

  @override
  State<LibrariesSettingsPane> createState() => _LibrariesSettingsPaneState();
}

class _LibrariesSettingsPaneState extends State<LibrariesSettingsPane> {
  late final LibrariesProvider _libraries;
  late List<MediaLibrary> _order;

  /// The library picked up with the remote, and the order to restore on BACK.
  String? _movingKey;
  List<MediaLibrary>? _orderBeforeMove;

  /// Handle and switch focus nodes by library, so focus follows a library as
  /// it moves.
  final Map<String, FocusNode> _handleNodes = {};
  final Map<String, FocusNode> _switchNodes = {};

  @override
  void initState() {
    super.initState();
    _libraries = context.read<LibrariesProvider>();
    _order = List.of(_libraries.libraries);
    _libraries.addListener(_onLibrariesChanged);
  }

  @override
  void dispose() {
    _libraries.removeListener(_onLibrariesChanged);
    for (final node in [..._handleNodes.values, ..._switchNodes.values]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Follows loads and changes made elsewhere, keeping the order shown. A move
  /// in progress keeps its rows; placing it reconciles against the provider.
  void _onLibrariesChanged() {
    if (!mounted || _movingKey != null) return;
    setState(() => _order = reconcileLibraryOrder(_order, _libraries.libraries));
  }

  void _save() => _libraries.updateLibraryOrder(reconcileLibraryOrder(_order, _libraries.libraries));

  FocusNode _handleNode(MediaLibrary library) =>
      _handleNodes.putIfAbsent(library.globalKey, () => FocusNode(debugLabel: 'library_move_${library.globalKey}'));

  FocusNode _switchNode(MediaLibrary library) =>
      _switchNodes.putIfAbsent(library.globalKey, () => FocusNode(debugLabel: 'library_shown_${library.globalKey}'));

  Future<void> _toggle(MediaLibrary library, {required bool show}) {
    final hidden = context.read<HiddenLibrariesProvider>();
    return show ? hidden.unhideLibrary(library.globalKey) : hidden.hideLibrary(library.globalKey);
  }

  void _onDragReorder(int oldIndex, int newIndex) {
    setState(() {
      final library = _order.removeAt(oldIndex);
      _order.insert(newIndex, library);
    });
    _save();
  }

  void _pickUp(MediaLibrary library) => setState(() {
    _movingKey = library.globalKey;
    _orderBeforeMove = List.of(_order);
  });

  void _place() {
    _save();
    setState(() {
      _movingKey = null;
      _orderBeforeMove = null;
    });
  }

  void _cancelMove() => setState(() {
    _order = _orderBeforeMove ?? _order;
    _movingKey = null;
    _orderBeforeMove = null;
  });

  void _step(MediaLibrary library, int delta) {
    final from = _order.indexOf(library);
    final to = from + delta;
    if (from < 0 || to < 0 || to >= _order.length) return;
    setState(() => _order.insert(to, _order.removeAt(from)));
    // The row rebuilds at its new index; keep it in view once laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _handleNodes[library.globalKey]?.context;
      if (rowContext != null && rowContext.mounted) {
        Scrollable.ensureVisible(rowContext, alignment: 0.3, duration: tokens(context).fast);
      }
    });
  }

  KeyEventResult _onHandleKey(MediaLibrary library, KeyEvent event) {
    if (_movingKey != library.globalKey) {
      // The settings pane takes any LEFT a control leaves alone back to the
      // category list, so the handle must hand LEFT to its own switch.
      if (event.isActionable && event.logicalKey.isLeftKey) {
        _switchNode(library).requestFocus();
        return KeyEventResult.handled;
      }
      return handleOneShotSelect(event, () => _pickUp(library));
    }
    final back = handleBackKeyAction(event, _cancelMove);
    if (back != KeyEventResult.ignored) return back;
    final select = handleOneShotSelect(event, _place);
    if (select != KeyEventResult.ignored) return select;
    final key = event.logicalKey;
    if (event.isActionable && key.isUpKey) _step(library, -1);
    if (event.isActionable && key.isDownKey) _step(library, 1);
    // Held in place while moving: no other key may walk focus off the row.
    return key.isDpadDirection ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final hiddenKeys = context.watch<HiddenLibrariesProvider>().hiddenLibraryKeys;
    final theme = Theme.of(context);
    final t0 = tokens(context);
    final multipleServers = _order.map((l) => l.serverId).whereType<String>().toSet().length > 1;

    return CustomScrollView(
      primary: false,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverToBoxAdapter(
            child: Text(
              _order.isEmpty
                  ? t.libraries.noLibrariesFound
                  : PlatformDetector.isTV()
                  ? t.libraries.sidebarIntroTv
                  : t.libraries.sidebarIntro,
              style: theme.textTheme.bodyMedium?.copyWith(color: t0.textMuted),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverReorderableList(
            itemCount: _order.length,
            onReorderItem: _onDragReorder,
            proxyDecorator: (child, _, _) => Material(
              color: Colors.transparent,
              elevation: 8,
              shadowColor: Colors.black54,
              borderRadius: BorderRadius.circular(t0.radiusLg),
              child: child,
            ),
            itemBuilder: (context, index) {
              final library = _order[index];
              return _LibraryRow(
                key: ValueKey(library.globalKey),
                library: library,
                index: index,
                count: _order.length,
                shown: !hiddenKeys.contains(library.globalKey),
                showServer: multipleServers,
                moving: _movingKey == library.globalKey,
                handleNode: _handleNode(library),
                switchNode: _switchNode(library),
                onToggle: (show) => _toggle(library, show: show),
                onHandleKey: (event) => _onHandleKey(library, event),
              );
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        const SliverSystemBottomInset(),
      ],
    );
  }
}

class _LibraryRow extends StatelessWidget {
  final MediaLibrary library;
  final int index;
  final int count;
  final bool shown;
  final bool showServer;
  final bool moving;
  final FocusNode handleNode;
  final FocusNode switchNode;
  final ValueChanged<bool> onToggle;
  final KeyEventResult Function(KeyEvent event) onHandleKey;

  const _LibraryRow({
    super.key,
    required this.library,
    required this.index,
    required this.count,
    required this.shown,
    required this.showServer,
    required this.moving,
    required this.handleNode,
    required this.switchNode,
    required this.onToggle,
    required this.onHandleKey,
  });

  @override
  Widget build(BuildContext context) {
    final t0 = tokens(context);
    final subtitle = moving
        ? t.libraries.movingHint
        : showServer
        ? library.serverName
        : null;

    return Padding(
      padding: EdgeInsets.only(top: index == 0 ? 0 : t0.groupGap),
      child: Material(
        // A picked-up row lifts to the focus fill so it reads as held.
        color: moving ? Color.alphaBlend(t0.text.withValues(alpha: 0.12), t0.surface) : t0.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: groupItemRadii(context, index, count)),
        child: ListTileTheme.merge(
          visualDensity: PlatformDetector.isAutomotive() ? VisualDensity.standard : const VisualDensity(vertical: -3),
          child: Row(
            children: [
              Expanded(
                child: AnimatedOpacity(
                  opacity: shown ? 1 : 0.55,
                  duration: t0.fast,
                  child: FocusableSwitchListTile(
                    focusNode: switchNode,
                    secondary: AppIcon(ContentTypeHelper.getLibraryIcon(library.kind.id), fill: 1),
                    title: Text(library.title),
                    subtitle: subtitle == null ? null : Text(subtitle),
                    value: shown,
                    // Never disabled: a held row must not read as greyed out, and
                    // the handle owns focus for the whole move anyway.
                    onChanged: onToggle,
                  ),
                ),
              ),
              _MoveHandle(
                index: index,
                node: handleNode,
                moving: moving,
                label: t.libraries.moveLibrary(title: library.title),
                onKey: onHandleKey,
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoveHandle extends StatelessWidget {
  final int index;
  final FocusNode node;
  final bool moving;
  final String label;
  final KeyEventResult Function(KeyEvent event) onKey;

  const _MoveHandle({
    required this.index,
    required this.node,
    required this.moving,
    required this.label,
    required this.onKey,
  });

  @override
  Widget build(BuildContext context) {
    final t0 = tokens(context);
    return Semantics(
      button: true,
      label: label,
      child: ReorderableDragStartListener(
        index: index,
        child: Focus(
          focusNode: node,
          onKeyEvent: (_, event) => onKey(event),
          child: ListenableBuilder(
            listenable: node,
            builder: (context, _) => MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: AnimatedContainer(
                duration: t0.fast,
                width: 44,
                height: 44,
                decoration: FocusTheme.textFillFocusDecoration(
                  context,
                  isFocused: node.hasFocus || moving,
                  borderRadius: MonoTokens.radiusFull,
                ),
                child: Center(
                  child: AppIcon(
                    moving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
                    fill: 1,
                    color: moving || node.hasFocus ? t0.text : t0.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
