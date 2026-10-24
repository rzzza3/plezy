/// Silo's managed downloads, as the phone app runs them
/// (`research/silo-playback.md` section 7): the capability gate, one
/// creation per file, the ranged `/file` stream, the `/manifest` tracks, and
/// revision-bound status reports.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/app_logger.dart';
import 'silo_http.dart';
import 'silo_models.dart';

/// A download call failed. [code] names the failure and [status] the HTTP
/// status when there was one. Neither carries a credential or a URL.
class SiloDownloadException implements Exception {
  final String code;
  final int? status;

  /// Whether a later attempt can succeed with the same partial bytes.
  final bool retriable;

  const SiloDownloadException(this.code, {this.status, this.retriable = false});

  @override
  String toString() => 'SiloDownloadException($code${status == null ? '' : ', HTTP $status'})';
}

/// `GET /api/v2/capabilities/downloads`. Downloads are usable only when the
/// feature is on, this profile may download, and a revisioned capability is
/// `available`.
class SiloDownloadCapability {
  final String? revision;
  final String? state;
  final bool enabled;
  final bool downloadAllowed;
  final List<String> qualityPresets;

  const SiloDownloadCapability({
    this.revision,
    this.state,
    this.enabled = false,
    this.downloadAllowed = false,
    this.qualityPresets = const [],
  });

  factory SiloDownloadCapability.fromJson(Object? body) {
    final json = siloObject(body, 'capability');
    String? text(String key) => json[key] is String ? json[key] as String : null;
    final presets = json['quality_presets'];
    return SiloDownloadCapability(
      revision: text('revision'),
      state: text('state'),
      enabled: json['enabled'] == true,
      downloadAllowed: json['download_allowed'] == true,
      qualityPresets: presets is List ? [for (final p in presets) ?(p is String ? p : null)] : const [],
    );
  }

  bool get isUsable =>
      enabled && downloadAllowed && (revision == null || (revision!.trim().isNotEmpty && state == 'available'));
}

/// One registry entry, accepted only when it belongs to this installation
/// and carries a revision.
class SiloDownloadRecord {
  final String id;
  final String contentId;
  final String? episodeId;
  final String? batchId;
  final String deviceId;
  final int mediaFileId;
  final int fileSize;
  final int bytesSent;
  final String kind;
  final String status;
  final String quality;
  final String? effectiveQuality;
  final String? deliveryFormat;
  final int revision;
  final String? createdAt;
  final String? completedAt;

  const SiloDownloadRecord({
    required this.id,
    required this.contentId,
    this.episodeId,
    this.batchId,
    required this.deviceId,
    required this.mediaFileId,
    this.fileSize = 0,
    this.bytesSent = 0,
    this.kind = 'queued',
    required this.status,
    this.quality = 'original',
    this.effectiveQuality,
    this.deliveryFormat,
    required this.revision,
    this.createdAt,
    this.completedAt,
  });

  factory SiloDownloadRecord.fromJson(Object? body, {required String expectedDevice}) {
    final json = siloObject(body, 'download');
    String required(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
      throw SiloDecodeException(key);
    }

    String? optional(String key) =>
        json[key] is String && (json[key] as String).isNotEmpty ? json[key] as String : null;
    int count(String key) {
      final value = json[key];
      return value is num && value == value.roundToDouble() && value >= 0 ? value.toInt() : 0;
    }

    final id = required('id');
    final device = optional('device_id');
    if (device != expectedDevice) throw const SiloDecodeException('device_id');
    final revision = json['revision'];
    if (revision is! num || revision != revision.roundToDouble() || revision < 1) {
      throw const SiloDecodeException('revision');
    }
    return SiloDownloadRecord(
      id: id,
      contentId: required('content_id'),
      episodeId: optional('episode_id'),
      batchId: optional('batch_id'),
      deviceId: device!,
      mediaFileId: siloDownloadFileId(json['media_file_id']),
      fileSize: count('file_size'),
      bytesSent: count('bytes_sent'),
      kind: optional('kind') ?? 'queued',
      status: optional('status') ?? '',
      quality: optional('quality') ?? 'original',
      effectiveQuality: optional('effective_quality'),
      deliveryFormat: optional('delivery_format'),
      revision: revision.toInt(),
      createdAt: optional('created_at'),
      completedAt: optional('completed_at'),
    );
  }

