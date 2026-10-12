import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_session.dart';

import '../silo/fake_silo.dart';

export '../silo/fake_silo.dart';

class FakeSiloProfile {
  final String id;
  final String name;
  final String? pin;

  const FakeSiloProfile(this.id, this.name, {this.pin});
}

typedef FakePollReply = FutureOr<http.Response> Function(String deviceCode, int pollCount);

/// A Silo server with the sign-in and profile routes S2 uses, answering the
/// shapes recorded in `docs/silo-migration/research/samples/`.
class FakeSiloServer {
  final String serverId;
  final String username;
  final String password;
  final int codeLifetimeSeconds;
  final int codeInterval;
  final List<FakeSiloProfile> profiles;

  /// Answers every `device/poll`. Defaults to pending.
  FakePollReply pollReply;

  /// Holds `auth/login` until completed, to race it against the device code.
  Completer<void>? loginGate;

  final List<String> issuedCodes = [];
  final List<String> cancelledCodes = [];
  late final FakeSilo fake = FakeSilo(_handle);

  FakeSiloServer({
    this.serverId = 'server-1',
    this.username = 'alice',
    this.password = 'secret',
    this.codeLifetimeSeconds = 900,
    this.codeInterval = 5,
    this.profiles = const [FakeSiloProfile('p-1', 'Alice'), FakeSiloProfile('p-2', 'Kids', pin: '1234')],
    FakePollReply? pollReply,
  }) : pollReply = pollReply ?? ((_, _) => pending());

  http.Client get client => fake.client;

  List<RecordedRequest> get requests => fake.requests;

  List<RecordedRequest> to(String path) => fake.to(path);

  int _polls = 0;

  static http.Response pending({int? pollAfter, bool opened = false, String? expiresAt}) =>
      jsonResponse({'status': 'pending', 'poll_after': ?pollAfter, 'opened': opened, 'expires_at': ?expiresAt}, 200);

  static http.Response approved({String access = 'access-D', String refresh = 'refresh-D'}) => jsonResponse({
    'status': 'approved',
    'tokens': {'access_token': access, 'refresh_token': refresh, 'expires_in': 3600},
  }, 200);

  static http.Response status(String status) => jsonResponse({'status': status}, 200);

  static http.Response problem(int status, String code) => jsonResponse(
    {'type': 'https://silo.dev/problems/$code', 'title': code, 'status': status, 'detail': code},
    status,
    headers: {'content-type': 'application/problem+json'},
  );

  Future<http.Response> _handle(RecordedRequest request) async {
    final body = request.body.isEmpty ? const {} : jsonDecode(request.body) as Map<String, dynamic>;
    final path = request.url.path;
    switch ((request.method, path)) {
      case ('GET', '/api/v2/system/identity'):
        return jsonResponse({'server_id': serverId}, 200);
      case ('GET', '/api/v2/theme/branding'):
        return jsonResponse({'server_name': 'Silo'}, 200);
      case ('GET', '/api/v2/system/info'):
        return jsonResponse({'server_version': '1', 'api_major': 2}, 200);
      case ('GET', '/api/v2/system/setup'):
        return jsonResponse({'needs_setup': false, 'wizard_completed': true}, 200);
      case ('GET', '/api/v2/auth/signup'):
        return jsonResponse({'enabled': true}, 200);
      case ('GET', '/api/v2/auth/device/capability'):
        return jsonResponse({'state': 'available', 'cancel': true, 'opened_signal': true}, 200);
      case ('POST', '/api/v2/auth/device/start'):
        final code = 'device-code-${issuedCodes.length + 1}';
        issuedCodes.add(code);
        return jsonResponse({
          'device_code': code,
          'user_code': '1234567${issuedCodes.length}',
          'match_code': '42',
          'verification_uri': 'https://silo.ruleone.xyz/activate/',
          'verification_uri_complete': 'https://silo.ruleone.xyz/activate?code=1234567${issuedCodes.length}',
          'expires_at': DateTime.utc(2026, 10, 12, 12).add(Duration(seconds: codeLifetimeSeconds)).toIso8601String(),
          'expires_in': codeLifetimeSeconds,
          'interval': codeInterval,
        }, 201);
      case ('POST', '/api/v2/auth/device/poll'):
        return pollReply(body['device_code'] as String, ++_polls);
      case ('POST', '/api/v2/auth/device/cancel'):
        cancelledCodes.add(body['device_code'] as String);
        return jsonResponse({'status': 'canceled'}, 200);
      case ('POST', '/api/v2/auth/login'):
        await loginGate?.future;
        if (body['username'] != username || body['password'] != password) {
          return problem(401, 'invalid_credentials');
        }
        return jsonResponse({
          'access_token': 'access-P',
          'refresh_token': 'refresh-P',
          'expires_in': 3600,
          'user': {'id': 'u-1', 'username': username, 'role': 'admin'},
        }, 200);
      case ('GET', '/api/v2/account/me'):
        return jsonResponse({'id': 'u-1', 'username': username, 'email': 'a@b.c', 'role': 'admin'}, 200);
      case ('GET', '/api/v2/profiles'):
        return jsonResponse({
          'items': [
            for (final profile in profiles)
              {'id': profile.id, 'name': profile.name, 'has_pin': profile.pin != null, 'is_primary': false},
          ],
        }, 200);
      case ('POST', _) when path.endsWith('/verify-pin'):
        final id = path.split('/')[4];
        final profile = profiles.firstWhere((p) => p.id == id);
        final valid = body['pin'] == profile.pin;
        return jsonResponse({'valid': valid, 'profile_token': valid ? 'profile-token-$id' : null}, 200);
    }
    return jsonResponse({}, 404);
  }
}

/// A clock that moves only when the code under test waits, so poll timing
/// is asserted exactly.
class FakeSiloClock {
  DateTime now = DateTime.utc(2026, 10, 12, 12);
  final List<Duration> waits = [];

  Future<void> wait(Duration duration) async {
    waits.add(duration);
    now = now.add(duration);
  }
}

Future<SiloSessionController> emptySiloSession() => SiloSessionController.load(MemorySiloSessionStore());

SiloHttp siloHttpForServer(FakeSiloServer server, SiloSessionController session) =>
    SiloHttp(origin: siloTestOrigin, session: session, device: siloTestDevice, client: server.client);
