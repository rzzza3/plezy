import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_mappers.dart';
import 'package:plezy/silo/silo_models.dart';
import 'package:plezy/silo/silo_playback.dart';
import 'package:plezy/silo/silo_playback_journal.dart';
import 'package:plezy/silo/silo_playback_session.dart';

import 'fake_silo.dart';

Map<String, Object?> _version(String fileId, {String? resolution, int bitrate = 0, int size = 0}) => {
  'file_id': fileId,
  'resolution': ?resolution,
  'bitrate': bitrate,
  'file_size': size,
  'duration_seconds': 6780.5,
  'container': 'mkv',
  'audio_tracks': [
    {'index': 0, 'codec': 'eac3', 'channels': 6, 'language': 'eng', 'default': true},
    {'index': 0, 'codec': 'aac', 'channels': 2, 'language': 'fra'},
  ],
  'subtitle_tracks': [
    {'index': 0, 'codec': 'subrip', 'language': 'eng'},
  ],
  'effective_audio_track_index': 0,
};

Map<String, Object?> _watch({Object? userData}) => {
  'content_id': 'movie-tmdb-1',
  'type': 'movie',
  'title': 'Secret Title',
  'versions': [_version('41', resolution: '1080p', bitrate: 8000)],
  'intro': {'start_seconds': 30.0, 'end_seconds': 95.0},
  'credits': {'start_seconds': 6500.0, 'end_seconds': 6780.0},
  'user_data': userData,
};

const SiloDeviceFacts _tv = (
  formFactor: 'tv',
  appVersion: '1.2.3',
  platform: 'android',
  osVersion: '14',
  manufacturer: 'Google',
  model: 'TV',
);

Map<String, Object?> _decision({
  Object? plan = const {},
  String outcome = 'playable',
  List<String> features = const ['playback_plan_v3', 'neutral_playback_v3_contract_v1'],
}) => {
  'protocol_version': 3,
  'server_features': features,
  'outcome': outcome,
  'session_id': 'sess-1',
  'playback_plan': plan,
};

Map<String, Object?> _plan({
  String delivery = 'original_http',
  String url = '/api/v2/stream/v3/sess-1/file',
  Map<String, Object?> extra = const {},
}) => {
  'protocol_version': 3,
  'plan_id': 'plan-1',
  'plan_attempt_key': 'key-1',
  'session_id': 'sess-1',
  'delivery': delivery,
  'stream': {'url': url, 'protocol': delivery == 'original_http' ? 'http_progressive' : 'hls'},
  'timeline': {'player_start_seconds': 0.0, 'source_start_seconds': 120.0, 'timeline_offset_seconds': 120.0},
  'decision_reason': 'direct_play',
  'source': {'duration_seconds': 6780.5, 'container': 'mkv'},
  ...extra,
};

