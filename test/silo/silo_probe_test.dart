import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/silo/silo_headers.dart';

import '../../tool/silo_probe.dart';

class _FakeServer {
  final HttpServer server;
  final List<({String method, String path, Map<String, String> headers})> requests = [];
  final List<Object?> pollReplies;

  _FakeServer(this.server, this.pollReplies) {
    server.listen(_handle);
  }

  static Future<_FakeServer> start(List<Object?> pollReplies) async =>
      _FakeServer(await HttpServer.bind(InternetAddress.loopbackIPv4, 0), pollReplies);

  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> _handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(','));
    final path = request.uri.path;
    requests.add((method: request.method, path: path, headers: headers));
    final sent = await utf8.decoder.bind(request).join();
    final sentJson = sent.isEmpty ? null : jsonDecode(sent);
    final authorized = headers['authorization'] == 'Bearer access-secret';
    final (int status, Object? body) = switch (path) {
      '/api/v2/system/info' => (200, {'api_major': 2, 'server_version': '1.0'}),
      '/api/v2/system/identity' => (200, {'server_id': 'srv'}),
      '/api/v2/auth/device/capability' => (200, {'state': 'available', 'cancel': true}),
      '/api/v2/auth/device/start' => (
        201,
        {
          'device_code': 'device-secret',
          'user_code': '12345678',
          'verification_uri': 'https://silo.example/activate',
          'verification_uri_complete': 'https://silo.example/activate?code=12345678',
          'expires_at': DateTime.now().toUtc().add(const Duration(seconds: 600)).toIso8601String(),
          'expires_in': pollReplies.isEmpty ? 1 : 600,
          'interval': 5,
        },
      ),
      '/api/v2/auth/device/poll' =>
        pollReplies.isEmpty
            ? (200, {'status': 'pending', 'poll_after': 1})
            : switch (pollReplies.removeAt(0)) {
                final int s => (s, null),
                final Object? reply => (200, reply),
              },
      '/api/v2/auth/device/cancel' => (200, {'status': 'canceled'}),
      '/api/v2/account/me' when authorized => (200, {'id': '1', 'username': 'Secret Name', 'role': 'admin'}),
      '/api/v2/profiles' when authorized => (
        200,
        {
          'items': [
            {'id': '9', 'name': 'Secret Name', 'has_pin': false, 'is_primary': true, 'avatar_url': '/a.png'},
          ],
        },
      ),
      '/api/v2/home/sections' when authorized && headers['x-profile-id'] == '9' => (
        200,
        {
          'sections': [
            {
              'id': 's1',
              'section_type': 'continue_watching',
              'title': 'Secret Title',
              'items': [
                {'content_id': 'c1', 'title': 'Secret Title', 'poster_url': '/p.jpg', 'year': 2020},
              ],
            },
            {'id': 's2', 'section_type': 'recently_added', 'title': 'Secret Title', 'items': []},
          ],
        },
      ),
      '/api/v2/user/libraries' when authorized => (
        200,
        {
          'items': [
            {'id': '1', 'name': 'Secret Name', 'type': 'movies'},
          ],
        },
      ),
      '/api/v2/auth/logout' when authorized => (204, null),
      '/api/v2/watched/c1' || '/api/v2/watchlist/c1' when authorized => (204, null),
      '/api/v2/playback/capabilities' when authorized => (
        200,
        {
          'installation_id': 'inst-1',
          'state': 'available',
          'allowed': true,
          'protocol_versions': [3],
          'features': ['sequenced_progress_v1'],
        },
      ),
      '/api/v2/catalog/items/movie-1' when authorized => (
        200,
        {
          'content_id': 'movie-1',
          'title': 'Secret Title',
          'user_data': {'position_seconds': 40.0, 'played': false, 'is_in_progress': true},
        },
      ),
      '/api/v2/watch/movie-1' when authorized => (
        200,
        {
          'content_id': 'movie-1',
          'title': 'Secret Title',
          'versions': [
            {'file_id': '41', 'resolution': '1080p', 'duration_seconds': 100.0, 'container': 'mkv'},
          ],
          'user_data': {'position_seconds': 50.0, 'played': false},
        },
      ),
      '/api/v2/playback/start' when authorized => (
        201,
        {
          'protocol_version': 3,
          'server_features': ['playback_plan_v3', 'neutral_playback_v3_contract_v1'],
          'outcome': 'playable',
          'session_id': 'sess-secret',
          'playback_plan': {
            'plan_id': 'plan-1',
            'plan_attempt_key': 'key-1',
            'session_id': 'sess-secret',
            'delivery': 'original_http',
            'stream': {
              'url': '/api/v2/stream/v3/sess-secret/file?sig=secret-sig',
              'protocol': 'http_progressive',
              'headers': {'X-Stream-Token': 'stream-secret'},
            },
            'decision_reason': 'direct_play',
          },
        },
      ),
      '/api/v2/stream/v3/sess-secret/file' when authorized && headers['x-stream-token'] == 'stream-secret' => (
        206,
        null,
      ),
      '/api/v2/playback/sess-secret/progress' when authorized => (
        200,
        {
          'outcome': 'applied',
          'accepted': {'sequence': 1, 'position': 43.0, 'is_paused': true},
        },
      ),
      '/api/v2/playback/sess-secret' when authorized && request.method == 'DELETE' => (
        200,
        {'outcome': 'stopped', 'stop_id': (sentJson as Map)['stop_id']},
      ),
      _ => (401, {'type': 'https://silo/problems/authentication_required', 'title': 'Unauthorized', 'status': 401}),
    };
    request.response.statusCode = status;
    if (body != null) {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(body));
    }
    await request.response.close();
  }

  int count(String path) => requests.where((r) => r.path == path).length;
}

