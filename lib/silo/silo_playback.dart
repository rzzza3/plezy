/// The Silo v3 playback contract, as `research/silo-playback.md` sections 2
/// and 9 describe it. Wire shapes are parsed once here. Request bodies follow
/// SiloJson's `encodeDefaults = true, explicitNulls = false`: every default is
/// sent and every null is left out (`S/network/SiloHttpClientImpl.kt:17-23`).
library;

import 'silo_models.dart';

const int siloPlaybackProtocol = 3;
const String siloSequencedProgressFeature = 'sequenced_progress_v1';
const String siloSeekReanchorFeature = 'seek_reanchor_v1';

/// The replans Plezy asks for (`S/model/playback/PlaybackProtocolV3.kt:67-78`).
enum SiloReplanOperation {
  trackChange('track_change'),
  qualityChange('quality_change'),
  seekReanchor('seek_reanchor');

  const SiloReplanOperation(this.wire);

  final String wire;
}

String? _str(SiloJson json, String key) {
  final value = json[key];
  return value is String && value.isNotEmpty ? value : null;
}

int? _integer(SiloJson json, String key) {
  final value = json[key];
  return value is num && value == value.roundToDouble() ? value.toInt() : null;
}

double? _number(SiloJson json, String key) {
  final value = json[key];
  return value is num && value.isFinite ? value.toDouble() : null;
}

List<String> _stringList(SiloJson json, String key) {
  final value = json[key];
  return value is List ? [for (final entry in value) ?(entry is String ? entry : null)] : const [];
}

SiloJson? _object(SiloJson json, String key) {
  final value = json[key];
  return value is Map<String, Object?> ? value : null;
}

/// A file id arrives as a decimal string and must be positive
/// (`S/network/apiv2/WatchDetailV2Api.kt:28-33`).
int _fileId(Object? value, String field) {
  final id = value is String ? int.tryParse(value) : null;
  if (id == null || id <= 0 || '$id' != value) throw SiloDecodeException(field);
  return id;
}

/// One video stream of a file (`S/model/catalog/CatalogModels.kt:397-412`).
class SiloVideoTrack {
  final String? codec;
  final String? profile;
  final int? width;
  final int? height;
  final double? frameRate;
  final bool hdr;
  final String? hdrFormat;

  const SiloVideoTrack({
    this.codec,
    this.profile,
    this.width,
    this.height,
    this.frameRate,
    this.hdr = false,
    this.hdrFormat,
  });

  factory SiloVideoTrack.fromJson(SiloJson json) => SiloVideoTrack(
    codec: _str(json, 'codec'),
    profile: _str(json, 'profile'),
    width: _integer(json, 'width'),
    height: _integer(json, 'height'),
    frameRate: _number(json, 'frame_rate'),
    hdr: json['hdr'] == true,
    hdrFormat: _str(json, 'hdr_format'),
  );
}

class SiloAudioTrack {
  final String? codec;
  final int? channels;
  final String? channelLayout;
  final int? sampleRate;
  final String? language;
  final String? title;
  final bool isDefault;

  const SiloAudioTrack({
    this.codec,
    this.channels,
    this.channelLayout,
    this.sampleRate,
    this.language,
    this.title,
    this.isDefault = false,
  });

  factory SiloAudioTrack.fromJson(SiloJson json) => SiloAudioTrack(
    codec: _str(json, 'codec'),
    channels: _integer(json, 'channels'),
    channelLayout: _str(json, 'layout'),
    sampleRate: _integer(json, 'sample_rate'),
    language: _str(json, 'language'),
    title: _str(json, 'title'),
    isDefault: json['default'] == true,
  );
}

class SiloSubtitleTrack {
  final String? codec;
  final String? language;
  final String? title;
  final bool forced;
  final bool isDefault;

  const SiloSubtitleTrack({this.codec, this.language, this.title, this.forced = false, this.isDefault = false});

  factory SiloSubtitleTrack.fromJson(SiloJson json) => SiloSubtitleTrack(
    codec: _str(json, 'codec'),
    language: _str(json, 'language'),
    title: _str(json, 'title'),
    forced: json['forced'] == true,
    isDefault: json['default'] == true,
  );
}

class SiloFileVersion {
  final int fileId;
  final String? resolution;

