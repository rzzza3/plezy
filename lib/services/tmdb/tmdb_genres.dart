/// A genre the Library tab's Genres row can show.
class LibraryGenre {
  /// Stored in `SettingsService.libraryGenres`.
  final String id;
  final String name;

  /// The genre names Silo lists on a title that put it in this genre. Silo
  /// takes its genres from TMDB, which names some for TV alone ("Sci-Fi &
  /// Fantasy", "Action & Adventure").
  final List<String> names;

  /// TMDB genre ids for `with_genres`, `|`-separated, ranking the genre's
  /// films and series by popularity. Null where TMDB has no such genre for
  /// that kind.
  final String? tmdbMovieGenres;
  final String? tmdbTvGenres;

  const LibraryGenre(this.id, this.name, {required this.names, this.tmdbMovieGenres, this.tmdbTvGenres});
}

/// The genres the Library tab's Genres row can show: the most common film
/// and TV genres, after TMDB's two genre lists.
class TmdbGenres {
  TmdbGenres._();

  static const List<LibraryGenre> all = [
    LibraryGenre(
      'action',
      'Action',
      names: ['Action', 'Action & Adventure'],
      tmdbMovieGenres: '28',
      tmdbTvGenres: '10759',
    ),
    LibraryGenre(
      'adventure',
      'Adventure',
      names: ['Adventure', 'Action & Adventure'],
      tmdbMovieGenres: '12',
      tmdbTvGenres: '10759',
    ),
    LibraryGenre('animation', 'Animation', names: ['Animation'], tmdbMovieGenres: '16', tmdbTvGenres: '16'),
    LibraryGenre('comedy', 'Comedy', names: ['Comedy'], tmdbMovieGenres: '35', tmdbTvGenres: '35'),
    LibraryGenre('crime', 'Crime', names: ['Crime'], tmdbMovieGenres: '80', tmdbTvGenres: '80'),
    LibraryGenre('documentary', 'Documentary', names: ['Documentary'], tmdbMovieGenres: '99', tmdbTvGenres: '99'),
    LibraryGenre('drama', 'Drama', names: ['Drama'], tmdbMovieGenres: '18', tmdbTvGenres: '18'),
    LibraryGenre('family', 'Family', names: ['Family'], tmdbMovieGenres: '10751', tmdbTvGenres: '10751'),
    LibraryGenre(
      'fantasy',
      'Fantasy',
      names: ['Fantasy', 'Sci-Fi & Fantasy'],
      tmdbMovieGenres: '14',
      tmdbTvGenres: '10765',
    ),
    LibraryGenre('history', 'History', names: ['History'], tmdbMovieGenres: '36'),
    LibraryGenre('horror', 'Horror', names: ['Horror'], tmdbMovieGenres: '27'),
    LibraryGenre('kids', 'Kids', names: ['Kids', 'Children'], tmdbTvGenres: '10762'),
    LibraryGenre('music', 'Music', names: ['Music', 'Musical'], tmdbMovieGenres: '10402'),
    LibraryGenre('mystery', 'Mystery', names: ['Mystery'], tmdbMovieGenres: '9648', tmdbTvGenres: '9648'),
    LibraryGenre('reality', 'Reality', names: ['Reality', 'Reality-TV'], tmdbTvGenres: '10764'),
    LibraryGenre('romance', 'Romance', names: ['Romance'], tmdbMovieGenres: '10749'),
    LibraryGenre(
      'science-fiction',
      'Science Fiction',
      names: ['Science Fiction', 'Sci-Fi', 'Science-Fiction', 'Sci-Fi & Fantasy'],
      tmdbMovieGenres: '878',
      tmdbTvGenres: '10765',
    ),
    LibraryGenre('thriller', 'Thriller', names: ['Thriller', 'Suspense'], tmdbMovieGenres: '53'),
    LibraryGenre('war', 'War', names: ['War', 'War & Politics'], tmdbMovieGenres: '10752', tmdbTvGenres: '10768'),
    LibraryGenre('western', 'Western', names: ['Western'], tmdbMovieGenres: '37', tmdbTvGenres: '37'),
  ];

  /// Shown until the user picks their own.
  static const List<String> defaultIds = ['action', 'comedy', 'drama', 'horror', 'science-fiction', 'animation'];
}
