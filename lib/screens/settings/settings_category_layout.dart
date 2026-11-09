import 'package:flutter/material.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/key_event_utils.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/focusable_tab_chip.dart';
import '../../widgets/focused_scroll_scaffold.dart';

/// Accent for the selected category bar and enabled switches in the settings
/// pane. The rest of the app stays monochrome; settings borrows the classic
/// streaming-TV red so the active section reads at a distance.
const settingsAccent = Color(0xFFE50914);

/// One entry in the settings category list. [builder] returns the pane body,
/// which must be a scrollable: either a [CustomScrollView] or a settings page
/// built on [FocusedScrollScaffold] (rendered inline by the pane).
class SettingsCategory {
  final String id;
  final String label;
  final WidgetBuilder builder;

  const SettingsCategory({required this.id, required this.label, required this.builder});
}

/// Category list beside a content pane, after the old Netflix TV settings:
/// large category labels on the left, the selected category's options on the
/// right. Narrow windows put the categories in a chip strip above the pane.
///
/// D-pad: moving focus through the list switches the pane immediately; RIGHT
/// enters the pane, LEFT in the pane returns to the list, and LEFT from the
/// list calls [onExitLeft] (the app sidebar).
class SettingsCategoryLayout extends StatefulWidget {
  final List<SettingsCategory> categories;
  final String selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onExitLeft;

  /// Pinned below the list on wide layouts (the active profile).
  final Widget? railFooter;

  const SettingsCategoryLayout({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    required this.onExitLeft,
    this.railFooter,
  });

  /// Below this width the category list collapses into a chip strip.
  static const double wideBreakpoint = 600;

  static Key categoryKey(String id) => ValueKey('settings_category_$id');

  @override
  State<SettingsCategoryLayout> createState() => SettingsCategoryLayoutState();
}

class SettingsCategoryLayoutState extends State<SettingsCategoryLayout> {
  final Map<String, FocusNode> _categoryNodes = {};
  final _paneScope = FocusScopeNode(debugLabel: 'settings_pane');

