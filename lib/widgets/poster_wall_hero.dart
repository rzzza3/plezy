import 'package:flutter/material.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../utils/media_image_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/provider_extensions.dart';
import 'optimized_media_image.dart';
import 'tv_browse_rail.dart';

/// The Library tab's hero, shared by its network pages: a [PosterWall] faded
/// into the page behind a large [title] (or its [logoUrl]), with [actions]
/// (if any) below it.
class PosterWallHero extends StatelessWidget {
  final String title;

  /// A logo shown in white in place of [title], which stands in while it
  /// loads or if it fails.
  final String? logoUrl;
  final List<MediaItem> posters;

  /// Posters to light up on the wall ([PosterWall.highlights]).
  final Map<String, double>? highlights;
  final Widget? actions;

  /// Space under the title block.
  final double bottomPadding;

  const PosterWallHero({
    super.key,
    required this.title,
    this.logoUrl,
    required this.posters,
    this.highlights,
    this.actions,
    this.bottomPadding = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isTv = PlatformDetector.isTV();
    final background = Theme.of(context).scaffoldBackgroundColor;
    // Line up with the section titles below.
    final horizontalPadding = isTv
        ? TvBrowseRailLayout.horizontalInsetForScale(TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context)))
        : 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 700;
        final titleStyle =
            (isTv || !compact ? Theme.of(context).textTheme.displayMedium : null) ??
            Theme.of(context).textTheme.headlineLarge;

        final titleText = Text(
          title,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: titleStyle?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: -1,
            height: 1.05,
          ),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: compact ? 0 : width * 0.3,
              top: 0,
              right: 0,
              bottom: 0,
              child: PosterWall(items: posters, highlights: highlights),
            ),
            // Fade the wall into the page: left behind the copy, then bottom.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    background,
                    background.withValues(alpha: compact ? 0.7 : 0.92),
                    background.withValues(alpha: 0),
                  ],
                  stops: compact ? const [0, 0.5, 1] : const [0.25, 0.45, 0.8],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [background.withValues(alpha: 0), background],
                  stops: const [0.6, 1],
                ),
              ),
            ),
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              bottom: bottomPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: compact ? width : width * 0.55),
                    child: logoUrl == null ? titleText : _logo(logoUrl!, titleText, isTv: isTv, compact: compact),
                  ),
                  if (actions case final actions?) ...[SizedBox(height: isTv ? 32 : 24), actions],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// [url]'s logo in white, left-aligned in a box about a title's size.
Widget _logo(String url, Widget title, {required bool isTv, required bool compact}) {
  // The title, shrunk to the logo's box.
  final fallback = FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: title);
  final height = isTv ? 52.0 : (compact ? 44.0 : 60.0);
  final width = height * 4;
  return Align(
    alignment: Alignment.centerLeft,
    widthFactor: 1,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: width, maxHeight: height),
      child: ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: OptimizedMediaImage(
          imagePath: url,
          width: width,
          height: height,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          imageType: ImageType.logo,
          placeholder: (context, _) => fallback,
          errorWidget: (context, _, _) => fallback,
        ),
      ),
    ),
  );
}

/// Rows of posters tilted in perspective so the wall recedes to the left.
/// Repeats [items] to fill the wall; draws empty tiles while there are none.
///
/// With [highlights], the wall becomes a map of what is in progress: the
/// highlighted posters sit lit near its right edge, where it is closest and
/// clear of the hero's fades, with a ring and their watch progress, and every
/// other poster turns grey and recedes.
class PosterWall extends StatelessWidget {
  static const int rows = 4;
  static const int maxPosters = 48;

  /// Where highlighted posters go, in order: (row, column counted from the
  /// right edge). The middle two rows, which the hero shows whole.
  static const List<(int, int)> highlightSlots = [(1, 2), (2, 1), (1, 5), (2, 4)];

