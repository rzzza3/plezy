import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_action_bar.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/app_locale_utils.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../providers/multi_server_provider.dart';
import '../services/silo_client.dart';
import '../utils/app_logger.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../widgets/clickable_cursor.dart';
import '../widgets/hub_section.dart';
import '../widgets/tv_browse_rail.dart';
import 'media_detail_screen.dart';

/// The Library tab's Calendar: a strip of days (the 3 before today, today and
/// the 6 after) over the TV episodes airing on the selected day. Moving
/// through the strip switches the day; the row below reuses Home's rails.
///
/// One `GET /api/v2/calendar` per connected Silo server covers the window.
/// The selected day's episodes are then read in full so their cards get the
/// episode still and open like any other episode.
class LibraryCalendarSection extends StatefulWidget {
  /// UP from the day strip.
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateToSidebar;

  /// DOWN from the episodes, or from the strip on a day without any.
  final VoidCallback? onNavigateDown;

  /// Focus entered the section, so the page can scroll it into view.
  final VoidCallback? onFocusEntered;

  const LibraryCalendarSection({
    super.key,
    required this.onNavigateUp,
    required this.onNavigateToSidebar,
    this.onNavigateDown,
    this.onFocusEntered,
  });

  @override
  State<LibraryCalendarSection> createState() => LibraryCalendarSectionState();
}

class LibraryCalendarSectionState extends State<LibraryCalendarSection> {
  static const int daysBefore = 3;
  static const int daysAfter = 6;
  static const Duration _staleAfter = Duration(minutes: 30);

  final _stripKey = GlobalKey<FocusableActionBarState>();
  final _tvRailKey = GlobalKey<TvBrowseRailState>();
  final _hubKey = GlobalKey<HubSectionState>();
  final _focusMemory = HubFocusMemory();
  late final List<FocusNode> _dayNodes = [
    for (var i = 0; i <= daysBefore + daysAfter; i++) FocusNode(debugLabel: 'calendar_day_$i'),
  ];

  late DateTime _today;
  int _selected = daysBefore;
  bool _loading = true;
  bool _failed = false;
  bool _hasSilo = true;
  DateTime? _loadedAt;
  int _generation = 0;

  /// Calendar episodes per local ISO date, from the calendar read.
  Map<String, List<MediaItem>> _byDate = const {};

  /// Full reads of calendar episodes, by item id.
  final Map<String, MediaItem> _details = {};
  final Set<String> _detailsRequested = {};

  /// Air instants, by `serverId/itemId`, where the server knows the air time.
  Map<String, DateTime> _airAt = const {};

  /// Series backdrops, by `serverId/seriesId`, for episodes without a still
  /// of their own (most that have not aired yet).
  final Map<String, String> _seriesArt = {};
  final Set<String> _seriesRequested = {};

  // Memoized on its inputs so rebuilds hand the rails the same hub list and
  // they keep their scroll position.
  List<MediaHub>? _hubs;
  Object? _hubsKey;

  @override
  void initState() {
    super.initState();
    _today = _dateOnly(DateTime.now());
    for (var i = 0; i < _dayNodes.length; i++) {
      final index = i;
      _dayNodes[i].addListener(() {
        if (_dayNodes[index].hasFocus) _select(index);
      });
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final node in _dayNodes) {
      node.dispose();
    }
    super.dispose();
  }

  static DateTime _dateOnly(DateTime time) => DateTime(time.year, time.month, time.day);

