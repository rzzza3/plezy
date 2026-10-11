import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_contract_gate.dart';
import 'package:plezy/silo/silo_headers.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_session.dart';

const String _usage = '''
Usage: dart run tool/silo_probe.dart [origin] [options]

Signs in to a Silo server by device code, records the structure of the
read-only responses, and signs out. Tokens stay in memory.

  origin                   Server origin. Default https://silo.ruleone.xyz
  --samples <dir>          Where structural summaries go.
                           Default docs/silo-migration/research/samples
  --device-id-file <path>  Where the X-Silo-Device-Id persists between runs.
                           Default ~/.config/plezy-silo-probe/device_id
  --time-home <n>          Time n extra GET /api/v2/home/sections calls.
  --force-refresh          Expire the access token locally before home.
  --revoked                Sign out server-side, then reuse the old tokens.
''';

Future<void> main(List<String> args) async {
  final options = SiloProbeOptions.parse(args);
  if (options == null) {
    stderr.write(_usage);
    exitCode = 64;
    return;
  }
  exitCode = await runSiloProbe(options, out: stdout);
}

class SiloProbeOptions {
  final Uri origin;
  final String samplesDir;
  final String deviceIdFile;
  final int timeHome;
  final bool forceRefresh;
  final bool revoked;

  const SiloProbeOptions({
    required this.origin,
    required this.samplesDir,
    required this.deviceIdFile,
    this.timeHome = 0,
    this.forceRefresh = false,
    this.revoked = false,
  });

  static SiloProbeOptions? parse(List<String> args) {
    var origin = 'https://silo.ruleone.xyz';
    var samples = 'docs/silo-migration/research/samples';
    var deviceIdFile =
        '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/.config/plezy-silo-probe/device_id';
    var timeHome = 0;
    var forceRefresh = false;
    var revoked = false;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next() => i + 1 < args.length ? args[++i] : throw const FormatException();
      try {
        switch (arg) {
          case '--samples':
            samples = next();
          case '--device-id-file':
            deviceIdFile = next();
          case '--time-home':
            timeHome = int.parse(next());
          case '--force-refresh':
            forceRefresh = true;
          case '--revoked':
            revoked = true;
          case '-h' || '--help':
            return null;
          default:
            if (arg.startsWith('-')) return null;
            origin = arg;
        }
      } on FormatException {
        return null;
      }
    }
    final uri = Uri.tryParse(origin);
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http') || uri.host.isEmpty) return null;
    return SiloProbeOptions(
      origin: uri,
      samplesDir: samples,
      deviceIdFile: deviceIdFile,
      timeHome: timeHome,
      forceRefresh: forceRefresh,
      revoked: revoked,
    );
  }
}

class FileSiloDeviceIdStore implements SiloDeviceIdStore {
  final File file;

  FileSiloDeviceIdStore(String path) : file = File(path);

  @override
  Future<String?> read() async => await file.exists() ? (await file.readAsString()).trim() : null;

  @override
  Future<void> write(String deviceId) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(deviceId);
  }
}

class _ProbeFailure implements Exception {
  final int exitCode;
  final String message;

  const _ProbeFailure(this.exitCode, this.message);
}

const Duration _maxBackoff = Duration(seconds: 30);