  /// Grey, darker and half see-through, so lit posters stand out. One filter
  /// over the whole wall, not one per poster.
  static const ColorFilter _recede = ColorFilter.matrix([
    0.2126 * 0.62, 0.7152 * 0.62, 0.0722 * 0.62, 0, 0, //
    0.2126 * 0.62, 0.7152 * 0.62, 0.0722 * 0.62, 0, 0, //
    0.2126 * 0.62, 0.7152 * 0.62, 0.0722 * 0.62, 0, 0, //
    0, 0, 0, 0.5, 0,
  ]);

  final List<MediaItem> items;

  /// Watch progress (0 to 1) by poster path, for the posters to light up. The
  /// first [highlightSlots] of [items] found here are lit; null leaves the
  /// wall as it is.
  final Map<String, double>? highlights;

  const PosterWall({super.key, required this.items, this.highlights});

  @override
  Widget build(BuildContext context) {
    final lit = <MediaItem>[];
    final rest = <MediaItem>[];
    for (final item in items) {
      final progress = highlights?[item.posterThumb()];
      (progress != null && lit.length < highlightSlots.length ? lit : rest).add(item);
    }
    final litAt = {for (final (i, item) in lit.indexed) highlightSlots[i]: item};

    return LayoutBuilder(
      builder: (context, constraints) {
        final rowHeight = constraints.maxHeight / 3.2;
        final posterWidth = rowHeight * 2 / 3;
        final gap = rowHeight * 0.07;
        // Overfill: the perspective shrinks the far (left) edge of the wall.
        final columns = (constraints.maxWidth * 1.6 / (posterWidth + gap)).ceil() + 1;
        final placeholder = Colors.white.withValues(alpha: 0.06);

        Widget poster(MediaItem? item) => ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: posterWidth,
            height: rowHeight,
            child: item == null
                ? ColoredBox(color: placeholder)
                : OptimizedMediaImage.poster(
                    client: context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
                    imagePath: item.posterThumb(),
                    width: posterWidth,
                    height: rowHeight,
                    placeholder: (context, _) => ColoredBox(color: placeholder),
                  ),
          ),
        );

        Widget litPoster(MediaItem item) {
          final inset = posterWidth * 0.07;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2.5),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 22, offset: const Offset(0, 8)),
                ],
              ),
              child: Stack(
                children: [
                  poster(item),
                  Positioned(
                    left: inset,
                    right: inset,
                    bottom: inset,
                    child: _WallProgress(
                      value: highlights![item.posterThumb()]!,
                      height: (rowHeight * 0.03).clamp(3, 8),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // [front] draws only the lit posters, over a [back] with gaps where
        // they go; both share one layout, so the two line up.
        Widget wall({required bool front}) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var row = 0; row < rows; row++)
              Padding(
                // Stagger alternate rows by half a poster.
                padding: EdgeInsets.only(bottom: gap, right: row.isOdd ? (posterWidth + gap) / 2 : 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var col = 0; col < columns; col++)
                      Padding(
                        padding: EdgeInsets.only(right: gap),
                        child: switch (litAt[(row, columns - 1 - col)]) {
                          final item? => front ? litPoster(item) : SizedBox(width: posterWidth, height: rowHeight),
                          null when front => SizedBox(width: posterWidth, height: rowHeight),
                          null => poster(rest.isEmpty ? null : rest[(row * columns + col + row * 3) % rest.length]),
                        },
                      ),
                  ],
                ),
              ),
          ],
        );

        final Widget tilted = lit.isEmpty
            ? wall(front: false)
            : Stack(
                children: [
                  ColorFiltered(colorFilter: _recede, child: wall(front: false)),
                  wall(front: true),
                ],
              );

        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            alignment: Alignment.centerRight,
            child: Transform(
              alignment: Alignment.centerRight,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0008)
                ..rotateY(0.45)
                ..rotateZ(-0.04),
              child: tilted,
            ),
          ),
        );
      },
    );
  }
}

/// A lit poster's watch progress: white on a faint track.
class _WallProgress extends StatelessWidget {
  final double value;
  final double height;

  const _WallProgress({required this.value, required this.height});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.25),
        borderRadius: radius,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 3, offset: const Offset(0, 1))],
      ),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0),
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.white, borderRadius: radius),
        ),
      ),
    );
  }
}