  static String _iso(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  DateTime _dayAt(int index) => DateTime(_today.year, _today.month, _today.day + index - daysBefore);

  /// Focus the selected day in the strip, coming DOWN from above. With no
  /// Silo server the section isn't shown, so focus carries on down.
  void requestFocus() {
    if (!_hasSilo) return widget.onNavigateDown?.call();
    _dayNodes[_selected].requestFocus();
  }

  /// Reload when the day rolled over or the last read is old.
  void refreshIfStale() {
    final loadedAt = _loadedAt;
    final today = _dateOnly(DateTime.now());
    if (today != _today || loadedAt == null || DateTime.now().difference(loadedAt) > _staleAfter) {
      if (today != _today) {
        _today = today;
        _selected = daysBefore;
      }
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final clients = context
        .read<MultiServerProvider>()
        .serverManager
        .visibleOnlineClients
        .values
        .whereType<SiloClient>()
        .toList();
    if (clients.isEmpty) {
      setState(() {
        _hasSilo = false;
        _loading = false;
      });
      return;
    }
    setState(() {
      _hasSilo = true;
      _loading = _byDate.isEmpty;
      _failed = false;
    });

    final first = _dayAt(0);
    final last = _dayAt(daysBefore + daysAfter);
    var failures = 0;
    final results = await Future.wait([
      for (final client in clients)
        client.fetchCalendarEpisodes(first, last).catchError((Object error) {
          failures++;
          appLogger.w('Library calendar: read failed for ${client.serverId} (${error.runtimeType})');
          return const <({MediaItem item, DateTime? airAt})>[];
        }),
    ]);
    if (!mounted || generation != _generation) return;

    final byDate = <String, List<MediaItem>>{};
    final airAt = <String, DateTime>{};
    for (final (:item, airAt: at) in results.expand((episodes) => episodes)) {
      byDate.putIfAbsent(item.originallyAvailableAt!, () => []).add(item);
      if (at != null) airAt[_itemKey(item)] = at;
    }
    for (final entry in byDate.entries) {
      entry.value.sort(_compareEpisodes);
      // A season dropped at once is one card: its first episode.
      final seen = <String>{};
      entry.value.retainWhere((item) => seen.add('${item.serverId}/${item.grandparentId ?? item.id}'));
    }
    setState(() {
      _byDate = byDate;
      _airAt = airAt;
      _loading = false;
      _failed = failures == clients.length;
      _loadedAt = DateTime.now();
    });
    unawaited(_resolveSelectedDay());
  }

  static int _compareEpisodes(MediaItem a, MediaItem b) {
    final byShow = (a.grandparentTitle ?? '').toLowerCase().compareTo((b.grandparentTitle ?? '').toLowerCase());
    if (byShow != 0) return byShow;
    final bySeason = (a.parentIndex ?? 0).compareTo(b.parentIndex ?? 0);
    return bySeason != 0 ? bySeason : (a.index ?? 0).compareTo(b.index ?? 0);
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    unawaited(_resolveSelectedDay());
  }

  /// Read the selected day's episodes in full, once each.
  Future<void> _resolveSelectedDay() async {
    final pending = [
      for (final item in _byDate[_iso(_dayAt(_selected))] ?? const <MediaItem>[])
        if (_detailsRequested.add(item.id)) item,
    ];
    if (pending.isEmpty) return;
    final clients = context.read<MultiServerProvider>().serverManager.visibleOnlineClients;
    final generation = _generation;
    final resolved = await Future.wait([
      for (final stub in pending)
        () async {
          final client = clients[stub.serverId];
          if (client == null) return null;
          try {
            final item = await client.fetchItem(stub.id);
            return item == null || item.kind != MediaKind.episode ? null : _merge(stub, item);
          } on Exception catch (error) {
            appLogger.w('Library calendar: episode read failed (${error.runtimeType})');
            return null;
          }
        }(),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      for (final item in resolved) {
        if (item != null) _details[item.id] = item;
      }
    });

    final series = <String, MediaItem>{
      for (final (index, stub) in pending.indexed)
        if (_artFor(resolved[index] ?? stub) == null && stub.grandparentId != null)
          if (_seriesRequested.add(_seriesKey(stub))) _seriesKey(stub): stub,
    };
    if (series.isEmpty) return;
    final art = await Future.wait([
      for (final stub in series.values)
        () async {
          try {
            return (await clients[stub.serverId]?.fetchItem(stub.grandparentId!))?.artPath;
          } on Exception catch (error) {
            appLogger.w('Library calendar: series read failed (${error.runtimeType})');
            return null;
          }
        }(),
    ]);
    if (!mounted || generation != _generation) return;
    setState(() {
      for (final (index, key) in series.keys.indexed) {
        final path = art[index];
        if (path != null) _seriesArt[key] = path;
      }
    });
  }

  static String _itemKey(MediaItem item) => '${item.serverId}/${item.id}';

  /// Whether [item] airs later than now: by its air time when the server
  /// knows it, else by its local air date.
  bool _isUpcoming(MediaItem item) {
    final airAt = _airAt[_itemKey(item)];
    if (airAt != null) return airAt.isAfter(DateTime.now());
    final date = item.originallyAvailableAt;
    return date != null && date.compareTo(_iso(DateTime.now())) > 0;
  }

  /// An episode that has not aired has nothing to play, so it opens its show
  /// on the latest season instead. Aired episodes keep the normal activation.
  Future<void> _activate(MediaItem item) async {
    if (_isUpcoming(item)) {
      await Navigator.push<bool>(
        context,
        mediaDetailRoute(metadata: mediaDetailNavigationTargetFor(item).metadata, openLatestSeason: true),
      );
    } else {
      await navigateToMediaItem(context, item);
    }
  }

  static String _seriesKey(MediaItem item) => '${item.serverId}/${item.grandparentId}';

  static String? _artFor(MediaItem item) => item.thumbPath ?? item.artPath;

  /// The episode's still, else its own backdrop, else the series backdrop.
  MediaItem _withArt(MediaItem item) {
    if (item.thumbPath != null) return item;
    final art = item.artPath ?? _seriesArt[_seriesKey(item)];
    return art == null ? item : item.copyWith(thumbPath: art);
  }

  /// The full read, keeping what only the calendar carries: the series poster
  /// and the local air date the strip buckets by.
  static MediaItem _merge(MediaItem stub, MediaItem detail) => detail.copyWith(
    grandparentTitle: detail.grandparentTitle ?? stub.grandparentTitle,
    grandparentThumbPath: detail.grandparentThumbPath ?? stub.grandparentThumbPath,
    originallyAvailableAt: stub.originallyAvailableAt,
  );

  String _dayTitle(DateTime day) {
    if (day == _today) return t.libraryHome.today;
    return DateFormat.MMMMEEEEd(LocaleSettings.currentLocale.intlLocaleName).format(day);
  }

  List<MediaHub> _hubsForSelected() {
    final day = _dayAt(_selected);
    final stubs = _byDate[_iso(day)] ?? const <MediaItem>[];
    final resolved = [for (final stub in stubs) _details[stub.id] ?? stub];
    final key = (
      day,
      Object.hashAll(resolved),
      Object.hashAll([for (final item in resolved) _seriesArt[_seriesKey(item)]]),
      t.libraryHome.today,
    );
    if (_hubs != null && key == _hubsKey) return _hubs!;
    _hubsKey = key;
    final items = [for (final item in resolved) _withArt(item)];
    return _hubs = items.isEmpty
        ? const []
        : [
            MediaHub(
              id: 'library_calendar',
              identifier: 'library_calendar',
              title: _dayTitle(day),
              type: 'episode',
              size: items.length,
              more: false,
              items: items,
            ),
          ];
  }

  /// DOWN from the day strip: the episodes. While they load, focus stays on
  /// the strip instead of skipping past a row that is about to appear.
  void _focusRow() {
    final tvRail = _tvRailKey.currentState;
    final hub = _hubKey.currentState;
    if (tvRail != null) {
      tvRail.requestFocus();
    } else if (hub != null) {
      hub.requestFocusFromMemory();
    } else if (!_loading) {
      widget.onNavigateDown?.call();
    }
  }

  /// UP from the section below: the episodes, else the day strip.
  void requestFocusFromBelow() {
    if (!_hasSilo) return widget.onNavigateUp();
    if (_tvRailKey.currentState != null || _hubKey.currentState != null) {
      _focusRow();
    } else {
      requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasSilo) return const SizedBox.shrink();
    final isTv = PlatformDetector.isTV();
    // Line up with the titles of the TV rails above and below.
    final inset = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;
    final theme = Theme.of(context);
    final hubs = _hubsForSelected();

    final Widget row;
    if (_loading) {
      row = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else if (_failed || hubs.isEmpty) {
      row = Padding(
        padding: EdgeInsets.fromLTRB(inset, 24, inset, 48),
        child: Text(
          _failed ? t.libraryHome.calendarFailed : t.libraryHome.nothingAiring,
          style: theme.textTheme.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.6)),
        ),
      );
    } else if (isTv) {
      row = TvBrowseRail(
        key: _tvRailKey,
        hubs: hubs,
        focusMemory: _focusMemory,
        onNavigateUp: requestFocus,
        onNavigateToSidebar: widget.onNavigateToSidebar,
        onBack: widget.onNavigateToSidebar,
        onNavigateDown: widget.onNavigateDown,
        tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
        extraItemGap: 16,
        showHubHeaders: false,
        onActivateItem: (hub, item) {
          if (!_isUpcoming(item)) return false;
          unawaited(_activate(item));
          return true;
        },
      );
    } else {
      row = HubSection(
        key: _hubKey,
        hub: hubs.first,
        focusMemory: _focusMemory,
        icon: Symbols.calendar_month_rounded,
        showHeader: false,
        onItemTap: (item) => unawaited(_activate(item)),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(inset, isTv ? 24 : 16, inset, 16),
            child: Text(
              t.libraryHome.calendar,
              // The rails' own title styles, so it reads as a sibling of
              // Continue Watching.
              style: isTv
                  ? TvSectionHeaderTokens.title.copyWith(color: theme.colorScheme.onSurface)
                  : theme.textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: _buildStrip(context, isTv: isTv),
            ),
          ),
          SizedBox(height: isTv ? 12 : 8),
          row,
        ],
      ),
    );
  }

  Widget _buildStrip(BuildContext context, {required bool isTv}) {
    final locale = LocaleSettings.currentLocale.intlLocaleName;
    final weekday = DateFormat.E(locale);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FocusableActionBar(
          key: _stripKey,
          spacing: 4,
          revealFocusedAction: true,
          onNavigateLeft: widget.onNavigateToSidebar,
          onNavigateUp: widget.onNavigateUp,
          onNavigateDown: _focusRow,
          onBack: widget.onNavigateToSidebar,
          actions: [
            for (var i = 0; i < _dayNodes.length; i++)
              FocusableAction(
                debugLabel: 'calendar_day_$i',
                focusNode: _dayNodes[i],
                onPressed: () {
                  _select(i);
                  _focusRow();
                },
                builder: (context, state) {
                  final day = _dayAt(i);
                  return _DayChip(
                    weekday: day == _today ? t.libraryHome.today : weekday.format(day),
                    dayOfMonth: '${day.day}',
                    selected: i == _selected,
                    focused: state.showFocus,
                    duration: state.animationDuration,
                    large: isTv,
                    onTap: () => _select(i),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String weekday;
  final String dayOfMonth;
  final bool selected;
  final bool focused;
  final bool large;
  final Duration duration;
  final VoidCallback onTap;

  const _DayChip({
    required this.weekday,
    required this.dayOfMonth,
    required this.selected,
    required this.focused,
    required this.large,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final foreground = focused ? Colors.black : Colors.white;
    final Color background = focused
        ? Colors.white
        : selected
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.transparent;

    return ClickableCursor(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: duration,
          constraints: BoxConstraints(minWidth: large ? 56 : 48),
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: large ? 6 : 4),
          decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(10)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                weekday.toUpperCase(),
                style: textTheme.labelSmall?.copyWith(
                  color: foreground.withValues(alpha: focused || selected ? 1 : 0.7),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
              ),
              Text(
                dayOfMonth,
                style: (large ? textTheme.titleLarge : textTheme.titleMedium)?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
