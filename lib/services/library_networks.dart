import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../media/media_item.dart';
import '../media/media_kind.dart';
import 'silo_client.dart';
import 'tmdb/tmdb_client.dart';
import 'tmdb/tmdb_models.dart';
import 'tmdb/tmdb_networks.dart';

/// Library titles of one kind, keyed for matching TMDB results: by TMDB id
/// when the server lists one, else by title and year
/// (`S/repository/NetworksRepository.kt:516-536`).
class LibraryTitleIndex {
  final Map<String, MediaItem> _keys;

  LibraryTitleIndex(Iterable<({MediaItem item, int? tmdbId})> titles) : _keys = {} {
    for (final title in titles) {
      if (title.tmdbId case final id?) _keys.putIfAbsent('$id', () => title.item);
      if (title.item.year case final year?) {
        _keys.putIfAbsent(_titleKey(title.item.title ?? '', year), () => title.item);
      }
    }
  }

  bool get isEmpty => _keys.isEmpty;

  /// [yearSlack] also accepts the title that many years either side, for a
  /// small set where a near year can't be another title's.
  MediaItem? lookup(TmdbMedia result, {int yearSlack = 0}) {
    if (_keys['${result.id}'] case final item?) return item;
    final year = result.year;
    if (year == null) return null;
    for (final offset in [
      0,
      for (var slack = 1; slack <= yearSlack; slack++) ...[-slack, slack],
    ]) {
      if (_keys[_titleKey(result.title, year + offset)] case final item?) return item;
    }
    return null;
  }

  /// Letters and digits only, lowercased: "Grey's Anatomy" and "Greys
  /// Anatomy" meet.
  static String _titleKey(String title, int year) =>
      't:${title.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '')}|$year';
}

/// The Library tab's Networks row, after Silo's `NetworksRepository`: TMDB
/// lists each network's most popular titles and only the ones in the library
/// are kept, so every card is a library item.
class LibraryNetworks {
  /// TMDB discover pages read per list (20 titles each).
  static const int pagesPerList = 10;

  /// Below this a network's row would look empty, so it is hidden.
  static const int minimumCount = 6;

  final TmdbClient tmdb;

  LibraryNetworks(this.tmdb);

  /// Year listings read at once by [readLibrary].
  static const int libraryReadConcurrency = 12;

  /// Year ranges that together cover every year, so [readLibrary] reads a
  /// large library as many short listings side by side rather than one long
  /// cursor chain (a 58,000-title library took about two minutes as one).
  /// Decades before 2000, where libraries are thin, then single years.
  @visibleForTesting
  static List<(int, int)> libraryYearRanges(int currentYear) => [
    (-999999, 1949),
    for (var decade = 1950; decade < 2000; decade += 10) (decade, decade + 9),
    for (var year = 2000; year <= currentYear + 1; year++) (year, year),
    (currentYear + 2, 999999),
  ];

  /// Every movie and series on [clients], indexed. Throws when any read
  /// fails, so a partial library never passes for a complete one.
  static Future<({LibraryTitleIndex movies, LibraryTitleIndex shows})> readLibrary(List<SiloClient> clients) async {
    const kinds = [MediaKind.movie, MediaKind.show];
    final reads = [
      for (final kind in kinds)
        for (final client in clients)
          for (final years in libraryYearRanges(DateTime.now().year)) (kind: kind, client: client, years: years),
    ];
    // Filled by index, so the order is the same however the reads finish.
    final results = List<List<({MediaItem item, int? tmdbId})>>.filled(reads.length, const []);
    var next = 0;
    Future<void> worker() async {
      while (next < reads.length) {
        final index = next++;
        final read = reads[index];
        results[index] = await read.client.fetchTitles(read.kind, years: read.years);
      }
    }

    await Future.wait([for (var i = 0; i < libraryReadConcurrency; i++) worker()]);
    Iterable<({MediaItem item, int? tmdbId})> of(MediaKind kind) => [
      for (var index = 0; index < reads.length; index++)
        if (reads[index].kind == kind) ...results[index],
    ];
    return (movies: LibraryTitleIndex(of(MediaKind.movie)), shows: LibraryTitleIndex(of(MediaKind.show)));
  }

  /// [brand]'s library titles, movies and series merged most popular first.
  Future<List<MediaItem>> match(
    TmdbNetworkBrand brand, {
    required LibraryTitleIndex movies,
    required LibraryTitleIndex shows,
  }) async {
    final lists = await Future.wait([
      discoverMatches(TmdbMediaType.tv, {'with_networks': '${brand.id}'}, shows),
      if (brand.watchProviders case final providers?)
        discoverMatches(TmdbMediaType.movie, {
          'with_watch_providers': providers,
          'watch_region': brand.watchRegion,
          'with_watch_monetization_types': 'flatrate',
        }, movies),
    ]);
    final merged = lists.expand((list) => list).toList()..sort((a, b) => b.popularity.compareTo(a.popularity));
    final seen = <String>{};
    return [
      for (final match in merged)
        if (seen.add('${match.item.serverId}:${match.item.id}')) match.item,
    ];
  }

