import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import 'clickable_cursor.dart';
import 'optimized_media_image.dart';
import 'poster_wall_hero.dart' show PosterWall;
import 'tv_browse_rail.dart';

/// The Library hero's accent: the title to resume in the copy, the ring on
/// its poster and the watch progress on the fanned posters.
const Color libraryHeroAccent = Color(0xFFF2B53A);

/// How much larger than the reference layout (a 420-high hero on desktop)
/// the hero draws its copy, for the [actions] built outside it to match.
/// TVs render at many logical sizes (a 1080p panel is often 960x540), so the
/// hero sizes its type from its own height rather than from the platform.
class LibraryHeroScale extends InheritedWidget {
  final double scale;

  const LibraryHeroScale({super.key, required this.scale, required super.child});

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LibraryHeroScale>()?.scale ?? 1;

  @override
  bool updateShouldNotify(LibraryHeroScale oldWidget) => scale != oldWidget.scale;
}

/// A poster in the Library hero's fan: [item] with its watch [progress]
/// (0 to 1), or none for a title not started.
typedef LibraryHeroPoster = ({MediaItem item, double? progress});

/// The Library tab's hero: an [eyebrow], a large [headline], a [subtitle] and
/// [actions] on the left, over a dimmed [PosterWall] of [wallItems] on the
/// right with up to three [posters] fanned out in front of it. The first
/// poster is the one Resume plays, and wears the accent ring.
///
/// On phones the fan sits above the copy instead of beside it.
class LibraryResumeHero extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final InlineSpan? subtitle;
  final Widget actions;
  final List<MediaItem> wallItems;
  final List<LibraryHeroPoster> posters;

  /// Tapping a fanned poster (pointer only; D-pad users have Resume and the
  /// Continue Watching row).
  final ValueChanged<MediaItem>? onPosterTap;

  /// Space under the copy.
  final double bottomPadding;

  const LibraryResumeHero({
    super.key,
    required this.eyebrow,
    required this.headline,
    this.subtitle,
    required this.actions,
    required this.wallItems,
    required this.posters,
    this.onPosterTap,
    this.bottomPadding = 40,
  });

  /// Darker and half-faded, so the wall reads as texture behind the fan.
  static const ColorFilter _dim = ColorFilter.matrix([
    0.42, 0, 0, 0, 0, //
    0, 0.42, 0, 0, 0, //
    0, 0, 0.42, 0, 0, //
    0, 0, 0, 0.75, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final background = Theme.of(context).scaffoldBackgroundColor;
    final topInset = isTv ? 0.0 : MediaQuery.paddingOf(context).top;
    // Line up with the section titles below.
    final horizontalPadding = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compact = !isTv && width < 700;
        final scale = compact ? 1.0 : (height / 420).clamp(0.78, 1.6);

        final copy = LibraryHeroScale(
          scale: scale,
          child: _Copy(
            eyebrow: eyebrow,
            headline: headline,
            subtitle: subtitle,
            actions: actions,
            compact: compact,
            scale: scale,
          ),
        );

        if (compact) {
          final cardHeight = math.min(180.0, height * 0.3);
          return Stack(
            fit: StackFit.expand,
            children: [
              ColorFiltered(
                colorFilter: _dim,
                child: PosterWall(items: wallItems),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      background.withValues(alpha: 0.7),
                      background.withValues(alpha: 0.2),
                      background.withValues(alpha: 0.85),
                      background,
                    ],
                    stops: const [0, 0.25, 0.5, 0.62],
                  ),
                ),
              ),
              if (posters.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: topInset + 20,
                  child: Center(
                    child: _PosterFan(posters: posters, cardHeight: cardHeight, onTap: onPosterTap),
                  ),
                ),
              Positioned(left: horizontalPadding, right: horizontalPadding, bottom: bottomPadding, child: copy),
            ],
          );
        }

        // The fan takes the right of the hero; the copy, the left.
        final cardHeight = math.min(height * 0.54, 300 * scale);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: width * 0.34,
              top: 0,
              right: 0,
              bottom: 0,
              child: ColorFiltered(
                colorFilter: _dim,
                child: PosterWall(items: wallItems),
              ),
            ),
            // Fade the wall into the page behind the copy, then at the bottom
            // where the first row starts.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [background, background, background.withValues(alpha: 0.7), background.withValues(alpha: 0)],
                  stops: const [0, 0.36, 0.48, 0.7],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    background.withValues(alpha: 0.5),
                    background.withValues(alpha: 0),
                    background.withValues(alpha: 0),
                    background,
                  ],
                  stops: const [0, 0.18, 0.72, 1],
                ),
              ),
            ),
            // The copy takes the width its buttons need, up to most of the
            // hero; the fan shrinks into what is left.
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              top: topInset,
              bottom: bottomPadding,
              child: Row(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: width * 0.62 - horizontalPadding),
                    child: copy,
                  ),
                  SizedBox(width: 24 * scale),
                  Expanded(
                    child: posters.isEmpty
                        ? const SizedBox.shrink()
                        : LayoutBuilder(
                            builder: (context, space) => Center(
                              child: _PosterFan(
                                posters: posters,
                                cardHeight: math.min(cardHeight, space.maxWidth / _PosterFan.widthPerCardHeight),
                                onTap: onPosterTap,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Copy extends StatelessWidget {
  final String eyebrow;
  final String headline;
  final InlineSpan? subtitle;
  final Widget actions;
  final bool compact;
  final double scale;

  const _Copy({
    required this.eyebrow,
    required this.headline,
    required this.subtitle,
    required this.actions,
    required this.compact,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final headlineSize = compact ? 34.0 : 52.0 * scale;
    final bodySize = compact ? 14.0 : math.max(13.0, 16.0 * scale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          eyebrow.toUpperCase(),
          style: theme.textTheme.labelMedium?.copyWith(
            color: onSurface.withValues(alpha: 0.6),
            fontSize: math.max(10.5, 12 * scale),
            fontWeight: FontWeight.w600,
            letterSpacing: 1.4,
          ),
        ),
        SizedBox(height: 12 * scale),
        // Narrow enough to break into two even lines, as a display headline.
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: headlineSize * 7.6),
          child: Text(
            headline,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.displayMedium?.copyWith(
              color: onSurface,
              fontSize: headlineSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -headlineSize * 0.025,
              height: 1.04,
            ),
          ),
        ),
        if (subtitle case final subtitle?) ...[
          SizedBox(height: 14 * scale),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: bodySize * 30),
            child: Text.rich(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: onSurface.withValues(alpha: 0.78),
                fontSize: bodySize,
                height: 1.4,
              ),
            ),
          ),
        ],
        SizedBox(height: compact ? 20 : 26 * scale),
        // Wide enough for the pills on any screen; phones scroll them.
        SingleChildScrollView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, child: actions),
      ],
    );
  }
}

