import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../models/catalog/catalog_item.dart';
import '../profiles/profile.dart';
import '../services/base_shared_preferences_service.dart';
import '../services/catalog/library_watchlist_candidates.dart';
import '../services/catalog/catalog_source.dart';
import '../services/catalog/anilist_catalog_source.dart';
import '../services/catalog/mdblist_catalog_source.dart';
import '../services/catalog/mal_catalog_source.dart';
import '../services/catalog/seerr_catalog_source.dart';
import '../services/catalog/simkl_catalog_source.dart';
import '../services/catalog/trakt_catalog_source.dart';
import '../services/trackers/future_coalescer.dart';
import '../services/seerr/seerr_client.dart';
import '../services/trackers/anilist/anilist_client.dart';
import '../services/trackers/mal/mal_client.dart';
import '../services/trackers/mdblist/mdblist_client.dart';
import '../services/trackers/simkl/simkl_client.dart';
import '../services/trackers/trakt/trakt_client.dart';
import 'seerr_account_provider.dart';
import 'trackers_provider.dart';

/// Owns one client/source pair and applies the shared rebind/dispose contract.
class _CatalogSourceBinding<Client extends Object, Source extends CatalogSource> {
  _CatalogSourceBinding(this._create, {bool Function(Client? previous, Client? next)? equals})
    : _equals = equals ?? ((previous, next) => identical(previous, next));

  final Source Function(Client client) _create;
  final bool Function(Client? previous, Client? next) _equals;
  Client? _client;
  Source? source;

  bool update(Client? next) {
    if (_equals(_client, next)) return false;
    final replacement = next == null ? null : _create(next);
    source?.dispose();
    _client = next;
    source = replacement;
    return true;
  }

  void dispose() {
    source?.dispose();
    source = null;
    _client = null;
  }
}