final Map<String, Object?> _approved = {
  'status': 'approved',
  'profile_id': '',
  'profile_token': '',
  'tokens': {'access_token': 'access-secret', 'refresh_token': 'refresh-secret', 'expires_in': 900},
};

void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('silo_probe_test'));
  tearDown(() async => temp.delete(recursive: true));

  SiloProbeOptions optionsFor(Uri origin) =>
      SiloProbeOptions(origin: origin, samplesDir: '${temp.path}/samples', deviceIdFile: '${temp.path}/device_id');

  test('the probe signs in by device code, records structure only, and logs out', () async {
    final server = await _FakeServer.start([
      {'status': 'pending', 'poll_after': 2, 'profile_id': '', 'profile_token': '', 'temporary': false},
      503,
      {
        'status': 'approved',
        'poll_after': 2,
        'profile_id': '',
        'profile_token': '',
        'temporary': false,
        'tokens': {
          'access_token': 'access-secret',
          'refresh_token': 'refresh-secret',
          'expires_in': 900,
          'user': {'id': 1, 'username': 'Secret Name'},
        },
      },
    ]);
    addTearDown(() => server.server.close(force: true));
    final out = StringBuffer();
    final waits = <Duration>[];
    var clock = DateTime.utc(2026, 10, 11);

    final code = await runSiloProbe(
      optionsFor(server.origin),
      out: out,
      sleep: (d) async {
        waits.add(d);
        clock = clock.add(d);
      },
      now: () => clock,
    );

    final log = out.toString();
    expect(code, 0, reason: log);
    expect(log, contains('USER_CODE 1234 5678'));
    expect(log, contains('VERIFY https://silo.example/activate'));
    expect(log, contains('identity 200 authorization_header=absent'));
    expect(log, contains('home 200 sections=2'));
    expect(log.trim().split('\n').last, 'logout 204');
    expect(waits, [
      const Duration(seconds: 2),
      const Duration(seconds: 2),
    ], reason: 'poll_after replaces the interval, then backoff starts from it (DeviceLoginRepository.kt:73-75, :170)');
    expect(server.count('/api/v2/auth/device/poll'), 3);
    expect(server.count('/api/v2/auth/logout'), 1);

    final home = jsonDecode(await File('${temp.path}/samples/home-sections.json').readAsString()) as Map;
    expect(home['status'], 200);
    expect(home['section_type_values'], ['continue_watching', 'recently_added']);
    final shape = home['shape'] as Map;
    expect(((shape['keys'] as Map)['sections'] as Map)['count'], 2);

    final files = temp.listSync(recursive: true).whereType<File>().where((f) => f.path.contains('/samples/')).toList();
    expect(files.map((f) => f.uri.pathSegments.last).toSet(), {
      'system-info.json',
      'system-identity.json',
      'device-capability.json',
      'account-me.json',
      'profiles.json',
      'home-sections.json',
      'user-libraries.json',
    });
    for (final file in files) {
      final text = await file.readAsString();
      for (final secret in [
        'access-secret',
        'refresh-secret',
        'device-secret',
        'Secret Title',
        'Secret Name',
        '/p.jpg',
      ]) {
        expect(text, isNot(contains(secret)), reason: '${file.path} leaks $secret');
      }
    }
    for (final secret in ['access-secret', 'refresh-secret', 'device-secret']) {
      expect(log, isNot(contains(secret)));
    }
  });

  test('--actions runs watched and watchlist writes in the one session, printing ids only', () async {
    final server = await _FakeServer.start([_approved]);
    addTearDown(() => server.server.close(force: true));
    final actions = File('${temp.path}/actions.txt')
      ..writeAsStringSync('''
# lane 1
home
watched c1
sleep 2
unwatched c1
watchlist-add c1
watchlist-remove c1
toggle c1 3 1.5
''');
    final out = StringBuffer();
    final waits = <Duration>[];
    var clock = DateTime.utc(2026, 10, 14);

    final code = await runSiloProbe(
      SiloProbeOptions(
        origin: server.origin,
        samplesDir: '${temp.path}/samples',
        deviceIdFile: '${temp.path}/device_id',
        actions: actions.path,
        profile: '9',
      ),
      out: out,
      sleep: (d) async {
        waits.add(d);
        clock = clock.add(d);
      },
      now: () => clock,
    );

    final log = out.toString();
    expect(code, 0, reason: log);
    expect(log, contains('profile selected id=9 pin_token=false'));
    expect(log, contains('section continue_watching ids=c1\n'));
    expect(log, contains('section recently_added ids=\n'));
    expect(log, contains('action watched c1 204 done_ms='));
    expect(log, contains('action watchlist-remove c1 204 done_ms='));
    expect(server.requests.where((r) => r.path.endsWith('/c1')).map((r) => '${r.method} ${r.path}'), [
      'POST /api/v2/watched/c1',
      'DELETE /api/v2/watched/c1',
      'PUT /api/v2/watchlist/c1',
      'DELETE /api/v2/watchlist/c1',
      'POST /api/v2/watched/c1',
      'DELETE /api/v2/watched/c1',
      'POST /api/v2/watched/c1',
    ]);
    expect(waits.skip(waits.length - 3), [
      const Duration(seconds: 2),
      const Duration(milliseconds: 1500),
      const Duration(milliseconds: 1500),
    ]);
    expect(server.count('/api/v2/auth/device/start'), 1, reason: 'one approval covers every action');
    expect(log.trim().split('\n').last, 'logout 204');
    for (final secret in ['Secret Title', 'access-secret']) {
      expect(log, isNot(contains(secret)));
    }
  });

  test('--actions watch and ids print positions and ids, never the title', () async {
    final server = await _FakeServer.start([_approved]);
    addTearDown(() => server.server.close(force: true));
    final actions = File('${temp.path}/actions.txt')..writeAsStringSync('watch movie-1\nids /api/v2/watch/movie-1\n');
    final out = StringBuffer();

    final code = await runSiloProbe(
      SiloProbeOptions(
        origin: server.origin,
        samplesDir: '${temp.path}/samples',
        deviceIdFile: '${temp.path}/device_id',
        actions: actions.path,
        profile: '9',
      ),
      out: out,
    );

    final log = out.toString();
    expect(code, 0, reason: log);
    expect(
      log,
      contains(
        'action watch movie-1 200 position=50.0 played=false audio=0 subtitles=0 '
        'user_data_keys=position_seconds,played\n',
      ),
    );
    expect(log, contains('action item movie-1 200 position=40.0 played=false in_progress=true\n'));
    expect(log, contains('action ids /api/v2/watch/movie-1 200\nid movie-1 type=null season=null episode=null\n'));
    expect(log, isNot(contains('Secret Title')));
  });

  test('--play starts, describes, reports and stops one session without printing secrets', () async {
    final server = await _FakeServer.start([_approved]);
    addTearDown(() => server.server.close(force: true));
    final out = StringBuffer();

    final code = await runSiloProbe(
      SiloProbeOptions(
        origin: server.origin,
        samplesDir: '${temp.path}/samples',
        deviceIdFile: '${temp.path}/device_id',
        profile: '9',
        play: const ['movie-1'],
      ),
      out: out,
      sleep: (_) async {},
    );

    final log = out.toString();
    printOnFailure(log);
    expect(code, 0, reason: log);
    expect(log, contains('playback_capabilities 200 state=available allowed=true protocols=[3]'));
    expect(
      log,
      contains(
        'watch 200 versions=1 file=41 resolution=1080p container=mkv audio=0 subtitles=0 resume=true start=43.0',
      ),
    );
    expect(log, contains('start 201 session=true'));
    expect(log, contains('decision SiloPlayable'));
    expect(log, contains('plan delivery=original_http protocol=http_progressive header_refresh=session'));
    expect(log, contains('plan_url /api/vN/stream/vN/SESSION/file?sig=… headers=[X-Stream-Token]'));
    expect(log, contains('stream 206 same_origin=true'));
    expect(log, contains('progress 200 outcome=applied accepted_sequence=1'));
    expect(log, contains('stop 200 outcome=stopped stop_id_echoed=true'));
    expect(
      server.requests.map((r) => '${r.method} ${r.path}').where((r) => r.contains('playback') || r.contains('stream')),
      [
        'GET /api/v2/playback/capabilities',
        'POST /api/v2/playback/start',
        'GET /api/v2/stream/v3/sess-secret/file',
        'POST /api/v2/playback/sess-secret/progress',
        'DELETE /api/v2/playback/sess-secret',
      ],
    );
    for (final secret in ['sess-secret', 'secret-sig', 'stream-secret', 'access-secret', 'Secret Title']) {
      expect(log, isNot(contains(secret)), reason: 'the log leaks $secret');
    }
  });

  test('--profile and --actions parse', () {
    final options = SiloProbeOptions.parse(['--profile', 'p-7', '--actions', '-'])!;

    expect(options.profile, 'p-7');
    expect(options.actions, '-');
    expect(SiloProbeOptions.parse(['--profile']), isNull);
  });

  test('an unknown action stops the run with 64 and still logs out', () async {
    final server = await _FakeServer.start([_approved]);
    addTearDown(() => server.server.close(force: true));
    final actions = File('${temp.path}/actions.txt')..writeAsStringSync('watched c1\nrate c1 5\nunwatched c1\n');
    final out = StringBuffer();

    final code = await runSiloProbe(
      SiloProbeOptions(
        origin: server.origin,
        samplesDir: '${temp.path}/samples',
        deviceIdFile: '${temp.path}/device_id',
        actions: actions.path,
      ),
      out: out,
      sleep: (_) async {},
    );

    expect(code, 64);
    expect(server.requests.where((r) => r.path.startsWith('/api/v2/watched/')).map((r) => r.method), ['POST']);
    expect(out.toString().trim().split('\n').last, 'logout 204');
  });

  test('--baseline times the same authenticated home request on a bare HttpClient', () async {
    final server = await _FakeServer.start([
      {
        'status': 'approved',
        'profile_id': '9',
        'profile_token': 'profile-secret',
        'tokens': {'access_token': 'access-secret', 'refresh_token': 'refresh-secret', 'expires_in': 900},
      },
    ]);
    addTearDown(() => server.server.close(force: true));
    final out = StringBuffer();
    var clock = DateTime.utc(2026, 10, 11);

    final code = await runSiloProbe(
      SiloProbeOptions(
        origin: server.origin,
        samplesDir: '${temp.path}/samples',
        deviceIdFile: '${temp.path}/device_id',
        timeHome: 3,
        baseline: true,
      ),
      out: out,
      sleep: (d) async => clock = clock.add(d),
      now: () => clock,
    );

    final log = out.toString();
    expect(code, 0, reason: log);
    final lines = log.trim().split('\n');
    final timing = lines.skipWhile((l) => !l.startsWith('warmup')).takeWhile((l) => !l.startsWith('logout')).toList();
    expect(timing.map((l) => l.split(' ').first).toList(), [
      'warmup',
      'home_ms',
      'home_ms',
      'home_ms',
      'home_ms_median',
      'warmup',
      'raw_ms',
      'raw_ms',
      'raw_ms',
      'raw_ms_median',
      'delta_ms_median',
      'perf',
    ], reason: log);
    expect(timing.first, 'warmup siloHttp');
    expect(timing[5], 'warmup raw');
    expect(timing.where((l) => l.startsWith('raw_ms ')).every((l) => l.endsWith(' status=200')), isTrue, reason: log);
    expect(timing.last, anyOf('perf PASS', 'perf FAIL'));
    final siloMedian = int.parse(timing[4].split(' ').last);
    final rawMedian = int.parse(timing[9].split(' ').last);
    expect(timing[10], 'delta_ms_median ${siloMedian - rawMedian}');

    final homes = server.requests.where((r) => r.path == '/api/v2/home/sections').toList();
    expect(homes.length, 1 + 4 + 4, reason: 'first home, warmup + 3 timed on each client');
    expect(homes.last.headers, homes[4].headers, reason: 'the raw client sends what SiloHttp sent');
    expect(homes.last.headers['x-profile-token'], 'profile-secret');

    for (final secret in ['access-secret', 'refresh-secret', 'profile-secret', 'device-secret']) {
      expect(log, isNot(contains(secret)));
    }
  });

  test('a code that expires is withdrawn and no session is written', () async {
    final server = await _FakeServer.start([]);
    addTearDown(() => server.server.close(force: true));
    final out = StringBuffer();
    var clock = DateTime.utc(2026, 10, 11);

    final code = await runSiloProbe(
      optionsFor(server.origin),
      out: out,
      sleep: (d) async => clock = clock.add(d),
      now: () => clock,
    );

    expect(code, 3);
    expect(out.toString(), contains('code expired; withdrawn cancel=200; no tokens written'));
    expect(server.count('/api/v2/auth/device/cancel'), 1, reason: 'DeviceSignInMachine.kt:364-379');
    expect(server.count('/api/v2/auth/logout'), 0);
    expect(out.toString(), isNot(contains('logout')));
  });

  test('two runs send the same X-Silo-Device-Id', () async {
    final ids = <String?>[];
    for (var run = 0; run < 2; run++) {
      final server = await _FakeServer.start([]);
      var clock = DateTime.utc(2026, 10, 11);
      await runSiloProbe(
        optionsFor(server.origin),
        out: StringBuffer(),
        sleep: (d) async => clock = clock.add(d),
        now: () => clock,
      );
      ids.add(server.requests.first.headers[SiloHeaders.deviceId.toLowerCase()]);
      await server.server.close(force: true);
    }

    expect(ids.first, isNotNull);
    expect(ids.last, ids.first);
  });
}