  /// Kilobits per second: the test server lists a 1080p H.264 remux at
  /// 26,000.
  final int bitrate;
  final int fileSize;
  final double durationSeconds;
  final String? container;
  final String? fileName;
  final String? filePath;
  final String? videoCodec;
  final String? audioCodec;
  final bool hdr;

  /// The edition the file names, such as `Director's Cut`.
  final String? edition;
  final List<SiloVideoTrack> videoTracks;
  final List<SiloAudioTrack> audioTracks;
  final List<SiloSubtitleTrack> subtitleTracks;
  final int? effectiveAudioTrackIndex;

  const SiloFileVersion({
    required this.fileId,
    this.resolution,
    this.bitrate = 0,
    this.fileSize = 0,
    this.durationSeconds = 0,
    this.container,
    this.fileName,
    this.filePath,
    this.videoCodec,
    this.audioCodec,
    this.hdr = false,
    this.edition,
    this.videoTracks = const [],
    this.audioTracks = const [],
    this.subtitleTracks = const [],
    this.effectiveAudioTrackIndex,
  });

  /// A `versions[]` row of `GET /api/v2/watch/{id}`, which must carry a
  /// finite `duration_seconds` (`S/network/apiv2/WatchDetailV2Api.kt:25-55`).
  factory SiloFileVersion.fromJson(SiloJson json) {
    final duration = json['duration_seconds'];
    if (duration is! num || !duration.isFinite || duration < 0) throw const SiloDecodeException('duration_seconds');
    return SiloFileVersion._fromJson(json, duration.toDouble());
  }

  /// A `versions[]` row of the catalog item detail, whose duration is the
  /// optional `duration` (`S/network/apiv2/CatalogDetailReadV2Models.kt:189-214`).
  factory SiloFileVersion.fromCatalogJson(SiloJson json) {
    final duration = _number(json, 'duration');
    return SiloFileVersion._fromJson(json, duration == null || duration < 0 ? 0 : duration);
  }

  factory SiloFileVersion._fromJson(SiloJson json, double durationSeconds) {
    final video = json['video_tracks'];
    final audio = json['audio_tracks'];
    final subtitles = json['subtitle_tracks'];
    return SiloFileVersion(
      fileId: _fileId(json['file_id'], 'file_id'),
      resolution: _str(json, 'resolution'),
      bitrate: _integer(json, 'bitrate') ?? 0,
      fileSize: _integer(json, 'file_size') ?? 0,
      durationSeconds: durationSeconds,
      container: _str(json, 'container'),
      fileName: _str(json, 'file_name'),
      filePath: _str(json, 'file_path'),
      videoCodec: _str(json, 'codec_video'),
      audioCodec: _str(json, 'codec_audio'),
      hdr: json['hdr'] == true,
      edition: _str(json, 'edition_raw'),
      videoTracks: video is List
          ? [for (final t in siloObjectList(video, 'video_tracks')) SiloVideoTrack.fromJson(t)]
          : const [],
      audioTracks: audio is List
          ? [for (final t in siloObjectList(audio, 'audio_tracks')) SiloAudioTrack.fromJson(t)]
          : const [],
      subtitleTracks: subtitles is List
          ? [for (final t in siloObjectList(subtitles, 'subtitle_tracks')) SiloSubtitleTrack.fromJson(t)]
          : const [],
      effectiveAudioTrackIndex: _integer(json, 'effective_audio_track_index'),
    );
  }
}

typedef SiloTimeRange = ({double start, double end});

/// `GET /api/v2/watch/{id}` (`S/network/apiv2/WatchDetailV2Api.kt:14-55`).
class SiloWatchDetail {
  final String contentId;
  final List<SiloFileVersion> versions;
  final SiloTimeRange? intro;
  final SiloTimeRange? credits;
  final double? positionSeconds;
  final int? lastFileId;

  const SiloWatchDetail({
    required this.contentId,
    required this.versions,
    this.intro,
    this.credits,
    this.positionSeconds,
    this.lastFileId,
  });

