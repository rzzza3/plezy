import '../media/media_backend.dart';
import '../media/media_source_info.dart';

/// Offline reads of the playback metadata a download left in the API cache.
///
/// Silo caches no per-item playback row (its media info and markers come
/// from the playback decision), so every read is a miss and offline
/// playback runs on the downloaded file alone.
class CachedPlaybackMetadataService {
  const CachedPlaybackMetadataService._();

  static Future<MediaSourceInfo?> fetchMediaSourceInfo({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    int mediaIndex = 0,
    Duration? position,
  }) async => null;

  static Future<PlaybackExtras?> fetchPlaybackExtras({
    required MediaBackend backend,
    required String cacheServerId,
    required String itemId,
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async => null;
}
