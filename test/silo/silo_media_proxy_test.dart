import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_media_proxy.dart';
import 'package:plezy/silo/silo_session.dart';

import 'fake_silo.dart';

typedef _Seen = ({String path, String? query, String? authorization, String? profile, String? plan, String? range});

/// A loopback origin that answers like the live server: a signed `st` query
/// authenticates, and the HLS playlist names segments through EXT-X-DEFINE.
class _Origin {
  late final HttpServer server;
  final List<_Seen> seen = [];
  String token = 'access-A';
  String otherOrigin = '';

  Uri get origin => Uri.parse('http://127.0.0.1:${server.port}');

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    seen.add((
      path: path,
      query: request.uri.query.isEmpty ? null : request.uri.query,
      authorization: request.headers.value('authorization'),
      profile: request.headers.value('x-profile-id'),
      plan: request.headers.value('x-plan'),
      range: request.headers.value('range'),
    ));
    final response = request.response;
    final signed = request.uri.queryParameters['st'] == 'sig-secret';
    if (request.headers.value('authorization') != 'Bearer $token') {
      response.statusCode = 401;
    } else if (path == '/api/v2/stream/S1' && signed) {
      response.statusCode = 206;
      response.headers.set('content-range', 'bytes 0-3/10');
      response.headers.set('accept-ranges', 'bytes');
      response.headers.set('etag', '"e1"');
      response.add([1, 2, 3, 4]);
    } else if (path == '/api/v2/playback/transcode/S1/master.m3u8' && signed) {
      response.headers.contentType = ContentType.parse('application/vnd.apple.mpegurl');
      response.write(
        '#EXTM3U\n'
        '#EXT-X-VERSION:11\n'
        '#EXT-X-DEFINE:NAME="silo_query",VALUE="st=sig-secret"\n'
        '#EXT-X-MAP:URI="init.mp4?{\$silo_query}"\n'
        '#EXTINF:6,\n'
        'segment/seg_0.m4s?{\$silo_query}\n'
        '#EXTINF:6,\n'
        '$otherOrigin/seg_1.m4s\n'
        '#EXT-X-ENDLIST\n',
      );
    } else if ((path.endsWith('/seg_0.m4s') || path.endsWith('/init.mp4')) && signed) {
      response.add([9, 9]);
    } else if (path == '/api/v2/stream/S1/subtitles/0.vtt') {
      response.write('WEBVTT\n');
    } else if (path == '/api/v2/redirect') {
      response.statusCode = 302;
      response.headers.set('location', '$otherOrigin/elsewhere');
    } else {
      response.statusCode = 404;
    }
    await response.close();
  }
}

class _Other {
  late final HttpServer server;
  final List<String?> authorizations = [];

  Future<void> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      authorizations.add(request.headers.value('authorization'));
      request.response.add([7]);
      await request.response.close();
    });
  }

  String get origin => 'http://127.0.0.1:${server.port}';
}

Future<({int status, List<int> body, HttpHeaders headers})> _get(Uri url, {String? range}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(url);
    if (range != null) request.headers.set('range', range);
    final response = await request.close();
    final body = <int>[];
    await for (final chunk in response) {
      body.addAll(chunk);
    }
    return (status: response.statusCode, body: body, headers: response.headers);
  } finally {
    client.close(force: true);
  }
}

