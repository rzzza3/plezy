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
    await utf8.decoder.bind(request).join();
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