/// Up to three posters fanned out: the first in front, tilted left, with the
/// accent ring; the others behind it to the right.
class _PosterFan extends StatelessWidget {
  final List<LibraryHeroPoster> posters;
  final double cardHeight;
  final ValueChanged<MediaItem>? onTap;

  const _PosterFan({required this.posters, required this.cardHeight, required this.onTap});

  /// Per slot: (x step in card widths, y offset in card heights, turn in radians).
  /// The fan's width over its card height: three cards a little apart, plus
  /// room for the tilt.
  static const double widthPerCardHeight = 2 / 3 * (1 + 2 * 1.02) + 0.12;

  static const _slots = [(0.0, 0.04, -0.035), (1.0, -0.05, -0.012), (2.0, 0.0, 0.06)];

  @override
  Widget build(BuildContext context) {
    final cardWidth = cardHeight * 2 / 3;
    final step = cardWidth * 1.02;
    final shown = posters.take(_slots.length).toList();
    final width = cardWidth + step * (shown.length - 1);
    // Room for the tilt and the vertical offsets.
    final height = cardHeight * 1.14;

    Widget card(int index) {
      final (dx, dy, turn) = _slots[index];
      final poster = shown[index];
      return Positioned(
        left: dx * step,
        top: (height - cardHeight) / 2 + dy * cardHeight,
        child: Transform.rotate(
          angle: turn,
          child: _FanCard(
            item: poster.item,
            progress: poster.progress,
            highlighted: index == 0,
            width: cardWidth,
            height: cardHeight,
            onTap: onTap == null ? null : () => onTap!(poster.item),
          ),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        // The first poster paints last, in front.
        children: [for (var i = shown.length - 1; i >= 0; i--) card(i)],
      ),
    );
  }
}

class _FanCard extends StatelessWidget {
  final MediaItem item;
  final double? progress;
  final bool highlighted;
  final double width;
  final double height;
  final VoidCallback? onTap;

  const _FanCard({
    required this.item,
    required this.progress,
    required this.highlighted,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(10);
    final placeholder = Colors.white.withValues(alpha: 0.06);
    final barHeight = (height * 0.022).clamp(4.0, 8.0);

    final card = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: highlighted
            ? Border.all(color: libraryHeroAccent, width: 2.5)
            : Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            OptimizedMediaImage.poster(
              client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
              imagePath: item.posterThumb(),
              width: width,
              height: height,
              placeholder: (context, _) => ColoredBox(color: placeholder),
            ),
            if (progress case final progress?)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: barHeight,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: const ColoredBox(color: libraryHeroAccent),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return card;
    return Semantics(
      button: true,
      label: item.isEpisode ? (item.grandparentTitle ?? item.displayTitle) : item.displayTitle,
      child: ClickableCursor(
        child: GestureDetector(onTap: onTap, child: card),
      ),
    );
  }
}