/// Returns the process exit code. Writes one line per step to [out], never a
/// token, title or name.
Future<int> runSiloProbe(
  SiloProbeOptions options, {
  required StringSink out,
  http.Client? client,
  SiloDeviceIdStore? deviceIds,
  Future<void> Function(Duration wait)? sleep,
  DateTime Function()? now,
}) async {
  final wait = sleep ?? (d) => Future<void>.delayed(d);
  final clock = now ?? DateTime.now;
  final device = await SiloHeaders.load(
    store: deviceIds ?? FileSiloDeviceIdStore(options.deviceIdFile),
    isTv: true,
    manufacturer: 'Plezy',
    model: 'Silo Probe',
    clientName: 'Plezy',
  );
  out.writeln('device_id ${device.id}');

  final session = await SiloSessionController.load(MemorySiloSessionStore(), now: clock);
  var refreshCalls = 0;
  var expired = false;
  final expiredSub = session.sessionExpired.listen((_) => expired = true);
  final exchanges = <SiloExchange>[];
  final silo = SiloHttp(
    origin: options.origin,
    session: session,
    device: device,
    client: client,
    onExchange: (exchange) {
      exchanges.add(exchange);
      if (exchange.url.path == '/api/v2/auth/refresh') refreshCalls++;
    },
  );
  final samples = Directory(options.samplesDir);

  try {
    final info = await silo.send(const SiloRequest.get('/api/v2/system/info', auth: SiloAuth.none, gated: false));
    final infoJson = info.isSuccess ? _tryJson(info.body) : null;
    final apiMajor = infoJson is Map ? infoJson['api_major'] : null;
    silo.gate.recordProbe(status: info.statusCode, body: info.body, apiMajor: apiMajor is int ? apiMajor : null);
    out.writeln('info ${info.statusCode} api_major=$apiMajor contract=${silo.gate.contract.name}');
    if (silo.gate.isBlocked) throw const _ProbeFailure(4, SiloUpdateRequiredException.message);
    await _writeSample(samples, 'system-info.json', 'GET /api/v2/system/info', info);

    final before = exchanges.length;
    final identity = await silo.send(const SiloRequest.get('/api/v2/system/identity', auth: SiloAuth.none));
    final sentAuthorization = exchanges
        .skip(before)
        .any((e) => e.headerNames.any((h) => h.toLowerCase() == 'authorization'));
    out.writeln(
      'identity ${identity.statusCode} authorization_header=${sentAuthorization ? 'present' : 'absent'} '
      'headers=${exchanges.skip(before).first.headerNames.join(',')}',
    );
    await _writeSample(samples, 'system-identity.json', 'GET /api/v2/system/identity', identity);

    final capability = await silo.send(const SiloRequest.get('/api/v2/auth/device/capability', auth: SiloAuth.none));
    final capabilityJson = capability.isSuccess ? _tryJson(capability.body) : null;
    final available = capabilityJson is Map && capabilityJson['state'] == 'available';
    final canCancel = available && capabilityJson['cancel'] == true;
    out.writeln('capability ${capability.statusCode} available=$available cancel=$canCancel');
    await _writeSample(samples, 'device-capability.json', 'GET /api/v2/auth/device/capability', capability);
    if (capability.isSuccess && !available) throw const _ProbeFailure(2, 'device sign-in unavailable');

    final approved = await _signIn(silo, out: out, wait: wait, clock: clock, canCancel: canCancel);
    final tokens = approved['tokens'] as Map;
    final generation = session.generation;
    await session.replaceAccountSession(
      origin: silo.origin.toString(),
      accessToken: tokens['access_token'] as String,
      refreshToken: tokens['refresh_token'] as String,
      expiresInSeconds: tokens['expires_in'] is int ? tokens['expires_in'] as int : 0,
      expectedGeneration: generation,
    );
    out.writeln('signed_in generation=${session.generation}');

    final me = await silo.send(const SiloRequest.get('/api/v2/account/me'));
    out.writeln('account_me ${me.statusCode}');
    await _writeSample(samples, 'account-me.json', 'GET /api/v2/account/me', me);

    final profiles = await silo.send(const SiloRequest.get('/api/v2/profiles'));
    out.writeln('profiles ${profiles.statusCode}');
    await _writeSample(samples, 'profiles.json', 'GET /api/v2/profiles', profiles);
    final profile = _pickProfile(approved, profiles.isSuccess ? profiles.json() : null);
    if (profile != null) {
      await session.selectProfile(profile.id, profile.token);
      out.writeln('profile selected pin_token=${profile.token != null}');
    } else {
      out.writeln('profile none');
    }

    if (options.revoked) {
      final stale = session.session!;
      final logout = await silo.send(const SiloRequest.post('/api/v2/auth/logout', single: true));
      out.writeln('revoke_logout ${logout.statusCode}');
      await session.replaceAccountSession(
        origin: stale.origin,
        accessToken: stale.tokens.accessToken,
        refreshToken: stale.tokens.refreshToken,
        expiresInSeconds: 0,
      );
      await session.selectProfile(stale.profileId, stale.profileToken);
    }
    if (options.forceRefresh) {
      final current = session.session!;
      await session.saveRefreshedTokens(
        accessToken: current.tokens.accessToken,
        refreshToken: current.tokens.refreshToken,
        expiresInSeconds: 0,
      );
    }

    final refreshesBefore = refreshCalls;
    final SiloResponse home;
    try {
      home = await silo.send(const SiloRequest.get('/api/v2/home/sections'));
    } on SiloCredentialsRepudiatedException {
      out.writeln('refresh count=${refreshCalls - refreshesBefore}');
      out.writeln(expired ? 'session expired' : 'credentials repudiated');
      return 5;
    }
    final homeJson = home.isSuccess ? home.json() : null;
    final sections = homeJson is Map && homeJson['sections'] is List ? (homeJson['sections'] as List).length : 0;
    if (options.forceRefresh || options.revoked) out.writeln('refresh count=${refreshCalls - refreshesBefore}');
    out.writeln('home ${home.statusCode} sections=$sections');
    await _writeSample(samples, 'home-sections.json', 'GET /api/v2/home/sections', home);

    final libraries = await silo.send(const SiloRequest.get('/api/v2/user/libraries'));
    out.writeln('libraries ${libraries.statusCode}');
    await _writeSample(samples, 'user-libraries.json', 'GET /api/v2/user/libraries', libraries);

    if (options.timeHome > 0) {
      final timings = <int>[];
      for (var i = 0; i < options.timeHome; i++) {
        final watch = Stopwatch()..start();
        final timed = await silo.send(const SiloRequest.get('/api/v2/home/sections'));
        watch.stop();
        timings.add(watch.elapsedMilliseconds);
        out.writeln('home_ms ${watch.elapsedMilliseconds} status=${timed.statusCode}');
      }
      timings.sort();
      out.writeln('home_ms_median ${timings[timings.length ~/ 2]}');
    }
    return 0;
  } on _ProbeFailure catch (failure) {
    out.writeln(failure.message);
    return failure.exitCode;
  } finally {
    if (session.session != null) {
      try {
        final logout = await silo.send(const SiloRequest.post('/api/v2/auth/logout', single: true));
        out.writeln('logout ${logout.statusCode}');
      } on Exception catch (e) {
        out.writeln('logout failed ${e.runtimeType}');
      }
      await session.signOut();
    }
    await expiredSub.cancel();
    await session.close();
    if (client == null) silo.close();
  }
}

