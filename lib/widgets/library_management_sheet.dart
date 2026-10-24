import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/dpad_reorder_mixin.dart';
import '../focus/focus_theme.dart';
import '../focus/input_mode_tracker.dart';
import '../i18n/strings.g.dart';
import '../media/media_library.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../utils/content_utils.dart';
import '../utils/dialogs.dart';
import '../utils/platform_detector.dart';
import 'app_icon.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'overlay_sheet.dart';

/// Shows the manage/reorder-libraries sheet (dialog on TV, overlay sheet
/// otherwise). Reorder and hide/unhide are provider-backed, so any screen can
/// open it.
///
/// [onOrderChanged] runs after the new order is written to
/// [LibrariesProvider] (the libraries screen uses it to poke MainScreen's
/// side nav). [onToggleVisibility] overrides the default plain hide/unhide
/// (the libraries screen adds "re-select first visible library" logic).
///
Future<void> showLibraryManagementSheet(
  BuildContext context, {
  VoidCallback? onOrderChanged,
  Future<void> Function(MediaLibrary library)? onToggleVisibility,
}) {
  final librariesProvider = context.read<LibrariesProvider>();
  final hiddenLibrariesProvider = context.read<HiddenLibrariesProvider>();
  Future<void> defaultToggleVisibility(MediaLibrary library) async {
    final isHidden = hiddenLibrariesProvider.hiddenLibraryKeys.contains(library.globalKey);
    if (isHidden) {
      await hiddenLibrariesProvider.unhideLibrary(library.globalKey);
    } else {
      await hiddenLibrariesProvider.hideLibrary(library.globalKey);
    }
  }

  Widget buildSheet({required bool isDialog}) => _LibraryManagementSheet(
    isDialog: isDialog,
    librariesProvider: librariesProvider,
    hiddenLibraryKeys: hiddenLibrariesProvider.hiddenLibraryKeys,
    onReorder: (reorderedLibraries) {
      librariesProvider.updateLibraryOrder(reconcileLibraryOrder(reorderedLibraries, librariesProvider.libraries));
      onOrderChanged?.call();
    },
    onToggleVisibility: onToggleVisibility ?? defaultToggleVisibility,
  );

  if (PlatformDetector.isTV()) {
    return showScopedDialog<void>(context: context, builder: (context) => buildSheet(isDialog: true));
  }
  // Use the host supplied by the calling screen when available while keeping
  // this reusable entry point safe for routes without one. isScrollControlled
  // keeps that modal fallback from capping the sheet at ~9/16 of the screen.
  return OverlaySheetController.showAdaptive<void>(
    context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => buildSheet(isDialog: false),
  );
}

/// [sheetOrder] as the sheet shows it, applied to the provider's [current]
/// libraries: rows keep the sheet's order, libraries loaded since the sheet
/// last synced follow in their current order, and libraries that have gone
/// are dropped. A reorder therefore never saves a stale snapshot, which would
/// drop newly loaded libraries or bring back removed ones.
@visibleForTesting
List<MediaLibrary> reconcileLibraryOrder(List<MediaLibrary> sheetOrder, List<MediaLibrary> current) {
  final remaining = {for (final library in current) library.globalKey: library};
  return [for (final library in sheetOrder) ?remaining.remove(library.globalKey), ...remaining.values];
}

class _LibraryManagementSheet extends StatefulWidget {
  final bool isDialog;
  final LibrariesProvider librariesProvider;
  final Set<String> hiddenLibraryKeys;
  final Function(List<MediaLibrary>) onReorder;
  final Function(MediaLibrary) onToggleVisibility;

  const _LibraryManagementSheet({
    this.isDialog = false,
    required this.librariesProvider,
    required this.hiddenLibraryKeys,
    required this.onReorder,
    required this.onToggleVisibility,
  });

  @override
  State<_LibraryManagementSheet> createState() => _LibraryManagementSheetState();
}

