part of '../media_detail_screen.dart';

/// Geometry, type and chrome of the TV detail hero, after Silo's TV detail
/// screen (TvDetailHero, TvSquaredButtons, TvExpandableSynopsis).
abstract final class TvDetailTokens {
  static const double horizontalInset = 50;
  static const double contentMaxWidth = 540;
  static const double editorialSpacing = 7;
  static const double actionGap = 12;

  /// Crisp artwork in the top-right corner: a share of the screen width, at
  /// a 16:9 box trimmed in height.
  static const double artworkWidthFraction = 0.64;
  static const double artworkHeightFraction = 0.70;

  static const double logoHeight = 80;
  static const double minLogoHeight = 40;
  static const double logoMaxWidth = 325;
  static const TextStyle title = TextStyle(fontSize: 42, height: 46 / 42, fontWeight: FontWeight.w900);
  static const Offset titleShadowOffset = Offset(0, 4);
  static const double titleShadowBlur = 16;
  static const TextStyle episodeTitle = TextStyle(fontSize: 20, height: 22 / 20, fontWeight: FontWeight.w800);
  static const double episodeTitleHeight = 24;

  static const TextStyle metadata = TextStyle(fontSize: 14, height: 16 / 14, fontWeight: FontWeight.w500);
  static const double metadataHeight = 18;

  static const TextStyle synopsis = TextStyle(fontSize: 13, height: 17.5 / 13, fontWeight: FontWeight.w400);
  static const int synopsisLines = 3;

  static const TextStyle credit = TextStyle(fontSize: 12, height: 14 / 12, fontWeight: FontWeight.w500);
  static const double creditHeight = 14;
  static const double playbackSummaryHeight = 20;

  static const double actionSize = 38;
  static const double actionIconSize = 18;
  static const double actionSpacing = 9;
  static const double playHorizontalPadding = 27;
  static const double playLabelGap = 9;
  static const TextStyle playLabel = TextStyle(fontSize: 14, fontWeight: FontWeight.w600);
  static const TextStyle actionLabel = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// Horizontal room a focused circle adds around its label.
  static const double actionLabelChrome = 54;
  static const Duration actionExpand = Duration(milliseconds: 280);
  static const Duration actionLabelFade = Duration(milliseconds: 180);
  static const Duration actionLabelDelay = Duration(milliseconds: 60);

  static TextStyle ink(BuildContext context, TextStyle style, [double alpha = 1]) =>
      style.copyWith(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha));

  /// Ink alphas over the theme's on-surface colour. Silo is dark-only and
  /// uses white; Plezy's light themes need the same hierarchy in dark ink.
  static const double episodeTitleAlpha = 0.94;
  static const double metadataAlpha = 0.88;
  static const double synopsisAlpha = 0.82;
  static const double creditAlpha = 0.62;
  static const double actionFillAlpha = 0.10;
  static const double actionBorderAlpha = 0.34;
  static const double actionFocusedBorderAlpha = 0.12;
  static const double actionBorderWidth = 1.4;
  static const double actionFocusedBorderWidth = 0.8;
}

/// The TV detail page surface: opaque, with the item's artwork crisp in the
/// top-right corner and dissolving into the page at its leading and lower
/// edges.
class _TvDetailArtwork extends StatelessWidget {
  final MediaItem item;
  final MediaServerClient? client;
  final String? Function(String artworkPath)? localArtworkPathResolver;
  final bool allowNetwork;

  const _TvDetailArtwork({
    required this.item,
    required this.client,
    required this.localArtworkPathResolver,
    required this.allowNetwork,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final aspect = size.width / size.height;
    // Whole device pixels: a fractional leading edge leaves the mask's first
    // pixel column unmasked, a visible seam down the artwork's edge.
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    double snap(double logical) => (logical * pixelRatio).floorToDouble() / pixelRatio;
    final width = snap(size.width * TvDetailTokens.artworkWidthFraction);
    final height = snap(size.width * 9 / 16 * TvDetailTokens.artworkHeightFraction);

    return ColoredBox(
      color: surface,
      child: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: width,
          height: height,
          child: RepaintBoundary(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                colors: [Colors.transparent, Colors.white, Colors.white],
                stops: [0, 0.68, 1],
              ).createShader(rect),
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Color.fromRGBO(255, 255, 255, 0.88),
                    Color.fromRGBO(255, 255, 255, 0.58),
                    Color.fromRGBO(255, 255, 255, 0.24),
                    Colors.transparent,
                  ],
                  stops: [0, 0.38, 0.52, 0.68, 0.81, 0.90],
                ).createShader(rect),
                child: CyclingMediaBackdrop(
                  mediaKey: item.globalKey,
                  imagePaths: item.heroRotationPaths(containerAspectRatio: aspect),
                  fallbackImagePaths: [
                    ...item.heroArtCandidates(containerAspectRatio: aspect),
                    ?item.thumbPath,
                  ],
                  client: client,
                  localArtworkPathResolver: localArtworkPathResolver,
                  allowNetwork: allowNetwork,
                  // Requested at full-screen size, like the home spotlight, so
                  // both share the cached transcode.
                  width: size.width,
                  height: size.height,
                  fallbackColor: surface,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular TV detail action. Focus inverts it to a white disc and widens
/// it to a capsule that reveals [label].
class _TvDetailCircleAction extends StatelessWidget {
  final Widget icon;
  final String? label;
  final bool focused;
  final VoidCallback? onPressed;
  final Color? foregroundColor;

  const _TvDetailCircleAction({
    required this.icon,
    required this.label,
    required this.focused,
    required this.onPressed,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final showLabel = focused && label != null && label.isNotEmpty;
    final ink = Theme.of(context).colorScheme.onSurface;
    final page = Theme.of(context).scaffoldBackgroundColor;
    final restingForeground = foregroundColor ?? ink;
    final foreground = focused
        ? page
        : onPressed == null
        ? restingForeground.withValues(alpha: 0.38)
        : restingForeground;
    var width = TvDetailTokens.actionSize;
    if (showLabel) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: TvDetailTokens.actionLabel),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      width = painter.width + TvDetailTokens.actionLabelChrome;
      painter.dispose();
    }

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: DevicePerformance.reducedDuration(TvDetailTokens.actionExpand),
          curve: Curves.easeOutCubic,
          width: width,
          height: TvDetailTokens.actionSize,
          clipBehavior: Clip.antiAlias,
          decoration: ShapeDecoration(
            color: focused ? ink : ink.withValues(alpha: TvDetailTokens.actionFillAlpha),
            shape: StadiumBorder(
              side: BorderSide(
                color: focused
                    ? page.withValues(alpha: TvDetailTokens.actionFocusedBorderAlpha)
                    : ink.withValues(alpha: TvDetailTokens.actionBorderAlpha),
                width: focused ? TvDetailTokens.actionFocusedBorderWidth : TvDetailTokens.actionBorderWidth,
              ),
            ),
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: foreground, size: TvDetailTokens.actionIconSize),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icon,
                if (showLabel) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: DevicePerformance.reducedDuration(
                        TvDetailTokens.actionLabelDelay + TvDetailTokens.actionLabelFade,
                      ),
                      curve: const Interval(1 / 4, 1),
                      builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TvDetailTokens.actionLabel.copyWith(color: foreground),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