/// Starts a device code and polls it until approval. Follows
/// `DeviceLoginRepository.kt:68-189`: poll at once, then every `interval`,
/// replaced by `poll_after`, never under 1 s; back off from the interval,
/// doubling to 30 s; clamp every wait to the deadline.
Future<Map<String, Object?>> _signIn(
  SiloHttp silo, {
  required StringSink out,
  required Future<void> Function(Duration) wait,
  required DateTime Function() clock,
  required bool canCancel,
}) async {
  Map<String, Object?>? start;
  var startBackoff = Duration.zero;
  while (start == null) {
    int? status;
    try {
      final response = await silo.send(
        SiloRequest.post(
          '/api/v2/auth/device/start',
          body: {'device_name': 'Plezy Silo Probe', 'device_platform': silo.device.platform},
          auth: SiloAuth.none,
          single: true,
        ),
      );
      status = response.statusCode;
      final json = response.statusCode == 201 ? _tryJson(response.body) : null;
      if (json is Map<String, Object?>) {
        start = json;
        break;
      }
    } on Exception {
      status = null;
    }
    if (status == 404 || status == 501) throw const _ProbeFailure(2, 'device sign-in unavailable');
    if (status == 410 || status == 426) throw const _ProbeFailure(4, SiloUpdateRequiredException.message);
    if (status != null && status >= 400 && status < 500 && status != 408 && status != 429) {
      throw _ProbeFailure(3, 'start failed $status');
    }
    startBackoff = _nextBackoff(startBackoff, const Duration(seconds: 1));
    out.writeln('start retry ${status ?? 'network'} wait=${startBackoff.inSeconds}s');
    await wait(startBackoff);
  }

  final deviceCode = start['device_code'] as String;
  final userCode = '${start['user_code']}';
  final grouped = userCode.length == 8 ? '${userCode.substring(0, 4)} ${userCode.substring(4)}' : userCode;
  out.writeln('USER_CODE $grouped');
  out.writeln('VERIFY ${start['verification_uri']}');
  out.writeln('VERIFY_COMPLETE ${start['verification_uri_complete']}');

  final startedAt = clock();
  final expiresIn = start['expires_in'] is int ? start['expires_in'] as int : 0;
  final lifetime = Duration(seconds: expiresIn < 1 ? 1 : expiresIn);
  var deadline = startedAt.add(lifetime);
  final serverExpiry = DateTime.tryParse('${start['expires_at']}');
  final skew = serverExpiry == null ? null : startedAt.add(lifetime).difference(serverExpiry);
  final rawInterval = start['interval'] is int ? start['interval'] as int : 1;
  var interval = Duration(seconds: rawInterval < 1 ? 1 : rawInterval);
  var backoff = Duration.zero;

  Duration clamp(Duration d) {
    final left = deadline.difference(clock());
    if (left <= Duration.zero) return Duration.zero;
    return d < left ? d : left;
  }

  while (true) {
    if (!clock().isBefore(deadline)) {
      var cancelStatus = 'skipped';
      if (canCancel) {
        try {
          final cancel = await silo
              .send(
                SiloRequest.post(
                  '/api/v2/auth/device/cancel',
                  body: {'device_code': deviceCode},
                  auth: SiloAuth.none,
                  single: true,
                ),
              )
              .timeout(const Duration(seconds: 5));
          cancelStatus = '${cancel.statusCode}';
        } on Object {
          cancelStatus = 'failed';
        }
      }
      throw _ProbeFailure(3, 'code expired; withdrawn cancel=$cancelStatus; no tokens written');
    }

    int? status;
    Object? json;
    try {
      final response = await silo.send(
        SiloRequest.post(
          '/api/v2/auth/device/poll',
          body: {'device_code': deviceCode},
          auth: SiloAuth.none,
          single: true,
        ),
      );
      status = response.statusCode;
      json = response.statusCode == 200 ? _tryJson(response.body) : null;
    } on Exception {
      status = null;
    }

    if (json is Map<String, Object?>) {
      backoff = Duration.zero;
      switch (json['status']) {
        case 'pending':
          final pendingExpiry = DateTime.tryParse('${json['expires_at']}');
          if (pendingExpiry != null && skew != null) {
            final extended = pendingExpiry.add(skew);
            if (extended.isAfter(deadline)) deadline = extended;
          }
          if (json['poll_after'] case final int after) interval = Duration(seconds: after < 1 ? 1 : after);
          final next = clamp(interval);
          out.writeln('poll pending opened=${json['opened'] == true} wait=${next.inSeconds}s');
          await wait(next);
        case 'approved':
          final tokens = json['tokens'];
          if (tokens is Map &&
              tokens['access_token'] is String &&
              (tokens['access_token'] as String).isNotEmpty &&
              tokens['refresh_token'] is String &&
              (tokens['refresh_token'] as String).isNotEmpty) {
            out.writeln('poll approved');
            return json;
          }
          throw const _ProbeFailure(3, 'approved without tokens');
        case 'denied':
          throw const _ProbeFailure(3, 'code denied; no tokens written');
        case 'expired' || 'consumed' || 'canceled':
          throw _ProbeFailure(3, 'code ${json['status']}; no tokens written');
        default:
          throw _ProbeFailure(3, 'poll unknown status ${json['status']}');
      }
      continue;
    }

    if (status == 410 || status == 426) throw const _ProbeFailure(4, SiloUpdateRequiredException.message);
    final transient = status == null || status == 0 || status == 408 || status == 429 || status >= 500;
    if (!transient) throw _ProbeFailure(3, 'code gone $status; no tokens written');
    backoff = _nextBackoff(backoff, interval);
    final next = clamp(backoff);
    out.writeln('poll retry ${status ?? 'network'} wait=${next.inSeconds}s');
    await wait(next);
  }
}

