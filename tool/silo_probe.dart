import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:plezy/silo/silo_contract_gate.dart';
import 'package:plezy/silo/silo_headers.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_playback.dart';
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
  --play <id>[@quality]    Start one playback session on the item, print
                           the plan's structure, fetch the stream once, post
                           one paused progress sample at the start position,
                           then stop the session. Repeatable. The quality is
                           the quality_preference, auto by default.
  --baseline               With --time-home, also time n of the same request
                           on a bare dart:io HttpClient and judge the 50 ms
                           rule.
  --force-refresh          Expire the access token locally before home.
  --revoked                Sign out server-side, then reuse the old tokens.
  --profile <id>           Act as this profile instead of the one the
                           approval or the primary open profile gives. It
                           must have no PIN.
  --actions <file|->       After the reads, run one action per line from the
                           file or stdin, in the same session, then log out:
                             home                   ids per section_type
                             watch <content_id>     stored position, played
                                                    and track counts
                             ids </api/v2/...>      every content_id in a GET,
                                                    with type, season, episode
                             watched <content_id>   POST /watched/{id}
                             unwatched <content_id> DELETE /watched/{id}
                             watchlist-add <id>     PUT /watchlist/{id}
                             watchlist-remove <id>  DELETE /watchlist/{id}
                             toggle <id> <n> <s>    n watched/unwatched
                                                    flips, s seconds apart
                             sleep <seconds>
                           Each write prints its status and done_ms, the
                           epoch milliseconds the 204 arrived.
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
  final List<String> play;
  final bool baseline;
  final bool forceRefresh;
  final bool revoked;
  final String? actions;
  final String? profile;

  const SiloProbeOptions({
    required this.origin,
    required this.samplesDir,
    required this.deviceIdFile,
    this.timeHome = 0,
    this.play = const [],
    this.baseline = false,
    this.forceRefresh = false,
    this.revoked = false,
    this.actions,
    this.profile,
  });

  static SiloProbeOptions? parse(List<String> args) {
    var origin = 'https://silo.ruleone.xyz';
    var samples = 'docs/silo-migration/research/samples';
    var deviceIdFile =
        '${Platform.environment['HOME'] ?? Directory.systemTemp.path}/.config/plezy-silo-probe/device_id';
    var timeHome = 0;
    final play = <String>[];
    var baseline = false;
    var forceRefresh = false;
    var revoked = false;
    String? actions;
    String? profile;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      String next() => i + 1 < args.length ? args[++i] : throw const FormatException();
      try {
        switch (arg) {
          case '--samples':
            samples = next();
          case '--device-id-file':
            deviceIdFile = next();
          case '--play':
            play.add(next());
          case '--time-home':
            timeHome = int.parse(next());
          case '--baseline':
            baseline = true;
          case '--force-refresh':
            forceRefresh = true;
          case '--revoked':
            revoked = true;
          case '--actions':
            actions = next();
          case '--profile':
            profile = next();
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
    if (baseline && timeHome < 1) return null;
    return SiloProbeOptions(
      origin: uri,
      samplesDir: samples,
      deviceIdFile: deviceIdFile,
      timeHome: timeHome,
      play: play,
      baseline: baseline,
      forceRefresh: forceRefresh,
      revoked: revoked,
      actions: actions,
      profile: profile,
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
const int _perfBudgetMs = 50;

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
    // The operator named this origin on the command line, which is the
    // consent the app asks for on screen.
    cleartextApproved: (origin) => origin == siloOrigin(options.origin),
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
    final chosen = options.profile;
    final profile = chosen != null
        ? (id: chosen, token: null)
        : _pickProfile(approved, profiles.isSuccess ? profiles.json() : null);
    if (profile != null) {
      await session.selectProfile(profile.id, profile.token);
      out.writeln('profile selected id=${profile.id} pin_token=${profile.token != null}');
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
      await silo.send(const SiloRequest.get('/api/v2/home/sections'));
      out.writeln('warmup siloHttp');
      final timings = <int>[];
      for (var i = 0; i < options.timeHome; i++) {
        final watch = Stopwatch()..start();
        final timed = await silo.send(const SiloRequest.get('/api/v2/home/sections'));
        watch.stop();
        timings.add(watch.elapsedMilliseconds);
        out.writeln('home_ms ${watch.elapsedMilliseconds} status=${timed.statusCode}');
      }
      final siloMedian = _median(timings);
      out.writeln('home_ms_median $siloMedian');

      if (options.baseline) {
        final current = session.session!;
        final headers = {
          'Content-Type': 'application/json',
          SiloHeaders.authorization: 'Bearer ${current.tokens.accessToken}',
          SiloHeaders.profileId: ?current.profileId,
          SiloHeaders.profileToken: ?current.profileToken,
          ...device.toMap(),
        };
        final sent = exchanges.last.headerNames.toSet();
        if (!sent.containsAll(headers.keys) || sent.length != headers.length) {
          throw _ProbeFailure(6, 'baseline headers differ from SiloHttp: ${sent.join(',')}');
        }
        final rawMedian = await _timeRawHome(
          options.origin.resolve('/api/v2/home/sections'),
          headers,
          options.timeHome,
          out,
        );
        final delta = siloMedian - rawMedian;
        out.writeln('delta_ms_median $delta');
        out.writeln(delta <= _perfBudgetMs ? 'perf PASS' : 'perf FAIL');
      }
    }
    for (final play in options.play) {
      final at = play.indexOf('@');
      await probeSiloPlayback(
        silo,
        session,
        at < 0 ? play : play.substring(0, at),
        quality: at < 0 ? 'auto' : play.substring(at + 1),
        out: out,
        samples: samples,
      );
    }
    final actions = options.actions;
    if (actions != null) {
      final lines = actions == '-' ? stdin : File(actions).openRead();
      await for (final line in lines.transform(utf8.decoder).transform(const LineSplitter())) {
        final action = parseSiloProbeAction(line);
        if (action == null) throw const _ProbeFailure(64, 'action unknown');
        await _runAction(silo, action, out: out, wait: wait, clock: clock);
      }
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

/// The curl-equivalent baseline for the S1 perf rule: one keep-alive
/// connection, no SiloHttp layers, the full body read on every call.
Future<int> _timeRawHome(Uri url, Map<String, String> headers, int n, StringSink out) async {
  final client = HttpClient()..connectionTimeout = siloConnectTimeout;
  Future<int> get() async {
    final request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode;
  }

  try {
    await get();
    out.writeln('warmup raw');
    final timings = <int>[];
    for (var i = 0; i < n; i++) {
      final watch = Stopwatch()..start();
      final status = await get();
      watch.stop();
      timings.add(watch.elapsedMilliseconds);
      out.writeln('raw_ms ${watch.elapsedMilliseconds} status=$status');
    }
    final median = _median(timings);
    out.writeln('raw_ms_median $median');
    return median;
  } finally {
    client.close(force: true);
  }
}

sealed class SiloProbeAction {
  const SiloProbeAction();
}

final class SiloProbeSkip extends SiloProbeAction {
  const SiloProbeSkip();
}

final class SiloProbeHome extends SiloProbeAction {
  const SiloProbeHome();
}

final class SiloProbeSleep extends SiloProbeAction {
  final Duration duration;

  const SiloProbeSleep(this.duration);
}

final class SiloProbeWrite extends SiloProbeAction {
  final String name;
  final String method;
  final String path;

  const SiloProbeWrite(this.name, this.method, this.path);
}

final class SiloProbeWatch extends SiloProbeAction {
  final String id;

  const SiloProbeWatch(this.id);
}

final class SiloProbeIds extends SiloProbeAction {
  final Uri uri;

  const SiloProbeIds(this.uri);
}

final class SiloProbeToggle extends SiloProbeAction {
  final String id;
  final int times;
  final Duration interval;

  const SiloProbeToggle(this.id, this.times, this.interval);
}

/// Null for an unknown command or a malformed argument.
SiloProbeAction? parseSiloProbeAction(String line) {
  final words = line.trim().split(RegExp(r'\s+'));
  if (words.first.isEmpty || words.first.startsWith('#')) return const SiloProbeSkip();
  String id(String word) => Uri.encodeComponent(word);
  return switch (words) {
    ['home'] => const SiloProbeHome(),
    ['watch', final c] => SiloProbeWatch(c),
    ['ids', final path] when path.startsWith('/api/v2/') => SiloProbeIds(Uri.parse(path)),
    ['sleep', final s] when double.tryParse(s) != null => SiloProbeSleep(
      Duration(milliseconds: (double.parse(s) * 1000).round()),
    ),
    ['watched', final c] => SiloProbeWrite('watched', 'POST', '/api/v2/watched/${id(c)}'),
    ['unwatched', final c] => SiloProbeWrite('unwatched', 'DELETE', '/api/v2/watched/${id(c)}'),
    ['watchlist-add', final c] => SiloProbeWrite('watchlist-add', 'PUT', '/api/v2/watchlist/${id(c)}'),
    ['watchlist-remove', final c] => SiloProbeWrite('watchlist-remove', 'DELETE', '/api/v2/watchlist/${id(c)}'),
    ['toggle', final c, final n, final s] when (int.tryParse(n) ?? 0) > 0 && double.tryParse(s) != null =>
      SiloProbeToggle(c, int.parse(n), Duration(milliseconds: (double.parse(s) * 1000).round())),
    _ => null,
  };
}

/// Prints ids, statuses and times only, never a title.
Future<void> _runAction(
  SiloHttp silo,
  SiloProbeAction action, {
  required StringSink out,
  required Future<void> Function(Duration) wait,
  required DateTime Function() clock,
}) async {
  Future<void> write(SiloProbeWrite write) async {
    final response = await silo.send(SiloRequest(write.method, write.path, single: true));
    out.writeln(
      'action ${write.name} ${Uri.decodeComponent(write.path.split('/').last)} ${response.statusCode} '
      'done_ms=${clock().millisecondsSinceEpoch}',
    );
  }

  switch (action) {
    case SiloProbeSkip():
      return;
    case SiloProbeSleep(:final duration):
      await wait(duration);
    case SiloProbeWrite():
      await write(action);
    case SiloProbeToggle(:final id, :final times, :final interval):
      for (var i = 0; i < times; i++) {
        if (i > 0) await wait(interval);
        await write(parseSiloProbeAction('${i.isEven ? 'watched' : 'unwatched'} $id')! as SiloProbeWrite);
      }
    case SiloProbeWatch(:final id):
      final watch = await silo.send(SiloRequest.get('/api/v2/watch/${Uri.encodeComponent(id)}'));
      final json = watch.isSuccess ? _tryJson(watch.body) : null;
      final userData = json is Map && json['user_data'] is Map ? json['user_data'] as Map : const {};
      final versions = json is Map && json['versions'] is List
          ? (json['versions'] as List).whereType<Map>()
          : const <Map>[];
      int count(Map version, String key) => version[key] is List ? (version[key] as List).length : 0;
      out.writeln(
        'action watch $id ${watch.statusCode} position=${userData['position_seconds']} played=${userData['played']} '
        'audio=${versions.map((v) => count(v, 'audio_tracks')).join(',')} '
        'subtitles=${versions.map((v) => count(v, 'subtitle_tracks')).join(',')}',
      );
    case SiloProbeIds(:final uri):
      final response = await silo.send(SiloRequest.get(uri.path, query: uri.hasQuery ? uri.queryParameters : null));
      out.writeln('action ids ${uri.path} ${response.statusCode}');
      void walk(Object? node) {
        if (node is List) node.forEach(walk);
        if (node is! Map) return;
        if (node['content_id'] is String) {
          out.writeln(
            'id ${node['content_id']} type=${node['type']} '
            'season=${node['season_number']} episode=${node['episode_number']}',
          );
        }
        node.values.forEach(walk);
      }

      walk(response.isSuccess ? _tryJson(response.body) : null);
    case SiloProbeHome():
      final home = await silo.send(const SiloRequest.get('/api/v2/home/sections'));
      final json = home.isSuccess ? _tryJson(home.body) : null;
      final sections = json is Map && json['sections'] is List ? json['sections'] as List : const [];
      out.writeln('action home ${home.statusCode} sections=${sections.length}');
      for (final section in sections.whereType<Map>()) {
        final items = section['items'] is List ? section['items'] as List : const [];
        final ids = [for (final item in items.whereType<Map>()) ?item['content_id']];
        out.writeln('section ${section['section_type']} ids=${ids.join(',')}');
      }
  }
}

int _median(List<int> values) => (values.toList()..sort())[values.length ~/ 2];

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

/// Replaces the session id and every digit run, and keeps query keys only,
/// so a URL can be printed without a credential or a signed value.
String siloUrlShape(String url, String sessionId) {
  final uri = Uri.parse(url.replaceAll(sessionId, 'SESSION'));
  final path = uri.path.replaceAll(RegExp(r'\d+'), 'N');
  final keys = uri.queryParameters.keys.toList()..sort();
  final origin = uri.hasScheme ? '${uri.scheme}://{host}' : '';
  return '$origin$path${keys.isEmpty ? '' : '?${keys.map((k) => '$k=…').join('&')}'}';
}

/// One real start, one stream fetch, one progress sample and one stop,
/// printed as structure only (`research/silo-playback.md` open questions).
Future<void> probeSiloPlayback(
  SiloHttp silo,
  SiloSessionController session,
  String contentId, {
  required String quality,
  required StringSink out,
  required Directory samples,
}) async {
  final caps = await silo.send(const SiloRequest.get('/api/v2/playback/capabilities'));
  final capsJson = caps.isSuccess ? _tryJson(caps.body) : null;
  final admission = siloAdmission(caps.statusCode, capsJson);
  if (capsJson is Map) {
    out.writeln(
      'playback_capabilities ${caps.statusCode} state=${capsJson['state']} allowed=${capsJson['allowed']} '
      'protocols=${capsJson['protocol_versions']} features=${capsJson['features']}',
    );
  } else {
    out.writeln('playback_capabilities ${caps.statusCode}');
  }
  await _writeSample(samples, 'playback-capabilities.json', 'GET /api/v2/playback/capabilities', caps);
  if (admission is! SiloAdmitted) {
    out.writeln('admission ${admission.runtimeType}');
    return;
  }

  final watch = await silo.send(SiloRequest.get('/api/v2/watch/${Uri.encodeComponent(contentId)}'));
  await _writeSample(samples, 'watch-detail.json', 'GET /api/v2/watch/{id}', watch);
  final detail = SiloWatchDetail.fromJson(_tryJson(watch.body), contentId);
  final version = selectSiloVersion(detail.versions, lastFileId: detail.lastFileId, preferredQuality: quality);
  final start = siloStartPosition(savedPosition: detail.positionSeconds);
  out.writeln(
    'watch ${watch.statusCode} versions=${detail.versions.length} file=${version.fileId} '
    'resolution=${version.resolution} container=${version.container} audio=${version.audioTracks.length} '
    'subtitles=${version.subtitleTracks.length} resume=${detail.positionSeconds != null} start=$start',
  );

  final profileId = session.session?.profileId;
  if (profileId == null) {
    out.writeln('play skipped, no profile');
    return;
  }
  final body = siloStartBody(
    fileId: version.fileId,
    profileId: profileId,
    attemptId: _uuid(),
    installationId: admission.installationId,
    capabilities: siloMpvCodecCapabilities(),
    context: siloMpvPlaybackContext((
      formFactor: 'tv',
      appVersion: 'probe',
      platform: 'linux',
      osVersion: null,
      manufacturer: 'Plezy',
      model: 'Silo Probe',
    )),
    qualityPreference: quality,
    startPosition: start,
  );
  final started = await silo.send(SiloRequest.post('/api/v2/playback/start', body: body, single: true));
  await _writeSample(samples, 'playback-start.json', 'POST /api/v2/playback/start', started);
  final startJson = _tryJson(started.body);
  final sessionId = startJson is Map ? startJson['session_id'] : null;
  out.writeln('start ${started.statusCode} session=${sessionId is String && sessionId.isNotEmpty}');
  if (started.statusCode != 201 || sessionId is! String || sessionId.isEmpty) {
    final problem = started.problem;
    out.writeln('start_problem ${problem?.code}');
    return;
  }

  try {
    final decision = parseSiloDecision(startJson);
    out.writeln('decision ${decision.runtimeType}');
    final SiloPlan? plan = switch (decision) {
      SiloPlayable(:final plan) => plan,
      SiloReplanRequired(:final plan, :final reason) => (() {
        out.writeln('replan_required $reason');
        return plan;
      })(),
      SiloTerminal(:final reason) => (() {
        out.writeln('terminal $reason');
        return null;
      })(),
      SiloIncompatible() => null,
    };
    if (plan != null) await _describePlan(silo, session, plan, sessionId, out);

    final progress = await silo.send(
      SiloRequest.post(
        '/api/v2/playback/${Uri.encodeComponent(sessionId)}/progress',
        body: {'installation_id': admission.installationId, 'sequence': 1, 'position': start ?? 0, 'is_paused': true},
      ),
    );
    final progressJson = _tryJson(progress.body);
    out.writeln(
      'progress ${progress.statusCode} outcome=${progressJson is Map ? progressJson['outcome'] : null} '
      'accepted_sequence=${progressJson is Map && progressJson['accepted'] is Map ? (progressJson['accepted'] as Map)['sequence'] : null}',
    );
  } finally {
    final stopId = _uuid();
    final stopped = await silo.send(
      SiloRequest(
        'DELETE',
        '/api/v2/playback/${Uri.encodeComponent(sessionId)}',
        body: {'installation_id': admission.installationId, 'stop_id': stopId},
        single: true,
      ),
    );
    final stopJson = _tryJson(stopped.body);
    out.writeln(
      'stop ${stopped.statusCode} outcome=${stopJson is Map ? stopJson['outcome'] : null} '
      'stop_id_echoed=${stopJson is Map && stopJson['stop_id'] == stopId}',
    );
  }
}

Future<void> _describePlan(
  SiloHttp silo,
  SiloSessionController session,
  SiloPlan plan,
  String sessionId,
  StringSink out,
) async {
  final t = plan.timeline;
  out.writeln(
    'plan delivery=${plan.delivery} protocol=${plan.stream.protocol} header_refresh=${plan.stream.headerRefresh} '
    'reason=${plan.decisionReason} effective_file=${plan.effectiveMediaFileId} duration=${plan.sourceDurationSeconds}',
  );
  out.writeln('plan_url ${siloUrlShape(plan.stream.url, sessionId)} headers=${plan.stream.headers.keys.toList()}');
  out.writeln(
    'plan_timeline source_start=${t.sourceStartSeconds} player_start=${t.playerStartSeconds} '
    'offset=${t.timelineOffsetSeconds} window=${t.seekWindowStartSeconds}..${t.seekWindowEndSeconds} '
    'seek_anywhere=${t.canSeekAnywhere}',
  );
  out.writeln(
    'plan_subtitles mode=${plan.subtitleMode} selected=${plan.selectedSubtitle != null} '
    'inventory=${[for (final r in plan.subtitleInventory) '${r.source}/${r.codec}/${r.delivery}']}',
  );
  for (final row in plan.subtitleInventory.take(2)) {
    final url = row.url;
    if (url != null) out.writeln('plan_subtitle_url ${siloUrlShape(url, sessionId)}');
  }

  final current = session.session;
  if (current == null) return;
  final url = silo.origin.resolve(plan.stream.url);
  final sameOrigin = isSameSiloOrigin(url, silo.origin);
  final client = HttpClient();
  try {
    Future<HttpClientResponse> fetch(Uri target, {bool range = false}) async {
      final request = await client.getUrl(target);
      request.followRedirects = false;
      if (isSameSiloOrigin(target, silo.origin)) {
        request.headers.set(SiloHeaders.authorization, 'Bearer ${current.tokens.accessToken}');
        if (current.profileId != null) request.headers.set(SiloHeaders.profileId, current.profileId!);
        if (current.profileToken != null) request.headers.set(SiloHeaders.profileToken, current.profileToken!);
        silo.device.toMap().forEach(request.headers.set);
      }
      plan.stream.headers.forEach(request.headers.set);
      if (range) request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-1');
      return request.close();
    }

    if (plan.stream.protocol == 'hls') {
      final master = await fetch(url);
      final text = master.statusCode == 200 ? await utf8.decodeStream(master) : '';
      if (master.statusCode != 200) await master.drain<void>();
      out.writeln('stream ${master.statusCode} same_origin=$sameOrigin type=${master.headers.contentType?.mimeType}');
      final uris = [
        for (final line in const LineSplitter().convert(text))
          if (line.isNotEmpty && !line.startsWith('#')) line,
      ];
      for (final line in uris.take(3)) {
        out.writeln('stream_child ${siloUrlShape(line, sessionId)}');
      }
      if (uris.isNotEmpty && uris.first.contains('.m3u8')) {
        final child = url.resolve(uris.first);
        final media = await fetch(child);
        final childText = media.statusCode == 200 ? await utf8.decodeStream(media) : '';
        if (media.statusCode != 200) await media.drain<void>();
        out.writeln(
          'stream_media ${media.statusCode} same_directory=${child.path.startsWith(url.path.substring(0, url.path.lastIndexOf('/') + 1))}',
        );
        final segments = [
          for (final line in const LineSplitter().convert(childText))
            if (line.isNotEmpty && !line.startsWith('#')) line,
        ];
        for (final line in segments.take(2)) {
          out.writeln('stream_segment ${siloUrlShape(line, sessionId)}');
        }
        out.writeln('stream_segments ${segments.length} endlist=${childText.contains('#EXT-X-ENDLIST')}');
      }
    } else {
      final response = await fetch(url, range: true);
      await response.drain<void>();
      out.writeln(
        'stream ${response.statusCode} same_origin=$sameOrigin accept_ranges=${response.headers.value('accept-ranges')} '
        'content_range=${response.headers.value('content-range') != null} etag=${response.headers.value('etag') != null} '
        'type=${response.headers.contentType?.mimeType}',
      );
    }
  } on Exception catch (error) {
    out.writeln('stream_error ${error.runtimeType}');
  } finally {
    client.close(force: true);
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = [for (var i = 0; i < 16; i++) random.nextInt(256)];
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
