import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../utils/app_logger.dart';
import 'silo_headers.dart';
import 'silo_http.dart';
import 'silo_session.dart';

/// A loopback HTTP server between mpv and Silo. mpv only ever sees
/// `http://127.0.0.1:<port>/r/<route>/<upstream path>`, so signed query
/// values and credentials never reach the player or its logs.
///
/// Same-origin requests get the current bearer and profile headers, and the
/// plan's `stream.headers` only inside the stream's directory. A 401 is
/// refreshed once and replayed. Nothing is forwarded to another origin
/// (`A/player/AuthenticatedDataSourceFactory.kt:98-118,206-267`,
/// `A/player/SiloPlayerFactory.kt:549-573`).
class SiloMediaProxy {
  final HttpServer _server;
  final HttpClient _upstream;
  final Map<String, SiloMediaRoute> _routes = {};

  SiloMediaProxy._(this._server, this._upstream) {
    _server.listen(_serve, onError: (Object _) {});
  }

  static Future<SiloMediaProxy> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final upstream = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = false;
    return SiloMediaProxy._(server, upstream);
  }

  int get port => _server.port;

  /// A route for one plan. [stream] is the plan's absolute stream URL.
  SiloMediaRoute open({required SiloHttp http, required Uri stream, Map<String, String> planHeaders = const {}}) {
    final random = Random.secure();
    final id = [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    final directory = stream.path.substring(0, stream.path.lastIndexOf('/') + 1);
    final route = SiloMediaRoute._(this, id, http, directory, planHeaders);
    _routes[id] = route;
    return route;
  }

  Future<void> close() async {
    _routes.clear();
    await _server.close(force: true);
    _upstream.close(force: true);
  }

  static const _forwardedRequestHeaders = ['range', 'if-range', 'accept'];
  static const _forwardedResponseHeaders = [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'etag',
    'last-modified',
  ];

  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      final route = segments.length >= 2 && segments.first == 'r' ? _routes[segments[1]] : null;
      if (route == null) {
        response.statusCode = HttpStatus.notFound;
        return;
      }
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      final path = '/${segments.skip(2).map(Uri.encodeComponent).join('/')}';
      final query = route._queries[path];
      final target = route.http.origin.replace(path: path, query: query?.isEmpty ?? true ? null : query);
      await _forward(request, route, target);
    } on Exception catch (error) {
      appLogger.i('Silo proxy: upstream failed (${error.runtimeType})');
      try {
        response.statusCode = HttpStatus.badGateway;
      } on StateError {
        // Headers already went out; closing ends the body early.
      }
    } finally {
      await response.close().catchError((Object _) {});
    }
  }

  Future<HttpClientResponse> _send(HttpRequest request, SiloMediaRoute route, Uri target, SiloSession? auth) async {
    final upstream = await _upstream.openUrl(request.method, target);
    upstream.followRedirects = false;
    for (final name in _forwardedRequestHeaders) {
      final value = request.headers.value(name);
      if (value != null) upstream.headers.set(name, value);
    }
    if (auth != null) {
      upstream.headers.set(SiloHeaders.authorization, 'Bearer ${auth.tokens.accessToken}');
      if (auth.profileId case final id?) upstream.headers.set(SiloHeaders.profileId, id);
      if (auth.profileToken case final token?) upstream.headers.set(SiloHeaders.profileToken, token);
    }
    if (target.path.startsWith(route._directory)) route._planHeaders.forEach(upstream.headers.set);
    return upstream.close();
  }

  Future<void> _forward(HttpRequest request, SiloMediaRoute route, Uri target) async {
    final http = route.http;
    final generation = http.session.generation;
    final session = http.session.session;
    final auth = session != null && isSameSiloOrigin(Uri.parse(session.origin), http.origin) ? session : null;
    var upstream = await _send(request, route, target, auth);
    if (upstream.statusCode == HttpStatus.unauthorized && auth != null) {
      await upstream.drain<void>();
      final outcome = await http.refresh(sentAccessToken: auth.tokens.accessToken, generation: generation);
      if (outcome is SiloRefreshed && http.session.generation == generation) {
        upstream = await _send(request, route, target, outcome.session);
      } else {
        upstream = await _send(request, route, target, null);
      }
    }

    // Closed by [_serve], which owns the response for every path.
    // ignore: close_sinks
    final response = request.response;
    response.statusCode = upstream.statusCode;
    if (upstream.isRedirect) {
      final location = upstream.headers.value(HttpHeaders.locationHeader);
      await upstream.drain<void>();
      if (location != null) {
        response.headers.set(HttpHeaders.locationHeader, '${route.playerUrl(target.resolve(location))}');
      }
      return;
    }
    final type = upstream.headers.contentType?.mimeType ?? '';
    final isPlaylist =
        upstream.statusCode == HttpStatus.ok && (type.contains('mpegurl') || target.path.endsWith('.m3u8'));
    if (isPlaylist) {
      final text = await utf8.decodeStream(upstream);
      final rewritten = utf8.encode(route._rewritePlaylist(text, target));
      response.headers.contentType = ContentType.parse(type.isEmpty ? 'application/vnd.apple.mpegurl' : type);
      response.headers.contentLength = rewritten.length;
      if (request.method == 'GET') response.add(rewritten);
      return;
    }
    for (final name in _forwardedResponseHeaders) {
      final value = upstream.headers.value(name);
      if (value != null) response.headers.set(name, value);
    }
    await response.addStream(upstream);
  }
}