Duration _nextBackoff(Duration current, Duration interval) {
  if (current <= Duration.zero) {
    if (interval < const Duration(seconds: 1)) return const Duration(seconds: 1);
    return interval > _maxBackoff ? _maxBackoff : interval;
  }
  final doubled = current * 2;
  return doubled > _maxBackoff ? _maxBackoff : doubled;
}

({String id, String? token})? _pickProfile(Map<String, Object?> approved, Object? profilesJson) {
  final polledId = approved['profile_id'];
  if (polledId is String && polledId.isNotEmpty) {
    final token = approved['profile_token'];
    return (id: polledId, token: token is String && token.isNotEmpty ? token : null);
  }
  if (profilesJson is! Map || profilesJson['items'] is! List) return null;
  final open = [
    for (final item in profilesJson['items'] as List)
      if (item is Map && item['has_pin'] != true && item['id'] != null) item,
  ];
  if (open.isEmpty) return null;
  final primary = open.where((p) => p['is_primary'] == true);
  return (id: '${(primary.isEmpty ? open.first : primary.first)['id']}', token: null);
}

Object? _tryJson(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

Future<void> _writeSample(Directory dir, String file, String endpoint, SiloResponse response) async {
  final json = _tryJson(response.body);
  final sectionTypes = <String>{};
  _collectSectionTypes(json, sectionTypes);
  final summary = {
    'endpoint': endpoint,
    'status': response.statusCode,
    'content_type': response.headers['content-type']?.split(';').first,
    'shape': json == null ? (response.body.isEmpty ? 'empty' : 'non-json') : describeJsonShape(json),
    if (sectionTypes.isNotEmpty) 'section_type_values': sectionTypes.toList()..sort(),
  };
  await dir.create(recursive: true);
  await File('${dir.path}/$file').writeAsString('${const JsonEncoder.withIndent('  ').convert(summary)}\n');
}

void _collectSectionTypes(Object? json, Set<String> into) {
  if (json is Map) {
    for (final entry in json.entries) {
      if (entry.key == 'section_type' && entry.value is String) {
        into.add(entry.value as String);
      } else {
        _collectSectionTypes(entry.value, into);
      }
    }
  } else if (json is List) {
    for (final item in json) {
      _collectSectionTypes(item, into);
    }
  }
}

/// Keys and value types only. Every string, number and boolean value is
/// replaced by its type name, so no token, title or name survives.
Object describeJsonShape(Object? json) {
  if (json is Map) {
    return {
      'type': 'object',
      'keys': {for (final entry in json.entries) '${entry.key}': describeJsonShape(entry.value)},
    };
  }
  if (json is List) {
    Object? items;
    for (final item in json) {
      final shape = describeJsonShape(item);
      items = items == null ? shape : _mergeShapes(items, shape);
    }
    return {'type': 'array', 'count': json.length, 'items': ?items};
  }
  return switch (json) {
    null => 'null',
    String() => 'string',
    int() => 'int',
    double() => 'number',
    bool() => 'bool',
    _ => 'unknown',
  };
}

Object _mergeShapes(Object a, Object b) {
  if (jsonEncode(a) == jsonEncode(b)) return a;
  if (a is Map && b is Map && a['type'] == 'object' && b['type'] == 'object') {
    final aKeys = a['keys'] as Map;
    final bKeys = b['keys'] as Map;
    return {
      'type': 'object',
      'keys': {
        for (final key in {...aKeys.keys, ...bKeys.keys})
          key: switch ((aKeys[key], bKeys[key])) {
            (final Object x, final Object y) => _mergeShapes(x, y),
            (final Object x, null) || (null, final Object x) => _mergeShapes(x, 'absent'),
            _ => 'absent',
          },
      },
    };
  }
  if (a is Map && b is Map && a['type'] == 'array' && b['type'] == 'array') {
    final ai = a['items'];
    final bi = b['items'];
    return {
      'type': 'array',
      'items': ?(ai == null ? bi : (bi == null ? ai : _mergeShapes(ai as Object, bi as Object))),
    };
  }
  final variants = <String, Object>{};
  for (final shape in [a, b]) {
    if (shape is Map && shape['type'] == 'union') {
      for (final v in shape['of'] as List) {
        variants[jsonEncode(v)] = v as Object;
      }
    } else {
      variants[jsonEncode(shape)] = shape;
    }
  }
  return {'type': 'union', 'of': variants.values.toList()};
}