  /// The response must name the requested item, and a watch with no versions
  /// cannot play (`T/ui/screens/player/TvVideoPlaybackStarter.kt:97-103`).
  factory SiloWatchDetail.fromJson(Object? body, String requestedId) {
    final json = siloObject(body, 'watch');
    if (json['content_id'] != requestedId) throw const SiloDecodeException('content_id');
    final versions = [for (final v in siloObjectList(json['versions'], 'versions')) SiloFileVersion.fromJson(v)];
    if (versions.isEmpty) throw const SiloDecodeException('versions');
    SiloTimeRange? range(String key) {
      final marker = _object(json, key);
      final start = marker == null ? null : _number(marker, 'start_seconds');
      final end = marker == null ? null : _number(marker, 'end_seconds');
      return start == null || end == null ? null : (start: start, end: end);
    }

    final userData = _object(json, 'user_data');
    final lastFile = userData?['last_file_id'];
    return SiloWatchDetail(
      contentId: requestedId,
      versions: versions,
      intro: range('intro'),
      credits: range('credits'),
      positionSeconds: userData == null ? null : _number(userData, 'position_seconds'),
      lastFileId: lastFile == null ? null : _fileId(lastFile, 'last_file_id'),
    );
  }
}

final RegExp _resolutionHeight = RegExp(r'\b(\d{3,4})(?:p|i)?\b');

/// `S/playback/PlaybackVersionSelector.kt:31-50`.
int siloResolutionRank(String? value) {
  final normalized = value?.trim().toLowerCase() ?? '';
  final numeric = int.tryParse(_resolutionHeight.firstMatch(normalized)?.group(1) ?? '');
  if (numeric != null) return numeric;
  if (normalized.contains('4320') || normalized.contains('8k')) return 4320;
  if (normalized.contains('2160') || normalized.contains('4k') || normalized.contains('uhd')) return 2160;
  if (normalized.contains('1440') || normalized.contains('qhd')) return 1440;
  if (normalized.contains('1080') || normalized.contains('fhd')) return 1080;
  if (normalized.contains('720') || normalized.contains('hd')) return 720;
  if (normalized.contains('576')) return 576;
  if (normalized.contains('480') || normalized.contains('sd')) return 480;
  return 0;
}

int _compareVersions(SiloFileVersion a, SiloFileVersion b) {
  final byRank = siloResolutionRank(a.resolution).compareTo(siloResolutionRank(b.resolution));
  if (byRank != 0) return byRank;
  final byBitrate = a.bitrate.compareTo(b.bitrate);
  return byBitrate != 0 ? byBitrate : a.fileSize.compareTo(b.fileSize);
}

/// The last played file, else the best for `auto` or `original`, else the
/// highest at or below the preferred height (`S/playback/PlaybackVersionSelector.kt:5-29`).
SiloFileVersion selectSiloVersion(List<SiloFileVersion> versions, {int? lastFileId, String? preferredQuality}) {
  if (lastFileId != null) {
    for (final version in versions) {
      if (version.fileId == lastFileId) return version;
    }
  }
  final best = versions.reduce((a, b) => _compareVersions(b, a) > 0 ? b : a);
  final target = preferredQuality?.trim().toLowerCase() ?? '';
  if (target.isEmpty || target == 'auto' || target == 'original') return best;
  final cap = siloResolutionRank(target);
  final sorted = [...versions]..sort((a, b) => _compareVersions(b, a));
  for (final version in sorted) {
    if (siloResolutionRank(version.resolution) <= cap) return version;
  }
  return best;
}

/// The file a start or reload asks for: a version picked before playback
/// names its file id, else [index] points into the live session's
/// [sessionFileIds]. Null leaves the pick to [selectSiloVersion]; the session
/// also falls back to it when the named file is not in the watch detail.
int? siloRequestedFileId({String? sourceId, required int index, required List<int> sessionFileIds}) {
  final requested = int.tryParse(sourceId ?? '');
  if (requested != null && requested > 0) return requested;
  return index >= 0 && index < sessionFileIds.length ? sessionFileIds[index] : null;
}

const double siloResumeRewindSeconds = 7;
const double siloMinResumeForRewindSeconds = 30;

/// The request position: an explicit override as given, else the saved
/// position less the 7 s rewind for resumes of 30 s or more
/// (`S/model/playback/PlaybackStartPosition.kt:17-72`,
/// `T/ui/screens/player/TvVideoPlaybackStarter.kt:203-226`).
double? siloStartPosition({double? override, double? savedPosition}) {
  if (override != null) return override.isFinite && override >= 0 ? override : null;
  final saved = savedPosition;
  if (saved == null || !saved.isFinite || saved <= 0) return null;
  if (saved < siloMinResumeForRewindSeconds) return saved;
  final rewound = saved - siloResumeRewindSeconds;
  return rewound < 0 ? 0 : rewound;
}

sealed class SiloAdmission {
  const SiloAdmission();
}