  bool get isCompleted => status == 'completed';
}

/// `media_file_id` is a positive id, sent as a decimal string and read from
/// either a string or a number.
int siloDownloadFileId(Object? value) {
  final id = switch (value) {
    final String text => int.tryParse(text) is int && '${int.parse(text)}' == text ? int.parse(text) : null,
    final num number when number == number.roundToDouble() => number.toInt(),
    _ => null,
  };
  if (id == null || id <= 0) throw const SiloDecodeException('media_file_id');
  return id;
}

class SiloDownloadRequest {
  final String contentId;
  final String? episodeId;
  final int fileId;
  final String quality;

  const SiloDownloadRequest({required this.contentId, this.episodeId, required this.fileId, this.quality = 'original'});

  Map<String, Object?> toJson() => {
    'content_id': contentId,
    'episode_id': ?episodeId,
    'media_file_id': '$fileId',
    'quality': quality,
  };
}

/// A subtitle sidecar the manifest lists for the delivered file.
class SiloOfflineSubtitle {
  final int ordinal;
  final String fetchUrl;

  /// Canonical format: `srt`, `vtt`, `ass`, `ssa`, `pgs` or `ttml`.
  final String format;
  final String? language;
  final String? title;
  final bool forced;
  final bool hearingImpaired;
  final String? revision;

  const SiloOfflineSubtitle({
    required this.ordinal,
    required this.fetchUrl,
    required this.format,
    this.language,
    this.title,
    this.forced = false,
    this.hearingImpaired = false,
    this.revision,
  });
}

/// The track part of `GET /api/v2/downloads/{id}/manifest`.
class SiloOfflineManifest {
  final String? deliveryFormat;
  final int? selectedAudioTrackIndex;
  final List<SiloJson> audioTracks;

  /// Only the sidecars the player can mount and that sit under this
  /// download's own subtitle path.
  final List<SiloOfflineSubtitle> subtitles;

  const SiloOfflineManifest({
    this.deliveryFormat,
    this.selectedAudioTrackIndex,
    this.audioTracks = const [],
    this.subtitles = const [],
  });

