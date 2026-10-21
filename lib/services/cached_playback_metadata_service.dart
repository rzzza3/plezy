import '../media/ids.dart';

import '../media/media_backend.dart';
import '../media/media_source_info.dart';
import '../utils/app_logger.dart';
import '../utils/plex_cache_parser.dart';
import 'api_cache.dart';
import 'plex_mappers.dart';

class CachedPlaybackMetadataService {
  const CachedPlaybackMetadataService._();

  /// [position] (item time) picks the file of an item stacked across several
  /// files (Plex); the first file otherwise.
  static Future<MediaSourceInfo?> fetchMediaSourceInfo({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    int mediaIndex = 0,
    Duration? position,
  }) async {
    try {
      return await switch (backend) {
        MediaBackend.plex => _fetchPlexMediaSourceInfo(
          ServerId(cacheServerId),
          itemId,
          mediaIndex: mediaIndex,
          position: position,
        ),
        MediaBackend.silo => Future.value(null),
      };
    } catch (e) {
      appLogger.d('Cached media source info unavailable for $cacheServerId:$itemId', error: e);
      return null;
    }
  }

  static Future<PlaybackExtras?> fetchPlaybackExtras({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async {
    try {
      return await switch (backend) {
        MediaBackend.plex => _fetchPlexPlaybackExtras(
          ServerId(cacheServerId),
          itemId,
          introPattern: introPattern,
          creditsPattern: creditsPattern,
          forceChapterFallback: forceChapterFallback,
        ),
        MediaBackend.silo => Future.value(null),
      };
    } catch (e) {
      appLogger.d('Cached playback extras unavailable for $cacheServerId:$itemId', error: e);
      return null;
    }
  }

  static Future<MediaSourceInfo?> _fetchPlexMediaSourceInfo(
    ServerId serverId,
    String itemId, {
    required int mediaIndex,
    Duration? position,
  }) async {
    final metadata = await _plexMetadata(ServerId(serverId), itemId);
    if (metadata == null) return null;
    // The file is already on disk: stale server accessibility must not
    // substitute another version's tracks for the downloaded file.
    final selection = resolvePlexPlaybackSelection(
      metadata,
      mediaIndex: mediaIndex,
      preferPlayable: false,
      position: position,
    );
    return selection == null ? null : plexMediaSourceInfoForSelection(metadata, selection);
  }

  static Future<PlaybackExtras?> _fetchPlexPlaybackExtras(
    ServerId serverId,
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async {
    final metadata = await _plexMetadata(ServerId(serverId), itemId);
    if (metadata == null) return null;
    final extras = plexPlaybackExtrasFromCacheJson(
      metadata,
      introPattern: introPattern,
      creditsPattern: creditsPattern,
      forceChapterFallback: forceChapterFallback,
    );
    // Offline twin of the suppression in `PlexClient.getPlaybackExtras`;
    // cache-only, so an uncached show row fails open and keeps the markers.
    return plexApplyCreditsDetectionPreference(
      extras,
      metadata,
      loadMetadataJson: (ratingKey) => _plexMetadata(serverId, ratingKey),
    );
  }

  static Future<Map<String, dynamic>?> _plexMetadata(ServerId serverId, String itemId) async {
    final cached = await ApiCache.forBackend(MediaBackend.plex).get(serverId, '/library/metadata/$itemId');
    return PlexCacheParser.extractFirstMetadata(cached);
  }
}
