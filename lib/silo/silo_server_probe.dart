import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'silo_headers.dart';
import 'silo_http.dart';
import 'silo_session.dart';

/// The candidate origins for what the person typed, per
/// `TvServerSetupViewModel.kt:324-337`: an explicit scheme is the only
/// candidate, otherwise `https://` then `http://`.
List<Uri> siloAddressCandidates(String input) {
  var text = input.trim();
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty || text.contains(RegExp(r'\s'))) return const [];
  final lower = text.toLowerCase();
  final raw = lower.startsWith('http://') || lower.startsWith('https://') ? [text] : ['https://$text', 'http://$text'];
  return [
    for (final candidate in raw)
      if (Uri.tryParse(candidate) case final uri?
          when uri.host.isNotEmpty && uri.userInfo.isEmpty && (uri.scheme == 'http' || uri.scheme == 'https'))
        Uri.parse(siloOrigin(uri)),
  ];
}

sealed class SiloServerProbeResult {
  const SiloServerProbeResult();
}

final class SiloServerFound extends SiloServerProbeResult {
  final Uri origin;
  final bool needsSetup;
  final bool signupEnabled;

  const SiloServerFound(this.origin, {required this.needsSetup, required this.signupEnabled});
}

final class SiloServerInvalidAddress extends SiloServerProbeResult {
  const SiloServerInvalidAddress();
}

final class SiloServerNeedsUpdate extends SiloServerProbeResult {
  const SiloServerNeedsUpdate();
}

final class SiloServerUnreachable extends SiloServerProbeResult {
  const SiloServerUnreachable();
}

/// Tries each candidate in order, per `TvServerSetupViewModel.kt:249-312`:
/// `system/info` (3 s, only an update verdict stops), `system/setup` (an
/// error moves on), then `auth/signup` (any failure means false).
Future<SiloServerProbeResult> probeSiloServer(
  String input, {
  required SiloHeaders device,
  http.Client? client,
  Duration infoBound = const Duration(seconds: 3),
}) async {
  final candidates = siloAddressCandidates(input);
  if (candidates.isEmpty) return const SiloServerInvalidAddress();
  final session = await SiloSessionController.load(MemorySiloSessionStore());
  for (final candidate in candidates) {
    final silo = SiloHttp(origin: candidate, session: session, device: device, client: client ?? _sharedClient());
    try {
      try {
        final info = await silo
            .send(const SiloRequest.get('/api/v2/system/info', auth: SiloAuth.none, gated: false))
            .timeout(infoBound);
        final json = info.statusCode == 200 ? _decode(info.body) : null;
        final apiMajor = json is Map ? json['api_major'] : null;
        silo.gate.recordProbe(status: info.statusCode, body: info.body, apiMajor: apiMajor is int ? apiMajor : null);
        if (silo.gate.isBlocked) return const SiloServerNeedsUpdate();
      } on Object {
        // Only an update verdict stops the flow here.
      }

      final bool needsSetup;
      try {
        final setup = await silo.send(const SiloRequest.get('/api/v2/system/setup', auth: SiloAuth.none));
        final json = setup.statusCode == 200 ? _decode(setup.body) : null;
        if (json is! Map) continue;
        needsSetup = json['needs_setup'] == true;
      } on Object {
        continue;
      }

      var signupEnabled = false;
      try {
        final signup = await silo.send(const SiloRequest.get('/api/v2/auth/signup', auth: SiloAuth.none));
        final json = signup.statusCode == 200 ? _decode(signup.body) : null;
        signupEnabled = json is Map && json['enabled'] == true;
      } on Object {
        signupEnabled = false;
      }
      return SiloServerFound(candidate, needsSetup: needsSetup, signupEnabled: signupEnabled);
    } finally {
      if (client == null) silo.close();
    }
  }
  return const SiloServerUnreachable();
}

http.Client _sharedClient() => SiloHttp.newSiloHttpClient();

/// The person's one-time approvals of `http://` origins. Stores SHA-256
/// digests of the canonical origin, like `CleartextConsentStore.kt:33-61`.
class SiloCleartextConsent {
  final Set<String> _digests;

  SiloCleartextConsent([Iterable<String> digests = const []]) : _digests = {...digests};

  Iterable<String> get digests => _digests;

  bool isApproved(String origin) => _digests.contains(digestOf(origin));

  /// Returns false when [origin] is not a cleartext origin that can be named
  /// safely.
  bool approve(String origin) {
    final uri = Uri.tryParse(origin);
    if (uri == null || uri.scheme != 'http' || uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    _digests.add(digestOf(origin));
    return true;
  }

  static String digestOf(String origin) => sha256.convert(utf8.encode(siloOrigin(Uri.parse(origin)))).toString();
}

Object? _decode(String body) {
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}
