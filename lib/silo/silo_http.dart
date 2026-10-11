import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../utils/abortable_http_request.dart';
import '../utils/serial_future_queue.dart';
import 'silo_artwork.dart';
import 'silo_contract_gate.dart';
import 'silo_headers.dart';
import 'silo_problem.dart';
import 'silo_session.dart';

const Duration siloConnectTimeout = Duration(seconds: 10);
const Duration siloRequestTimeout = Duration(seconds: 60);
const Duration siloProactiveRefreshMargin = Duration(seconds: 60);
const int _maxRedirects = 20;

enum SiloAuth {
  /// No `Authorization` and no profile headers. Device headers still go to
  /// the trusted origin.
  none,

  /// `Authorization` and profile headers from the active session.
  bearer,
}

class SiloRequest {
  final String method;
  final String path;
  final Map<String, String>? query;
  final Object? body;
  final SiloAuth auth;

  /// Never refreshed proactively and never retried after a 401, because the
  /// call is not safe to replay.
  final bool single;

  /// Subject to the contract gate. Only the contract probe itself opts out.
  final bool gated;

  final Duration timeout;

  const SiloRequest(
    this.method,
    this.path, {
    this.query,
    this.body,
    this.auth = SiloAuth.bearer,
    this.single = false,
    this.gated = true,
    this.timeout = siloRequestTimeout,
  });

  const SiloRequest.get(String path, {Map<String, String>? query, SiloAuth auth = SiloAuth.bearer, bool gated = true})
    : this('GET', path, query: query, auth: auth, gated: gated);

  const SiloRequest.post(String path, {Object? body, SiloAuth auth = SiloAuth.bearer, bool single = false})
    : this('POST', path, body: body, auth: auth, single: single);
}

class SiloResponse {
  final int statusCode;

  /// The URL that produced this response, after redirects. Artwork resolves
  /// against its origin.
  final Uri url;
  final Map<String, String> headers;
  final String body;

  const SiloResponse({required this.statusCode, required this.url, required this.headers, required this.body});

  bool get isSuccess => statusCode >= 200 && statusCode < 300;

  Object? json() => resolveSiloArtworkUrls(jsonDecode(body), url);

  SiloProblem? get problem => SiloProblem.tryParse(body);
}

/// One wire exchange, for request logs. Carries header names only, never
/// values, so a log can never leak a credential.
class SiloExchange {
  final String method;
  final Uri url;
  final List<String> headerNames;
  final int? statusCode;
  final Duration elapsed;

  const SiloExchange({
    required this.method,
    required this.url,
    required this.headerNames,
    required this.statusCode,
    required this.elapsed,
  });
}

/// The proactive refresh was rejected, or the session vanished while the
/// request waited for it. The request was not sent.
class SiloCredentialsRepudiatedException implements Exception {
  const SiloCredentialsRepudiatedException();

  @override
  String toString() => 'SiloCredentialsRepudiatedException';
}

String siloOrigin(Uri url) {
  final scheme = url.scheme.toLowerCase();
  final host = url.host.toLowerCase();
  final bracketed = host.contains(':') ? '[$host]' : host;
  final defaultPort = scheme == 'https' ? 443 : 80;
  return url.port == defaultPort ? '$scheme://$bracketed' : '$scheme://$bracketed:${url.port}';
}

bool isSameSiloOrigin(Uri a, Uri b) {
  const schemes = {'http', 'https'};
  if (!schemes.contains(a.scheme.toLowerCase()) || !schemes.contains(b.scheme.toLowerCase())) return false;
  if (a.userInfo.isNotEmpty || b.userInfo.isNotEmpty) return false;
  return siloOrigin(a) == siloOrigin(b);
}

class SiloHttp {
  final Uri origin;
  final SiloSessionController session;
  final SiloHeaders device;
  final SiloContractGate gate;
  final http.Client _client;
  final void Function(SiloExchange exchange)? onExchange;
  final SerialFutureQueue _refreshLock = SerialFutureQueue();