class SiloMediaRoute {
  final SiloMediaProxy _proxy;
  final String _id;
  final SiloHttp http;
  final String _directory;
  final Map<String, String> _planHeaders;

  /// Upstream path to its query, kept here so signed values stay out of mpv.
  final Map<String, String> _queries = {};

  SiloMediaRoute._(this._proxy, this._id, this.http, this._directory, this._planHeaders);

  /// The URL mpv opens for [upstream]. Another origin is returned unchanged,
  /// so mpv fetches it directly with no Silo credential.
  Uri playerUrl(Uri upstream) {
    if (!isSameSiloOrigin(upstream, http.origin)) return upstream;
    if (upstream.query.isNotEmpty) _queries[upstream.path] = upstream.query;
    return Uri(scheme: 'http', host: '127.0.0.1', port: _proxy.port, path: '/r/$_id${upstream.path}');
  }

  void close() => _proxy._routes.remove(_id);

  static final RegExp _define = RegExp(r'^#EXT-X-DEFINE:(.*)$');
  static final RegExp _attribute = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
  static final RegExp _uriAttribute = RegExp(r'URI="([^"]*)"');
  static final RegExp _variable = RegExp(r'\{\$([A-Za-z0-9_-]+)\}');

  /// Substitutes `EXT-X-DEFINE` variables (NAME/VALUE and QUERYPARAM, RFC
  /// 8216bis 4.4.2.3), drops the DEFINE lines, and points every same-origin
  /// URI at this route.
  String _rewritePlaylist(String text, Uri playlist) {
    final variables = <String, String>{};
    final lines = const LineSplitter().convert(text);
    final out = <String>[];
    String substitute(String value) => value.replaceAllMapped(_variable, (m) => variables[m.group(1)!] ?? m.group(0)!);
    String point(String uri) => '${playerUrl(playlist.resolve(substitute(uri)))}';
    for (final line in lines) {
      final define = _define.firstMatch(line);
      if (define != null) {
        final attrs = {
          for (final m in _attribute.allMatches(define.group(1)!)) m.group(1)!: m.group(2)!.replaceAll('"', ''),
        };
        final name = attrs['NAME'];
        final param = attrs['QUERYPARAM'];
        if (name != null && attrs['VALUE'] != null) variables[name] = attrs['VALUE']!;
        final fromQuery = param == null ? null : playlist.queryParameters[param];
        if (fromQuery != null) variables[param!] = fromQuery;
        continue;
      }
      if (line.isEmpty) {
        out.add(line);
      } else if (line.startsWith('#')) {
        out.add(line.replaceAllMapped(_uriAttribute, (m) => 'URI="${point(m.group(1)!)}"'));
      } else {
        out.add(point(line.trim()));
      }
    }
    return '${out.join('\n')}\n';
  }
}