final class SiloAdmitted extends SiloAdmission {
  final String installationId;

  const SiloAdmitted(this.installationId);
}

final class SiloUpdateRequired extends SiloAdmission {
  const SiloUpdateRequired();
}

final class SiloPlaybackUnavailable extends SiloAdmission {
  const SiloPlaybackUnavailable();
}

/// `GET /api/v2/playback/capabilities`. A 404 means the server must be
/// updated (`S/repository/SequencedPlayback.kt:191-205`).
SiloAdmission siloAdmission(int status, Object? body) {
  if (status == 404) return const SiloUpdateRequired();
  if (status != 200 || body is! Map<String, Object?>) return const SiloPlaybackUnavailable();
  final installation = _str(body, 'installation_id');
  final protocols = body['protocol_versions'];
  final admitted =
      _stringList(body, 'features').contains(siloSequencedProgressFeature) &&
      body['allowed'] == true &&
      body['state'] == 'available' &&
      installation != null &&
      installation.trim().isNotEmpty &&
      protocols is List &&
      protocols.contains(siloPlaybackProtocol);
  return admitted ? SiloAdmitted(installation) : const SiloPlaybackUnavailable();
}

/// Features Plezy's mpv player backs. Android also sends
/// `client_video_transformations_v1` and `device_quirks_v1`, which name
/// Media3 behaviour mpv does not have (port note 2,
/// `S/model/playback/PlaybackProtocolV3.kt:91-118`).
const List<String> siloClientFeatures = ['playback_plan_v3', 'seek_reanchor_v1', 'direct_stream_resume_v1'];

const List<String> _mpvVideoCodecs = ['h264', 'hevc', 'vp9', 'vp8', 'av1', 'mpeg2video', 'mpeg4', 'vc1'];
const List<String> _mpvAudioCodecs = [
  'aac',
  'ac3',
  'eac3',
  'truehd',
  'dts',
  'dts_hd',
  'flac',
  'opus',
  'vorbis',
  'mp3',
  'alac',
];
const List<String> _mpvOriginalContainers = [
  'mp4',
  'm4v',
  'mov',
  'qt',
  'webm',
  'mkv',
  'matroska',
  'avi',
  'ts',
  'mpegts',
  'mpeg-ts',
  'mp3',
  'm4a',
  'm4b',
  'aac',
  'flac',
  'wav',
  'ogg',
  'oga',
  'opus',
];

Map<String, Object?> _subtitleCapabilities({required bool assStyling, required bool fonts}) => {
  'native_embedded': const <Object>[],
  'embedded_text': true,
  'sidecar_text': true,
  'ass_styling': assStyling,
  'embedded_bitmap': true,
  'sidecar_bitmap': true,
  'font_attachments': fonts,
};

Map<String, Object?> _delivery({
  required bool enabled,
  String? failureReason,
  required List<String> containers,
  required Map<String, Object?> subtitles,
  required List<String> features,
}) => {
  'enabled': enabled,
  'supported_on_device': enabled,
  'failure_reason': ?failureReason,
  'containers': containers,
  'video_codecs': _mpvVideoCodecs,
  'audio_decode_codecs': _mpvAudioCodecs,
  'audio_passthrough_codecs': const <String>[],
  'subtitles': subtitles,
  'features': features,
  'transformations': const <Object>[],
  'auth_header_refresh': enabled,
  'validated_claims': const <String>[],
};

/// What mpv can do, at `declared` evidence because libmpv exposes no decoder
/// inventory (`S/model/playback/PlaybackProtocolV3.kt:48-56`). `original_http`
/// and `hls` are on, and `progressive` is off as on Android (port note 1,
/// `A/player/PlaybackCapabilityDetector.kt:513-638`).
Map<String, Object?> siloMpvCodecCapabilities() => {
  'video_evidence': 'declared',
  'audio_evidence': 'declared',
  'codecs_video': _mpvVideoCodecs,
  'codecs_video_hardware': const <String>[],
  'codecs_audio': _mpvAudioCodecs,
  'containers': _mpvOriginalContainers,
  'hdr': false,
  'video_decode': const <Object>[],
};

typedef SiloDeviceFacts = ({
  String formFactor,
  String appVersion,
  String? platform,
  String? osVersion,
  String? manufacturer,
  String? model,
});

