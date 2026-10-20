import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../media/ids.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../utils/active_client_scope.dart';
import '../utils/global_key_utils.dart';
import '../utils/isolate_helper.dart';
import 'api_cache.dart';

/// Silo items on top of the shared [ApiCache] substrate.
///
/// Silo has no raw payload worth keeping, so a row holds the mapped
/// [MediaItem] as [MediaItem.toJson] under `/silo/items/{id}`. Rows live in
/// the profile scope `silo:<server_id>/<profile_id>`, which itself contains a
/// colon, so every query here matches on the full `<scope>:/silo/items/`
/// prefix instead of splitting the cache key at its first colon.
class SiloApiCache extends ApiCache {
  static final _singleton = ApiCacheSingleton<SiloApiCache>(const {MediaBackend.silo}, 'SiloApiCache');
  static SiloApiCache get instance => _singleton.instance;

  /// Null until [initialize] runs, so a client used without the app's
  /// database (tests, the probe) reads through without caching.
  static SiloApiCache? get instanceOrNull => _singleton.instanceOrNull;

  SiloApiCache._(super.db);

  static void initialize(AppDatabase db) => _singleton.install(SiloApiCache._(db));

  static const _itemPrefix = '/silo/items/';

  static String itemEndpoint(String itemId) => '$_itemPrefix${Uri.encodeComponent(itemId)}';

  String _itemKey(ServerId scope, String itemId) => '$scope:${itemEndpoint(itemId)}';

  /// Writes [item] for [scope]. A pinned row stays pinned.
  Future<void> putItem(ServerId scope, MediaItem item) => put(scope, itemEndpoint(item.id), item.toJson());

  @override
  Future<MediaItem?> getMetadata(ServerId serverId, String itemId) async {
    final cached = await get(serverId, itemEndpoint(itemId));
    return cached == null ? null : _decode(cached);
  }

  @override
  Future<void> pinForOffline(ServerId serverId, String itemId) => pin(serverId, itemEndpoint(itemId));

  @override
  Future<void> deleteForItem(ServerId serverId, String itemId) async {
    final key = _itemKey(serverId, itemId);
    await (database.delete(database.apiCache)..where((t) => t.cacheKey.equals(key))).go();
  }

  @override
  Future<void> applyWatchState({
    required ServerId serverId,
    required String itemId,
    required bool isWatched,
    int? viewOffsetMs,
    int? lastViewedAt,
    int? viewedLeafCount,
  }) async {
    final item = await getMetadata(serverId, itemId);
    if (item == null) return;
    final viewCount = item.viewCount ?? 0;
    await putItem(
      serverId,
      item.copyWith(
        viewCount: isWatched ? (viewCount < 1 ? 1 : viewCount) : 0,
        viewOffsetMs: viewOffsetMs ?? 0,
        lastViewedAt: lastViewedAt ?? (isWatched ? DateTime.now().millisecondsSinceEpoch ~/ 1000 : item.lastViewedAt),
        viewedLeafCount: viewedLeafCount ?? item.viewedLeafCount,
      ),
    );
  }

  @override
  Future<Map<String, MediaItem>> getAllPinnedMetadata({Set<ServerId>? cacheServerIds}) async {
    final query = database.select(database.apiCache)..where((t) => t.pinned.equals(true));
    if (cacheServerIds == null) {
      query.where((t) => t.cacheKey.like('%:$_itemPrefix%'));
    } else {
      if (cacheServerIds.isEmpty) return {};
      query.where(
        (t) => cacheServerIds
            .map((scope) => t.cacheKey.like('${_escapeLike(scope)}:${_escapeLike(_itemPrefix)}%', escapeChar: r'\'))
            .reduce((a, b) => a | b),
      );
    }
    final rows = [
      for (final row in await query.get())
        if (_parseKey(row.cacheKey) case final key?) (scope: key.scope, data: row.data),
    ];
    if (rows.isEmpty) return {};

    return await tryIsolateRun(
      () => decodeCachedMediaRows(
        rows,
        serializedData: (row) => row.data,
        decode: (row, json) {
          final item = _decode(json);
          if (item == null) return null;
          final publicServerId = SiloProfileScopeId.tryParse(row.scope)?.publicServerId ?? ServerId(row.scope);
          return MapEntry(buildGlobalKey(publicServerId, item.id), item);
        },
      ),
    );
  }

  static MediaItem? _decode(Map<String, dynamic> json) {
    final item = MediaItem.fromJson(json);
    return item.backend == MediaBackend.silo ? item : null;
  }

  static ({String scope, String itemId})? _parseKey(String cacheKey) {
    final at = cacheKey.lastIndexOf(':$_itemPrefix');
    if (at <= 0) return null;
    final encoded = cacheKey.substring(at + 1 + _itemPrefix.length);
    if (encoded.isEmpty || encoded.contains('/')) return null;
    return (scope: cacheKey.substring(0, at), itemId: Uri.decodeComponent(encoded));
  }

  static String _escapeLike(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
}
