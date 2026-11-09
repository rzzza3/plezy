import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:plezy/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../focus/focus_theme.dart';
import '../focus/focusable_wrapper.dart';
import '../mixins/context_menu_tap_mixin.dart';
import '../models/download_models.dart';
import '../providers/download_provider.dart';
import '../providers/watch_state_store.dart';
import 'package:provider/provider.dart';

import '../services/settings_service.dart';
import 'settings_builder.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../widgets/collapsible_text.dart';
import '../widgets/download_status_icon.dart';
import '../widgets/watched_indicator.dart';
import '../widgets/optimized_media_image.dart';
import '../utils/platform_detector.dart';
import '../utils/formatters.dart';
import '../utils/media_quality_labels.dart';
import '../widgets/media_context_menu.dart';
import '../widgets/placeholder_container.dart';
import '../theme/mono_tokens.dart';
import '../media/media_server_client.dart';
import '../i18n/strings.g.dart';

/// How an [EpisodeCard] lays out its thumbnail and text.
enum EpisodeCardLayout {
  /// Full-width row: thumbnail on the left, title, summary and metadata on the right.
  row,

  /// Fixed-width tile for a horizontal rail: thumbnail on top, a compact caption below.
  rail,
}

/// Episode card widget with D-pad long-press support
class EpisodeCard extends StatefulWidget {
  final MediaItem episode;
  final MediaServerClient? client;
  final VoidCallback onTap;
  final Future<void> Function(MediaItem source)? onRefresh;
  final Future<void> Function()? onListRefresh;
  final bool autofocus;
  final bool isOffline;
  final String? localPosterPath;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final EpisodeCardLayout layout;

  /// Tile width for [EpisodeCardLayout.rail]; ignored by the row layout.
  final double railWidth;

  /// Whether the rail caption includes a two-line summary.
  final bool railShowsSummary;

  const EpisodeCard({
    super.key,
    required this.episode,
    this.client,
    required this.onTap,
    this.onRefresh,
    this.onListRefresh,
    this.autofocus = false,
    this.isOffline = false,
    this.localPosterPath,
    this.focusNode,
    this.onNavigateUp,
    this.layout = EpisodeCardLayout.row,
    this.railWidth = 240,
    this.railShowsSummary = false,
  });

  /// Height of the caption under a rail tile's thumbnail, at a text scale of 1.
  /// The episode label, a two-line title and a metadata line, plus the summary
  /// when [showsSummary]. Scale it with the ambient [TextScaler].
  static double railCaptionHeight({required bool showsSummary}) => showsSummary ? 128 : 92;

  /// Total rail tile height for [width] under [textScaler].
  static double railHeightFor(double width, TextScaler textScaler, {required bool showsSummary}) =>
      width * 9 / 16 + textScaler.scale(railCaptionHeight(showsSummary: showsSummary));