/// Enumerates the connected [CatalogSource]s for the active profile and owns
/// which one the Explore tab shows.
///
/// Profile-scoped. Tracker/Seerr sources are rebuilt through the proxy-provider update hook so
/// every source appears and disappears with its owning account connection
/// (which also drives the Explore tab's visibility).
class CatalogSourcesProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  final _CatalogSourceBinding<TraktClient, TraktCatalogSource> _trakt = _CatalogSourceBinding(TraktCatalogSource.new);
  final _CatalogSourceBinding<MalClient, MalCatalogSource> _mal = _CatalogSourceBinding(MalCatalogSource.new);
  final _CatalogSourceBinding<AnilistClient, AnilistCatalogSource> _anilist = _CatalogSourceBinding(
    AnilistCatalogSource.new,
  );
  final _CatalogSourceBinding<SimklClient, SimklCatalogSource> _simkl = _CatalogSourceBinding(SimklCatalogSource.new);
  final _CatalogSourceBinding<MdblistClient, MdblistCatalogSource> _mdblist = _CatalogSourceBinding(
    MdblistCatalogSource.new,
  );
  final _CatalogSourceBinding<SeerrClient, SeerrCatalogSource> _seerr = _CatalogSourceBinding(SeerrCatalogSource.new);
  int _profileBindingGeneration = 0;
  static const String _activeSourceBaseKey = 'catalog_active_source';
  CatalogSourceId? _preferredSourceId;
  String _activeUserUuid = '';

  // Per-item watchlist candidates (see [watchlistCandidatesFor]): the
  // coalescer keeps one load in flight per item, the results map gives menu
  // surfaces synchronous access for labeling, and the generation guard keeps
  // a load that outlives a source rebind from repopulating disposed sources.
  final KeyedFutureCoalescer<String, List<WatchlistCandidate>> _watchlistCandidateLoads = KeyedFutureCoalescer();
  final Map<String, List<WatchlistCandidate>> _watchlistCandidateResults = {};
  int _watchlistCandidateGeneration = 0;

  List<CatalogSource> get connectedSources => [
    ?_trakt.source,
    ?_mal.source,
    ?_anilist.source,
    ?_simkl.source,
    ?_mdblist.source,
    ?_seerr.source,
  ];

  bool get hasAnySource => connectedSources.isNotEmpty;

  /// The connected Seerr source, for the request surfaces (detail-screen
  /// Request action and sheet) that need Seerr's client beyond the
  /// [CatalogSource] interface.
  SeerrCatalogSource? get seerrSource => _seerr.source;

  /// The source whose rows the Explore tab shows: the user's persisted pick
  /// when it is still connected, otherwise the first connected source.
  CatalogSource? get activeSource {
    final sources = connectedSources;
    return sources.firstWhereOrNull((s) => s.id == _preferredSourceId) ?? sources.firstOrNull;
  }

  /// The source backing watchlist membership/mutation surfaces (media-detail
  /// action). Independent of [activeSource] so switching the Explore tab to a
  /// watchlist-less source (e.g. a future Seerr) keeps the action alive.
  CatalogSource? get watchlistCapableSource => connectedSources.firstWhereOrNull((s) => s.supportsWatchlist);

  /// All connected sources whose watchlist can be read and mutated, for
  /// surfaces that offer a choice (media-detail bookmark with several
  /// providers connected).
  List<CatalogSource> get watchlistCapableSources => [...connectedSources.where((source) => source.supportsWatchlist)];

  /// The watchlist source catalog-item surfaces (detail screen, card menu)
  /// must bind to: the item's OWN source — a MAL card toggles the MAL Plan to
  /// Watch, never another provider's list. An item whose source is connected
  /// but has no watchlist (Seerr) gets none at all — no falling back to
  /// another provider's list. The fallback exists only for items whose
  /// source got disconnected mid-session.
  CatalogSource? watchlistSourceFor(CatalogItem item) {
    final own = connectedSources.firstWhereOrNull((s) => s.id == item.source);
    if (own != null) return own.supportsWatchlist ? own : null;
    return watchlistCapableSource;
  }

  static String _watchlistItemKey(MediaItem item) => '${item.serverId ?? ''}/${item.id}';

  /// Session-cached [resolveWatchlistCandidates] for a library item: every
  /// watchlist-capable source the item exists in, with its per-source ids.
  /// Shared by the detail screen and card context menus so an item resolves
  /// its external ids at most once per session. Failures are not cached (the
  /// next call retries) — nor is an answer missing a source that failed to
  /// resolve, which would otherwise hide that source's action for the rest of
  /// the session; a null [client] (server offline) resolves to nothing without
  /// caching the miss. Invalidated when sources rebind.
  Future<List<WatchlistCandidate>> watchlistCandidatesFor(MediaItem item, {required MediaServerClient? client}) {
    final key = _watchlistItemKey(item);
    final cached = _watchlistCandidateResults[key];
    if (cached != null) return Future.value(cached);
    if (client == null) return Future.value(const []);
    final generation = _watchlistCandidateGeneration;
    return _watchlistCandidateLoads.run(key, () async {
      var complete = true;
      final candidates = await resolveWatchlistCandidates(
        client: client,
        item: item,
        sources: watchlistCapableSources,
        onSourceFailed: (_) => complete = false,
      );
      if (complete && !isDisposed && generation == _watchlistCandidateGeneration) {
        _watchlistCandidateResults[key] = candidates;
      }
      return candidates;
    });
  }

  /// The already-resolved candidates for [item], or null when never resolved
  /// this session. Menu surfaces label from this without awaiting; an empty
  /// list means no connected source can hold the item.
  List<WatchlistCandidate>? cachedWatchlistCandidatesFor(MediaItem item) =>
      _watchlistCandidateResults[_watchlistItemKey(item)];

  void _invalidateWatchlistCandidates() {
    _watchlistCandidateGeneration++;
    _watchlistCandidateLoads.clear();
    _watchlistCandidateResults.clear();
  }

  /// Hydrate the per-profile active-source preference.
  Future<void> onActiveProfileChanged(String? userUuid) async {
    final generation = ++_profileBindingGeneration;
    _activeUserUuid = userUuid ?? '';
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(profileScopedPrefsKey(_activeUserUuid, _activeSourceBaseKey));
    if (isDisposed || generation != _profileBindingGeneration) return;

    _preferredSourceId = CatalogSourceId.values.asNameMap()[raw];
    safeNotifyListeners();
  }

  CatalogSourceId? get preferredSourceId => _preferredSourceId;

  /// Null clears the override and restores the first connected source.
  Future<void> setActiveSource(CatalogSourceId? id, {void Function()? checkCurrent}) async {
    if (id != null && _preferredSourceId == id) return;
    final userScope = _activeUserUuid;
    final generation = _profileBindingGeneration;
    final prefs = await BaseSharedPreferencesService.sharedCache();
    if (isDisposed || generation != _profileBindingGeneration) return;
    checkCurrent?.call();
    final key = profileScopedPrefsKey(userScope, _activeSourceBaseKey);
    if (id == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, id.name);
    }
    if (isDisposed || generation != _profileBindingGeneration) return;
    checkCurrent?.call();
    _preferredSourceId = id;
    safeNotifyListeners();
  }

  /// Proxy-provider update hook: rebuild a source when its catalog client
  /// was rebound (connect/disconnect/profile switch).
  void update(TrackersProvider trackers, SeerrAccountProvider seerr) {
    var changed = false;
    changed = _trakt.update(trackers.traktCatalogClient) || changed;
    changed = _mal.update(trackers.malCatalogClient) || changed;
    changed = _anilist.update(trackers.anilistCatalogClient) || changed;
    changed = _simkl.update(trackers.simklCatalogClient) || changed;
    changed = _mdblist.update(trackers.mdblistCatalogClient) || changed;
    changed = _seerr.update(seerr.catalogClient) || changed;
    if (changed) {
      _invalidateWatchlistCandidates();
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    _trakt.dispose();
    _mal.dispose();
    _anilist.dispose();
    _mdblist.dispose();
    _simkl.dispose();
    _seerr.dispose();
    super.dispose();
  }
}
