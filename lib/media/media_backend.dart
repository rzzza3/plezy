import '../utils/app_logger.dart';
import 'media_browser_dialect.dart';

/// Backend identifier for a media item, library, or server.
///
/// Used as a discriminator on neutral domain types so consumers can branch on
/// backend-specific behavior (e.g. only Plex supports server-side play queues
/// in v1) and so persisted records can round-trip the source of an item.
enum MediaBackend {
  plex,
  jellyfin,
  emby,
  silo;

  String get id => switch (this) {
    MediaBackend.plex => 'plex',
    MediaBackend.jellyfin => 'jellyfin',
    MediaBackend.emby => 'emby',
    MediaBackend.silo => 'silo',
  };

  static MediaBackend fromId(String id) => switch (id) {
    'plex' => MediaBackend.plex,
    'jellyfin' => MediaBackend.jellyfin,
    'emby' => MediaBackend.emby,
    'silo' => MediaBackend.silo,
    _ => throw ArgumentError('Unknown MediaBackend id: $id'),
  };

  /// Like [fromId] but tolerant of persisted values, for JSON deserialization
  /// of cached offline data:
  /// - `null` is the pre-Jellyfin shape, which only Plex wrote, so it reads
  ///   as Plex.
  /// - An unrecognized non-null id logs a warning and returns `null`, so the
  ///   caller drops the row instead of decoding another backend's data as
  ///   Plex.
  static MediaBackend? fromString(String? id) {
    if (id == null) return MediaBackend.plex;
    return switch (id) {
      'plex' => MediaBackend.plex,
      'jellyfin' => MediaBackend.jellyfin,
      'emby' => MediaBackend.emby,
      'silo' => MediaBackend.silo,
      _ => _unknown(id),
    };
  }

  static MediaBackend? _unknown(String id) {
    appLogger.w('Unknown MediaBackend id "$id"; dropping the row');
    return null;
  }

  /// True for backends served by the MediaBrowser HTTP API — Jellyfin and its
  /// Emby ancestor. They share one client stack, one query grammar and one set
  /// of DTO shapes, so behaviour keyed to "not Plex" should test this instead
  /// of comparing against [MediaBackend.jellyfin].
  bool get usesMediaBrowserApi => dialect != null;

  /// The MediaBrowser dialect this backend speaks, or `null` for Plex and
  /// Silo.
  MediaBrowserDialect? get dialect => switch (this) {
    MediaBackend.plex || MediaBackend.silo => null,
    MediaBackend.jellyfin => MediaBrowserDialect.jellyfin,
    MediaBackend.emby => MediaBrowserDialect.emby,
  };
}