void main() {
  late _Origin origin;
  late _Other other;
  late SiloMediaProxy proxy;
  late SiloHttp http;
  late FakeSilo refresher;

  setUp(() async {
    origin = _Origin();
    other = _Other();
    await origin.start();
    await other.start();
    origin.otherOrigin = other.origin;
    proxy = await SiloMediaProxy.start();
    final session = await SiloSessionController.load(MemorySiloSessionStore());
    await session.replaceAccountSession(
      origin: origin.origin.toString(),
      accessToken: 'access-A',
      refreshToken: 'refresh-A',
      expiresInSeconds: 3600,
    );
    await session.selectProfile('p-1', 'profile-token');
    refresher = FakeSilo(
      (r) => r.url.path == '/api/v2/auth/refresh' ? tokenPair('access-B', 'refresh-B') : jsonResponse({}, 404),
    );
    http = SiloHttp(origin: origin.origin, session: session, device: siloTestDevice, client: refresher.client);
  });

  tearDown(() async {
    await proxy.close();
    await origin.server.close(force: true);
    await other.server.close(force: true);
  });

  test(
    'a direct stream plays through the proxy with credentials and its signed query (AuthenticatedDataSourceFactory.kt:206-251)',
    () async {
      final route = proxy.open(http: http, stream: origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));
      final playerUrl = route.playerUrl(origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));

      final got = await _get(playerUrl, range: 'bytes=0-3');

      expect('$playerUrl', isNot(contains('sig-secret')), reason: 'mpv never sees the signed value');
      expect(playerUrl.host, '127.0.0.1');
      expect(got.status, 206);
      expect(got.body, [1, 2, 3, 4]);
      expect(got.headers.value('content-range'), 'bytes 0-3/10');
      expect(got.headers.value('etag'), '"e1"');
      final upstream = origin.seen.single;
      expect(upstream.query, 'st=sig-secret');
      expect(upstream.authorization, 'Bearer access-A');
      expect(upstream.profile, 'p-1');
      expect(upstream.range, 'bytes=0-3');
    },
  );

  test('an HLS playlist is rewritten: variables substituted, DEFINE dropped, same-origin URIs proxied', () async {
    final master = origin.origin.resolve('/api/v2/playback/transcode/S1/master.m3u8?st=sig-secret');
    final route = proxy.open(http: http, stream: master);

    final playlist = utf8.decode((await _get(route.playerUrl(master))).body);

    expect(playlist, isNot(contains('sig-secret')));
    expect(playlist, isNot(contains('EXT-X-DEFINE')));
    expect(playlist, isNot(contains(r'{$silo_query}')));
    final lines = const LineSplitter().convert(playlist);
    final segment = Uri.parse(lines.firstWhere((l) => l.endsWith('seg_0.m4s')));
    final init = RegExp(r'URI="([^"]+)"').firstMatch(lines.firstWhere((l) => l.startsWith('#EXT-X-MAP')))!.group(1)!;
    expect(segment.host, '127.0.0.1');
    expect(lines, contains('${other.origin}/seg_1.m4s'), reason: 'another origin is left for mpv to fetch itself');

    expect((await _get(segment)).body, [9, 9]);
    expect((await _get(Uri.parse(init))).body, [9, 9]);
    final segmentRequest = origin.seen.firstWhere((s) => s.path.endsWith('/seg_0.m4s'));
    expect(segmentRequest.query, 'st=sig-secret');
    expect(segmentRequest.path, '/api/v2/playback/transcode/S1/segment/seg_0.m4s');
  });

  test(
    'a segment on another origin is fetched without credentials (AuthenticatedDataSourceFactory.kt:262-267)',
    () async {
      final master = origin.origin.resolve('/api/v2/playback/transcode/S1/master.m3u8?st=sig-secret');
      final route = proxy.open(http: http, stream: master);
      final playlist = utf8.decode((await _get(route.playerUrl(master))).body);
      final foreign = Uri.parse(const LineSplitter().convert(playlist).firstWhere((l) => l.startsWith(other.origin)));

      await _get(foreign);

      expect(other.authorizations, [null]);
    },
  );

  test('a redirect to another origin is handed back without credentials (PlayerOkHttpClient.kt:40-49)', () async {
    final route = proxy.open(http: http, stream: origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));

    final got = await _get(route.playerUrl(origin.origin.resolve('/api/v2/redirect')));

    expect(got.body, [7], reason: 'the client followed the Location itself');
    expect(other.authorizations, [null]);
  });

  test('a 401 refreshes once and replays (MediaAuthSession.kt:103-158)', () async {
    origin.token = 'access-B';
    final route = proxy.open(http: http, stream: origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));

    final got = await _get(route.playerUrl(origin.origin.resolve('/api/v2/stream/S1?st=sig-secret')));

    expect(got.status, 206);
    expect(origin.seen.map((s) => s.authorization), ['Bearer access-A', 'Bearer access-B']);
    expect(refresher.to('/api/v2/auth/refresh'), hasLength(1));
  });

  test(
    'plan headers go only to the stream directory, credentials to the whole origin (SiloPlayerFactory.kt:549-573)',
    () async {
      final master = origin.origin.resolve('/api/v2/playback/transcode/S1/master.m3u8?st=sig-secret');
      final route = proxy.open(http: http, stream: master, planHeaders: {'X-Plan': 'plan-value'});

      await _get(route.playerUrl(master));
      await _get(route.playerUrl(origin.origin.resolve('/api/v2/stream/S1/subtitles/0.vtt')));

      final inside = origin.seen.firstWhere((s) => s.path.endsWith('master.m3u8'));
      final outside = origin.seen.firstWhere((s) => s.path.endsWith('0.vtt'));
      expect(inside.plan, 'plan-value');
      expect(outside.plan, isNull);
      expect(outside.authorization, 'Bearer access-A');
    },
  );

  test('an unknown route is 404, a closed route is gone, and only GET and HEAD pass', () async {
    final route = proxy.open(http: http, stream: origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));
    final url = route.playerUrl(origin.origin.resolve('/api/v2/stream/S1?st=sig-secret'));
    final client = HttpClient();
    addTearDown(() => client.close(force: true));

    final post = await (await client.postUrl(url)).close();
    await post.drain<void>();
    expect(post.statusCode, 405);
    route.close();
    expect((await _get(url)).status, 404);
    expect((await _get(Uri.parse('http://127.0.0.1:${proxy.port}/r/nope/x'))).status, 404);
    expect(origin.seen, isEmpty);
  });

  group('proxy subtitles (ProxyAuxiliaryV2.kt:16-56)', () {
    test('are fetched once with the captured headers', () async {
      final bytes = await fetchSiloProxySubtitle(origin.origin.resolve('/api/v2/stream/S1/subtitles/0.vtt'), {
        'Authorization': 'Bearer access-A',
        'X-Profile-Id': 'p-1',
      });

      expect(utf8.decode(bytes!), 'WEBVTT\n');
      expect(origin.seen.single.authorization, 'Bearer access-A');
    });

    test('a 401 is not refreshed or retried, and a redirect is not followed', () async {
      final refused = await fetchSiloProxySubtitle(origin.origin.resolve('/api/v2/stream/S1/subtitles/0.vtt'), {
        'Authorization': 'Bearer stale',
      });
      final moved = await fetchSiloProxySubtitle(origin.origin.resolve('/api/v2/redirect'), {
        'Authorization': 'Bearer access-A',
      });

      expect(refused, isNull);
      expect(moved, isNull);
      expect(origin.seen, hasLength(2));
      expect(other.authorizations, isEmpty);
      expect(refresher.to('/api/v2/auth/refresh'), isEmpty);
    });

    test('are recognised by the /stream/v3/ path only', () {
      expect(isSiloProxySubtitle(Uri.parse('https://h/stream/v3/S1/subtitles/0.srt')), isTrue);
      expect(isSiloProxySubtitle(Uri.parse('https://h/api/v2/stream/S1/subtitles/0.vtt')), isFalse);
    });
  });
}
