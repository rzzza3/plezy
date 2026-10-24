import '../utils/app_logger.dart';

/// Backend identifier for a media item, library, or server.
///
/// Silo is the only backend. The enum stays as the persisted discriminator,
/// so stored records keep round-tripping their source and rows written by a
/// removed backend can be recognised and dropped.
enum MediaBackend {
  silo;

  String get id => switch (this) {
    MediaBackend.silo => 'silo',
  };

  /// Ids written by backends Plezy no longer ships. Their rows are dropped.
  static const removedIds = {'plex', 'jellyfin', 'emby'};

  static MediaBackend fromId(String id) => switch (id) {
    'silo' => MediaBackend.silo,
    _ => throw ArgumentError('Unknown MediaBackend id: $id'),
  };

  /// Like [fromId] but tolerant of persisted values, for JSON deserialization
  /// of cached offline data and stored rows. `null` (the oldest stored shape,
  /// which only Plex wrote) and any other id, including the [removedIds],
  /// log a warning and return `null`, so the caller drops the row instead of
  /// decoding another backend's data as Silo.
  static MediaBackend? fromString(String? id) {
    if (id == 'silo') return MediaBackend.silo;
    appLogger.w('Unknown MediaBackend id "$id"; dropping the row');
    return null;
  }
}