Map<String, Object?> siloMpvPlaybackContext(SiloDeviceFacts device) => {
  'protocol_version': siloPlaybackProtocol,
  'form_factor': device.formFactor,
  'app_version': device.appVersion,
  'device': {
    'platform': ?device.platform,
    'os_version': ?device.osVersion,
    'manufacturer': ?device.manufacturer,
    'model': ?device.model,
    'platform_details': const <String, String>{},
  },
  'output': {'current_sink': 'local_output'},
  'deliveries': {
    'original_http': _delivery(
      enabled: true,
      containers: _mpvOriginalContainers,
      subtitles: _subtitleCapabilities(assStyling: true, fonts: true),
      features: const ['track_switching', 'audio_delay', 'subtitle_delay', 'libass_subtitles'],
    ),
    'progressive': _delivery(
      enabled: false,
      failureReason: 'disabled_pending_seekable_transport',
      containers: const ['mp4', 'm4v', 'webm', 'mkv', 'matroska'],
      subtitles: _subtitleCapabilities(assStyling: false, fonts: false),
      features: const ['progressive', 'track_switching'],
    ),
    'hls': _delivery(
      enabled: true,
      containers: const ['m3u8', 'hls'],
      subtitles: _subtitleCapabilities(assStyling: true, fonts: false),
      features: const ['hls', 'track_switching', 'libass_subtitles'],
    ),
  },
};

String siloTrackId(int fileId, String kind, int index) => 'file:$fileId:$kind:$index';

/// The exact `POST /api/v2/playback/start` body, with `installation_id` added
/// and `file_id` as a string (`S/network/apiv2/PlaybackV2Api.kt:69-74`,
/// `A/player/PlaybackSessionManager.kt:352-381`). An off subtitle is left
/// out, never sent as -1 (`:364-373`).
Map<String, Object?> siloStartBody({
  required int fileId,
  required String profileId,
  required String attemptId,
  required String installationId,
  required Map<String, Object?> capabilities,
  required Map<String, Object?> context,
  String qualityPreference = 'auto',
  double? startPosition,
  int? audioTrackIndex,
  int? subtitleTrackIndex,
  int? bandwidthCapKbps,
  bool? allowAlternateVersions,
}) {
  final subtitle = subtitleTrackIndex != null && subtitleTrackIndex >= 0 ? subtitleTrackIndex : null;
  return {
    'protocol_version': siloPlaybackProtocol,
    'client_features': siloClientFeatures,
    'file_id': '$fileId',
    'profile_id': profileId,
    'playback_attempt_id': attemptId,
    'quality_preference': qualityPreference.toLowerCase(),
    'subtitle_fidelity_preference': 'preserve',
    'start_position': ?startPosition,
    'progress_persistence': 'server',
    'audio_track_id': ?(audioTrackIndex == null ? null : siloTrackId(fileId, 'audio', audioTrackIndex)),
    'audio_track_index': ?audioTrackIndex,
    'subtitle_track_id': ?(subtitle == null ? null : siloTrackId(fileId, 'subtitle', subtitle)),
    'subtitle_track_index': ?subtitle,
    'metered': false,
    'bandwidth_cap_kbps': ?(bandwidthCapKbps != null && bandwidthCapKbps > 0 ? bandwidthCapKbps : null),
    'allow_alternate_versions': ?allowAlternateVersions,
    'client_capabilities': capabilities,
    'client_playback_context': context,
    'installation_id': installationId,
  };
}

class SiloStream {
  final String url;
  final String protocol;
  final Map<String, String> headers;
  final String headerRefresh;

  const SiloStream({
    required this.url,
    required this.protocol,
    this.headers = const {},
    this.headerRefresh = 'session',
  });
}

class SiloTimeline {
  final double sourceStartSeconds;
  final double playerStartSeconds;
  final double timelineOffsetSeconds;
  final double? seekWindowStartSeconds;
  final double? seekWindowEndSeconds;
  final bool canSeekAnywhere;

  const SiloTimeline({
    this.sourceStartSeconds = 0,
    this.playerStartSeconds = 0,
    this.timelineOffsetSeconds = 0,
    this.seekWindowStartSeconds,
    this.seekWindowEndSeconds,
    this.canSeekAnywhere = true,
  });

  /// `source = player + offset` (`A/player/seek/PlaybackTimelineSeekPolicy.kt:61-66`).
  double toSource(double playerSeconds) => playerSeconds + timelineOffsetSeconds;

