part of '../media_detail_screen.dart';

/// Geometry, type and chrome of the TV detail hero, after Silo's TV detail
/// screen (TvDetailHero, TvSquaredButtons, TvExpandableSynopsis).
abstract final class TvDetailTokens {
  static const double horizontalInset = 50;
  static const double contentMaxWidth = 540;
  static const double editorialSpacing = 7;
  static const double actionGap = 12;

  /// The hero's bottom inset, as a share of the screen height, and its floor
  /// and ceiling before TV scaling.
  static const double heroBottomFraction = 0.09;
  static const double minHeroBottom = 32;
  static const double maxHeroBottom = 72;

  /// Top inset of the page under the hero, and the logo or title centred
  /// there above the rails.
  static const double railsPageTop = 28;
  static const double railsPageLogoHeight = 64;
  static const double railsPageLogoMaxWidth = 360;
  static const double railsPageLogoGap = 8;
  static const Duration pageSlide = Duration(milliseconds: 650);

  /// Over the hero-to-rails scroll: the hero and its scrims are gone by 60%
  /// of the way, and the rails fade in over the second half.
  static const Interval heroFade = Interval(0, 0.6, curve: Curves.easeOut);
  static const Interval railsFade = Interval(0.3, 1, curve: Curves.easeIn);

  /// Blur of the artwork behind the rails page.
  static const double railsArtworkBlur = 24;

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

  /// Widest a pill's label grows before it ellipsizes; download states carry
  /// long sentences as their label.
  static const double actionLabelMaxWidth = 150;

  /// Horizontal room a pill adds around its label: icon, gap and padding.
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

/// The TV detail page surface: the item's artwork full-bleed, washed toward
/// the page at its leading and lower edges so the hero text over it reads.
/// It blurs while [blurred] is set, as the page scrolls down to the rails.
class _TvDetailArtwork extends StatelessWidget {
  final MediaItem item;
  final MediaServerClient? client;
  final String? Function(String artworkPath)? localArtworkPathResolver;
  final bool allowNetwork;
  final ValueNotifier<bool> blurred;

  const _TvDetailArtwork({
    required this.item,
    required this.client,
    required this.localArtworkPathResolver,
    required this.allowNetwork,
    required this.blurred,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final surface = Theme.of(context).scaffoldBackgroundColor;
    final aspect = size.width / size.height;

    return ColoredBox(
      color: surface,
      child: ValueListenableBuilder<bool>(
        valueListenable: blurred,
        // Same travel as the hero-to-rails scroll, so the blur lands with it.
        builder: (context, isBlurred, child) => TweenAnimationBuilder<double>(
          tween: Tween(end: isBlurred ? 1 : 0),
          duration: TvDetailTokens.pageSlide,
          curve: Curves.easeInOutCubic,
          child: child,
          builder: (context, progress, child) {
            if (progress == 0) return child!;
            final sigma = TvDetailTokens.railsArtworkBlur * progress;
            return ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
              child: child,
            );
          },
        ),
        child: RepaintBoundary(
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
    );
  }
}

/// The hero's scrims: a wash from the leading edge behind the text and one up
/// from the bottom behind the actions. They lift off the rails page, which
/// shows the artwork blurred instead.
class _TvDetailHeroScrim extends StatelessWidget {
  const _TvDetailHeroScrim();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).scaffoldBackgroundColor;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RasterizedGradient(
            gradient: LinearGradient(
              colors: [
                surface.withValues(alpha: 0.86),
                surface.withValues(alpha: 0.55),
                surface.withValues(alpha: 0.12),
                surface.withValues(alpha: 0),
              ],
              stops: const [0, 0.32, 0.6, 0.78],
            ),
          ),
          RasterizedGradient(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [surface.withValues(alpha: 0.92), surface.withValues(alpha: 0.5), surface.withValues(alpha: 0)],
              stops: const [0, 0.3, 0.62],
            ),
          ),
        ],
      ),
    );
  }
}

/// A TV detail action pill: icon and [label] on a translucent capsule that
/// focus inverts to a solid one. Without a label it is a circle.
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
    final showLabel = label != null && label.isNotEmpty;
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
      width = math.min(painter.width, TvDetailTokens.actionLabelMaxWidth) + TvDetailTokens.actionLabelChrome;
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
                        overflow: TextOverflow.ellipsis,
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