  SiloHttp({
    required Uri origin,
    required this.session,
    required this.device,
    SiloContractGate? gate,
    http.Client? client,
    this.onExchange,
  }) : origin = Uri.parse(siloOrigin(origin)),
       gate = gate ?? SiloContractGate(),
       _client = client ?? newSiloHttpClient();

  static http.Client newSiloHttpClient() => IOClient(HttpClient()..connectionTimeout = siloConnectTimeout);

  void close() => _client.close();

  Future<SiloResponse> send(SiloRequest request) async {
    if (request.gated) gate.check();
    final url = _resolve(request);
    final generation = session.generation;
    final current = session.session;
    final hasBearer =
        request.auth == SiloAuth.bearer && current != null && isSameSiloOrigin(Uri.parse(current.origin), origin);
    if (!hasBearer) return _exchange(request, url, null);

    var active = current;
    final sentAccess = current.tokens.accessToken;
    final replayable = !request.single && !_isAuthPath(url);
    var proactiveFailedTransiently = false;
    if (replayable &&
        shouldRefreshProactively(
          remaining: current.tokens.expiresAt.difference(session.now()),
          lifetime: current.tokens.lifetime,
          margin: siloProactiveRefreshMargin,
        )) {
      final outcome = await refresh(sentAccessToken: sentAccess, generation: generation);
      switch (outcome) {
        case SiloRefreshed(:final session):
          active = session;
        case SiloRefreshRejected():
          throw const SiloCredentialsRepudiatedException();
        case SiloRefreshTransient():
          proactiveFailedTransiently = true;
          active = _installedOrThrow(generation);
        case SiloRefreshNotAttempted():
          active = _installedOrThrow(generation);
      }
    }

    final response = await _exchange(request, url, active);
    if (response.statusCode != HttpStatus.unauthorized || !replayable) return response;
    if (!isSameSiloOrigin(response.url, origin) || session.generation != generation) return response;

    final outcome = await refresh(
      sentAccessToken: active.tokens.accessToken,
      generation: generation,
      allowNetwork: !proactiveFailedTransiently,
    );
    if (outcome is! SiloRefreshed || session.generation != generation) return response;
    return _exchange(request, url, outcome.session);
  }

  /// One refresh at a time. Inside the lock, a token that differs from the
  /// one the caller sent means another caller already rotated it, so this one
  /// reuses it without a network call: refresh tokens rotate, and two
  /// parallel refreshes would void each other.
  Future<SiloRefreshOutcome> refresh({
    required String sentAccessToken,
    required int generation,
    bool allowNetwork = true,
  }) => _refreshLock.run(() async {
    final before = session.session;
    if (before == null || session.generation != generation) return const SiloRefreshNotAttempted();
    if (before.tokens.accessToken != sentAccessToken) return SiloRefreshed(before, usedNetwork: false);
    if (before.tokens.refreshToken.isEmpty) return const SiloRefreshNotAttempted();
    if (!allowNetwork) return const SiloRefreshTransient();

    final SiloResponse response;
    try {
      response = await _send(
        'POST',
        origin.resolve('/api/v2/auth/refresh'),
        {'Content-Type': 'application/json'},
        jsonEncode({'refresh_token': before.tokens.refreshToken}),
        siloRequestTimeout,
      );
    } on Exception {
      return const SiloRefreshTransient();
    }

    // A logout or identity switch that landed during the round trip owns the
    // session now; saving these tokens would sign the user back in.
    final after = session.session;
    if (after == null || session.generation != generation || after.tokens.refreshToken.isEmpty) {
      return const SiloRefreshNotAttempted();
    }

    final status = response.statusCode;
    if (status == HttpStatus.ok) {
      final tokens = _decodeTokenPair(response.body);
      if (tokens == null) return SiloRefreshTransient(status: status);
      final saved = await session.saveRefreshedTokens(
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        expiresInSeconds: tokens.expiresIn,
      );
      return saved == null ? const SiloRefreshNotAttempted() : SiloRefreshed(saved, usedNetwork: true);
    }
    if (status == 400 || status == 401 || status == 403) {
      await session.invalidate();
      return SiloRefreshRejected(status);
    }
    return SiloRefreshTransient(
      status: status,
      providerUnavailable: status == 503 && response.problem?.code == 'provider_unavailable',
    );
  });