  double toPlayer(double sourceSeconds) => sourceSeconds - timelineOffsetSeconds;

  /// Seek natively inside the window, or anywhere when there is no window and
  /// the plan allows it. Otherwise the server must reanchor
  /// (`A/player/seek/PlaybackTimelineSeekPolicy.kt:131-210`).
  bool canSeekNatively(double sourceSeconds) {
    final start = seekWindowStartSeconds;
    final end = seekWindowEndSeconds;
    if (start == null || end == null) return canSeekAnywhere;
    return sourceSeconds >= start && sourceSeconds <= end;
  }
}

class SiloSubtitleRow {
  final String trackId;
  final int combinedIndex;
  final String source;
  final String? codec;
  final String? language;
  final String? label;
  final bool forced;
  final bool isDefault;
  final String delivery;
  final String? url;

  /// The sync name of an external or downloaded row, `stored-<id>` for a
  /// subtitle the server stored from a provider
  /// (`S/model/playback/PlaybackProtocolV3.kt:381-385`).
  final String? syncKey;

  const SiloSubtitleRow({
    required this.trackId,
    required this.combinedIndex,
    required this.source,
    this.codec,
    this.language,
    this.label,
    this.forced = false,
    this.isDefault = false,
    required this.delivery,
    this.url,
    this.syncKey,
  });

  /// A provider subtitle the server stored for this file. It is never in the
  /// container, so direct play mounts it as a sidecar too.
  bool get isDownloaded => source == 'downloaded';
}

class SiloPlan {
  final String planId;
  final String planAttemptKey;
  final String? sessionId;
  final String delivery;
  final SiloStream stream;
  final SiloTimeline timeline;
  final ({String id, int? index})? selectedAudio;
  final ({String id, int? index})? selectedSubtitle;
  final String subtitleMode;
  final String? subtitleArtifactUrl;
  final bool subtitleEmbedded;
  final List<SiloSubtitleRow> subtitleInventory;
  final List<({String name, String executor, String recipeVersion})> transformations;
  final List<String> runtimeCorrections;
  final String decisionReason;
  final int? effectiveMediaFileId;
  final double? sourceDurationSeconds;

  const SiloPlan({
    required this.planId,
    required this.planAttemptKey,
    this.sessionId,
    required this.delivery,
    required this.stream,
    this.timeline = const SiloTimeline(),
    this.selectedAudio,
    this.selectedSubtitle,
    this.subtitleMode = 'off',
    this.subtitleArtifactUrl,
    this.subtitleEmbedded = false,
    this.subtitleInventory = const [],
    this.transformations = const [],
    this.runtimeCorrections = const [],
    required this.decisionReason,
    this.effectiveMediaFileId,
    this.sourceDurationSeconds,
  });

  bool get isTranscode => delivery == 'server_transcode_hls';
}

/// Every delivery URL is `/api/v2/...` or absolute http(s), never v1
/// (`S/repository/SequencedPlayback.kt:519-527`).
bool _deliveryUrlAllowed(String url) =>
    !url.contains('/api/v1/') &&
    (url.startsWith('/api/v2/') || url.startsWith('https://') || url.startsWith('http://'));

({String id, int? index})? _track(SiloJson? json) {
  final id = json == null ? null : _str(json, 'id');
  return id == null ? null : (id: id, index: _integer(json!, 'index'));
}

int? _optionalFileId(Object? value, String field) {
  if (value == null) return null;
  if (value is num) {
    return value > 0 && value == value.roundToDouble() ? value.toInt() : throw SiloDecodeException(field);
  }
  return _fileId(value, field);
}

