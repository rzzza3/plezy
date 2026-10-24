/// Season of a parent series as numbered by each external provider.
///
/// Populated from the Fribb mapping's `season: {tvdb: N, tmdb: M}`.
class ExternalSeasonRef {
  final int? tvdb;
  final int? tmdb;

  const ExternalSeasonRef({this.tvdb, this.tmdb});

  bool get hasAny => tvdb != null || tmdb != null;

  /// True when this entry covers a later season under either provider.
  ///
  /// Independent of [agreedSeason]: it answers "is this a sequel at all",
  /// which stays knowable when the two providers disagree. Callers use it to
  /// drop the ±1 year window, because a sequel's catalog year is its own
  /// season's, not the parent show's.
  bool get isSequel => (tvdb ?? 0) > 1 || (tmdb ?? 0) > 1;

  /// The season number both providers mapped and agree on, else null.
  ///
  /// TVDB and TMDB disagree on split-cour / continuation seasons — a season
  /// the former numbers `2` the latter often folds into `1` at an episode
  /// offset. Which one a library follows is a server-side setting, not
  /// anything a dataset can tell us, and it is NOT inferable from which ids an
  /// item exposes (a show can carry all three regardless). So when the two
  /// disagree the honest answer is "cannot tell" and the caller must not gate.
  ///
  /// A missing number is not agreement either: `tvdb: 2, tmdb: null` means
  /// Fribb has no TMDB season mapping, and a TMDB-ordered server would number
  /// that season by the mapping we do not have. Holds for 1133 of the 1185
  /// gate-eligible Fribb rows; the other 52 simply go ungated.
  int? get agreedSeason => tvdb != null && tvdb == tmdb ? tvdb : null;

  Map<String, Object?> toJson() => {if (tvdb != null) 'tvdb': tvdb, if (tmdb != null) 'tmdb': tmdb};

  factory ExternalSeasonRef.fromJson(Map<String, Object?> json) =>
      ExternalSeasonRef(tvdb: json['tvdb'] as int?, tmdb: json['tmdb'] as int?);

  @override
  bool operator ==(Object other) => other is ExternalSeasonRef && other.tvdb == tvdb && other.tmdb == tmdb;

  @override
  int get hashCode => Object.hash(tvdb, tmdb);
}

/// External IDs (IMDb / TMDB / TVDB / AniDB) extracted from a media server's
/// metadata. Shared by the Trakt and tracker resolvers.
class ExternalIds {
  final String? imdb;
  final int? tmdb;
  final int? tvdb;

  /// AniDB series id. Separate from the three catalog ids because almost
  /// nothing accepts it: it names a Fribb row (and through it
  /// MAL/AniList/Simkl) but Trakt, Seerr and the Anime-Lists episode mappings
  /// are all keyed the other way.
  final int? anidb;

  const ExternalIds({this.imdb, this.tmdb, this.tvdb, this.anidb});

  bool get hasAny => hasCatalogIds || anidb != null;

  /// The ids a title database can be queried with. Callers that can only search
  /// IMDb/TMDB/TVDB gate on this rather than [hasAny], so an AniDB-only item
  /// does not send them looking for something they cannot express.
  bool get hasCatalogIds => imdb != null || tmdb != null || tvdb != null;

  /// True when any id form matches [other]. Used to verify reverse-lookup
  /// candidates (never yields false positives; the two sides may carry
  /// different id subsets).
  bool intersects(ExternalIds other) =>
      (imdb != null && imdb == other.imdb) ||
      (tmdb != null && tmdb == other.tmdb) ||
      (tvdb != null && tvdb == other.tvdb) ||
      (anidb != null && anidb == other.anidb);

  /// Round-trips through the persisted tracker write queue. Absent ids stay
  /// absent so a re-read yields the same [hasAny]/[intersects] answers.
  Map<String, Object?> toJson() => {
    if (imdb != null) 'imdb': imdb,
    if (tmdb != null) 'tmdb': tmdb,
    if (tvdb != null) 'tvdb': tvdb,
    if (anidb != null) 'anidb': anidb,
  };

  factory ExternalIds.fromJson(Map<String, Object?> json) => ExternalIds(
    imdb: json['imdb'] as String?,
    tmdb: (json['tmdb'] as num?)?.toInt(),
    tvdb: (json['tvdb'] as num?)?.toInt(),
    anidb: (json['anidb'] as num?)?.toInt(),
  );
}