  FocusNode _nodeFor(String id) => _categoryNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'settings_category_$id'));

  @override
  void didUpdateWidget(SettingsCategoryLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ids = {for (final c in widget.categories) c.id};
    _categoryNodes.removeWhere((id, node) {
      if (ids.contains(id)) return false;
      node.dispose();
      return true;
    });
  }

  @override
  void dispose() {
    for (final node in _categoryNodes.values) {
      node.dispose();
    }
    _paneScope.dispose();
    super.dispose();
  }

  /// Focus the selected category's entry in the list.
  void focusSelectedCategory() => _nodeFor(_selected.id).requestFocus();

  SettingsCategory get _selected =>
      widget.categories.firstWhere((c) => c.id == widget.selectedId, orElse: () => widget.categories.first);

  void _focusPane() {
    final remembered = _paneScope.focusedChild;
    if (remembered != null && (remembered.context?.mounted ?? false)) {
      remembered.requestFocus();
      return;
    }
    _paneScope.requestFocus();
    _paneScope.nextFocus();
  }

  void _step(int delta) {
    final index = widget.categories.indexOf(_selected) + delta;
    if (index < 0) {
      widget.onExitLeft();
      return;
    }
    if (index >= widget.categories.length) return;
    final next = widget.categories[index];
    widget.onSelected(next.id);
    _nodeFor(next.id).requestFocus();
  }

  KeyEventResult _handlePaneKey(FocusNode _, KeyEvent event) {
    // Only LEFTs no pane control consumed reach here (sliders and segmented
    // groups keep their own).
    if (event.isActionable && event.logicalKey.isLeftKey) {
      focusSelectedCategory();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= SettingsCategoryLayout.wideBreakpoint;
        final pane = _buildPane(context, showTitle: wide);
        if (!wide) {
          return Column(
            crossAxisAlignment: .stretch,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 8), child: _buildChipStrip()),
              Expanded(child: pane),
            ],
          );
        }
        return Row(
          crossAxisAlignment: .stretch,
          children: [
            SizedBox(width: (constraints.maxWidth * 0.3).clamp(200, 300), child: _buildRail(context)),
            Expanded(child: pane),
          ],
        );
      },
    );
  }

  Widget _buildRail(BuildContext context) {
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: .stretch,
        children: [
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
              children: [
                for (final category in widget.categories)
                  _CategoryRailItem(
                    key: SettingsCategoryLayout.categoryKey(category.id),
                    label: category.label,
                    selected: category.id == _selected.id,
                    focusNode: _nodeFor(category.id),
                    onSelect: () => widget.onSelected(category.id),
                    onFocused: () => widget.onSelected(category.id),
                    onLeft: widget.onExitLeft,
                    onRight: _focusPane,
                  ),
              ],
            ),
          ),
          if (widget.railFooter != null)
            Padding(padding: const EdgeInsets.fromLTRB(24, 0, 8, 16), child: widget.railFooter),
        ],
      ),
    );
  }

  Widget _buildChipStrip() {
    return TabChipStrip(
      children: [
        for (final category in widget.categories)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FocusableTabChip(
              key: SettingsCategoryLayout.categoryKey(category.id),
              label: category.label,
              isSelected: category.id == _selected.id,
              focusNode: _nodeFor(category.id),
              onSelect: () => widget.onSelected(category.id),
              onNavigateLeft: () => _step(-1),
              onNavigateRight: () => _step(1),
              onNavigateDown: _focusPane,
            ),
          ),
      ],
    );
  }

  Widget _buildPane(BuildContext context, {required bool showTitle}) {
    final theme = Theme.of(context);
    final category = _selected;
    return Theme(
      data: theme.copyWith(
        switchTheme: theme.switchTheme.copyWith(
          trackColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? settingsAccent : null,
          ),
          thumbColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? Colors.white : null,
          ),
          trackOutlineColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected) ? settingsAccent : null,
          ),
        ),
      ),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _handlePaneKey,
        child: FocusScope(
          node: _paneScope,
          child: Column(
            crossAxisAlignment: .stretch,
            children: [
              if (showTitle)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    category.label.toUpperCase(),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: tokens(context).textMuted,
                      fontWeight: .w600,
                      letterSpacing: 2.4,
                    ),
                  ),
                ),
              Expanded(
                child: EmbeddedSettingsPage(
                  child: KeyedSubtree(
                    key: ValueKey(category.id),
                    child: Builder(builder: category.builder),
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

class _CategoryRailItem extends StatefulWidget {
  final String label;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback onSelect;
  final VoidCallback onFocused;
  final VoidCallback onLeft;
  final VoidCallback onRight;

  const _CategoryRailItem({
    super.key,
    required this.label,
    required this.selected,
    required this.focusNode,
    required this.onSelect,
    required this.onFocused,
    required this.onLeft,
    required this.onRight,
  });

  @override
  State<_CategoryRailItem> createState() => _CategoryRailItemState();
}

class _CategoryRailItemState extends State<_CategoryRailItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final selected = widget.selected;
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (focused) {
        setState(() => _focused = focused);
        if (focused) widget.onFocused();
      },
      onKeyEvent: dpadKeyHandler(onLeft: widget.onLeft, onRight: widget.onRight, onSelect: widget.onRight),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onSelect,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: .stretch,
                children: [
                  AnimatedContainer(duration: t.fast, width: 3, color: selected ? settingsAccent : Colors.transparent),
                  Expanded(
                    child: AnimatedContainer(
                      duration: t.fast,
                      padding: const EdgeInsets.fromLTRB(13, 8, 12, 8),
                      decoration: BoxDecoration(
                        color: _focused ? t.text.withValues(alpha: 0.08) : Colors.transparent,
                        borderRadius: BorderRadius.horizontal(right: Radius.circular(t.radiusSm)),
                      ),
                      child: AnimatedDefaultTextStyle(
                        duration: t.fast,
                        style: Theme.of(context).textTheme.titleLarge!.copyWith(
                          fontSize: selected ? 20 : 17,
                          fontWeight: selected ? .w700 : .w300,
                          color: selected || _focused ? t.text : t.textMuted,
                        ),
                        child: Text(widget.label, maxLines: 1, overflow: .ellipsis),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