  SiloSession _installedOrThrow(int generation) {
    final installed = session.session;
    if (installed == null || session.generation != generation) throw const SiloCredentialsRepudiatedException();
    return installed;
  }

  Uri _resolve(SiloRequest request) {
    final url = origin.resolve(request.path);
    return request.query == null ? url : url.replace(queryParameters: request.query);
  }

  Future<SiloResponse> _exchange(SiloRequest request, Uri url, SiloSession? credentials) {
    final body = request.body == null ? null : jsonEncode(_withoutNulls(request.body));
    return _send(request.method, url, _headersFor(credentials), body, request.timeout);
  }

  Map<String, String> _headersFor(SiloSession? credentials) => {
    'Content-Type': 'application/json',
    if (credentials != null) ...{
      SiloHeaders.authorization: 'Bearer ${credentials.tokens.accessToken}',
      SiloHeaders.profileId: ?credentials.profileId,
      SiloHeaders.profileToken: ?credentials.profileToken,
    },
    ...device.toMap(),
  };

  /// Follows redirects by hand so every hop is checked against the trusted
  /// origin: a hop to any other origin loses every credential and device
  /// header, and they never come back on later hops.
  Future<SiloResponse> _send(
    String method,
    Uri url,
    Map<String, String> headers,
    String? body,
    Duration timeout,
  ) async {
    var hopMethod = method;
    var hopUrl = url;
    var hopBody = body;
    var trusted = isSameSiloOrigin(url, origin);
    for (var hop = 0; ; hop++) {
      final hopHeaders = trusted
          ? headers
          : {
              for (final entry in headers.entries)
                if (!SiloHeaders.isCredentialHeader(entry.key)) entry.key: entry.value,
            };
      final started = DateTime.now();
      http.Response? response;
      try {
        response = await sendAbortableHttpRequest(
          _client,
          hopMethod,
          hopUrl,
          headers: hopHeaders,
          body: hopBody,
          timeout: timeout,
          followRedirects: false,
        );
      } finally {
        onExchange?.call(
          SiloExchange(
            method: hopMethod,
            url: hopUrl,
            headerNames: hopHeaders.keys.toList(growable: false),
            statusCode: response?.statusCode,
            elapsed: DateTime.now().difference(started),
          ),
        );
      }
      final location = response.headers['location'];
      if (!_isRedirect(response.statusCode) || location == null) {
        return SiloResponse(
          statusCode: response.statusCode,
          url: hopUrl,
          headers: response.headers,
          body: response.body,
        );
      }
      if (hop >= _maxRedirects) throw http.ClientException('Too many redirects', url);
      hopUrl = hopUrl.resolve(location);
      trusted = trusted && isSameSiloOrigin(hopUrl, origin);
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) && hopMethod == 'POST')) {
        hopMethod = 'GET';
        hopBody = null;
      }
    }
  }
}

bool _isRedirect(int status) => status == 301 || status == 302 || status == 303 || status == 307 || status == 308;

bool _isAuthPath(Uri url) => url.path.endsWith('/auth/refresh') || url.path.endsWith('/auth/login');

({String access, String refresh, int expiresIn})? _decodeTokenPair(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final access = json['access_token'];
    final refresh = json['refresh_token'];
    final expiresIn = json['expires_in'];
    if (access is! String || refresh is! String || expiresIn is! int) return null;
    return (access: access, refresh: refresh, expiresIn: expiresIn);
  } on FormatException {
    return null;
  }
}

Object? _withoutNulls(Object? value) {
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.value != null) entry.key: _withoutNulls(entry.value),
    };
  }
  if (value is List) return [for (final item in value) _withoutNulls(item)];
  return value;
}