SiloPlan _parsePlan(SiloJson json) {
  final stream = siloObject(json['stream'], 'stream');
  final url = _str(stream, 'url') ?? '';
  final protocol = _str(stream, 'protocol');
  if (protocol != 'http_progressive' && protocol != 'hls') throw const SiloDecodeException('stream.protocol');
  if (url.isNotEmpty && !_deliveryUrlAllowed(url)) throw const SiloDecodeException('stream.url');
  final headers = _object(stream, 'headers') ?? const {};
  final timeline = _object(json, 'timeline') ?? const {};
  final selected = _object(json, 'selected_tracks') ?? const {};
  final subtitle = _object(json, 'subtitle') ?? const {};
  final inventory = subtitle['inventory'] is List
      ? siloObjectList(subtitle['inventory'], 'subtitle.inventory')
      : const <SiloJson>[];
  final artifact = _object(subtitle, 'artifact');
  final source = _object(json, 'source') ?? const {};
  final transforms = json['transformations'] is List
      ? siloObjectList(json['transformations'], 'transformations')
      : const <SiloJson>[];
  final rows = [
    for (final row in inventory)
      SiloSubtitleRow(
        trackId: _str(row, 'track_id') ?? '',
        combinedIndex: _integer(row, 'combined_index') ?? -1,
        source: _str(row, 'source') ?? '',
        codec: _str(row, 'codec'),
        language: _str(row, 'language'),
        label: _str(row, 'label'),
        forced: row['forced'] == true,
        isDefault: row['default'] == true,
        delivery: _str(row, 'delivery') ?? '',
        url: _str(row, 'url'),
        syncKey: _str(row, 'sync_key'),
      ),
  ];
  for (final row in rows) {
    final rowUrl = row.url;
    if (rowUrl != null && !_deliveryUrlAllowed(rowUrl)) throw const SiloDecodeException('subtitle.inventory.url');
  }
  return SiloPlan(
    planId: _str(json, 'plan_id') ?? (throw const SiloDecodeException('plan_id')),
    planAttemptKey: _str(json, 'plan_attempt_key') ?? '',
    sessionId: _str(json, 'session_id'),
    delivery: _str(json, 'delivery') ?? (throw const SiloDecodeException('delivery')),
    stream: SiloStream(
      url: url,
      protocol: protocol!,
      headers: {
        for (final e in headers.entries)
          if (e.value is String) e.key: e.value! as String,
      },
      headerRefresh: _str(stream, 'header_refresh') ?? 'session',
    ),
    timeline: SiloTimeline(
      sourceStartSeconds: _number(timeline, 'source_start_seconds') ?? 0,
      playerStartSeconds: _number(timeline, 'player_start_seconds') ?? 0,
      timelineOffsetSeconds: _number(timeline, 'timeline_offset_seconds') ?? 0,
      seekWindowStartSeconds: _number(timeline, 'seek_window_start_seconds'),
      seekWindowEndSeconds: _number(timeline, 'seek_window_end_seconds'),
      canSeekAnywhere: timeline['can_seek_anywhere'] != false,
    ),
    selectedAudio: _track(_object(selected, 'audio')),
    selectedSubtitle: _track(_object(selected, 'subtitle')),
    subtitleMode: _str(subtitle, 'mode') ?? 'off',
    subtitleArtifactUrl: artifact == null ? null : _str(artifact, 'url'),
    subtitleEmbedded: _object(subtitle, 'embedded') != null,
    subtitleInventory: rows,
    transformations: [
      for (final t in transforms)
        (
          name: _str(t, 'name') ?? '',
          executor: _str(t, 'executor') ?? 'server',
          recipeVersion: _str(t, 'recipe_version') ?? '1',
        ),
    ],
    runtimeCorrections: _stringList(json, 'runtime_corrections'),
    decisionReason: _str(json, 'decision_reason') ?? (throw const SiloDecodeException('decision_reason')),
    effectiveMediaFileId: _optionalFileId(json['effective_media_file_id'], 'effective_media_file_id'),
    sourceDurationSeconds: _number(source, 'duration_seconds'),
  );
}

sealed class SiloDecision {
  const SiloDecision();
}

final class SiloPlayable extends SiloDecision {
  final SiloPlan plan;
  final String sessionId;
  final List<String> serverFeatures;

  const SiloPlayable(this.plan, this.sessionId, {this.serverFeatures = const []});
}

final class SiloTerminal extends SiloDecision {
  final String reason;
  final String message;
  final bool retryable;

  const SiloTerminal(this.reason, this.message, {this.retryable = false});
}

/// The server does not speak the neutral v3 contract. Any session it
/// allocated must still be stopped.
final class SiloIncompatible extends SiloDecision {
  final String? sessionId;

  const SiloIncompatible(this.sessionId);
}

final class SiloReplanRequired extends SiloDecision {
  final String reason;
  final SiloPlan plan;
  final String sessionId;

  const SiloReplanRequired(this.reason, this.plan, this.sessionId);
}

const String _invalidPlan = 'invalid_playback_plan';

