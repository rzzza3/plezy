import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../services/library_networks.dart';
import '../services/settings_service.dart';
import '../services/silo_client.dart';
import '../services/tmdb/tmdb_client.dart';
import '../services/tmdb/tmdb_models.dart';
import '../services/tmdb/tmdb_networks.dart';
import '../utils/app_logger.dart';
import 'library_network_screen.dart';
import 'library_strip_section.dart';

/// The Library tab's "Networks": a [LibraryStripSection] of network logos.
/// After Silo's Home Networks row (`S/repository/NetworksRepository.kt`):
/// TMDB lists each network's series (`with_networks`) and films (its
/// streaming providers), and only titles in the library are kept, so cards
/// are library items and open their Silo pages.
///
/// The networks are [SettingsService.libraryNetworks]. Per network it reads
/// up to [LibraryNetworks.pagesPerList] TMDB discover pages per list and one
/// `GET /3/network/{id}` for its logo. Shows nothing without TMDB
/// credentials.
class LibraryNetworksSection extends LibraryStripSection {
  const LibraryNetworksSection({
    super.key,
    required super.filter,
    required super.onNavigateUp,
    super.onNavigateDown,
    required super.onNavigateToSidebar,
    super.onFocusEntered,
  });

  @override
  State<LibraryNetworksSection> createState() => LibraryNetworksSectionState();
}

class LibraryNetworksSectionState extends LibraryStripSectionState<LibraryNetworksSection> {
  final Map<int, TmdbNetworkBrand> _brands = {for (final network in TmdbNetworks.all) network.id: network};

  /// TMDB's name and logo per network, once read.
  final Map<int, TmdbNetwork> _details = {};
  final Set<int> _detailsRequested = {};

  /// The library, indexed, once read.
  ({LibraryTitleIndex movies, LibraryTitleIndex shows})? _library;

  TmdbClient get _tmdb => context.read<TmdbClient>();

  @override
  StringListPref get pref => SettingsService.libraryNetworks;

  @override
  String get title => t.libraryHome.networks;

  @override
  IconData get icon => Symbols.live_tv_rounded;

  @override
  String get logLabel => 'Library networks';

  @override
  String get sectionKey => 'library_networks';

  /// Whether the missing-credentials warning was logged this run.
  static bool _loggedUnconfigured = false;

  /// Only with TMDB credentials, which are build-time defines. Without them
  /// the row hides itself; say so once a run, so a build missing them shows
  /// up in the log rather than as a row that never appears.
  @override
  bool get canLoad {
    final configured = _tmdb.isConfigured;
    if (!configured && !_loggedUnconfigured) {
      _loggedUnconfigured = true;
      appLogger.w(
        '$logLabel: hidden, this build has no TMDB credentials '
        '(build with --dart-define TMDB_READ_ACCESS_TOKEN or TMDB_API_KEY)',
      );
    }
    return configured;
  }

  @override
  List<String> choicesIn(List<String> ids) => [
    for (final id in ids.toSet())
      if (_brands.containsKey(int.tryParse(id))) id,
  ];

  TmdbNetworkBrand _brand(String id) => _brands[int.parse(id)]!;

  @override
  LibraryStripChoice describe(String id) {
    final network = _brand(id);
    return (
      name: _details[network.id]?.name ?? network.name,
      logoUrl: network.usesWordmark ? null : _details[network.id]?.logoUrl(),
    );
  }

  @override
  void onLoadStarted(List<String> ids) {
    for (final id in ids) {
      if (!_brand(id).usesWordmark) unawaited(_loadDetails(int.parse(id)));
    }
  }

  /// Reads every movie and series once (`GET /api/v2/catalog`, 100 a page,
  /// per connected Silo server).
  @override
  Future<void> prepare(List<SiloClient> clients) async {
    _library ??= await LibraryNetworks.readLibrary(clients);
  }

  @override
  Future<List<MediaItem>> match(String id, List<SiloClient> clients) {
    final library = _library!;
    return LibraryNetworks(_tmdb).match(_brand(id), movies: library.movies, shows: library.shows);
  }

  @override
  Widget pageFor(String id, List<MediaItem> items) {
    final network = _brand(id);
    return LibraryNetworkScreen(
      name: _details[network.id]?.name ?? network.name,
      logoUrl: network.usesWordmark ? null : _details[network.id]?.logoUrl('w500'),
      items: items,
    );
  }

  Future<void> _loadDetails(int id) async {
    if (!_detailsRequested.add(id)) return;
    try {
      final network = await _tmdb.network(id);
      if (mounted) setState(() => _details[id] = network);
    } catch (error) {
      // The strip keeps the network's name; a later load asks again.
      _detailsRequested.remove(id);
      appLogger.w('Library networks: details failed for $id (${error.runtimeType})');
    }
  }
}