void main() {
  group('player mapping', () {
    final version = SiloFileVersion.fromJson(_version('41', resolution: '1080p'));
    SiloPlan plan(String delivery, {String url = '/api/v2/stream/sess-1', Map<String, Object?> extra = const {}}) =>
        (parseSiloDecision(
                  _decision(
                    plan: _plan(delivery: delivery, url: url, extra: extra),
                  ),
                )
                as SiloPlayable)
            .plan;

    test(
      'audio ids are the ordinal plus one, and the plan\'s pick is selected (TvVideoPlaybackStarter.kt:554-557)',
      () {
        final info = siloMediaSourceInfo(
          version,
          plan(
            'original_http',
            extra: {
              'selected_tracks': {
                'audio': {'id': 'file:41:audio:1', 'index': 1},
              },
            },
          ),
          videoUrl: 'http://127.0.0.1:1/r/x/s',
          mediaIndex: 0,
        );

        expect(info.audioTracks.map((t) => (t.id, t.index, t.codec, t.selected)), [
          (1, 0, 'eac3', false),
          (2, 1, 'aac', true),
        ]);
        expect(info.defaultAudioStreamIndex, 2);
        expect(info.mediaSourceId, '41');
      },
    );

    test('direct play lists the container subtitles and loads no sidecar', () {
      final direct = plan('original_http');
      final info = siloMediaSourceInfo(version, direct, videoUrl: 'u', mediaIndex: 0);

      expect(info.subtitleTracks.map((t) => (t.id, t.language)), [(1, 'eng')]);
      expect(siloSubtitleSidecars(direct, (url) => Uri.parse('http://p$url')), isEmpty);
    });

    test('a transcode lists the inventory and loads its sidecars lazily through the player URL', () {
      final transcode = plan(
        'server_transcode_hls',
        url: '/api/v2/playback/transcode/sess-1/master.m3u8',
        extra: {
          'subtitle': {
            'inventory': [
              {
                'track_id': 't0',
                'combined_index': 0,
                'source': 'embedded',
                'codec': 'subrip',
                'language': 'eng',
                'delivery': 'sidecar',
                'url': '/api/v2/stream/sess-1/subtitles/0.vtt',
              },
            ],
          },
        },
      );

      final info = siloMediaSourceInfo(version, transcode, videoUrl: 'u', mediaIndex: 0);
      final sidecars = siloSubtitleSidecars(transcode, (url) => Uri.parse('http://127.0.0.1:9/r/x$url'));

      expect(info.subtitleTracks.single.usesExternalDelivery, isTrue);
      expect(sidecars.single.sourceStreamId, 1);
      expect(sidecars.single.preload, isFalse);
      expect(sidecars.single.track.uri, 'http://127.0.0.1:9/r/x/api/v2/stream/sess-1/subtitles/0.vtt');
    });
  });

  group('session (SequencedPlayback.kt)', () {
    late _PlaybackServer server;
    late SiloPlaybackJournal journal;
    late List<Duration> waits;

    setUp(() {
      server = _PlaybackServer();
      journal = SiloPlaybackJournal(MemorySiloJournalStore());
      waits = [];
    });

    Future<SiloPlaybackSession> start() async {
      final (session, _) = await signedInSession();
      await session.selectProfile('p-1', null);
      return SiloPlaybackSession.start(
        siloHttpFor(server.fake, session),
        journal,
        _request(),
        wait: (d) async => waits.add(d),
      );
    }

    test('start admits, reads watch detail, then sends the body once (SequencedPlayback.kt:186-262)', () async {
      final playback = await start();

      expect(server.paths, [
        'GET /api/v2/playback/capabilities',
        'GET /api/v2/watch/movie-tmdb-1',
        'POST /api/v2/playback/start',
      ]);
      expect(server.body('POST', '/api/v2/playback/start')!['start_position'], 593);
      expect(server.body('POST', '/api/v2/playback/start')!['installation_id'], 'inst-1');
      expect(playback.sessionId, 'sess-1');
      expect((await journal.entries()).single.sessionId, 'sess-1', reason: 'journalled until stopped');
    });

    test('a journalled open session is stopped before the next start (SequencedPlayback.kt:220-225)', () async {
      await start();
      server.calls.clear();

      final second = await start();

      expect(server.paths, [
        'GET /api/v2/playback/capabilities',
        'DELETE /api/v2/playback/sess-1',
        'GET /api/v2/watch/movie-tmdb-1',
        'POST /api/v2/playback/start',
      ]);
      expect([for (final e in await journal.entries()) e.sessionId], ['sess-2']);
      expect(second.sessionId, 'sess-2');
    });

    test(
      'leftovers get one stop each, the first failure ends the pass, and other installations are dropped (SequencedPlayback.kt:470-506)',
      () async {
        final origin = siloTestOrigin.toString();
        SiloJournalEntry left(String attempt, {String? session, String profile = 'p-1', String install = 'inst-1'}) =>
            SiloJournalEntry(
              origin: origin,
              profileId: profile,
              installationId: install,
              attemptId: attempt,
              sessionId: session,
            );
        await journal.put(left('a-other-install', session: 'old-0', install: 'inst-0'));
        await journal.put(left('a-other-profile', session: 'old-p2', profile: 'p-2'));
        await journal.put(left('a-no-session'));
        await journal.put(left('a-fails', session: 'old-1'));
        await journal.put(left('a-waits', session: 'old-2'));
        server.stopStatus = (id, _) => id == 'old-1' ? 503 : 200;

        await start();

        expect(server.paths.where((p) => p.startsWith('DELETE')), ['DELETE /api/v2/playback/old-1']);
        expect(waits, isEmpty, reason: 'a leftover gets one attempt, no backoff');
        expect([for (final e in await journal.entries()) e.attemptId].where((id) => id.startsWith('a-')), [
          'a-other-profile',
          'a-fails',
          'a-waits',
        ]);
      },
    );

    test('progress takes the next sequence in source seconds (SequencedPlayback.kt:406-410)', () async {
      final playback = await start();

      expect(await playback.progress(600, paused: false), isTrue);
      expect(await playback.progress(610, paused: true), isTrue);

      final sent = [
        for (final c in server.calls)
          if (c.$2.endsWith('/progress')) c.$3,
      ];
      expect(sent.map((b) => (b!['sequence'], b['position'], b['is_paused'])), [(1, 600, false), (2, 610, true)]);
    });

    test(
      'the reporter sends the latest observed sample each 10 s tick, and stop ends it (PlaybackSessionLifecycle.kt:666-678)',
      () async {
        final playback = await start();
        final ticks = StreamController<void>();
        addTearDown(ticks.close);
        List<Object?> sent() => [
          for (final c in server.calls)
            if (c.$2.endsWith('/progress')) (c.$3!['sequence'], c.$3!['position'], c.$3!['is_paused']),
        ];
        Future<void> tick() async {
          ticks.add(null);
          await pumpEventQueue();
        }

        playback
          ..observe(600, paused: false)
          ..startReporting(ticks: ticks.stream)
          ..observe(604, paused: false);
        await pumpEventQueue();
        expect(sent(), isEmpty, reason: 'player callbacks only update the cached sample');
        await tick();
        expect(sent(), [(1, 604, false)]);
        playback.observe(611, paused: true);
        await tick();
        await tick();
        expect(sent(), [(1, 604, false), (2, 611, true), (3, 611, true)], reason: 'each tick sends the latest');
        await playback.stop();
        expect(ticks.hasListener, isFalse, reason: 'stop ends the reporter');
        expect(siloProgressInterval, const Duration(seconds: 10));
      },
    );

    test('an unconfirmed sample is resent verbatim before the next (SequencedPlayback.kt:399-405)', () async {
      final playback = await start();
      server.progressReceipt = (_) => {'outcome': 'bogus'};
      expect(await playback.progress(600, paused: false), isFalse);
      server.progressReceipt = null;

      expect(await playback.progress(620, paused: false), isTrue);

      final sent = [
        for (final c in server.calls)
          if (c.$2.endsWith('/progress')) c.$3,
      ];
      expect(sent.map((b) => (b!['sequence'], b['position'])), [(1, 600), (1, 600), (2, 620)]);
    });

    test('a receipt that echoes a different sample is refused (SequencedPlayback.kt:415-423)', () async {
      final playback = await start();
      server.progressReceipt = (b) => {
        'outcome': 'applied',
        'accepted': {'sequence': b['sequence'], 'position': 1.0, 'is_paused': b['is_paused']},
      };

      expect(await playback.progress(600, paused: false), isFalse);
    });

    test('negative or non-finite positions are dropped (SequencedPlayback.kt:398)', () async {
      final playback = await start();

      expect(await playback.progress(-1, paused: false), isFalse);
      expect(await playback.progress(double.nan, paused: false), isFalse);
      expect(server.paths.where((p) => p.endsWith('/progress')), isEmpty);
    });

    test(
      'a track change replans the live session with the plan the server holds (PlaybackSessionManager.kt:880-945)',
      () async {
        final playback = await start();

        final plan = await playback.replan(operation: 'track_change', positionSeconds: 812.5, audioTrackIndex: 1);
        final body = server.body('POST', '/api/v2/playback/sess-1/replan')!;

        expect(plan.delivery, 'server_transcode_hls');
        expect(playback.plan.planId, 'plan-2');
        expect(body['operation'], 'track_change');
        expect(body['failed_plan_id'], 'plan-1');
        expect(body['plan_attempt_key'], 'key-1');
        expect(body['attempted_plan_keys'], ['key-1']);
        expect(body['attempt_count'], 1);
        expect(body['position_seconds'], 812.5);
        expect(body['selected_tracks'], {
          'audio': {'id': 'file:41:audio:1', 'index': 1},
        });
        expect(body.containsKey('failure'), isFalse, reason: 'intent operations carry no failure block');
        expect(body['installation_id'], 'inst-1');
        expect(body['playback_attempt_id'], server.body('POST', '/api/v2/playback/start')!['playback_attempt_id']);

        await playback.replan(operation: 'quality_change', positionSeconds: 900, quality: '720p');
        final second = server.body('POST', '/api/v2/playback/sess-1/replan')!;
        expect(second['failed_plan_id'], 'plan-2');
        expect(second['attempted_plan_keys'], ['key-1', 'key-2']);
        expect(second['attempt_count'], 2);
        expect(second['quality_preference'], '720p');
        expect(second['plan_attempt_id'], isNot(body['plan_attempt_id']));
      },
    );

    test('stop sends one stop_id, retries a 503 with 250 ms steps, and clears the journal', () async {
      final playback = await start();
      server.stopStatus = (_, attempt) => attempt < 3 ? 503 : 200;

      expect(await playback.stop(), isTrue);

      final stops = [
        for (final c in server.calls)
          if (c.$1 == 'DELETE') c.$3!['stop_id'],
      ];
      expect(stops, hasLength(3));
      expect(stops.toSet(), hasLength(1), reason: 'built once and resent verbatim (SequencedPlayback.kt:436-440)');
      expect(waits, [const Duration(milliseconds: 250), const Duration(milliseconds: 500)]);
      expect(await journal.entries(), isEmpty);
    });

    test('a 404 stop counts as stopped (SequencedPlayback.kt:443-459)', () async {
      final playback = await start();
      server.stopStatus = (_, _) => 404;

      expect(await playback.stop(), isTrue);
      expect(await journal.entries(), isEmpty);
    });

    test('a refused stop stays journalled with its unsent sample', () async {
      final playback = await start();
      server.progressReceipt = (_) => {'outcome': 'bogus'};
      await playback.progress(700, paused: true);
      server.stopStatus = (_, _) => 400;

      expect(await playback.stop(), isFalse);

      final left = (await journal.entries()).single;
      expect(left.stopId, isNotNull);
      expect(left.stopSample, (sequence: 1, position: 700.0, isPaused: true));
      expect(server.body('DELETE', '/api/v2/playback/sess-1')!['position'], 700);
    });

    test('the journal survives a restart on disk', () async {
      final dir = await Directory.systemTemp.createTemp('silo_journal');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/journal.json');
      journal = SiloPlaybackJournal(FileSiloJournalStore(file));
      await start();

      final reopened = await SiloPlaybackJournal(FileSiloJournalStore(file)).entries();

      expect(reopened.single.sessionId, 'sess-1');
      expect(reopened.single.installationId, 'inst-1');
      expect(await file.readAsString(), isNot(contains('access-A')), reason: 'no credential is journalled');
    });
  });

  group('watch detail (WatchDetailV2Api.kt:25-55)', () {
    test('file ids are positive decimal strings', () {
      final detail = SiloWatchDetail.fromJson(
        _watch(userData: {'position_seconds': 600.0, 'last_file_id': '41'}),
        'movie-tmdb-1',
      );

      expect(detail.versions.single.fileId, 41);
      expect(detail.versions.single.durationSeconds, 6780.5);
      expect(detail.versions.single.audioTracks.map((t) => t.codec), ['eac3', 'aac']);
      expect(detail.intro, (start: 30.0, end: 95.0));
      expect(detail.positionSeconds, 600.0);
      expect(detail.lastFileId, 41);
    });

    test('a numeric, zero or padded file id, another item, or no versions is refused', () {
      for (final bad in [
        {
          ..._watch(),
          'versions': [
            {..._version('41'), 'file_id': 41},
          ],
        },
        {
          ..._watch(),
          'versions': [_version('0')],
        },
        {
          ..._watch(),
          'versions': [_version('041')],
        },
        {..._watch(), 'content_id': 'movie-tmdb-2'},
        {..._watch(), 'versions': <Object>[]},
      ]) {
        expect(() => SiloWatchDetail.fromJson(bad, 'movie-tmdb-1'), throwsA(isA<SiloDecodeException>()));
      }
    });
  });

  group('version choice (PlaybackVersionSelector.kt:5-29)', () {
    final versions = [
      SiloFileVersion.fromJson(_version('1', resolution: '720p', bitrate: 9000)),
      SiloFileVersion.fromJson(_version('2', resolution: '2160p', bitrate: 20000)),
      SiloFileVersion.fromJson(_version('3', resolution: '1080p', bitrate: 8000)),
      SiloFileVersion.fromJson(_version('4', resolution: '1080p', bitrate: 12000)),
    ];

    test('the last played file wins', () {
      expect(selectSiloVersion(versions, lastFileId: 1).fileId, 1);
    });

    test('auto takes the highest resolution, then bitrate', () {
      expect(selectSiloVersion(versions).fileId, 2);
      expect(selectSiloVersion(versions, preferredQuality: 'Original').fileId, 2);
    });

    test('a height cap takes the best at or below it', () {
      expect(selectSiloVersion(versions, preferredQuality: '1080p').fileId, 4);
      expect(selectSiloVersion(versions, preferredQuality: '480p').fileId, 2, reason: 'nothing fits, so the best');
    });
  });

  group('start position (PlaybackStartPosition.kt:17-72)', () {
    test('a resume of 30 s or more starts 7 s earlier', () {
      expect(siloStartPosition(savedPosition: 600), 593);
      expect(siloStartPosition(savedPosition: 30), 23);
    });

    test('a short resume, no resume, or an explicit start is left alone', () {
      expect(siloStartPosition(savedPosition: 29.5), 29.5);
      expect(siloStartPosition(savedPosition: 0), isNull);
      expect(siloStartPosition(savedPosition: null), isNull);
      expect(siloStartPosition(override: 0, savedPosition: 600), 0, reason: 'Start Over is honoured');
      expect(siloStartPosition(override: 1234, savedPosition: 600), 1234);
    });
  });

  group('admission (SequencedPlayback.kt:191-205)', () {
    Map<String, Object?> caps({
      bool allowed = true,
      String state = 'available',
      List<Object> protocols = const [2, 3],
      List<String> features = const ['sequenced_progress_v1'],
      String? installation = 'inst-1',
    }) => {
      'installation_id': installation,
      'state': state,
      'allowed': allowed,
      'protocol_versions': protocols,
      'features': features,
    };

    test('a ready server admits with its installation id', () {
      expect((siloAdmission(200, caps()) as SiloAdmitted).installationId, 'inst-1');
    });

    test('a 404 asks for a server update', () {
      expect(siloAdmission(404, null), isA<SiloUpdateRequired>());
    });

    test('any missing condition refuses', () {
      for (final body in [
        caps(allowed: false),
        caps(state: 'maintenance'),
        caps(protocols: const [2]),
        caps(features: const []),
        caps(installation: ' '),
        caps(installation: null),
      ]) {
        expect(siloAdmission(200, body), isA<SiloPlaybackUnavailable>(), reason: '$body');
      }
    });
  });

  group('start body (PlaybackSessionManager.kt:352-381, PlaybackV2Api.kt:69-74)', () {
    final detail = SiloWatchDetail.fromJson(_watch(userData: {'position_seconds': 600.0}), 'movie-tmdb-1');
    final version = selectSiloVersion(detail.versions);

    Map<String, Object?> body({int? subtitle}) => siloStartBody(
      fileId: version.fileId,
      profileId: 'p-1',
      attemptId: 'attempt-1',
      installationId: 'inst-1',
      capabilities: siloMpvCodecCapabilities(),
      context: siloMpvPlaybackContext(_tv),
      startPosition: siloStartPosition(savedPosition: detail.positionSeconds),
      audioTrackIndex: 1,
      subtitleTrackIndex: subtitle,
    );

    test('carries every field in order, file_id as a string', () {
      final sent = body(subtitle: 0);

      expect(sent.keys.toList(), [
        'protocol_version',
        'client_features',
        'file_id',
        'profile_id',
        'playback_attempt_id',
        'quality_preference',
        'subtitle_fidelity_preference',
        'start_position',
        'progress_persistence',
        'audio_track_id',
        'audio_track_index',
        'subtitle_track_id',
        'subtitle_track_index',
        'metered',
        'client_capabilities',
        'client_playback_context',
        'installation_id',
      ]);
      expect(sent['protocol_version'], 3);
      expect(sent['client_features'], ['playback_plan_v3', 'seek_reanchor_v1', 'direct_stream_resume_v1']);
      expect(sent['file_id'], '41');
      expect(sent['profile_id'], 'p-1');
      expect(sent['playback_attempt_id'], 'attempt-1');
      expect(sent['quality_preference'], 'auto');
      expect(sent['subtitle_fidelity_preference'], 'preserve');
      expect(sent['start_position'], 593.0);
      expect(sent['progress_persistence'], 'server');
      expect(sent['audio_track_id'], 'file:41:audio:1');
      expect(sent['audio_track_index'], 1);
      expect(sent['subtitle_track_id'], 'file:41:subtitle:0');
      expect(sent['subtitle_track_index'], 0);
      expect(sent['metered'], false);
      expect(sent['installation_id'], 'inst-1');
    });

    test('subtitles off omit both subtitle fields, never -1 (PlaybackSessionManager.kt:364-373)', () {
      for (final off in [null, -1]) {
        final sent = body(subtitle: off);
        expect(sent.containsKey('subtitle_track_index'), isFalse);
        expect(sent.containsKey('subtitle_track_id'), isFalse);
      }
    });

    test('the context declares original_http and hls, with progressive off (port note 1)', () {
      final context = body()['client_playback_context']! as Map<String, Object?>;
      final deliveries = context['deliveries']! as Map<String, Object?>;

      expect(context['form_factor'], 'tv');
      expect((deliveries['original_http']! as Map)['enabled'], true);
      expect((deliveries['hls']! as Map)['enabled'], true);
      expect((deliveries['progressive']! as Map)['enabled'], false);
      expect((deliveries['progressive']! as Map)['failure_reason'], 'disabled_pending_seekable_transport');
      expect((deliveries['original_http']! as Map)['auth_header_refresh'], true);
    });

    test('no Media3-only feature, transformation or claim is advertised (port note 2)', () {
      final sent = body();
      final context = sent['client_playback_context']! as Map<String, Object?>;
      final deliveries = (context['deliveries']! as Map<String, Object?>).values.cast<Map<String, Object?>>();

      expect(sent['client_features'], isNot(contains('client_video_transformations_v1')));
      for (final delivery in deliveries) {
        expect(delivery['transformations'], isEmpty);
        expect(delivery['validated_claims'], isEmpty);
        expect(delivery['features'], isNot(contains('native_hls_playback_v1')));
      }
      expect((sent['client_capabilities']! as Map)['video_evidence'], 'declared');
    });
  });

  group('decision (PlaybackProtocolV3.kt:543-680)', () {
    test('a playable plan carries its stream, timeline and session', () {
      final decision = parseSiloDecision(_decision(plan: _plan())) as SiloPlayable;

      expect(decision.sessionId, 'sess-1');
      expect(decision.plan.delivery, 'original_http');
      expect(decision.plan.stream.url, '/api/v2/stream/v3/sess-1/file');
      expect(decision.plan.timeline.toSource(10), 130);
      expect(decision.plan.timeline.toPlayer(130), 10);
      expect(decision.plan.sourceDurationSeconds, 6780.5);
    });

    test('a server without the neutral contract is incompatible but keeps its session', () {
      final decision = parseSiloDecision(_decision(plan: _plan(), features: const ['playback_plan_v3']));

      expect(decision, isA<SiloIncompatible>());
      expect((decision as SiloIncompatible).sessionId, 'sess-1');
    });

    test('adaptation_unavailable is the server terminal', () {
      final decision = parseSiloDecision({
        ..._decision(outcome: 'adaptation_unavailable', plan: null),
        'terminal': {'reason': 'too_many_streams', 'message': 'Too many streams', 'retryable': true},
      });

      expect(decision, isA<SiloTerminal>());
      expect((decision as SiloTerminal).reason, 'too_many_streams');
      expect(decision.retryable, isTrue);
    });

    test('refresh_endpoint headers are terminal (port note 11)', () {
      final plan = _plan();
      final decision = parseSiloDecision(
        _decision(
          plan: {
            ...plan,
            'stream': {...plan['stream']! as Map<String, Object?>, 'header_refresh': 'refresh_endpoint'},
          },
        ),
      );

      expect((decision as SiloTerminal).reason, 'unsupported_header_refresh');
    });

    test('a client transformation or runtime correction asks for a replan', () {
      final transform = parseSiloDecision(
        _decision(
          plan: _plan(
            extra: {
              'transformations': [
                {'name': 'client_dv7_to_dv81', 'executor': 'client', 'recipe_version': '1'},
              ],
            },
          ),
        ),
      );
      final correction = parseSiloDecision(
        _decision(
          plan: _plan(
            extra: {
              'runtime_corrections': ['client_surface_recovery_v1'],
            },
          ),
        ),
      );

      expect((transform as SiloReplanRequired).reason, 'unsupported_client_transformation:client_dv7_to_dv81:1');
      expect(
        (correction as SiloReplanRequired).reason,
        'unsupported_client_runtime_correction:client_surface_recovery_v1',
      );
    });

    test('a v1 or relative non-api URL is refused (SequencedPlayback.kt:519-527)', () {
      for (final url in ['/api/v1/stream/x', '/stream/x', 'ftp://h/x']) {
        expect(
          parseSiloDecision(_decision(plan: _plan(url: url))),
          isA<SiloTerminal>(),
          reason: url,
        );
      }
    });

    test('a broken subtitle inventory is refused', () {
      final gap = parseSiloDecision(
        _decision(
          plan: _plan(
            extra: {
              'subtitle': {
                'inventory': [
                  {
                    'track_id': 't1',
                    'combined_index': 1,
                    'source': 'embedded',
                    'delivery': 'sidecar',
                    'url': '/api/v2/stream/v3/sess-1/subtitles/1.srt',
                  },
                ],
              },
            },
          ),
        ),
      );
      final sidecarWithoutUrl = parseSiloDecision(
        _decision(
          plan: _plan(
            extra: {
              'subtitle': {
                'inventory': [
                  {'track_id': 't0', 'combined_index': 0, 'source': 'embedded', 'delivery': 'sidecar'},
                ],
              },
            },
          ),
        ),
      );

      expect((gap as SiloTerminal).message, 'The server returned an invalid subtitle inventory.');
      expect(sidecarWithoutUrl, isA<SiloTerminal>());
    });

    test('the seek window decides native seeking (PlaybackTimelineSeekPolicy.kt:131-210)', () {
      const windowed = SiloTimeline(seekWindowStartSeconds: 100, seekWindowEndSeconds: 400);
      const open = SiloTimeline();
      const fixed = SiloTimeline(canSeekAnywhere: false);

      expect(windowed.canSeekNatively(250), isTrue);
      expect(windowed.canSeekNatively(401), isFalse);
      expect(open.canSeekNatively(5000), isTrue);
      expect(fixed.canSeekNatively(5000), isFalse);
    });
  });
}