bool _validInventory(SiloPlan plan) {
  final rows = plan.subtitleInventory;
  final indexes = [for (final r in rows) r.combinedIndex]..sort();
  for (var i = 0; i < indexes.length; i++) {
    if (indexes[i] != i) return false;
  }
  final ids = {for (final r in rows) r.trackId};
  if (rows.any((r) => r.trackId.isEmpty) || ids.length != rows.length) return false;
  for (final row in rows) {
    final hasUrl = row.url != null && row.url!.isNotEmpty;
    if (row.delivery == 'sidecar' && !hasUrl) return false;
    if (row.delivery == 'burn_in_only' && hasUrl) return false;
    if (row.delivery != 'sidecar' && row.delivery != 'burn_in_only') return false;
  }
  final selected = plan.selectedSubtitle;
  if (plan.subtitleArtifactUrl != null && selected == null) return false;
  if (selected == null) return true;
  return rows.any((r) => r.trackId == selected.id && (selected.index == null || r.combinedIndex == selected.index));
}

/// `validateForMedia3` less the Media3-only parts. mpv runs no client
/// transformation and no runtime correction, so any plan naming one asks for
/// a replan, and native embedded subtitle selection is never claimed
/// (`S/model/playback/PlaybackProtocolV3.kt:543-680`).
SiloDecision parseSiloDecision(Object? body) {
  final json = siloObject(body, 'decision');
  final sessionId = _str(json, 'session_id');
  final features = _stringList(json, 'server_features');
  if (json['protocol_version'] != siloPlaybackProtocol ||
      !features.contains('playback_plan_v3') ||
      !features.contains('neutral_playback_v3_contract_v1')) {
    return SiloIncompatible(sessionId);
  }
  final outcome = json['outcome'];
  if (outcome == 'adaptation_unavailable') {
    final terminal = _object(json, 'terminal');
    final reason = terminal == null ? null : _str(terminal, 'reason');
    final message = terminal == null ? null : _str(terminal, 'message');
    if (reason == null || message == null) {
      return const SiloTerminal(
        'invalid_terminal_response',
        'The server returned an incomplete playback terminal response.',
      );
    }
    return SiloTerminal(reason, message, retryable: terminal!['retryable'] == true);
  }
  if (outcome != 'playable') {
    return const SiloTerminal('invalid_playback_outcome', 'The server returned no recognized playback outcome.');
  }
  final rawPlan = _object(json, 'playback_plan');
  if (rawPlan == null) return const SiloTerminal(_invalidPlan, 'The server returned no executable playback plan.');
  final SiloPlan plan;
  try {
    plan = _parsePlan(rawPlan);
  } on SiloDecodeException {
    return const SiloTerminal(_invalidPlan, 'The server returned an unreadable playback plan.');
  }
  final session = plan.sessionId ?? sessionId;
  if (session == null) return const SiloTerminal(_invalidPlan, 'The server returned no playback session identity.');
  if ((_integer(rawPlan, 'protocol_version') ?? siloPlaybackProtocol) != siloPlaybackProtocol) {
    return const SiloTerminal(_invalidPlan, 'The server returned an unsupported plan version.');
  }
  if (plan.planAttemptKey.trim().isEmpty) {
    return const SiloTerminal(_invalidPlan, 'The server returned no plan-attempt identity.');
  }
  if (!_validInventory(plan)) {
    return const SiloTerminal(_invalidPlan, 'The server returned an invalid subtitle inventory.');
  }
  if (plan.subtitleEmbedded) return SiloReplanRequired('subtitle_embedded_failed', plan, session);
  if (plan.stream.url.isEmpty) return const SiloTerminal(_invalidPlan, 'The server returned an empty stream URL.');
  if (plan.stream.headerRefresh == 'refresh_endpoint') {
    return const SiloTerminal(
      'unsupported_header_refresh',
      'This playback plan requires a header refresh mode Plezy cannot execute.',
    );
  }
  if (plan.runtimeCorrections.isNotEmpty) {
    return SiloReplanRequired('unsupported_client_runtime_correction:${plan.runtimeCorrections.first}', plan, session);
  }
  for (final t in plan.transformations) {
    if (t.executor == 'client') {
      return SiloReplanRequired('unsupported_client_transformation:${t.name}:${t.recipeVersion}', plan, session);
    }
  }
  if (plan.delivery == 'original_http' && plan.transformations.any((t) => t.executor == 'server')) {
    return SiloReplanRequired('invalid_original_server_transformation', plan, session);
  }
  return SiloPlayable(plan, session, serverFeatures: features);
}