/// A `/stream/v3/{session}/subtitles/...` sidecar, fetched once with the
/// `Authorization` and `X-Profile-Id` captured from the start request: no
/// refresh, no retry, no redirect (`S/network/apiv2/ProxyAuxiliaryV2.kt:16-56`).
Future<List<int>?> fetchSiloProxySubtitle(Uri url, Map<String, String> captured, {HttpClient? client}) async {
  final http = client ?? HttpClient();
  try {
    final request = await http.getUrl(url);
    request.followRedirects = false;
    captured.forEach(request.headers.set);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
    }
    return bytes;
  } finally {
    if (client == null) http.close(force: true);
  }
}

/// Whether [url] names a session proxy subtitle (`S/network/apiv2/ProxyAuxiliaryV2.kt:6-14`).
bool isSiloProxySubtitle(Uri url) => url.path.startsWith('/stream/v3/') && url.path.contains('/subtitles/');

final RegExp _proxySubtitlePath = RegExp(
  r'^/stream/v3/([A-Za-z0-9_-]+)/subtitles/(0|[1-9][0-9]*)\.(ass|ssa|srt|vtt|sup)$',
);
final RegExp _proxySessionPath = RegExp(r'^/stream/v3/([A-Za-z0-9_-]+)(?:/.*)?$');
const Set<String> _auxiliaryQueryKeys = {
  'file_id',
  'embedded_stream_index',
  'external_subtitle_key',
  'downloaded_subtitle_id',
  'windowed',
  'position',
  'duration',
};

/// A proxy subtitle must sit on the stream's origin under this session, with
/// only the auxiliary pins and a positive `file_id`
/// (`S/network/apiv2/ProxyAuxiliaryV2.kt:28-44`).
bool validSiloProxySubtitle(Uri url, {required Uri stream, required String sessionId}) {
  if ((url.scheme != 'https' && url.scheme != 'http') || url.userInfo.isNotEmpty || url.hasFragment) return false;
  if (!isSameSiloOrigin(url, stream)) return false;
  final subtitle = _proxySubtitlePath.firstMatch(url.path);
  if (subtitle == null || subtitle.group(1) != sessionId) return false;
  if (stream.path.startsWith('/stream/v3/') && _proxySessionPath.firstMatch(stream.path)?.group(1) != sessionId) {
    return false;
  }
  if (!url.queryParametersAll.keys.every(_auxiliaryQueryKeys.contains)) return false;
  final files = url.queryParametersAll['file_id'] ?? const [];
  bool positive(String id) => (int.tryParse(id) ?? 0) > 0 && '${int.parse(id)}' == id;
  return files.isNotEmpty && files.every(positive);
}

/// Fetches each valid session proxy subtitle in [urls] into [directory] with
/// the [captured] start headers, and returns plan URL to local file. A row
/// that is invalid or does not answer 200 is left out, never retried.
Future<Map<String, File>> fetchSiloProxySubtitles(
  Iterable<String> urls, {
  required Uri origin,
  required Uri stream,
  required String sessionId,
  required Map<String, String> captured,
  required Directory directory,
  HttpClient? client,
}) async {
  final files = <String, File>{};
  for (final (index, planUrl) in urls.indexed) {
    final url = origin.resolve(planUrl);
    if (!validSiloProxySubtitle(url, stream: stream, sessionId: sessionId)) continue;
    final List<int>? bytes;
    try {
      bytes = await fetchSiloProxySubtitle(url, captured, client: client);
    } on Exception catch (error) {
      appLogger.i('Silo playback: proxy subtitle fetch failed (${error.runtimeType})');
      continue;
    }
    if (bytes == null) continue;
    final extension = _proxySubtitlePath.firstMatch(url.path)!.group(3);
    await directory.create(recursive: true);
    files[planUrl] = await File('${directory.path}/silo-subtitle-$index.$extension').writeAsBytes(bytes, flush: true);
  }
  return files;
}
