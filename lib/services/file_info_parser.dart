import '../media/media_file_info.dart';
import '../media/media_source_info.dart';
import '../utils/json_utils.dart';
import 'plex_constants.dart';

/// Backend-agnostic stream-array walker. Backends express the per-source
/// stream list (video/audio/subtitle entries) as `List<dynamic>` under
/// different field names; the per-backend [FileInfoStreamReader]
/// implementations encapsulate the naming differences so the call sites in
/// each client can hand a streams array straight to [walkStreams].
enum FileInfoStreamType { video, audio, subtitle }

/// Single-pass result of walking a streams array. Keeps the raw
/// `videoStream` map pointer (for callers that need to dig out keys the
/// parsed track classes don't carry — e.g. `colorSpace`, `BitDepth`,
/// `BitRate`) and the parsed neutral track lists.
class FileInfoStreams {
  final Map<String, dynamic>? videoStream;
  final List<MediaAudioTrack> audioTracks;
  final List<MediaSubtitleTrack> subtitleTracks;

  const FileInfoStreams({required this.videoStream, required this.audioTracks, required this.subtitleTracks});

  static const empty = FileInfoStreams(videoStream: null, audioTracks: [], subtitleTracks: []);
}

abstract class FileInfoStreamReader {
  /// Classify a raw stream entry — return null to skip (unknown / irrelevant).
  FileInfoStreamType? typeOf(Map<String, dynamic> stream);

  /// Build a neutral [MediaAudioTrack] from a backend-specific audio entry.
  /// [autoIndex] is the 1-based ordinal of this track among audio entries
  /// in the streams array; backends that lack a stable per-stream `id` can
  /// fall back to it.
  MediaAudioTrack toAudioTrack(Map<String, dynamic> stream, int autoIndex);

  /// Build a neutral [MediaSubtitleTrack] from a backend-specific subtitle
  /// entry. See [autoIndex] note on [toAudioTrack].
  MediaSubtitleTrack toSubtitleTrack(Map<String, dynamic> stream, int autoIndex);
}

typedef MalformedStreamHandler = void Function(Object error, StackTrace stackTrace, Map<String, dynamic> stream);

/// Walk [streams] in a single pass. Captures the first video entry (later
/// ones are ignored — both backends serve a single primary track per type),
/// accumulates *all* audio / subtitle tracks for selection UIs, and keeps
/// the raw video stream for display-metadata parsing.
FileInfoStreams walkStreams(
  List<dynamic>? streams,
  FileInfoStreamReader reader, {
  MalformedStreamHandler? onMalformed,
}) {
  if (streams == null || streams.isEmpty) return FileInfoStreams.empty;
  final audioTracks = <MediaAudioTrack>[];
  final subtitleTracks = <MediaSubtitleTrack>[];
  Map<String, dynamic>? videoStream;
  var audioIndex = 0;
  var subtitleIndex = 0;
  for (final raw in streams) {
    if (raw is! Map<String, dynamic>) continue;
    try {
      final type = reader.typeOf(raw);
      if (type == null) continue;
      switch (type) {
        case FileInfoStreamType.video:
          videoStream ??= raw;
        case FileInfoStreamType.audio:
          audioIndex++;
          audioTracks.add(reader.toAudioTrack(raw, audioIndex));
        case FileInfoStreamType.subtitle:
          subtitleIndex++;
          subtitleTracks.add(reader.toSubtitleTrack(raw, subtitleIndex));
      }
    } catch (error, stackTrace) {
      if (onMalformed == null) rethrow;
      onMalformed(error, stackTrace, raw);
    }
  }
  return FileInfoStreams(videoStream: videoStream, audioTracks: audioTracks, subtitleTracks: subtitleTracks);
}

/// Reader for Plex's `Part.Stream[]` entries. Field naming follows Plex's
/// camelCase: `streamType` (1=video, 2=audio, 3=subtitle), numeric `id`,
/// `language`/`languageCode`, `selected`/`forced` arrive as bool-ish strings
/// or 0/1 ints (handled by [flexibleBool]).
class PlexFileInfoStreamReader implements FileInfoStreamReader {
  const PlexFileInfoStreamReader();