  /// TMDB trending pages read for a network page's Trending row (20 titles
  /// each, movies and series mixed). Most networks have only a handful of
  /// titles in TMDB's first few hundred.
  static const int trendingPages = 50;

  /// Trending pages read at once, under TMDB's rate limit.
  static const int trendingConcurrency = 10;

  /// How long the week's trending list read for one network page serves the
  /// rest.
  static const Duration trendingMaxAge = Duration(hours: 6);

  static ({DateTime readAt, Future<List<TmdbMedia>> results})? _trendingRead;

  @visibleForTesting
  static void resetTrending() => _trendingRead = null;

  /// [items] (one network's library titles) trending on TMDB this week, most
  /// trending first. Matched by title and year, as the items carry no TMDB
  /// id; a year off by one still matches, as a series' first year often
  /// differs between TMDB and the server.
  Future<List<MediaItem>> trending(List<MediaItem> items) async {
    LibraryTitleIndex index(bool movies) => LibraryTitleIndex([
      for (final item in items)
        if ((item.kind == MediaKind.movie) == movies) (item: item, tmdbId: null),
    ]);
    final movies = index(true);
    final shows = index(false);
    if (movies.isEmpty && shows.isEmpty) return const [];
    final seen = <String>{};
    return [
      for (final result in await _trendingResults())
        if (switch (result.type) {
              TmdbMediaType.movie => movies.lookup(result, yearSlack: 1),
              TmdbMediaType.tv => shows.lookup(result, yearSlack: 1),
              _ => null,
            }
            case final item? when seen.add(item.globalKey))
          item,
    ];
  }

  /// The week's trending titles, read once per [trendingMaxAge]; a failed
  /// read is asked again next time.
  Future<List<TmdbMedia>> _trendingResults() {
    final last = _trendingRead;
    if (last != null && DateTime.now().difference(last.readAt) < trendingMaxAge) return last.results;
    final results = () async {
      Future<TmdbPage<TmdbMedia>> page(int number) => _retryingOnce(() => tmdb.trending(page: number));
      final first = await page(1);
      final pageCount = first.totalPages < trendingPages ? first.totalPages : trendingPages;
      final responses = [first];
      for (var start = 2; start <= pageCount; start += trendingConcurrency) {
        final end = math.min(start + trendingConcurrency - 1, pageCount);
        responses.addAll(await Future.wait([for (var number = start; number <= end; number++) page(number)]));
      }
      return [for (final response in responses) ...response.results];
    }();
    final read = (readAt: DateTime.now(), results: results);
    _trendingRead = read;
    unawaited(
      results.catchError((Object _) {
        if (identical(_trendingRead, read)) _trendingRead = null;
        return const <TmdbMedia>[];
      }),
    );
    return results;
  }

  /// [items] newest added first; undated ones last, and ties keep their
  /// order (the sort is stable).
  static List<MediaItem> newestFirst(List<MediaItem> items) {
    final sorted = [...items];
    mergeSort(sorted, compare: (a, b) => (b.addedAt ?? 0).compareTo(a.addedAt ?? 0));
    return sorted;
  }

  /// Library matches for one TMDB discover list, in its popularity order.
  Future<List<({MediaItem item, double popularity})>> discoverMatches(
    TmdbMediaType type,
    Map<String, String> filters,
    LibraryTitleIndex index,
  ) async {
    if (index.isEmpty) return const [];
    final query = {...filters, 'sort_by': 'popularity.desc'};
    Future<TmdbPage<TmdbMedia>> page(int number) =>
        _retryingOnce(() => tmdb.discover(type, filters: query, page: number));
    final first = await page(1);
    // The first page says how many there are, so the rest load together.
    final pageCount = first.totalPages < pagesPerList ? first.totalPages : pagesPerList;
    final rest = await Future.wait([for (var number = 2; number <= pageCount; number++) page(number)]);
    return [
      for (final response in [first, ...rest])
        for (final result in response.results)
          if (index.lookup(result) case final item?) (item: item, popularity: result.popularity ?? 0),
    ];
  }

  /// Retries once after a short pause, for a dropped connection or a brief
  /// rate limit.
  static Future<T> _retryingOnce<T>(Future<T> Function() request) async {
    try {
      return await request();
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
      return request();
    }
  }
}
