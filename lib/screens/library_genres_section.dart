import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../services/library_genres.dart';
import '../services/settings_service.dart';
import '../services/silo_client.dart';
import '../services/tmdb/tmdb_client.dart';
import '../services/tmdb/tmdb_genres.dart';
import 'library_network_screen.dart';
import 'library_strip_section.dart';

/// The Library tab's "Genres": a [LibraryStripSection] of genre names, each
/// over the library's titles Silo lists in that genre ([LibraryGenres]),
/// asked of Silo per genre rather than read from the whole library. The
/// genres are [SettingsService.libraryGenres]; each opens a page like a
/// network's. TMDB, when configured, only ranks a genre's titles by
/// popularity, so the row shows without it.
class LibraryGenresSection extends LibraryStripSection {
  const LibraryGenresSection({
    super.key,
    required super.filter,
    required super.onNavigateUp,
    super.onNavigateDown,
    required super.onNavigateToSidebar,
    super.onFocusEntered,
  });

  @override
  State<LibraryGenresSection> createState() => LibraryGenresSectionState();
}

class LibraryGenresSectionState extends LibraryStripSectionState<LibraryGenresSection> {
  final Map<String, LibraryGenre> _genres = {for (final genre in TmdbGenres.all) genre.id: genre};

  @override
  StringListPref get pref => SettingsService.libraryGenres;

  @override
  String get title => t.libraryHome.genres;

  @override
  IconData get icon => Symbols.theater_comedy_rounded;

  @override
  String get logLabel => 'Library genres';

  @override
  String get sectionKey => 'library_genres';

  @override
  List<String> choicesIn(List<String> ids) => [
    for (final id in ids.toSet())
      if (_genres.containsKey(id)) id,
  ];

  @override
  LibraryStripChoice describe(String id) => (name: _genres[id]!.name, logoUrl: null);

  @override
  Future<List<MediaItem>> match(String id, List<SiloClient> clients) =>
      LibraryGenres(context.read<TmdbClient?>()).match(_genres[id]!, clients);

  @override
  Widget pageFor(String id, List<MediaItem> items) {
    return LibraryNetworkScreen(name: _genres[id]!.name, items: items);
  }
}