class _LibraryManagementSheetState extends State<_LibraryManagementSheet>
    with DpadReorderListMixin<MediaLibrary, _LibraryManagementSheet> {
  late List<MediaLibrary> _tempLibraries;

  final FocusNode _listFocusNode = FocusNode();
  final ScrollController _dialogScrollController = ScrollController();
  final ScrollController _sheetScrollController = ScrollController();

  @override
  List<MediaLibrary> get reorderItems => _tempLibraries;

  @override
  set reorderItems(List<MediaLibrary> value) => _tempLibraries = value;

  @override
  int get lastReorderColumn => 1;

  /// Both layouts scroll the focused row into view: the TV dialog is the D-pad
  /// surface, and the sheet still shows the same cursor to a keyboard user.
  @override
  ScrollController? get reorderScrollController => widget.isDialog ? _dialogScrollController : _sheetScrollController;

  @override
  void onReorderMoveConfirmed() => widget.onReorder(_tempLibraries);

  @override
  void onReorderColumnActivated(int column, int index) {
    final library = _tempLibraries[index];
    if (column == 1) widget.onToggleVisibility(library);
  }

  @override
  void initState() {
    super.initState();
    _tempLibraries = List.of(widget.librariesProvider.libraries);
    widget.librariesProvider.addListener(_onLibrariesChanged);
  }

  /// Follows library loads and changes made while the sheet is open, keeping
  /// the order shown. A move in progress keeps its rows; its confirm is
  /// reconciled against the provider when it is saved.
  void _onLibrariesChanged() {
    if (!mounted || movingIndex != null) return;
    setState(() {
      _tempLibraries = reconcileLibraryOrder(_tempLibraries, widget.librariesProvider.libraries);
      if (focusedIndex >= _tempLibraries.length) {
        focusedIndex = _tempLibraries.isEmpty ? 0 : _tempLibraries.length - 1;
        focusedColumn = 0;
      }
    });
  }

  @override
  void dispose() {
    widget.librariesProvider.removeListener(_onLibrariesChanged);
    _listFocusNode.dispose();
    _dialogScrollController.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  void _reorderLibraries(int oldIndex, int newIndex) {
    setState(() {
      final library = _tempLibraries.removeAt(oldIndex);
      _tempLibraries.insert(newIndex, library);
    });
    // Apply immediately
    widget.onReorder(_tempLibraries);
  }

  /// Whether the libraries span more than one connected server.
  bool _hasMultipleServers() {
    final serverIds = _tempLibraries.where((lib) => lib.serverId != null).map((lib) => lib.serverId).toSet();
    return serverIds.length > 1;
  }

  @override
  Widget build(BuildContext context) {
    // Watch provider to rebuild when hidden libraries change
    final hiddenLibrariesProvider = context.watch<HiddenLibrariesProvider>();
    final hiddenLibraryKeys = hiddenLibrariesProvider.hiddenLibraryKeys;

    if (widget.isDialog) {
      return Dialog(
        child: PopScope(
          canPop: false, // Prevent system back from double-popping; handled by handleReorderKeyEvent
          // ignore: no-empty-block - required callback, blocks system back on Android TV
          onPopInvokedWithResult: (didPop, result) {},
          child: Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  const AppIcon(Symbols.edit_rounded, fill: 1),
                  const SizedBox(width: 12),
                  Text(t.libraries.manageLibraries),
                ],
              ),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const AppIcon(Symbols.close_rounded, fill: 1),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            body: Focus(
              focusNode: _listFocusNode,
              descendantsAreFocusable: false,
              autofocus: InputModeTracker.isKeyboardMode(context),
              onKeyEvent: handleReorderKeyEvent,
              child: _buildFlatLibraryList(_dialogScrollController, hiddenLibraryKeys, shrinkWrap: false),
            ),
          ),
        ),
      );
    }

    return BottomSheetPageScaffold(
      title: t.libraries.manageLibraries,
      icon: Symbols.edit_rounded,
      child: Focus(
        focusNode: _listFocusNode,
        descendantsAreFocusable: false,
        autofocus: InputModeTracker.isKeyboardMode(context),
        onKeyEvent: handleReorderKeyEvent,
        child: _buildFlatLibraryList(_sheetScrollController, hiddenLibraryKeys, shrinkWrap: true),
      ),
    );
  }

  /// Build flat library list with a server subtitle when multiple servers are
  /// connected. Each layout passes its own controller, which is also what
  /// [reorderScrollController] scrolls when the keyboard cursor moves.
  Widget _buildFlatLibraryList(
    ScrollController scrollController,
    Set<String> hiddenLibraryKeys, {
    required bool shrinkWrap,
  }) {
    final showServerNames = _hasMultipleServers();
    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);

    return ReorderableListView.builder(
      scrollController: scrollController,
      shrinkWrap: shrinkWrap,
      onReorderItem: _reorderLibraries,
      itemCount: _tempLibraries.length,
      padding: const EdgeInsets.symmetric(vertical: 8),
      buildDefaultDragHandles: false,
      itemBuilder: (context, index) {
        final library = _tempLibraries[index];
        final showServerName = showServerNames && library.serverName != null;
        final isFocused = isKeyboardMode && index == focusedIndex;
        final isMoving = index == movingIndex;
        return _buildLibraryTile(
          library,
          index,
          hiddenLibraryKeys,
          showServerName: showServerName,
          isFocused: isFocused,
          isMoving: isMoving,
          focusedColumn: isFocused ? focusedColumn : null,
        );
      },
    );
  }

  /// Build a single library tile
  Widget _buildLibraryTile(
    MediaLibrary library,
    int index,
    Set<String> hiddenLibraryKeys, {
    bool showServerName = false,
    bool isFocused = false,
    bool isMoving = false,
    int? focusedColumn,
  }) {
    final isHidden = hiddenLibraryKeys.contains(library.globalKey);
    final colorScheme = Theme.of(context).colorScheme;

    Color? tileColor;
    if (isMoving) {
      tileColor = colorScheme.primaryContainer;
    } else if (isFocused && focusedColumn == 0) {
      tileColor = colorScheme.surfaceContainerHighest;
    }

    final isVisibilityButtonFocused = isFocused && focusedColumn == 1;

    return Opacity(
      key: ValueKey(library.globalKey),
      opacity: isHidden ? 0.5 : 1.0,
      child: ListTile(
        tileColor: tileColor,
        leading: Row(
          mainAxisSize: .min,
          children: [
            ReorderableDragStartListener(
              index: index,
              child: AppIcon(
                isMoving ? Symbols.swap_vert_rounded : Symbols.drag_indicator_rounded,
                fill: 1,
                color: isMoving ? colorScheme.primary : IconTheme.of(context).color?.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(ContentTypeHelper.getLibraryIcon(library.kind.id), fill: 1),
          ],
        ),
        title: Text(library.title),
        subtitle: showServerName
            ? Text(
                library.serverName!,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: .min,
          children: [
            Container(
              decoration: FocusTheme.focusBackgroundDecoration(isFocused: isVisibilityButtonFocused, borderRadius: 20),
              child: IconButton(
                icon: AppIcon(isHidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded, fill: 1),
                tooltip: isHidden ? t.libraries.showLibrary : t.libraries.hideLibrary,
                onPressed: () => widget.onToggleVisibility(library),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