/// A Silo server for one playback flow. Every playback request is recorded
/// with its decoded body.
class _PlaybackServer {
  final List<(String, String, Map<String, Object?>?)> calls = [];
  int sessions = 0;
  int Function(String sessionId, int attempt) stopStatus = (_, _) => 200;
  final Map<String, int> _stopAttempts = {};
  Map<String, Object?> Function(Map<String, Object?> body)? progressReceipt;
  late final FakeSilo fake = FakeSilo(_handle);

  List<String> get paths => [for (final c in calls) '${c.$1} ${c.$2}'];

  Map<String, Object?>? body(String method, String path) => calls.lastWhere((c) => c.$1 == method && c.$2 == path).$3;

  http.Response _handle(RecordedRequest request) {
    final path = request.url.path;
    final body = request.body.isEmpty ? null : jsonDecode(request.body) as Map<String, Object?>;
    if (path.startsWith('/api/v2/playback') || path.startsWith('/api/v2/watch')) {
      calls.add((request.method, path, body));
    }
    if (path == '/api/v2/playback/capabilities') {
      return jsonResponse({
        'installation_id': 'inst-1',
        'state': 'available',
        'allowed': true,
        'protocol_versions': [3],
        'features': ['sequenced_progress_v1'],
      }, 200);
    }
    if (path == '/api/v2/watch/movie-tmdb-1') return jsonResponse(_watch(userData: {'position_seconds': 600.0}), 200);
    if (path == '/api/v2/playback/start') {
      final id = 'sess-${++sessions}';
      return jsonResponse(_decision(plan: {..._plan(), 'session_id': id})..['session_id'] = id, 201);
    }
    final replan = RegExp(r'^/api/v2/playback/([^/]+)/replan$').firstMatch(path);
    if (replan != null) {
      final count = calls.where((c) => c.$2.endsWith('/replan')).length;
      return jsonResponse(
        _decision(
          plan: {
            ..._plan(delivery: 'server_transcode_hls', url: '/api/v2/playback/transcode/sess-1/master.m3u8'),
            'plan_id': 'plan-${count + 1}',
            'plan_attempt_key': 'key-${count + 1}',
          },
        ),
        200,
      );
    }
    final progress = RegExp(r'^/api/v2/playback/([^/]+)/progress$').firstMatch(path);
    if (progress != null) {
      return jsonResponse(
        progressReceipt?.call(body!) ??
            {
              'outcome': 'applied',
              'accepted': {'sequence': body!['sequence'], 'position': body['position'], 'is_paused': body['is_paused']},
            },
        200,
      );
    }
    final stop = RegExp(r'^/api/v2/playback/([^/]+)$').firstMatch(path);
    if (stop != null && request.method == 'DELETE') {
      final id = stop.group(1)!;
      final attempt = _stopAttempts[id] = (_stopAttempts[id] ?? 0) + 1;
      final status = stopStatus(id, attempt);
      return status == 200
          ? jsonResponse({'outcome': 'stopped', 'stop_id': body!['stop_id']}, 200)
          : jsonResponse({}, status);
    }
    return jsonResponse({}, 404);
  }
}

SiloPlaybackRequest _request({double? start = 593}) => (
  contentId: 'movie-tmdb-1',
  profileId: 'p-1',
  device: _tv,
  fileId: null,
  quality: 'auto',
  startPosition: start,
  audioTrackIndex: null,
  bandwidthCapKbps: null,
);
