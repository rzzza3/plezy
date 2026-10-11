import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/silo/silo_headers.dart';
import 'package:plezy/silo/silo_http.dart';
import 'package:plezy/silo/silo_session.dart';

final Uri siloTestOrigin = Uri.parse('https://silo.ruleone.xyz');

const SiloHeaders siloTestDevice = SiloHeaders(
  id: '11111111-2222-4333-8444-555555555555',
  name: 'Plezy Test',
  platform: 'android-tv',
  clientName: 'Plezy',
  family: 'tv',
);

class RecordedRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;

  RecordedRequest(this.method, this.url, this.headers, this.body);

  String? header(String name) => headers[name.toLowerCase()];
}

typedef FakeHandler = FutureOr<http.Response> Function(RecordedRequest request);

/// A MockClient that records every request with lowercased header names.
class FakeSilo {
  final List<RecordedRequest> requests = [];
  final FakeHandler handler;
  late final MockClient client = MockClient((request) async {
    final recorded = RecordedRequest(request.method, request.url, {
      for (final e in request.headers.entries) e.key.toLowerCase(): e.value,
    }, request.body);
    requests.add(recorded);
    return handler(recorded);
  });

  FakeSilo(this.handler);

  List<RecordedRequest> to(String path) => requests.where((r) => r.url.path == path).toList();
}

http.Response jsonResponse(Object body, int status, {Map<String, String> headers = const {}}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json', ...headers});

http.Response tokenPair(String access, String refresh, {int expiresIn = 3600}) =>
    jsonResponse({'access_token': access, 'refresh_token': refresh, 'expires_in': expiresIn}, 200);

Future<(SiloSessionController, MemorySiloSessionStore)> signedInSession({
  String access = 'access-A',
  String refresh = 'refresh-A',
  int expiresIn = 3600,
  DateTime Function()? now,
}) async {
  final store = MemorySiloSessionStore();
  final controller = await SiloSessionController.load(store, now: now);
  await controller.replaceAccountSession(
    origin: siloTestOrigin.toString(),
    accessToken: access,
    refreshToken: refresh,
    expiresInSeconds: expiresIn,
  );
  return (controller, store);
}

SiloHttp siloHttpFor(FakeSilo fake, SiloSessionController session) =>
    SiloHttp(origin: siloTestOrigin, session: session, device: siloTestDevice, client: fake.client);