  @override
  State<EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<EpisodeCard> with ContextMenuTapMixin<EpisodeCard> {
  MediaItem _effectiveEpisode(BuildContext context) => context.withFreshWatchState(widget.episode);

  Widget _buildEpisodeMetaRow(BuildContext context, MediaItem episode, List<String> qualityLabels) {
    final mutedStyle = Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted, fontSize: 12);
    final children = <Widget>[];

    void addSeparator() {
      if (children.isEmpty) return;
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('•', style: mutedStyle),
        ),
      );
    }

    if (episode.durationMs != null) {
      children.add(Text(formatDurationTimestamp(Duration(milliseconds: episode.durationMs!)), style: mutedStyle));
    }

    if (episode.originallyAvailableAt != null) {
      addSeparator();
      children.add(Text(formatFullDate(episode.originallyAvailableAt!), style: mutedStyle));
    }

    if (episode.userRating != null && episode.userRating! > 0) {
      addSeparator();
      children.add(
        Row(
          mainAxisSize: .min,
          children: [
            const Padding(
              padding: .only(top: 2),
              child: AppIcon(Symbols.star_rounded, size: 12, fill: 1, color: Colors.amber),
            ),
            const SizedBox(width: 2),
            Text(
              (episode.userRating! / 2) == (episode.userRating! / 2).truncateToDouble()
                  ? '${(episode.userRating! / 2).toInt()}'
                  : formatRating(episode.userRating! / 2),
              style: mutedStyle,
            ),
          ],
        ),
      );
    }

    for (final label in qualityLabels) {
      addSeparator();
      children.add(Text(label, style: mutedStyle));
    }

    return Wrap(crossAxisAlignment: .center, runSpacing: 4, children: children);
  }

  @override
  Widget build(BuildContext context) {
    return SettingValueBuilder<bool>(
      pref: SettingsService.hideSpoilers,
      builder: (context, hideSpoilers, _) => _buildContent(context, hideSpoilers: hideSpoilers),
    );
  }

  Widget _buildContent(BuildContext context, {required bool hideSpoilers}) {
    final episode = _effectiveEpisode(context);
    final shouldBlur = hideSpoilers && episode.shouldHideSpoiler;
    final isRail = widget.layout == EpisodeCardLayout.rail;

    return Padding(
      padding: isRail ? EdgeInsets.zero : const EdgeInsets.symmetric(vertical: 2),
      // MergeSemantics: one node per card instead of one per text/progress —
      // the per-frame semantics pass scales with node count (see MediaCard).
      // The card has a single action, so merging is safe.
      child: MergeSemantics(
        child: FocusableWrapper(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          enableLongPress: true,
          onNavigateUp: widget.onNavigateUp,
          onSelect: widget.onTap,
          onLongPress: showContextMenuFromTap,
          disableScale: true,
          child: MediaContextMenu(
            key: contextMenuKey,
            item: episode,
            onRefresh: widget.onRefresh,
            onListRefresh: widget.onListRefresh,
            child: InkWell(
              key: Key(episode.id),
              mouseCursor: SystemMouseCursors.click,
              borderRadius: BorderRadius.circular(FocusTheme.defaultBorderRadius),
              onTap: widget.onTap,
              canRequestFocus: false,
              onTapDown: storeTapPosition,
              onLongPress: showContextMenuFromTap,
              onSecondaryTapDown: storeTapPosition,
              onSecondaryTap: showContextMenuFromTap,
              hoverColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.05),
              child: isRail
                  ? _buildRailBody(context, episode, shouldBlur: shouldBlur)
                  : _buildRowBody(context, episode, shouldBlur: shouldBlur),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowBody(BuildContext context, MediaItem episode, {required bool shouldBlur}) {
    final qualityLabels = [...buildMediaQualityLabels(episode), ?buildMediaSizeLabel(episode)];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(FocusTheme.defaultBorderRadius),
      ),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: .start,
        children: [
          SizedBox(
            width: 144,
            child: _buildThumbnailStack(episode, shouldBlur: shouldBlur, size: WatchedIndicatorSize.compact),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                _buildDownloadStatus(episode, (downloadStatusIcon) {
                  final index = episode.index;
                  // The prefix mirrors the server-provided episode
                  // number verbatim, including a genuine episode 0.
                  final titleText = index != null ? '$index. ${episode.title!}' : episode.title!;
                  return Row(
                    children: [
                      if (downloadStatusIcon != null) ...[downloadStatusIcon, const SizedBox(width: 8)],
                      Expanded(
                        child: Text(
                          titleText,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: .bold),
                          maxLines: 2,
                          overflow: .ellipsis,
                        ),
                      ),
                    ],
                  );
                }),

                if (!shouldBlur && episode.summary != null && episode.summary!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  if (PlatformDetector.isTV())
                    Text(
                      episode.summary!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted, height: 1.3),
                      maxLines: 3,
                      overflow: .ellipsis,
                    )
                  else
                    CollapsibleText(
                      text: episode.summary!,
                      maxLines: 3,
                      small: true,
                      suppressExpandSemantics: true,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted, height: 1.3),
                    ),
                ],

                const SizedBox(height: 6),
                _buildEpisodeMetaRow(context, episode, qualityLabels),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thumbnail on top, then "EPISODE N", the title and one metadata line. The
  /// caption has a fixed height (see [EpisodeCard.railCaptionHeight]) so every
  /// tile in a rail lines up regardless of title length.
  Widget _buildRailBody(BuildContext context, MediaItem episode, {required bool shouldBlur}) {
    final theme = Theme.of(context);
    final mutedColor = tokens(context).textMuted;
    final index = episode.index;
    final summary = episode.summary;
    final showsSummary = widget.railShowsSummary;
    final metaParts = [
      if (episode.durationMs != null) formatDurationTimestamp(Duration(milliseconds: episode.durationMs!)),
      if (episode.originallyAvailableAt != null) formatFullDate(episode.originallyAvailableAt!),
    ];

    return SizedBox(
      width: widget.railWidth,
      child: Column(
        crossAxisAlignment: .start,
        children: [
          _buildThumbnailStack(episode, shouldBlur: shouldBlur, size: WatchedIndicatorSize.standard),
          SizedBox(
            height: MediaQuery.textScalerOf(context).scale(EpisodeCard.railCaptionHeight(showsSummary: showsSummary)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
              child: Column(
                crossAxisAlignment: .start,
                children: [
                  _buildDownloadStatus(
                    episode,
                    (downloadStatusIcon) => Row(
                      children: [
                        if (downloadStatusIcon != null) ...[downloadStatusIcon, const SizedBox(width: 6)],
                        Expanded(
                          child: Text(
                            // Server-provided number verbatim, including a genuine episode 0.
                            index != null
                                ? '${t.common.mediaKind.episode} $index'.toUpperCase()
                                : t.common.mediaKind.episode.toUpperCase(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: mutedColor,
                              fontWeight: .bold,
                              letterSpacing: 1,
                            ),
                            maxLines: 1,
                            overflow: .ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    episode.title ?? '',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: .bold, height: 1.25),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
                  if (metaParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      metaParts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(color: mutedColor, fontSize: 12),
                      maxLines: 1,
                      overflow: .ellipsis,
                    ),
                  ],
                  if (showsSummary && !shouldBlur && summary != null && summary.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      style: theme.textTheme.bodySmall?.copyWith(color: mutedColor, height: 1.3),
                      maxLines: 2,
                      overflow: .ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailStack(MediaItem episode, {required bool shouldBlur, required WatchedIndicatorSize size}) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(6)),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: shouldBlur
                ? ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: _buildEpisodeThumbnail(episode),
                    ),
                  )
                : _buildEpisodeThumbnail(episode),
          ),
        ),

        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(6)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withValues(alpha: 0.2)],
              ),
            ),
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
                child: const AppIcon(Symbols.play_arrow_rounded, fill: 1, color: Colors.white, size: 20),
              ),
            ),
          ),
        ),

        Positioned.fill(
          child: WatchedIndicator(item: episode, size: size),
        ),
      ],
    );
  }

  /// Rebuilds [builder] with this episode's download status icon (null when
  /// it has none, and always null offline).
  Widget _buildDownloadStatus(MediaItem episode, Widget Function(Widget? downloadStatusIcon) builder) {
    return Selector<DownloadProvider, _DownloadSlice>(
      selector: (_, p) => _DownloadSlice.from(p.getProgress(episode.globalKey), p.isQueueing(episode.globalKey)),
      builder: (context, slice, _) {
        Widget? downloadStatusIcon;

        // Only show download status in online mode
        if (!widget.isOffline && episode.serverId != null) {
          final status = slice.status;
          final mutedBase = tokens(context).textMuted;

          if (slice.isQueueing) {
            downloadStatusIcon = DownloadQueueingSpinner(size: 12, color: mutedBase);
          } else if (status != null) {
            final iconSize = status == DownloadStatus.downloading ? 14.0 : 12.0;
            downloadStatusIcon = DownloadStatusIcon(
              status: status,
              size: iconSize,
              variant: DownloadStatusIconVariant.muted,
              mutedBase: mutedBase,
              progress: slice.progressPercent,
            );
          }
          // Note: No icon shown if not downloaded (null)
        }

        return builder(downloadStatusIcon);
      },
    );
  }

  Widget _buildEpisodeThumbnail(MediaItem episode) {
    if (widget.isOffline && widget.localPosterPath != null) {
      return OptimizedMediaImage.thumb(
        client: null,
        imagePath: null,
        localFilePath: widget.localPosterPath,
        fit: BoxFit.cover,
        errorWidget: (context, url, error) =>
            const PlaceholderContainer(child: AppIcon(Symbols.movie_rounded, fill: 1, size: 32)),
      );
    }
    if (episode.thumbPath != null) {
      return OptimizedMediaImage.thumb(
        client: widget.client,
        imagePath: episode.thumbPath,
        fit: BoxFit.cover,
        placeholder: (context, url) => const PlaceholderContainer(),
        errorWidget: (context, url, error) =>
            const PlaceholderContainer(child: AppIcon(Symbols.movie_rounded, fill: 1, size: 32)),
      );
    }
    return const PlaceholderContainer(child: AppIcon(Symbols.movie_rounded, fill: 1, size: 32));
  }
}

/// Captures only primitives so Selector equality avoids rebuilds on unrelated
/// download ticks (e.g. other episodes, unused `DownloadProgress` fields).
class _DownloadSlice {
  final DownloadStatus? status;
  final double? progressPercent;
  final bool isQueueing;

  const _DownloadSlice({required this.status, required this.progressPercent, required this.isQueueing});

  factory _DownloadSlice.from(DownloadProgress? p, bool isQueueing) =>
      _DownloadSlice(status: p?.status, progressPercent: p?.progressPercent, isQueueing: isQueueing);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _DownloadSlice &&
        other.status == status &&
        other.progressPercent == progressPercent &&
        other.isQueueing == isQueueing;
  }

  @override
  int get hashCode => Object.hash(status, progressPercent, isQueueing);
}
