import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../utils/app_logger.dart';
import 'silo_http.dart';
import 'silo_playback.dart';
import 'silo_playback_journal.dart';

/// Why a start produced nothing to play. [reason] is a stable code, safe to
/// log. [message] may come from the server and is for the screen only.
class SiloPlaybackFailure implements Exception {
  final String reason;
  final String message;

  const SiloPlaybackFailure(this.reason, this.message);

  @override
  String toString() => 'SiloPlaybackFailure($reason)';
}

String newSiloAttemptId() {
  final random = Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

Object? _json(SiloResponse response) {
  try {
    return jsonDecode(response.body);
  } on FormatException {
    return null;
  }
}

/// What the player needs from one started session.
typedef SiloPlaybackRequest = ({
  String contentId,
  String profileId,
  SiloDeviceFacts device,
  int? fileId,
  String quality,
  double? startPosition,
  int? audioTrackIndex,
  int? bandwidthCapKbps,
});

/// One server playback session from start to stop, journalled throughout
/// (`S/repository/SequencedPlayback.kt`).
class SiloPlaybackSession {
  final SiloHttp http;
  final SiloPlaybackJournal journal;
  final SiloWatchDetail detail;
  final SiloFileVersion version;
  final String sessionId;
  final Map<String, Object?> _capabilities;
  final Map<String, Object?> _context;
  String _quality;
  final int? _bandwidthCap;
  SiloPlan _plan;
  String _planAttemptId = newSiloAttemptId();
  final List<String> _attemptedKeys = [];
  int _attemptCount = 1;
  final Future<void> Function(Duration delay) _wait;
  SiloJournalEntry _entry;
  bool _stopped = false;

  SiloPlaybackSession._(
    this.http,
    this.journal,
    this.detail,
    this.version,
    this._plan,
    this.sessionId,
    this._entry,
    this._wait,
    this._capabilities,
    this._context,
    this._quality,
    this._bandwidthCap,
  );

  SiloPlan get plan => _plan;

  String get quality => _quality;

  bool get isStopped => _stopped;

  /// Admission, a stop for each session an earlier run left open, watch
  /// detail, then one `POST /playback/start` journalled before it is sent
  /// (`S/repository/SequencedPlayback.kt:186-262`).
  static Future<SiloPlaybackSession> start(
    SiloHttp http,
    SiloPlaybackJournal journal,
    SiloPlaybackRequest request, {
    Future<void> Function(Duration delay)? wait,
  }) async {
    final pause = wait ?? Future<void>.delayed;
    final caps = await http.send(const SiloRequest.get('/api/v2/playback/capabilities'));
    final admission = siloAdmission(caps.statusCode, caps.isSuccess ? _json(caps) : null);
    switch (admission) {
      case SiloUpdateRequired():
        throw const SiloPlaybackFailure('server_update_required', 'Update the Silo server to play here.');
      case SiloPlaybackUnavailable():
        throw const SiloPlaybackFailure('playback_unavailable', 'Playback is unavailable on this Silo server.');
      case SiloAdmitted():
    }

    try {
      await settleSiloLeftovers(
        http,
        journal,
        profileId: request.profileId,
        installationId: admission.installationId,
        wait: pause,
      );
    } on Exception catch (error) {
      appLogger.i('Silo playback: leftover stop failed (${error.runtimeType})');
    }

    final watch = await http.send(SiloRequest.get('/api/v2/watch/${Uri.encodeComponent(request.contentId)}'));
    if (watch.statusCode != 200) {
      throw SiloPlaybackFailure('watch_${watch.statusCode}', 'This item cannot be played.');
    }
    final detail = SiloWatchDetail.fromJson(_json(watch), request.contentId);
    final chosen = request.fileId;
    final version = chosen != null && detail.versions.any((v) => v.fileId == chosen)
        ? detail.versions.firstWhere((v) => v.fileId == chosen)
        : selectSiloVersion(detail.versions, lastFileId: detail.lastFileId, preferredQuality: request.quality);

    final attemptId = newSiloAttemptId();
    final capabilities = siloMpvCodecCapabilities();
    final context = siloMpvPlaybackContext(request.device);
    final body = siloStartBody(
      fileId: version.fileId,
      profileId: request.profileId,
      attemptId: attemptId,
      installationId: admission.installationId,
      capabilities: capabilities,
      context: context,
      qualityPreference: request.quality,
      startPosition: request.startPosition,
      audioTrackIndex: request.audioTrackIndex,
      bandwidthCapKbps: request.bandwidthCapKbps,
    );
    var entry = SiloJournalEntry(
      origin: http.origin.toString(),
      profileId: request.profileId,
      installationId: admission.installationId,
      attemptId: attemptId,
    );
    await journal.put(entry);

    final SiloResponse started;
    try {
      started = await http.send(SiloRequest.post('/api/v2/playback/start', body: body, single: true));
    } on Exception {
      await journal.remove(attemptId);
      rethrow;
    }
    final decisionJson = _json(started);
    final allocated = decisionJson is Map ? decisionJson['session_id'] : null;
    if (started.statusCode != 201 || allocated is! String || allocated.isEmpty) {
      await journal.remove(attemptId);
      final decision = started.statusCode == 201 ? parseSiloDecision(decisionJson) : null;
      if (decision is SiloTerminal) throw SiloPlaybackFailure(decision.reason, decision.message);
      throw SiloPlaybackFailure(
        started.problem?.code ?? 'start_${started.statusCode}',
        'The Silo server would not start playback.',
      );
    }
    entry = entry.copyWith(sessionId: allocated);
    await journal.put(entry);

    final decision = parseSiloDecision(decisionJson);
    appLogger.i('Silo playback: started, ${decision.runtimeType}');
    if (decision is SiloPlayable) {
      final plan = decision.plan;
      appLogger.i(
        'Silo playback: plan delivery=${plan.delivery} protocol=${plan.stream.protocol} '
        'reason=${plan.decisionReason} subtitles=${plan.subtitleInventory.length}',
      );
      return SiloPlaybackSession._(
        http,
        journal,
        detail,
        version,
        decision.plan,
        decision.sessionId,
        entry,
        pause,
        capabilities,
        context,
        request.quality,
        request.bandwidthCapKbps,
      );
    }
    final abandoned = SiloPlaybackSession._(
      http,
      journal,
      detail,
      version,
      switch (decision) {
        SiloReplanRequired(:final plan) => plan,
        _ => const SiloPlan(
          planId: '',
          planAttemptKey: '',
          delivery: '',
          stream: SiloStream(url: '', protocol: 'hls'),
          decisionReason: '',
        ),
      },
      allocated,
      entry,
      pause,
      capabilities,
      context,
      request.quality,
      request.bandwidthCapKbps,
    );
    await abandoned.stop();
    throw switch (decision) {
      SiloTerminal(:final reason, :final message) => SiloPlaybackFailure(reason, message),
      SiloReplanRequired(:final reason) => SiloPlaybackFailure(reason, 'This Silo plan needs a feature Plezy lacks.'),
      _ => const SiloPlaybackFailure('incompatible', 'This Silo server speaks a different playback contract.'),
    };
  }

  static bool _validReceipt(Object? json, SiloSample sent) {
    if (json is! Map) return false;
    if (!const {'applied', 'replayed', 'stale_sample'}.contains(json['outcome'])) return false;
    final accepted = json['accepted'];
    if (accepted is! Map) return false;
    final sequence = accepted['sequence'];
    if (sequence is! int || sequence < sent.sequence) return false;
    if (sequence == sent.sequence) {
      final position = accepted['position'];
      return position is num && position.toDouble() == sent.position && accepted['is_paused'] == sent.isPaused;
    }
    return true;
  }

  Future<bool> _send(SiloSample sample) async {
    final response = await http.send(
      SiloRequest.post(
        '/api/v2/playback/${Uri.encodeComponent(sessionId)}/progress',
        body: {
          'installation_id': _entry.installationId,
          'sequence': sample.sequence,
          'position': sample.position,
          'is_paused': sample.isPaused,
        },
      ),
    );
    return response.statusCode == 200 && _validReceipt(_json(response), sample);
  }

  /// One sample in source seconds. An unconfirmed earlier sample is resent
  /// verbatim first. Each new sample takes the next sequence and is
  /// journalled before it is sent (`S/repository/SequencedPlayback.kt:396-423`).
  Future<bool> progress(double sourcePosition, {required bool paused}) async {
    if (_stopped || !sourcePosition.isFinite || sourcePosition < 0) return false;
    final pending = _entry.sample;
    if (pending != null && !_entry.sampleReceipted) {
      if (!await _send(pending)) return false;
      _entry = _entry.copyWith(sampleReceipted: true);
      await journal.put(_entry);
    }
    final sample = (sequence: _entry.sequence + 1, position: sourcePosition, isPaused: paused);
    _entry = _entry.copyWith(sequence: sample.sequence, sample: sample, sampleReceipted: false);
    await journal.put(_entry);
    if (!await _send(sample)) {
      appLogger.i('Silo playback: progress ${sample.sequence} unconfirmed');
      return false;
    }
    _entry = _entry.copyWith(sampleReceipted: true);
    await journal.put(_entry);
    appLogger.i('Silo playback: progress ${sample.sequence} at ${sample.position.round()} s');
    return true;
  }

  /// A user's audio or quality change on the live session. Intent operations
  /// carry no failure block. The body addresses the plan the server holds
  /// (`A/player/PlaybackSessionManager.kt:880-945`,
  /// `S/model/playback/PlaybackProtocolV3.kt:454-487`).
  Future<SiloPlan> replan({
    required String operation,
    required double positionSeconds,
    int? audioTrackIndex,
    String? quality,
  }) async {
    final current = _plan;
    final keys = {..._attemptedKeys, current.planAttemptKey}.toList();
    final audio = audioTrackIndex ?? current.selectedAudio?.index;
    final subtitle = current.selectedSubtitle;
    final nextQuality = quality ?? _quality;
    final body = {
      'protocol_version': siloPlaybackProtocol,
      'client_features': siloClientFeatures,
      'operation': operation,
      'playback_attempt_id': _entry.attemptId,
      'replan_request_id': newSiloAttemptId(),
      'failed_plan_id': current.planId,
      'plan_attempt_id': _planAttemptId,
      'plan_attempt_key': current.planAttemptKey,
      'attempted_plan_keys': keys,
      'local_mutations': const <String>[],
      'attempt_count': _attemptCount,
      'quality_preference': nextQuality.toLowerCase(),
      'position_seconds': positionSeconds,
      'metered': false,
      'bandwidth_cap_kbps': ?(_bandwidthCap != null && _bandwidthCap > 0 ? _bandwidthCap : null),
      'selected_tracks': {
        'audio': ?(audio == null ? null : {'id': siloTrackId(version.fileId, 'audio', audio), 'index': audio}),
        'subtitle': ?(subtitle == null ? null : {'id': subtitle.id, 'index': ?subtitle.index}),
      },
      'client_capabilities': _capabilities,
      'client_playback_context': _context,
      'installation_id': _entry.installationId,
    };
    final response = await http.send(
      SiloRequest.post('/api/v2/playback/${Uri.encodeComponent(sessionId)}/replan', body: body, single: true),
    );
    final decision = response.statusCode == 200 ? parseSiloDecision(_json(response)) : null;
    if (decision is! SiloPlayable) {
      appLogger.i('Silo playback: replan refused (status ${response.statusCode}, ${decision.runtimeType})');
      throw SiloPlaybackFailure(
        decision is SiloTerminal ? decision.reason : 'replan_${response.statusCode}',
        'The Silo server could not change this stream.',
      );
    }
    _attemptedKeys
      ..clear()
      ..addAll(keys);
    _attemptCount++;
    _planAttemptId = newSiloAttemptId();
    _plan = decision.plan;
    _quality = nextQuality;
    appLogger.i('Silo playback: replanned $operation, delivery=${decision.plan.delivery}');
    return decision.plan;
  }

  /// `DELETE /playback/{session}` with one `stop_id`, at most 3 attempts.
  /// A 404 means the server already expired the session. A stop that never
  /// lands stays journalled for the next start (`S/repository/SequencedPlayback.kt:436-459`).
  Future<bool> stop() async {
    if (_stopped) return true;
    final confirmed = await _stopEntry(http, journal, _entry, _wait, attempts: 3);
    _stopped = confirmed;
    return confirmed;
  }
}

Future<bool> _stopEntry(
  SiloHttp http,
  SiloPlaybackJournal journal,
  SiloJournalEntry entry,
  Future<void> Function(Duration delay) wait, {
  required int attempts,
}) async {
  final sessionId = entry.sessionId;
  if (sessionId == null) {
    await journal.remove(entry.attemptId);
    return true;
  }
  var stop = entry;
  if (stop.stopId == null) {
    stop = stop.copyWith(stopId: newSiloAttemptId(), stopSample: entry.sampleReceipted ? null : entry.sample);
    await journal.put(stop);
  }
  final sample = stop.stopSample;
  final body = {
    'installation_id': stop.installationId,
    'stop_id': stop.stopId,
    'sequence': ?sample?.sequence,
    'position': ?sample?.position,
    'is_paused': ?sample?.isPaused,
  };
  for (var attempt = 1; attempt <= attempts; attempt++) {
    int? status;
    Object? receipt;
    try {
      final response = await http.send(
        SiloRequest('DELETE', '/api/v2/playback/${Uri.encodeComponent(sessionId)}', body: body, single: true),
      );
      status = response.statusCode;
      receipt = _json(response);
    } on Exception {
      status = null;
    }
    final confirmed =
        status == 404 ||
        (status == 200 &&
            receipt is Map &&
            ((receipt['outcome'] == 'stopped' && receipt['stop_id'] == stop.stopId) ||
                receipt['outcome'] == 'replayed'));
    if (confirmed) {
      await journal.remove(stop.attemptId);
      appLogger.i('Silo playback: stopped (status $status)');
      return true;
    }
    if (status != null && status != 503) break;
    if (attempt < attempts) await wait(Duration(milliseconds: 250 * attempt));
  }
  appLogger.i('Silo playback: stop left in the journal');
  return false;
}

/// One stop attempt for each session this profile left open on this server
/// under the current installation. The first that fails ends the pass, and
/// the rest wait for the next start. An attempt under another installation
/// can never be stopped and is dropped, and one with no session allocated
/// nothing (`S/repository/SequencedPlayback.kt:462-506`).
Future<void> settleSiloLeftovers(
  SiloHttp http,
  SiloPlaybackJournal journal, {
  required String profileId,
  required String installationId,
  Future<void> Function(Duration delay)? wait,
}) async {
  final origin = http.origin.toString();
  for (final entry in await journal.entries()) {
    if (entry.origin != origin || entry.profileId != profileId) continue;
    if (entry.installationId != installationId) {
      await journal.remove(entry.attemptId);
      continue;
    }
    if (!await _stopEntry(http, journal, entry, wait ?? Future<void>.delayed, attempts: 1)) return;
  }
}