  @override
  FileInfoStreamType? typeOf(Map<String, dynamic> stream) {
    final t = flexibleInt(stream['streamType']);
    return switch (t) {
      PlexStreamType.video => FileInfoStreamType.video,
      PlexStreamType.audio => FileInfoStreamType.audio,
      PlexStreamType.subtitle => FileInfoStreamType.subtitle,
      _ => null,
    };
  }

  @override
  MediaAudioTrack toAudioTrack(Map<String, dynamic> stream, int _) {
    return MediaAudioTrack(
      id: flexibleInt(stream['id']) ?? (throw const FormatException('Plex audio stream is missing a numeric id')),
      index: flexibleInt(stream['index']),
      codec: stream['codec'] as String?,
      language: stream['language'] as String?,
      languageCode: stream['languageCode'] as String?,
      title: stream['title'] as String?,
      displayTitle: stream['displayTitle'] as String?,
      channels: flexibleInt(stream['channels']),
      selected: flexibleBool(stream['selected']),
      isDefault: flexibleBool(stream['default']),
    );
  }

  @override
  MediaSubtitleTrack toSubtitleTrack(Map<String, dynamic> stream, int _) {
    return MediaSubtitleTrack(
      id: flexibleInt(stream['id']) ?? (throw const FormatException('Plex subtitle stream is missing a numeric id')),
      index: flexibleInt(stream['index']),
      codec: stream['codec'] as String?,
      language: stream['language'] as String?,
      languageCode: stream['languageCode'] as String?,
      title: stream['title'] as String?,
      displayTitle: stream['displayTitle'] as String?,
      selected: flexibleBool(stream['selected']),
      forced: flexibleBool(stream['forced']),
      key: stream['key'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Full per-stream detail extraction for the file-info sheet.
//
// [walkStreams] above deliberately keeps only what playback needs. The sheet
// needs every probed property, so these builders read the raw stream maps a
// second time and project them onto the neutral [MediaStreamDetails]. Both
// backends' field-name maps live side by side here for the same reason the
// readers above do: one place to compare when a server adds a key.
// ---------------------------------------------------------------------------

/// Classify a Plex `Part.Stream[]` entry. Plex numbers stream types 1–4
/// ([PlexStreamType]); anything else maps to [MediaStreamKind.unknown].
///
/// Type 4 is lyrics, not an embedded image — music tracks are the only items
/// that carry it, so the mismatch only became visible once File Info was
/// offered for tracks.
MediaStreamKind plexStreamKind(Map<String, dynamic> s) => switch (flexibleInt(s['streamType'])) {
  PlexStreamType.video => MediaStreamKind.video,
  PlexStreamType.audio => MediaStreamKind.audio,
  PlexStreamType.subtitle => MediaStreamKind.subtitle,
  PlexStreamType.lyrics => MediaStreamKind.lyric,
  _ => MediaStreamKind.unknown,
};

/// Project a Plex `Part.Stream[]` entry. [ordinal] is the 1-based position
/// among streams of the same kind.
MediaStreamDetails plexStreamDetails(Map<String, dynamic> s, int ordinal) {
  final kind = plexStreamKind(s);
  final dolbyVision = _plexDolbyVision(s);
  return MediaStreamDetails(
    kind: kind,
    ordinal: ordinal,
    id: s['id']?.toString(),
    index: flexibleInt(s['index']),
    title: _text(s['title']),
    displayTitle: _text(s['extendedDisplayTitle']) ?? _text(s['displayTitle']),
    codec: _text(s['codec']),
    codecTag: _text(s['codecID']),
    profile: _text(s['profile']),
    level: flexibleInt(s['level']),
    language: _text(s['language']),
    languageCode: _text(s['languageCode']) ?? _text(s['languageTag']),
    // Plex already reports stream bitrates in kbps.
    bitrateKbps: flexibleInt(s['bitrate']),
    isDefault: flexibleBoolNullable(s['default']),
    isForced: flexibleBoolNullable(s['forced']),
    isSelected: flexibleBoolNullable(s['selected']),
    isExternal: _plexIsExternal(s),
    isHearingImpaired: flexibleBoolNullable(s['hearingImpaired']),
    isDub: flexibleBoolNullable(s['dub']),
    isOriginal: flexibleBoolNullable(s['original']),
    width: flexibleInt(s['width']),
    height: flexibleInt(s['height']),
    codedWidth: flexibleInt(s['codedWidth']),
    codedHeight: flexibleInt(s['codedHeight']),
    frameRate: flexibleDouble(s['frameRate']),
    scanType: _text(s['scanType']),
    isInterlaced: _plexInterlaced(s),
    bitDepth: flexibleInt(s['bitDepth']),
    refFrames: flexibleInt(s['refFrames']),
    colorSpace: _text(s['colorSpace']),
    colorRange: _text(s['colorRange']),
    colorPrimaries: _text(s['colorPrimaries']),
    colorTransfer: _text(s['colorTrc']),
    chromaSubsampling: _text(s['chromaSubsampling']),
    chromaLocation: _text(s['chromaLocation']),
    pixelAspectRatio: _text(s['pixelAspectRatio']),
    isAnamorphic: flexibleBoolNullable(s['anamorphic']),
    videoRange: kind == MediaStreamKind.video ? _plexVideoRange(s, dolbyVision) : MediaVideoRange.unknown,
    dolbyVision: dolbyVision,
    hasScalingMatrix: flexibleBoolNullable(s['hasScalingMatrix']),
    streamIdentifier: _text(s['streamIdentifier']),
    channels: flexibleInt(s['channels']),
    channelLayout: _text(s['audioChannelLayout']),
    sampleRate: flexibleInt(s['samplingRate']),
    subtitleFormat: _text(s['format']),
    providerTitle: _text(s['providerTitle']),
    score: flexibleInt(s['score']),
    externalKey: _text(s['key']),
    isTransient: flexibleBoolNullable(s['transient']),
    sourceKey: _text(s['sourceKey']),
    comment: _text(s['comment']),
    hasDescriptions: flexibleBoolNullable(s['descriptions']),
    headerCompression: flexibleBoolNullable(s['headerCompression']),
  );
}

/// Trim and drop empties — both servers emit `""` for "not probed", and an
/// empty row is worse than an absent one.
String? _text(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// Plex marks sidecar subtitles with a `/library/streams/...` key rather than
/// an explicit flag.
bool? _plexIsExternal(Map<String, dynamic> s) {
  if (flexibleInt(s['streamType']) != PlexStreamType.subtitle) return null;
  final key = s['key'];
  return key is String && key.isNotEmpty;
}

bool? _plexInterlaced(Map<String, dynamic> s) {
  final scanType = _text(s['scanType'])?.toLowerCase();
  return scanType == null ? null : scanType != 'progressive';
}

MediaDolbyVisionInfo? _plexDolbyVision(Map<String, dynamic> s) {
  if (!flexibleBool(s['DOVIPresent'])) return null;
  return MediaDolbyVisionInfo(
    profile: flexibleInt(s['DOVIProfile']),
    level: flexibleInt(s['DOVILevel']),
    version: _text(s['DOVIVersion']),
    blCompatibilityId: flexibleInt(s['DOVIBLCompatID']),
    blPresent: flexibleBoolNullable(s['DOVIBLPresent']),
    elPresent: flexibleBoolNullable(s['DOVIELPresent']),
    rpuPresent: flexibleBoolNullable(s['DOVIRPUPresent']),
  );
}

/// Plex reports no dynamic-range field, so classify from the Dolby Vision
/// block first and fall back to the transfer characteristics.
MediaVideoRange _plexVideoRange(Map<String, dynamic> s, MediaDolbyVisionInfo? dolbyVision) {
  if (dolbyVision != null) {
    // `dv_bl_signal_compatibility_id`: 1 = HDR10, 2 = SDR/BT.709, 4 = HLG,
    // 6 = Blu-ray HDR10. Profile 7 always carries an HDR10 base layer, and
    // profile 5 carries none (0), so it stays plain Dolby Vision.
    final compatibility = dolbyVision.blCompatibilityId;
    if (compatibility == 4) return MediaVideoRange.dolbyVisionHlg;
    if (dolbyVision.profile == 7 || compatibility == 1 || compatibility == 6) {
      return MediaVideoRange.dolbyVisionHdr10;
    }
    return MediaVideoRange.dolbyVision;
  }
  return switch (_text(s['colorTrc'])?.toLowerCase()) {
    'smpte2084' => MediaVideoRange.hdr10,
    'arib-std-b67' => MediaVideoRange.hlg,
    null => MediaVideoRange.unknown,
    _ => MediaVideoRange.sdr,
  };
}

