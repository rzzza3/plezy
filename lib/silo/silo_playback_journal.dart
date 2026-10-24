import 'dart:convert';
import 'dart:io';

import '../utils/serial_future_queue.dart';

typedef SiloSample = ({int sequence, double position, bool isPaused});

/// One playback attempt, durable from before `POST /playback/start` until its
/// stop is confirmed. It holds no credential (`S/repository/SequencedPlayback.kt:16-47`).
class SiloJournalEntry {
  final String origin;
  final String profileId;
  final String installationId;
  final String attemptId;
  final String? sessionId;
  final int sequence;

  /// The last progress sample sent. Unconfirmed until [sampleReceipted].
  final SiloSample? sample;
  final bool sampleReceipted;

  /// Built once and resent verbatim until the server confirms it.
  final String? stopId;
  final SiloSample? stopSample;

  const SiloJournalEntry({
    required this.origin,
    required this.profileId,
    required this.installationId,
    required this.attemptId,
    this.sessionId,
    this.sequence = 0,
    this.sample,
    this.sampleReceipted = true,
    this.stopId,
    this.stopSample,
  });

  SiloJournalEntry copyWith({
    String? sessionId,
    int? sequence,
    SiloSample? sample,
    bool? sampleReceipted,
    String? stopId,
    SiloSample? stopSample,
  }) => SiloJournalEntry(
    origin: origin,
    profileId: profileId,
    installationId: installationId,
    attemptId: attemptId,
    sessionId: sessionId ?? this.sessionId,
    sequence: sequence ?? this.sequence,
    sample: sample ?? this.sample,
    sampleReceipted: sampleReceipted ?? this.sampleReceipted,
    stopId: stopId ?? this.stopId,
    stopSample: stopSample ?? this.stopSample,
  );

  static Map<String, Object?>? _sampleJson(SiloSample? s) =>
      s == null ? null : {'sequence': s.sequence, 'position': s.position, 'is_paused': s.isPaused};

  static SiloSample? _sample(Object? json) {
    if (json is! Map) return null;
    final sequence = json['sequence'];
    final position = json['position'];
    return sequence is int && position is num
        ? (sequence: sequence, position: position.toDouble(), isPaused: json['is_paused'] == true)
        : null;
  }

  Map<String, Object?> toJson() => {
    'origin': origin,
    'profile_id': profileId,
    'installation_id': installationId,
    'attempt_id': attemptId,
    'session_id': ?sessionId,
    'sequence': sequence,
    'sample': ?_sampleJson(sample),
    'sample_receipted': sampleReceipted,
    'stop_id': ?stopId,
    'stop_sample': ?_sampleJson(stopSample),
  };

  static SiloJournalEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final origin = json['origin'];
    final profile = json['profile_id'];
    final installation = json['installation_id'];
    final attempt = json['attempt_id'];
    if (origin is! String || profile is! String || installation is! String || attempt is! String) return null;
    final session = json['session_id'];
    final stopId = json['stop_id'];
    final sequence = json['sequence'];
    return SiloJournalEntry(
      origin: origin,
      profileId: profile,
      installationId: installation,
      attemptId: attempt,
      sessionId: session is String ? session : null,
      sequence: sequence is int ? sequence : 0,
      sample: _sample(json['sample']),
      sampleReceipted: json['sample_receipted'] != false,
      stopId: stopId is String ? stopId : null,
      stopSample: _sample(json['stop_sample']),
    );
  }
}

abstract interface class SiloJournalStore {
  Future<String?> read();
  Future<void> write(String contents);
}

/// Atomic: the new journal is written beside the old one and renamed over it.
class FileSiloJournalStore implements SiloJournalStore {
  final File file;

  FileSiloJournalStore(this.file);

  @override
  Future<String?> read() async => await file.exists() ? file.readAsString() : null;

  @override
  Future<void> write(String contents) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(file.path);
  }
}

class MemorySiloJournalStore implements SiloJournalStore {
  String? contents;

  @override
  Future<String?> read() async => contents;

  @override
  Future<void> write(String contents) async => this.contents = contents;
}

/// Every change is written before the request it guards is sent, one write
/// at a time, so a crash leaves at worst one attempt the next start stops.
class SiloPlaybackJournal {
  final SiloJournalStore store;
  final SerialFutureQueue _writes = SerialFutureQueue();
  List<SiloJournalEntry>? _entries;

  SiloPlaybackJournal(this.store);

  Future<List<SiloJournalEntry>> entries() async => List.unmodifiable(await _load());

  Future<List<SiloJournalEntry>> _load() async {
    final cached = _entries;
    if (cached != null) return cached;
    List<SiloJournalEntry> loaded;
    try {
      final raw = await store.read();
      final json = raw == null ? null : jsonDecode(raw);
      loaded = json is List ? [for (final e in json) ?SiloJournalEntry.fromJson(e)] : [];
    } on FormatException {
      loaded = [];
    }
    return _entries = loaded;
  }

  Future<void> put(SiloJournalEntry entry) => _writes.run(() async {
    final entries = await _load();
    final index = entries.indexWhere((e) => e.attemptId == entry.attemptId);
    if (index < 0) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await store.write(jsonEncode([for (final e in entries) e.toJson()]));
  });

  Future<void> remove(String attemptId) => _writes.run(() async {
    final entries = await _load();
    entries.removeWhere((e) => e.attemptId == attemptId);
    await store.write(jsonEncode([for (final e in entries) e.toJson()]));
  });
}
