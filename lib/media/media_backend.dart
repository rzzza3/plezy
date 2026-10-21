import '../utils/app_logger.dart';

/// Backend identifier for a media item, library, or server.
///
/// Used as a discriminator on neutral domain types so consumers can branch on
/// backend-specific behavior (e.g. only Plex supports server-side play queues
/// in v1) and so persisted records can round-trip the source of an item.
enum MediaBackend {
  plex,
  silo;

  String get id => switch (this) {
    MediaBackend.plex => 'plex',
    MediaBackend.silo => 'silo',
  };

  static MediaBackend fromId(String id) => switch (id) {
    'plex' => MediaBackend.plex,
    'silo' => MediaBackend.silo,
    _ => throw ArgumentError('Unknown MediaBackend id: $id'),
  };

  /// Like [fromId] but tolerant of persisted values, for JSON deserialization
  /// of cached offline data and stored rows:
  /// - `null` is the oldest stored shape, which only Plex wrote, so it reads
  ///   as Plex.
  /// - An unrecognized non-null id, including a backend Plezy no longer
  ///   ships, logs a warning and returns `null`, so the caller drops the row
  ///   instead of decoding another backend's data as Plex.
  static MediaBackend? fromString(String? id) {
    if (id == null) return MediaBackend.plex;
    return switch (id) {
      'plex' => MediaBackend.plex,
      'silo' => MediaBackend.silo,
      _ => _unknown(id),
    };
  }

  static MediaBackend? _unknown(String id) {
    appLogger.w('Unknown MediaBackend id "$id"; dropping the row');
    return null;
  }
}