  static SiloOfflineManifest? tryParse(String body) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (json is! Map<String, Object?>) return null;
    final rows = json['subtitles'];
    final audio = json['audio_tracks'];
    final selected = json['selected_audio_track_index'];
    final audioTracks = audio is List ? [for (final a in audio) ?(a is Map<String, Object?> ? a : null)] : <SiloJson>[];
    return SiloOfflineManifest(
      deliveryFormat: json['delivery_format'] is String ? json['delivery_format'] as String : null,
      selectedAudioTrackIndex: selected is int && selected >= 0 && selected < audioTracks.length ? selected : null,
      audioTracks: audioTracks,
      subtitles: [
        if (rows is List)
          for (final (ordinal, row) in rows.indexed)
            if (row is Map<String, Object?>) ?_subtitle(ordinal, row),
      ],
    );
  }

  static SiloOfflineSubtitle? _subtitle(int ordinal, SiloJson row) {
    String? text(String key) {
      final value = row[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    final format = siloOfflineSubtitleFormat(text('format'));
    final url = text('fetch_url');
    if (format == null || url == null || !isSiloOfflineSubtitleFetchUrl(url)) return null;
    return SiloOfflineSubtitle(
      ordinal: ordinal,
      fetchUrl: url,
      format: format,
      language: text('language'),
      title: text('title'),
      forced: row['forced'] == true,
      hearingImpaired: row['hearing_impaired'] == true,
      revision: text('revision'),
    );
  }
}

String? siloOfflineSubtitleFormat(String? format) {
  var value = format?.trim().toLowerCase() ?? '';
  if (value.startsWith('.')) value = value.substring(1);
  return switch (value) {
    'srt' || 'subrip' => 'srt',
    'vtt' || 'webvtt' => 'vtt',
    'ass' => 'ass',
    'ssa' => 'ssa',
    'sup' || 'pgs' || 'hdmv_pgs_subtitle' => 'pgs',
    'ttml' || 'dfxp' => 'ttml',
    _ => null,
  };
}

const String _downloadsPrefix = '/api/v2/downloads/';

/// The manifest's URLs are fetched with this profile's credentials, so only
/// a same-server managed-download subtitle path is followed.
bool isSiloOfflineSubtitleFetchUrl(String url) {
  final trimmed = url.trim();
  if (!trimmed.startsWith(_downloadsPrefix)) return false;
  if (trimmed.contains('://') || trimmed.contains('..') || trimmed.contains(r'\')) return false;
  return trimmed.substring(_downloadsPrefix.length).contains('/subtitles/');
}

String _downloadPath(String id) => '$_downloadsPrefix${Uri.encodeComponent(id)}';

/// The registry and creation calls for one profile on one installation.
/// Every call checks the session still holds [profileId] before and after
/// it runs, because a download belongs to the profile that created it.
class SiloDownloads {
  final SiloHttp http;
  final String profileId;
  final Duration manifestRetryDelay;

  SiloDownloads(this.http, {required this.profileId, this.manifestRetryDelay = const Duration(seconds: 2)});

  String get _device => http.device.id;

  void _requireOwner() {
    if (http.session.session?.profileId != profileId || _device.trim().isEmpty) {
      throw const SiloDownloadException('identity_changed');
    }
  }

  Future<SiloResponse> _send(SiloRequest request) async {
    _requireOwner();
    final response = await http.send(request);
    _requireOwner();
    return response;
  }

  Never _invalid(String code) => throw SiloDownloadException(code);

  Future<SiloDownloadCapability> capability() async {
    final response = await _send(const SiloRequest.get('/api/v2/capabilities/downloads'));
    if (response.statusCode != HttpStatus.ok) {
      throw SiloDownloadException('capability_failed', status: response.statusCode);
    }
    final capability = SiloDownloadCapability.fromJson(response.json());
    if ((capability.revision?.trim().isEmpty ?? true) || (capability.state?.trim().isEmpty ?? true)) {
      _invalid('invalid_download_registry');
    }
    return capability;
  }

  /// Every page, or nothing: a prefix of the registry is never returned.
  Future<List<SiloDownloadRecord>> list() async {
    final rows = <String, SiloDownloadRecord>{};
    final cursors = <String>{};
    String? cursor;
    for (var page = 0; page < 100; page++) {
      final response = await _send(SiloRequest.get('/api/v2/downloads', query: {'limit': '100', 'cursor': ?cursor}));
      if (response.statusCode != HttpStatus.ok) {
        throw SiloDownloadException('list_failed', status: response.statusCode);
      }
      final json = siloObject(response.json(), 'downloads');
      final items = json['items'];
      final info = json['page'];
      if (items is! List || info is! Map<String, Object?> || items.length > 100) _invalid('invalid_download_registry');
      for (final item in items) {
        final SiloDownloadRecord row;
        try {
          row = SiloDownloadRecord.fromJson(item, expectedDevice: _device);
        } on FormatException {
          _invalid('invalid_download_registry');
        }
        if (rows.containsKey(row.id)) _invalid('invalid_download_registry');
        rows[row.id] = row;
      }
      final next = info['next_cursor'] is String ? info['next_cursor'] as String : null;
      if (info['has_more'] != true) {
        if (next != null && next.trim().isNotEmpty) _invalid('invalid_download_registry');
        return rows.values.toList(growable: false);
      }
      if (next == null || next.trim().isEmpty || items.isEmpty || !cursors.add(next)) {
        _invalid('invalid_download_registry');
      }
      cursor = next;
    }
    _invalid('invalid_download_registry');
  }

  /// Reconciles against the registry first: an entry for the same file and
  /// quality that is usable is reused untouched. Otherwise one `POST` goes
  /// out, guarded by the revision it replaces, and is never replayed.
  Future<SiloDownloadRecord> create(SiloDownloadRequest request) async {
    if (request.fileId <= 0) _invalid('invalid_download_creation');
    final listed = await list();
    final matches = [
      for (final row in listed)
        if (row.mediaFileId == request.fileId ||
            (request.episodeId != null && row.episodeId == request.episodeId) ||
            row.episodeId == request.contentId ||
            (row.contentId == request.contentId && (row.episodeId == null || row.episodeId!.trim().isEmpty)))
          row,
    ];
    if (matches.length > 1) _invalid('invalid_download_creation');
    final existing = matches.firstOrNull;
    if (existing != null &&
        existing.mediaFileId == request.fileId &&
        existing.quality == request.quality &&
        const {'ready', 'preparing', 'queued', 'downloading', 'completed'}.contains(existing.status)) {
      return existing;
    }
    final response = await _send(
      SiloRequest(
        'POST',
        '/api/v2/downloads',
        query: const {'limit': '100'},
        body: {
          ...request.toJson(),
          'expected_revision': existing?.revision ?? 0,
          'expected_download_id': ?existing?.id,
        },
        single: true,
      ),
    );
    if (response.statusCode != HttpStatus.accepted) {
      throw SiloDownloadException(
        response.problem?.code ?? 'create_failed',
        status: response.statusCode,
        retriable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }
    final json = siloObject(response.json(), 'downloads');
    final items = json['items'];
    final skipped = json['skipped'];
    final info = json['page'];
    if (items is! List ||
        items.length != 1 ||
        (skipped is List && skipped.isNotEmpty) ||
        info is! Map<String, Object?> ||
        info['has_more'] == true ||
        (info['next_cursor'] is String && (info['next_cursor'] as String).isNotEmpty)) {
      _invalid('invalid_download_creation');
    }
    final SiloDownloadRecord row;
    try {
      row = SiloDownloadRecord.fromJson(items.single, expectedDevice: _device);
    } on FormatException {
      _invalid('invalid_download_creation');
    }
    if (row.mediaFileId != request.fileId || row.quality != request.quality) _invalid('invalid_download_creation');
    return row;
  }

  /// `PATCH /downloads/{id}`: one local status event at [revision]. [updatedAt]
  /// is when the local state changed, so a resend is the same event. A moved
  /// revision answers 409.
  Future<SiloDownloadRecord> reportStatus(
    String id, {
    required String status,
    required DateTime updatedAt,
    required int revision,
  }) async {
    if (id.trim().isEmpty || revision < 1 || (status != 'downloading' && status != 'completed')) {
      _invalid('invalid_download_registry');
    }
    final response = await _send(
      SiloRequest(
        'PATCH',
        _downloadPath(id),
        body: {'status': status, 'updated_at': updatedAt.toUtc().toIso8601String(), 'revision': revision},
      ),
    );
    if (response.statusCode == HttpStatus.conflict) {
      throw SiloDownloadException('revision_moved', status: response.statusCode);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SiloDownloadException('report_failed', status: response.statusCode);
    }
    final SiloDownloadRecord row;
    try {
      row = SiloDownloadRecord.fromJson(response.json(), expectedDevice: _device);
    } on FormatException {
      _invalid('invalid_download_registry');
    }
    if (row.id != id) _invalid('invalid_download_registry');
    return row;
  }

  /// One attempt, expecting 204.
  Future<void> delete(String id) async {
    final response = await _send(SiloRequest('DELETE', _downloadPath(id), single: true));
    if (response.statusCode != HttpStatus.noContent) {
      throw SiloDownloadException('delete_failed', status: response.statusCode);
    }
  }

  /// Three tries for a network failure, a 5xx or a 429. Any other status
  /// means the server has no manifest, and null is returned at once.
  Future<SiloOfflineManifest?> manifest(String id, {int attempts = 3}) async {
    for (var attempt = 0; attempt < attempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(manifestRetryDelay * attempt);
      try {
        final response = await _send(SiloRequest.get('${_downloadPath(id)}/manifest'));
        if (response.statusCode == HttpStatus.ok) return SiloOfflineManifest.tryParse(response.body);
        appLogger.i('Silo downloads: manifest unavailable (HTTP ${response.statusCode})');
        if (response.statusCode < 500 && response.statusCode != HttpStatus.tooManyRequests) return null;
      } on SiloDownloadException {
        rethrow;
      } on Exception catch (error) {
        appLogger.i('Silo downloads: manifest fetch failed (${error.runtimeType})');
      }
    }
    return null;
  }

  /// Saves one manifest sidecar to [target]. Only a vetted subtitle path is
  /// fetched, at most 256 MiB, and it lands whole or not at all.
  Future<void> fetchSidecar(String fetchUrl, File target) async {
    final path = Uri.parse(fetchUrl.trim());
    if (!isSiloOfflineSubtitleFetchUrl(fetchUrl) || path.hasScheme || path.hasAuthority) {
      throw const SiloDownloadException('invalid_subtitle_reference');
    }
    _requireOwner();
    final response = await http.openStream(fetchUrl.trim());
    if (response.statusCode != HttpStatus.ok) {
      await response.stream.drain<void>();
      throw SiloDownloadException('subtitle_failed', status: response.statusCode);
    }
    final partial = File('${target.path}.part');
    final sink = partial.openWrite();
    var written = 0;
    try {
      await for (final chunk in response.stream.timeout(siloDownloadIdleTimeout)) {
        written += chunk.length;
        if (written > _maxSidecarBytes) throw const SiloDownloadException('subtitle_too_large');
        sink.add(chunk);
      }
      await sink.close();
      if (written == 0) throw const SiloDownloadException('subtitle_empty');
      await partial.rename(target.path);
    } on Object {
      await sink.close().catchError((Object _) {});
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}

const int _maxSidecarBytes = 256 * 1024 * 1024;

/// No total limit on a transfer, only on silence between chunks.
const Duration siloDownloadIdleTimeout = Duration(seconds: 60);

/// `Content-Range: bytes start-end/total`, with a null total for `*`.
typedef SiloContentRange = ({int start, int end, int? total});

final RegExp _contentRange = RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$', caseSensitive: false);

SiloContentRange? parseSiloContentRange(String? header) {
  final match = _contentRange.firstMatch(header?.trim() ?? '');
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  if (start == null || end == null || end < start) return null;
  final token = match.group(3)!;
  final total = token == '*' ? null : int.tryParse(token);
  if (token != '*' && (total == null || total <= end)) return null;
  return (start: start, end: end, total: total);
}

/// The `If-Range` validator: a strong ETag, else `Last-Modified`. A weak ETag
/// is not valid for a byte range.
String? siloResumeValidator(Map<String, String> headers) {
  final etag = headers['etag']?.trim();
  if (etag != null && etag.isNotEmpty && !etag.startsWith('W/')) return etag;
  final modified = headers['last-modified']?.trim();
  return modified == null || modified.isEmpty ? null : modified;
}

/// What a resume needs to prove its partial came from the same entity:
/// written beside the partial, holding ids and the validator only.
class SiloResumeState {
  final String downloadId;
  final int revision;
  final String validator;

  const SiloResumeState({required this.downloadId, required this.revision, required this.validator});

  static Future<SiloResumeState?> read(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) return null;
      final id = json['download_id'];
      final revision = json['revision'];
      final validator = json['validator'];
      if (id is! String || revision is! int || validator is! String || validator.trim().isEmpty) return null;
      return SiloResumeState(downloadId: id, revision: revision, validator: validator);
    } on Exception {
      return null;
    }
  }

  Future<void> write(File file) => file.writeAsString(
    jsonEncode({'download_id': downloadId, 'revision': revision, 'validator': validator}),
    flush: true,
  );
}

/// Stops a running transfer. The partial stays for a resume unless the
/// caller deletes it.
class SiloTransferCancel {
  bool _cancelled = false;
  final Completer<void> _signal = Completer<void>();

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _signal.complete();
  }
}

class SiloTransferCancelledException implements Exception {
  const SiloTransferCancelledException();

  @override
  String toString() => 'SiloTransferCancelledException';
}

/// Streams `GET /downloads/{id}/file` into [target]. Bytes go to
/// `<target>.part`; the validator of a fresh response goes to
/// `<target>.part.silo`. A later run at the same id and revision resumes
/// with `Range` and `If-Range`, appends on a matching 206, and starts over
/// on a 200. A 416 drops the partial and starts from zero.
class SiloDownloadTransfer {
  final SiloDownloads downloads;
  final DateTime Function() now;

  SiloDownloadTransfer(this.downloads, {DateTime Function()? now}) : now = now ?? DateTime.now;

  static File partialFor(File target) => File('${target.path}.part');
  static File resumeStateFor(File target) => File('${target.path}.part.silo');

  /// Drops the partial bytes and their validator.
  static Future<void> discard(File target) async {
    for (final file in [partialFor(target), resumeStateFor(target)]) {
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> run({
    required SiloDownloadRecord record,
    required File target,
    void Function(int written, int total)? onProgress,
    SiloTransferCancel? cancel,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _attempt(record, target, onProgress, cancel);
        return;
      } on _RangeNotSatisfiable {
        if (attempt > 0) throw const SiloDownloadException('range_not_satisfiable', status: 416, retriable: true);
        appLogger.i('Silo downloads: partial rejected with 416, restarting from zero');
      }
    }
  }

  Future<void> _attempt(
    SiloDownloadRecord record,
    File target,
    void Function(int written, int total)? onProgress,
    SiloTransferCancel? cancel,
  ) async {
    final partial = partialFor(target);
    final stateFile = resumeStateFor(target);
    final state = await SiloResumeState.read(stateFile);
    final resumeFrom = await partial.exists() ? await partial.length() : 0;
    final canResume =
        state != null && state.downloadId == record.id && state.revision == record.revision && resumeFrom > 0;

    if (cancel?.isCancelled ?? false) throw const SiloTransferCancelledException();
    downloads._requireOwner();
    final response = await downloads.http.openStream(
      '${_downloadPath(record.id)}/file',
      headers: {
        'Accept-Encoding': 'identity',
        if (canResume) ...{'Range': 'bytes=$resumeFrom-', 'If-Range': state.validator},
      },
    );
    if (canResume && response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      await response.stream.drain<void>();
      await discard(target);
      throw const _RangeNotSatisfiable();
    }
    if (response.statusCode == HttpStatus.conflict) {
      await response.stream.drain<void>();
      throw const SiloDownloadException('download_preparing', status: HttpStatus.conflict, retriable: true);
    }
    final status = response.statusCode;
    if (status != HttpStatus.ok && status != HttpStatus.partialContent) {
      await response.stream.drain<void>();
      throw SiloDownloadException(
        'file_failed',
        status: status,
        retriable: status >= 500 || status == 401 || status == 408 || status == 429,
      );
    }

    final range = parseSiloContentRange(response.headers['content-range']);
    final resuming = canResume && status == HttpStatus.partialContent && range != null && range.start == resumeFrom;
    if (status == HttpStatus.partialContent && !resuming) {
      await response.stream.drain<void>();
      throw const SiloDownloadException('unusable_partial_response', retriable: true);
    }

    final int total;
    var written = 0;
    final IOSink sink;
    if (resuming) {
      total = range.total ?? -1;
      written = resumeFrom;
      sink = partial.openWrite(mode: FileMode.append);
      appLogger.i('Silo downloads: resuming at byte $resumeFrom');
    } else {
      await target.parent.create(recursive: true);
      total = int.tryParse(response.headers['content-length'] ?? '') ?? -1;
      sink = partial.openWrite();
      final validator = siloResumeValidator(response.headers);
      if (validator == null) {
        if (await stateFile.exists()) await stateFile.delete();
      } else {
        await SiloResumeState(downloadId: record.id, revision: record.revision, validator: validator).write(stateFile);
      }
    }

    final startedAt = now();
    await _report(record, 'downloading', startedAt);

    int shownTotal() => total > 0 ? total : (record.fileSize >= written ? record.fileSize : -1);
    final done = Completer<void>();
    StreamSubscription<List<int>>? subscription;
    void finish([Object? error]) {
      if (done.isCompleted) return;
      error == null ? done.complete() : done.completeError(error);
    }

    subscription = response.stream
        .timeout(siloDownloadIdleTimeout)
        .listen(
          (chunk) {
            sink.add(chunk);
            written += chunk.length;
            onProgress?.call(written, shownTotal());
          },
          onError: (Object error) => finish(error),
          onDone: finish,
          cancelOnError: true,
        );
    unawaited(cancel?._signal.future.then((_) => finish(const SiloTransferCancelledException())));
    try {
      await done.future;
    } finally {
      await subscription.cancel();
      await sink.close();
    }

    if (total > 0 && written != total) {
      throw const SiloDownloadException('truncated_download', retriable: true);
    }
    if (await target.exists()) await target.delete();
    await partial.rename(target.path);
    if (await stateFile.exists()) await stateFile.delete();

    final completedAt = now();
    final after = startedAt.add(const Duration(milliseconds: 1));
    await _report(record, 'completed', completedAt.isAfter(after) ? completedAt : after);
  }

  Future<void> _report(SiloDownloadRecord record, String status, DateTime at) async {
    try {
      await downloads.reportStatus(record.id, status: status, updatedAt: at, revision: record.revision);
    } on SiloDownloadException catch (error) {
      if (error.code == 'identity_changed') rethrow;
      appLogger.w('Silo downloads: $status report failed (${error.code})');
    } on Exception catch (error) {
      appLogger.w('Silo downloads: $status report failed (${error.runtimeType})');
    }
  }
}

class _RangeNotSatisfiable implements Exception {
  const _RangeNotSatisfiable();
}

/// `POST /api/v1/sync/progress`, the personal-data progress path an offline
/// playback reports through instead of a playback session. [position] and
/// [duration] are source seconds; [recordedAt] is when the position was
/// observed, so a late replay does not beat a newer one.
Future<void> siloSyncProgress(
  SiloHttp http, {
  required String contentId,
  required double position,
  required double duration,
  DateTime? recordedAt,
}) async {
  if (contentId.trim().isEmpty || !position.isFinite || position < 0) return;
  final response = await http.send(
    SiloRequest.post(
      '/api/v1/sync/progress',
      body: {
        'items': [
          {
            'media_item_id': contentId,
            'position': position,
            'duration': duration.isFinite && duration > 0 ? duration : 0.0,
            'force_overwrite': true,
            'updated_at': ?recordedAt?.toUtc().toIso8601String(),
          },
        ],
      },
    ),
  );
  if (!response.isSuccess) throw SiloDownloadException('progress_sync_failed', status: response.statusCode);
  final Object? json;
  try {
    json = jsonDecode(response.body);
  } on FormatException {
    return;
  }
  final results = json is Map<String, Object?> ? json['results'] : null;
  if (results is! List) return;
  for (final result in results) {
    if (result is Map<String, Object?> && result['media_item_id'] == contentId && result['status'] != 'ok') {
      throw const SiloDownloadException('progress_sync_rejected');
    }
  }
}
