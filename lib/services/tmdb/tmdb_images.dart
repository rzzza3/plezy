/// TMDB CDN image URLs. TMDB (and Seerr, which proxies it) serves relative
/// paths (`/abc.jpg`); the CDN serves each at a fixed set of sizes.
library;

String? tmdbImageUrl(String? path, String size) =>
    path == null || path.isEmpty ? null : 'https://image.tmdb.org/t/p/$size$path';

/// Width-keyed poster sizes, for [CatalogItem.posterVariants].
Map<int, String>? tmdbPosterVariants(String? path) {
  if (path == null || path.isEmpty) return null;
  return {
    92: tmdbImageUrl(path, 'w92')!,
    154: tmdbImageUrl(path, 'w154')!,
    185: tmdbImageUrl(path, 'w185')!,
    342: tmdbImageUrl(path, 'w342')!,
    500: tmdbImageUrl(path, 'w500')!,
    600: tmdbImageUrl(path, 'w600_and_h900_bestv2')!,
    780: tmdbImageUrl(path, 'w780')!,
  };
}

/// Width-keyed backdrop sizes, for [CatalogItem.backdropVariants].
Map<int, String>? tmdbBackdropVariants(String? path) {
  if (path == null || path.isEmpty) return null;
  return {
    300: tmdbImageUrl(path, 'w300')!,
    780: tmdbImageUrl(path, 'w780')!,
    1280: tmdbImageUrl(path, 'w1280')!,
    1920: tmdbImageUrl(path, 'w1920_and_h800_multi_faces')!,
  };
}
